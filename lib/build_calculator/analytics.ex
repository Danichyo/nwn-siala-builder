defmodule BuildCalculator.Analytics do
  @moduledoc """
  Счётчик посещений и событий калькулятора — свой, в базе своей развёртки
  (задача 4.54, решение Dan 03.10.2026: «в аналитике… главное, чтобы мы
  не логировали билды, т.е. чтобы не было утечек билдов»).

  Этот модуль — хранилище: что и в какой форме ложится в таблицы схемы
  `analytics` (миграция `CreateAnalytics`), как считается посетитель и как
  запись уходит в базу, не задерживая и не роняя того, кто её попросил.
  Решает, ЧТО считать и КОГДА, веб-слой (`BuildCalculatorWeb.Analytics`):
  только он знает маршрут, соединение и события экрана.

  ## 🔴 Ни одного билда — форма строки

  Строка посещения — день, редакция, **шаблон маршрута** (`/b/:code`, не код),
  хеш посетителя, хост источника и пять `utm_*`. Строка события — день,
  редакция, имя из закрытого списка (`events/0`) и версия ruleset'а. Других
  колонок нет, и сюда не приходит ничего, кроме этих полей: `record_visit/1`
  и `record_event/3` проверяют каждое (шаблон — по форме пути без query, длины —
  по потолкам таблицы) и непрошедшую строку выбрасывают целиком, а не обрезают.
  Сторож — `analytics_leak_test.exs`: все маршруты и все события с настоящим
  кодом билда, поиск кода, его кусков и имён в каждой записанной строке.

  ## Посетитель без cookie

  `visitor/2` — первые 16 байт HMAC-SHA256 по IP и User-Agent с ключом —
  солью ДНЯ (`BuildCalculator.Analytics.Salt`): соль живёт только в памяти
  и меняется в полночь UTC, так что хеш различает посетителей внутри дня
  и необратим и несравним между днями. Сами IP и User-Agent не хранятся нигде.
  Цена «соли только в памяти» — перезапуск приложения начинает новый день
  соли: посетитель до и после выката того же дня считается дважды.

  ## Запись не задерживает и не роняет

  По умолчанию запись уходит в `Task.Supervisor` (`BuildCalculator.Analytics.Tasks`,
  потолок задач — отказ базы не копит процессы без конца): вызывающий
  тратит только время на запуск задачи. Ошибка базы ловится в задаче
  и пишется в лог одной строкой — без значений строки, только вид отказа.
  `config :build_calculator, :analytics_writer, :inline` (тесты) пишет тем же
  путём, но в процессе вызывающего — песочнице Ecto так видна запись теста,
  а отказ ловится так же и наружу не выходит.

  ## Потолок строк в день — против бота, открывающего сокеты (задача 4.75)

  Строка посещения пишется на каждый первый join страницы, строка события —
  на действие; бот, открывающий сокеты, растил бы обе таблицы без предела.
  Поэтому у строки есть дневной бюджет (`quota/2` → `admit/1`, счёт в памяти —
  `BuildCalculator.RateLimit`, сутки UTC, как соль):

    * **200 строк на посетителя** (хеш IP и User-Agent). Строка — страница
      или действие; переподключение строкой не бывает (`_mounts` > 0). Игрок,
      открывающий страницу каждые две минуты шесть часов подряд, пишет 180.
      За потолком теряется только число его посещений: в уникальные он уже
      попал первой строкой дня. Бот с одного адреса и браузера — не больше
      200 строк в день (~30 КБ с индексом);
    * **2000 строк на адрес** (IPv4 или сеть IPv6 `/64`) — десять таких
      игроков за одним NAT. Бот, меняющий User-Agent на каждом сокете, —
      новый «посетитель» каждый раз, и держит его только этот потолок.
      Сначала спрашивается адрес: за его потолком новые посетители не
      заводят и счётчика в памяти.

  Потолок ставится только **публичному адресу** (решает веб-слой,
  `BuildCalculatorWeb.Analytics.Client.public?/1`). Адрес петли или частной
  сети значит, что `X-Forwarded-For` до приложения не дошёл и все игроки
  видны одним адресом прокси, — тогда потолок стал бы не страховкой,
  а выключателем счётчика (ровно этот довод держал без ограничения частоты
  короткие ссылки до 4.54). Ключи потолка — хеши с солью дня, как посетитель:
  сам адрес в памяти не лежит.

  Первая строка за потолком пишет в лог одно предупреждение без значений —
  по нему видно, что бот был.
  """

  require Logger

  alias BuildCalculator.Analytics.{Event, Salt, Visit}
  alias BuildCalculator.{RateLimit, Repo}

  @events [
    :link_opened,
    :export_downloaded,
    :text_imported,
    :game_log_imported,
    :reached_last_pre_epic_level,
    :reached_level_cap
  ]

  @utm_keys [:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content]

  # Потолки колонок — те же, что `CHECK` в миграции; здесь они отбрасывают
  # строку до похода в базу.
  @max_edition 32
  @max_page 64
  @max_host 253
  @max_utm 64
  @max_ruleset 32

  # Шаблон маршрута Phoenix: путь без query и фрагмента — строчные буквы,
  # цифры, `/`, `_`, `-` и `:` у параметров.
  @page_shape ~r{\A/[a-z0-9/_:\-]*\z}

  @tasks BuildCalculator.Analytics.Tasks

  # Потолки строк в день — числа и доводы в moduledoc («Потолок строк»).
  @rows_per_visitor_day 200
  @rows_per_address_day 2000

  @typedoc "Имя события калькулятора — закрытый список `events/0`."
  @type event ::
          :link_opened
          | :export_downloaded
          | :text_imported
          | :game_log_imported
          | :reached_last_pre_epic_level
          | :reached_level_cap

  @typedoc "Посетитель: день соли и 16 байт хеша."
  @type visitor :: {Date.t(), <<_::128>>}

  @typedoc """
  Ключи дневного потолка строк (`quota/2`): день соли, хеш посетителя
  и хеш адреса. `nil` — потолка нет.
  """
  @type quota :: %{day: Date.t(), visitor: <<_::128>>, address: <<_::128>>} | nil

  @doc "Все имена событий, которые принимает `record_event/3`."
  @spec events() :: [event()]
  def events, do: @events

  @doc "Ключи `utm_*`, которые хранит строка посещения."
  @spec utm_keys() :: [atom()]
  def utm_keys, do: @utm_keys

  @doc """
  Посетитель для строки посещения: день соли и хеш IP с User-Agent.

  `ip` — адрес клиента (`:inet.ip_address/0`) или `nil`, когда его не узнать;
  `user_agent` — строка или `nil`. День берётся у соли, а не у часов, — строка
  ляжет в тот день, чьей солью посчитана.
  """
  @spec visitor(:inet.ip_address() | nil, String.t() | nil) :: visitor()
  def visitor(ip, user_agent) do
    {day, salt} = Salt.current()
    {day, visitor_hash(salt, ip, user_agent)}
  end

  defp visitor_hash(salt, ip, user_agent) do
    ip_text = if ip, do: ip |> :inet.ntoa() |> to_string(), else: ""
    agent = if is_binary(user_agent), do: user_agent, else: ""

    :crypto.mac(:hmac, :sha256, salt, [<<byte_size(ip_text)::16>>, ip_text, agent])
    |> binary_part(0, 16)
  end

  @doc """
  Ключи дневного потолка строк для посетителя с адресом `ip` (публичным —
  решает вызывающий) и `user_agent`: тот же хеш посетителя, что у строки
  (`visitor/2`), и хеш адреса — IPv4 или сети IPv6 `/64`
  (`BuildCalculator.RateLimit.address/1`). Оба — с солью дня. `nil` без адреса.
  """
  @spec quota(:inet.ip_address() | nil, String.t() | nil) :: quota()
  def quota(nil, _user_agent), do: nil

  def quota(ip, user_agent) do
    {day, salt} = Salt.current()
    address = :erlang.term_to_binary(RateLimit.address(ip))

    %{
      day: day,
      visitor: visitor_hash(salt, ip, user_agent),
      address: :crypto.mac(:hmac, :sha256, salt, ["address", address]) |> binary_part(0, 16)
    }
  end

  @doc """
  Есть ли у строки место в дневном бюджете `quota` (`quota/2`): `:ok` —
  писать, `:capped` — за потолком (moduledoc, «Потолок строк»). Каждый вызов
  расходует бюджет. `nil` — потолка нет.
  """
  @spec admit(quota()) :: :ok | :capped
  def admit(nil), do: :ok

  def admit(%{day: %Date{} = day, visitor: visitor, address: address}) do
    expires = day |> Date.add(1) |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix()

    with :ok <-
           spend({:analytics_address, day, address}, @rows_per_address_day, expires, "address") do
      spend({:analytics_visitor, day, visitor}, @rows_per_visitor_day, expires, "visitor")
    end
  end

  defp spend(key, limit, expires, what) do
    case RateLimit.hit(key, limit, expires) do
      {:ok, _count} ->
        :ok

      {:limited, count} ->
        if count == limit + 1 do
          Logger.warning(
            "analytics: daily row cap reached for one #{what} (#{limit}); its later rows today are dropped"
          )
        end

        :capped
    end
  end

  @doc """
  Записывает посещение страницы.

  `attrs`: `:visitor` (`visitor/2`), `:edition`, `:page` — шаблон маршрута,
  `:referrer_host` (или `nil`) и `:utm` — карта `utm_keys/0` → строка или `nil`.
  Поле не по форме — строка не пишется вовсе (`{:error, :invalid}`).
  `:quota` (`quota/2`, необязательно) — дневной потолок строк: за ним строка
  не пишется (`{:error, :capped}`).
  """
  @spec record_visit(map()) :: :ok | {:error, :invalid | :capped}
  def record_visit(%{visitor: {%Date{} = day, <<_::128>> = hash}} = attrs) do
    utm = Map.get(attrs, :utm, %{})

    row =
      %{
        day: day,
        edition: attrs[:edition],
        page: attrs[:page],
        visitor: hash,
        referrer_host: attrs[:referrer_host],
        inserted_at: now()
      }
      |> Map.merge(Map.new(@utm_keys, &{&1, Map.get(utm, &1)}))

    cond do
      not valid_visit?(row) -> {:error, :invalid}
      admit(attrs[:quota]) == :capped -> {:error, :capped}
      true -> write(Visit, row)
    end
  end

  def record_visit(_attrs), do: {:error, :invalid}

  @doc """
  Записывает событие калькулятора: имя из `events/0`, редакцию и, где событие
  о билде, версию его ruleset'а (`nil` — билда нет). `quota` — дневной потолок
  строк посетителя (`quota/2`), тот же, что у посещений; `nil` — без потолка.
  """
  @spec record_event(String.t(), event(), String.t() | nil, quota()) ::
          :ok | {:error, :invalid | :capped}
  def record_event(edition, name, ruleset, quota \\ nil)

  def record_event(edition, name, ruleset, quota) when name in @events do
    row = %{
      day: Date.utc_today(),
      edition: edition,
      name: Atom.to_string(name),
      ruleset: ruleset,
      inserted_at: now()
    }

    cond do
      not (short?(edition, @max_edition) and (is_nil(ruleset) or short?(ruleset, @max_ruleset))) ->
        {:error, :invalid}

      admit(quota) == :capped ->
        {:error, :capped}

      true ->
        write(Event, row)
    end
  end

  def record_event(_edition, _name, _ruleset, _quota), do: {:error, :invalid}

  defp valid_visit?(row) do
    short?(row.edition, @max_edition) and short?(row.page, @max_page) and
      Regex.match?(@page_shape, row.page) and
      (is_nil(row.referrer_host) or short?(row.referrer_host, @max_host)) and
      Enum.all?(@utm_keys, fn key -> is_nil(row[key]) or short?(row[key], @max_utm) end)
  end

  defp short?(value, max) when is_binary(value),
    do: value != "" and String.valid?(value) and String.length(value) <= max

  defp short?(_value, _max), do: false

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # ------------------------------------------------------------------ write --

  defp write(schema, row) do
    insert = fn -> Repo.insert_all(schema, [row]) end

    case Application.get_env(:build_calculator, :analytics_writer, :task) do
      :inline ->
        guarded(insert)

      :task ->
        try do
          case Task.Supervisor.start_child(@tasks, fn -> guarded(insert) end) do
            {:ok, _pid} -> :ok
            {:error, reason} -> dropped(reason)
          end
        catch
          # Супервизор не запущен (mix-задача без приложения) — запись теряется,
          # вызывающий о ней не узнаёт.
          :exit, _reason -> dropped(:no_supervisor)
        end
    end
  end

  defp guarded(insert) do
    insert.()
    :ok
  rescue
    error -> dropped(error)
  catch
    :exit, _reason -> dropped(:exit)
  end

  # В лог — только ВИД отказа: сообщение Postgres может нести значения строки
  # (`DETAIL: Failing row contains …`), а значения не должны уходить и туда.
  defp dropped(reason) do
    Logger.warning("analytics: write dropped (#{kind(reason)})")
    :ok
  end

  defp kind(%Postgrex.Error{postgres: %{code: code}}), do: "postgres #{code}"
  defp kind(%{__struct__: module}), do: inspect(module)
  defp kind(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp kind(_reason), do: "other"
end
