defmodule BuildCalculatorWeb.Analytics do
  @moduledoc """
  Что считает счётчик посещений и событий и когда (задача 4.54). Хранилище —
  `BuildCalculator.Analytics`; здесь — маршрут, соединение и события экрана.

  Флаг — `Layouts.analytics?/0` (пресет редакции, у обеих включён). Выключен —
  в таблицы не пишется ничего, а разметка та же, что до задачи.

  ## Посещение — подключённый `mount`, первый раз на странице

  `on_mount/4` стоит последним в обоих `live_session` роутера и считает только
  ПОДКЛЮЧЁННОЕ монтирование: мёртвый рендер видят и боты, и превью ссылок
  Discord/Reddit, а сокет LiveView открывает только живой браузер. Повторный
  join той же страницы (обрыв связи, выкат) приходит с `_mounts` больше нуля
  и посещением не считается. Живая навигация (`navigate`) — новая страница
  и новое посещение, но без источника: `_live_referer` говорит, что пришли
  со своей же страницы.

  Строка пишется на первом `handle_params` (хук `:handle_params`, его LiveView
  зовёт сразу после `mount/3` и тогда, когда своего `handle_params/3` у экрана
  нет): только там известен адрес, а из адреса берётся **шаблон маршрута**
  (`Phoenix.Router.route_info/4` → `"/b/:code"`), не путь, и `utm_*`, не query.
  Монтирование, которое редиректит, до `handle_params` не доходит и не
  считается.

  ## События калькулятора — раз за сессию там, где это важно

  Сессия — процесс LiveView (`put_private/3`, не ассайн: в разметку и в
  `forget_build_ui/1` ей не нужно, это не состояние интерфейса).

    * `link_opened/2` — билд открыт по ссылке: один раз, на первом join
      страницы, не живой навигацией, не перезагрузкой и не «Назад»
      (`app.js` присылает вид перехода) и не со своего же сайта
      (`Client.plan/2`). Иначе каждое F5 над своим билдом считалось бы чужим
      переходом по ссылке;
    * `levelled_up/4` — билд взял последний неэпический уровень и кап: по разу
      на порог за сессию, только левелапом (замена билда целиком — ссылка,
      импорт — дошедшим не считается). Пороги — у ядра:
      `Rules.Epic.epic_level?/2` и `ruleset.level_cap`;
    * `imported/3` и «экспорт скачан» (`"analytics_export_downloaded"` от маяка
      `download_text/1`) — каждое, но не больше `@per_session` за сессию: событие
      присылает клиент, и зациклившийся клиент не должен писать без конца.

  Ловит событие маяка хук `:handle_event`, прицепленный здесь же к каждому
  экрану, — у экрана своего обработчика нет. Хук стоит и при выключенном
  флаге: событие гасится, а не роняет экран отсутствием обработчика
  (спрятанное спрятано и от события, `#h-4-4`).

  ## Не задерживает и не роняет

  `mount` только хеширует адрес и запускает запись (`BuildCalculator.Analytics`).
  Любое исключение здесь ловится и пишется в лог одной строкой — экрану
  отказ счётчика не виден.
  """

  import Phoenix.LiveView,
    only: [
      attach_hook: 4,
      detach_hook: 3,
      connected?: 1,
      get_connect_info: 2,
      get_connect_params: 1,
      put_private: 3
    ]

  require Logger

  alias BuildCalculator.Analytics, as: Store
  alias BuildCalculator.Rules.Epic
  alias BuildCalculatorWeb.Analytics.Client
  alias BuildCalculatorWeb.Edition

  @key :analytics

  # События от клиента (маяки разметки) — имя события сокета → имя строки.
  @client_events %{"analytics_export_downloaded" => :export_downloaded}

  # Потолок повторяемых событий за сессию — страховка от зациклившегося
  # клиента, а не от бота (тот переподключится и получит новую сессию).
  @per_session 20

  @doc """
  Имена событий сокета, которые гасит хук этого модуля, а не `handle_event/3`
  экрана, — для сторожа имён событий (задача 4.76, `live_event_names_test.exs`).
  """
  @spec client_events() :: [String.t()]
  def client_events, do: Map.keys(@client_events)

  @doc "Включён ли счётчик (`Layouts.analytics?/0`)."
  @spec enabled?() :: boolean()
  def enabled?, do: Edition.flag?(:analytics)

  @doc false
  def on_mount(:default, _params, _session, socket) do
    socket = attach_hook(socket, :analytics_client_events, :handle_event, &client_event/3)

    {:cont, guarded(socket, fn -> open_session(socket) end)}
  end

  defp open_session(socket) do
    if connected?(socket) and enabled?() do
      plan = Client.plan(get_connect_params(socket), socket.endpoint.host())
      ip = Client.ip(get_connect_info(socket, :peer_data), get_connect_info(socket, :x_headers))
      user_agent = get_connect_info(socket, :user_agent)

      socket =
        put_private(socket, @key, %{
          link_open?: plan.link_open?,
          reached: MapSet.new(),
          counts: %{},
          # Задача 4.75: дневной потолок строк посетителя и адреса — общий
          # у посещений и событий; только у публичного адреса (за прокси без
          # `X-Forwarded-For` все игроки — один адрес, и потолок стал бы
          # выключателем). Доводы и числа — `BuildCalculator.Analytics`.
          quota: if(Client.public?(ip), do: Store.quota(ip, user_agent))
        })

      if plan.visit? and socket.router do
        visitor = Store.visitor(ip, user_agent)

        attach_hook(socket, :analytics_visit, :handle_params, fn params, uri, socket ->
          visit(params, uri, socket, visitor, plan.referrer_host)
        end)
      else
        socket
      end
    else
      socket
    end
  end

  defp visit(params, uri, socket, visitor, referrer) do
    socket = detach_hook(socket, :analytics_visit, :handle_params)

    guarded(:ok, fn ->
      %URI{path: path, host: host} = URI.parse(uri)

      case Phoenix.Router.route_info(socket.router, "GET", path || "/", host) do
        %{route: route} ->
          Store.record_visit(%{
            visitor: visitor,
            edition: edition(),
            page: route,
            referrer_host: Client.referrer_host(referrer, host),
            utm: Client.utm(params),
            quota: quota(socket)
          })

        :error ->
          :ok
      end
    end)

    {:cont, socket}
  end

  defp client_event(event, _params, socket) do
    case Map.fetch(@client_events, event) do
      {:ok, name} -> {:halt, counted(socket, name, ruleset_version(socket))}
      :error -> {:cont, socket}
    end
  end

  defp ruleset_version(socket) do
    case socket.assigns do
      %{ruleset: %{version: version}} when is_binary(version) -> version
      _no_build -> nil
    end
  end

  @doc """
  Билд открыт по ссылке (`?b=`, `/b/:code`, `/builds/:id`) — ruleset `version`.

  Считается один раз за сессию и только у свежего перехода (см. moduledoc);
  мостик на чужой сайт и битая ссылка сюда не приходят.
  """
  @spec link_opened(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def link_opened(socket, version) do
    case socket.private[@key] do
      %{link_open?: true} = session ->
        socket = put_private(socket, @key, %{session | link_open?: false})
        record(:link_opened, version, session.quota)
        socket

      _no_session_or_counted ->
        socket
    end
  end

  @doc "Импорт принят: `:text` — текст ECB, `:game_log` — лог `.билд`."
  @spec imported(Phoenix.LiveView.Socket.t(), :text | :game_log, String.t()) ::
          Phoenix.LiveView.Socket.t()
  def imported(socket, :text, version), do: counted(socket, :text_imported, version)
  def imported(socket, :game_log, version), do: counted(socket, :game_log_imported, version)

  @doc """
  Левелап с `from` уровней на `to`: дошёл ли билд до последнего
  неэпического уровня и до капа — по разу на порог за сессию.
  """
  @spec levelled_up(Phoenix.LiveView.Socket.t(), map(), non_neg_integer(), non_neg_integer()) ::
          Phoenix.LiveView.Socket.t()
  def levelled_up(socket, ruleset, from, to) do
    case socket.private[@key] do
      %{reached: reached} = session ->
        crossed =
          for {name, crossed?} <- [
                reached_last_pre_epic_level:
                  not Epic.epic_level?(ruleset, from + 1) and Epic.epic_level?(ruleset, to + 1),
                reached_level_cap: from < ruleset.level_cap and to >= ruleset.level_cap
              ],
              crossed?,
              not MapSet.member?(reached, name),
              do: name

        Enum.each(crossed, &record(&1, ruleset.version, session.quota))

        put_private(socket, @key, %{session | reached: MapSet.union(reached, MapSet.new(crossed))})

      _no_session ->
        socket
    end
  end

  defp counted(socket, name, version) do
    case socket.private[@key] do
      %{counts: counts} = session ->
        count = Map.get(counts, name, 0)
        if count < @per_session, do: record(name, version, session.quota)
        put_private(socket, @key, %{session | counts: Map.put(counts, name, count + 1)})

      _no_session ->
        socket
    end
  end

  defp record(name, version, quota) do
    if enabled?(), do: guarded(:ok, fn -> Store.record_event(edition(), name, version, quota) end)
    :ok
  end

  defp quota(socket) do
    case socket.private[@key] do
      %{quota: quota} -> quota
      _no_session -> nil
    end
  end

  defp edition, do: Atom.to_string(Edition.current())

  # Отказ счётчика экрану не виден: исключение или выход (процесс соли
  # не отвечает) — строка в логе и `fallback`.
  defp guarded(fallback, fun) do
    fun.()
  rescue
    error ->
      Logger.warning("analytics: skipped (#{inspect(error.__struct__)})")
      fallback
  catch
    :exit, _reason ->
      Logger.warning("analytics: skipped (exit)")
      fallback
  end
end
