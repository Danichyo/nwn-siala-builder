defmodule BuildCalculatorWeb.LogLeakTest do
  @moduledoc """
  🔴 Сторож задачи 4.75: **ни одного билда в логе приложения** — с уровнем
  логгера, как в проде (`:info`, `config/prod.exs`).

  Слово Dan про аналитику — «главное, чтобы мы не логировали билды» — касается
  и логов: в проде их пишет Docker (`json-file`, 10 МБ × 3, `DEPLOY.md`),
  и до этой задачи `Phoenix.Logger` печатал туда `GET /b/<код>` на каждый
  переход по ссылке.

  Тест проходит, захватывая ВЕСЬ лог (`ExUnit.CaptureLog`), по каждому месту,
  где код билда приходит на сервер или лежит в процессе:

    * открытие `/b/<код>` (мёртвый рендер и сокет), `/?b=<код>`, короткой
      ссылки `/s/<ключ>` и её редиректа, сохранённого билда `/builds/<id>`,
      входа по ссылке `/users/log-in/<токен>`;
    * правки в конструкторе, «поделиться коротко», экспорт и маяк скачивания,
      импорт текста и лога `.билд`;
    * переход между `live_session` с кодом в адресе — его `Phoenix.LiveView`
      сам пишет предупреждением с адресом;
    * 🔴 падение процесса LiveView (конструктор и просмотр) с кодом в состоянии
      и в последнем сообщении — отчёт о падении. С 4.76 событие с чужим именем
      экран не роняет (`BuildCalculatorWeb.UnhandledEvent`); падение, до
      которого клиент ещё дотягивается, — имя `lv:…` (его разбирает сам
      LiveView и бросает `ArgumentError`). Билд в АРГУМЕНТАХ кадра стека
      (`FunctionClauseError` с сокетом) — экраном `CrashLive` ниже, без
      последней клаузы, как экраны до 4.76;
    * событие, отброшенное последней клаузой, — её строка `warning`;
    * падение запроса в настоящем Bandit — его строка ошибки с аргументами
      кадров стека.

  Затем в захваченном логе ищутся: каждый код и любой его кусок от 8 знаков
  (все окна длиной 8), ключ короткой ссылки, id сохранённого билда, токен
  входа, тексты импорта и лога — окнами по 8 байт; id классов и фитов билда.
  Находок — ноль.

  **Положительный контроль** — трижды: обязательные строки в логе есть (шаблон
  маршрута, отчёт о падении, предупреждение LiveView, строка Bandit — иначе
  «ноль находок» значил бы, что лог пуст); строка запроса, какой её печатал
  `Phoenix.Logger` до задачи, на том же запросе код несёт и поиском находится;
  отчёт о падении без фильтра `BuildCalculator.LogRedaction` код несёт.

  ⚠️ `async: false` — уровень логгера (`Logger.configure/1`) общий на всё
  приложение, захват лога видит чужие процессы, тест включает спрятанный
  на Сиале импорт текста (`Application.put_env/3`) и снимает фильтр лога
  на время контроля.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import BuildCalculatorWeb.EditionHelpers
  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias BuildCalculator.Accounts.Scope
  alias BuildCalculator.{AccountsFixtures, Encoding, LibraryFixtures, Rules}
  alias BuildCalculator.ShortLinks
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Export
  alias BuildCalculatorWeb.LogRedaction

  @dan_code "../fixtures/dan_build_2026-09-13.code"
            |> Path.expand(__DIR__)
            |> File.read!()
            |> String.trim()

  @log "../fixtures/game_logs/hela.log" |> Path.expand(__DIR__) |> File.read!()

  # Уровень `:info` открывает строки запросов и вне захвата — в вывод прогона
  # они не идут (на провале ExUnit их покажет).
  @moduletag :capture_log

  setup do
    # Фильтр ставит приложение при запуске — не тест.
    assert LogRedaction.installed?()

    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    use_edition(:siala)
    Application.put_env(:build_calculator, :import_ui, true)

    # Строка последней клаузы — одна в минуту на экран (4.76); счётчик общий,
    # и первую строку минуты мог съесть другой тест.
    :ets.match_delete(
      BuildCalculator.RateLimit,
      {{BuildCalculatorWeb.UnhandledEvent, :_, :_}, :_, :_}
    )

    :ok
  end

  test "Сиала: маршруты, события, переходы и падения — ни кода, ни его кусков", %{conn: conn} do
    {:ok, %{build: build, ruleset: ruleset}} = Encoding.decode(@dan_code)
    short_code = build |> Build.truncate(12) |> Encoding.encode()

    {found, log} = with_log(fn -> walk(conn, %{code: @dan_code, short_code: short_code}) end)

    # Обязательное записалось: строки запросов шаблонами, переход, падения.
    for line <- [
          "GET /b/:code",
          "GET /s/:key",
          "GET /builds/:id",
          "GET /users/log-in/:token",
          "Sent 302",
          "navigate event to",
          "GenServer",
          "{Phoenix.LiveView, BuildCalculatorWeb.BuilderLive,",
          "{Phoenix.LiveView, BuildCalculatorWeb.BuildViewLive,",
          "received unknown LiveView event",
          "LogLeakTest.CrashLive.handle_event/3",
          "(FunctionClauseError)",
          "an event no clause of handle_event/3 takes",
          "LogLeakTest.CrashPlug.crash/2"
        ] do
      assert log =~ line, "в логе нет #{inspect(line)}:\n#{log}"
    end

    assert findings(log, needles([@dan_code, short_code], found.texts, build, ruleset)) == []
  end

  test "ваниль: ссылка, конструктор и падение — ни кода, ни его кусков", %{conn: conn} do
    use_edition(:vanilla)
    ruleset = BuildCalculator.Data.ruleset!("vanilla")
    build = vanilla_build(ruleset.version)
    code = Encoding.encode(build)

    log =
      capture_log(fn ->
        {:ok, view, _html} = live(conn, "/b/#{code}")
        crash(view)
        {:ok, builder, _html} = live(conn, "/?b=#{code}")
        builder |> element("#export-button") |> render_click()
        crash(builder)
      end)

    assert log =~ "GET /b/:code"
    assert log =~ "{Phoenix.LiveView, BuildCalculatorWeb.BuilderLive,"
    assert findings(log, needles([code], [], build, ruleset)) == []
  end

  describe "положительный контроль" do
    test "строка запроса, какой её печатал Phoenix.Logger, несёт код — поиск его находит",
         %{conn: conn} do
      sent = get(conn, "/b/#{@dan_code}")
      assert sent.status == 200

      without_redaction()

      log =
        capture_log(fn ->
          Phoenix.Logger.phoenix_endpoint_start(
            [],
            %{},
            %{conn: sent, options: [log: :info]},
            :ok
          )
        end)

      assert log =~ "GET /b/"
      assert [_ | _] = findings(log, %{windows: windows(@dan_code), names: []})
    end

    test "отчёт о падении без фильтра несёт код и билд — поиск их находит", %{conn: conn} do
      {:ok, %{build: build, ruleset: ruleset}} = Encoding.decode(@dan_code)
      {:ok, by_event, _html} = live(conn, "/b/#{@dan_code}")
      {:ok, by_state, _html} = live(conn, "/b/#{@dan_code}")

      without_redaction()

      # Код в последнем сообщении — параметр события. Ключ — `sample`: ключ
      # с `b` (`b`, `probe`) `Phoenix.Socket.Message` печатает `[FILTERED]`
      # и без фильтра лога (`filter_parameters` сравнивает подстрокой).
      log = capture_log(fn -> crash(by_event, %{"sample" => @dan_code}) end)
      assert log =~ "{Phoenix.LiveView, BuildCalculatorWeb.BuildViewLive,"
      assert [_ | _] = findings(log, %{windows: windows(@dan_code), names: []})

      # Код в состоянии экрана просмотра: на `:info` состояние не печатается
      # и без фильтра — падение `lv:…` аргументов кадра не несёт.
      log = capture_log(fn -> crash(by_state) end)
      assert log =~ "{Phoenix.LiveView, BuildCalculatorWeb.BuildViewLive,"

      # Билд в аргументах кадра стека — сокет с раскодированным билдом.
      export = Export.text(build, ruleset, Rules.compute(build, ruleset))
      log = capture_log(fn -> crash_by_clause(conn, @dan_code) end)
      assert log =~ "LogLeakTest.CrashLive.handle_event/3"
      assert [_ | _] = findings(log, needles([], [export], build, ruleset))
    end
  end

  # Фильтр снимается до конца теста и возвращается, только если стоял: иначе
  # контроль, прошедший первым, ставил бы фильтр за приложение, и мутант
  # «приложение фильтр не ставит» выживал бы (так и было в первой редакции).
  defp without_redaction do
    installed? = LogRedaction.installed?()
    LogRedaction.uninstall()
    on_exit(fn -> if installed?, do: LogRedaction.install() end)
  end

  # ------------------------------------------------------------------ walk --

  defp walk(conn, %{code: code, short_code: short_code}) do
    user = AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)
    signed_in = log_in_user(conn, user)
    saved = LibraryFixtures.build_fixture(scope, %{code: code, name: "Probe save"})
    {:ok, %{key: key}} = ShortLinks.shorten(code)

    {token, _hashed} =
      AccountsFixtures.generate_user_magic_link_token(AccountsFixtures.user_fixture())

    {:ok, %{build: build}} = Encoding.decode(code)

    # Просмотр: мёртвый рендер и сокет, маяк скачивания.
    assert get(conn, "/b/#{code}").status == 200
    {:ok, view, _html} = live(conn, "/b/#{code}?utm_campaign=launch")
    view |> element("#view-download-analytics") |> render_hook("analytics_export_downloaded")

    # Короткая ссылка и её редирект.
    short = get(conn, "/s/#{key}")
    assert redirected_to(short) == "/b/#{code}"
    {:ok, _view, _html} = live(conn, redirected_to(short))

    # Конструктор по ссылке: правка, «поделиться коротко», экспорт.
    {:ok, builder, _html} = live(conn, "/?b=#{code}&l=5")
    builder |> element("#level-3") |> render_click()
    builder |> element("#export-button") |> render_click()
    builder |> element("#export-download-analytics") |> render_hook("analytics_export_downloaded")

    {:ok, sharer, _html} = live(conn, "/?b=#{short_code}")
    sharer |> element("#short-link-button") |> render_click()

    # Импорт текста — экспорт этого же билда; лог `.билд`.
    {:ok, %{ruleset: ruleset}} = Encoding.decode(code)
    export = Export.text(build, ruleset, Rules.compute(build, ruleset))
    {:ok, importer, _html} = live(conn, "/")
    importer |> element("#import-button") |> render_click()
    importer |> form("#import-form", %{"import" => %{"text" => export}}) |> render_submit()
    importer |> element("#import-apply") |> render_click()

    {:ok, logger, _html} = live(conn, "/")
    logger |> element("#game-log-import-button") |> render_click()

    logger
    |> form("#game-log-import-form", %{"game_log_import" => %{"text" => @log}})
    |> render_submit()

    logger |> element("#game-log-import-apply") |> render_click()

    # Сохранённый билд и вход по ссылке.
    {:ok, _view, _html} = live(signed_in, "/builds/#{saved.id}")
    get(conn, "/users/log-in/#{token}")

    # Переход между `live_session` с кодом в адресе: LiveView отказывает
    # и пишет предупреждение с адресом (клиент перезагрузит страницу).
    {:ok, form, _html} = live(signed_in, "/builds/new?b=#{code}")
    {:error, _} = live_redirect(form, to: "/?b=#{code}")

    {:ok, viewer, _html} = live(signed_in, "/b/#{code}")
    {:error, _} = live_redirect(viewer, to: "/builds/new?b=#{code}")

    {:ok, saved_view, _html} = live(signed_in, "/builds/#{saved.id}")
    {:error, _} = live_redirect(saved_view, to: "/builds/#{saved.id}/edit")

    # Падения процессов LiveView с кодом в состоянии и в событии.
    # Параметры события — куски билда (`pick_feat` шлёт id фита); `b`
    # и `text` прячет ещё и `filter_parameters` (`Phoenix.Socket.Message`
    # печатает полезную нагрузку через него), `sample` — нет.
    {:ok, crashing_view, _html} = live(conn, "/b/#{code}")
    crash(crashing_view, %{"b" => code, "sample" => code, "feat" => feat_with_underscore(build)})

    # Событие с вставленным текстом (как `import_parse`) — текст в последнем
    # сообщении процесса.
    {:ok, crashing_builder, _html} = live(conn, "/?b=#{code}")
    crash(crashing_builder, %{"b" => code, "import" => %{"text" => export}})

    # Билд в аргументах кадра стека: экран без последней клаузы.
    crash_by_clause(conn, code)

    # Отброшенные последней клаузой (4.76): имя — код, нагрузка — код и текст.
    {:ok, dropping, _html} = live(conn, "/?b=#{code}")
    render_hook(dropping, code, %{"sample" => code, "import" => %{"text" => export}})
    render_hook(dropping, "pick_race", %{"sample" => code})

    # Падение запроса в настоящем Bandit — его строка ошибки.
    bandit_crash("/builds/#{saved.id}?b=#{code}")

    %{texts: [export, @log, key, to_string(saved.id), token]}
  end

  defp feat_with_underscore(%Build{} = build) do
    build |> build_names(nil) |> Enum.find(&String.contains?(&1, "_")) || flunk("нет id с _")
  end

  # Событие `lv:…`, которого LiveView не знает, роняет процесс экрана —
  # `ArgumentError` в `Phoenix.LiveView.Channel.view_handle_event/3`, до
  # клауз экрана (задача 4.76: событие с обычным чужим именем экран больше
  # не роняет). Отчёт о падении несёт последнее сообщение и, на уровне
  # `:debug`, состояние.
  defp crash(view, value \\ %{}) do
    Process.flag(:trap_exit, true)
    pid = view.pid
    ref = Process.monitor(pid)
    catch_exit(render_hook(view, "lv:log_leak_probe", value))
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
  end

  # Экран без последней клаузы `handle_event/3` (`use Phoenix.LiveView`, а не
  # `use BuildCalculatorWeb, :live_view`): событие без обработчика роняет его
  # `FunctionClauseError`, и аргументы кадра — весь сокет с кодом, билдом и
  # текстом экспорта, как у экранов веб-слоя до 4.76.
  defmodule CrashLive do
    @moduledoc false
    use Phoenix.LiveView

    alias BuildCalculator.{Encoding, Rules}
    alias BuildCalculatorWeb.Builder.Export

    @impl true
    def mount(_params, %{"code" => code}, socket) do
      {:ok, %{build: build, ruleset: ruleset}} = Encoding.decode(code)
      export = Export.text(build, ruleset, Rules.compute(build, ruleset))
      {:ok, assign(socket, code: code, build: build, export: export)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="crash-live">{byte_size(@export)}</div>
      """
    end

    @impl true
    def handle_event("never_sent", _params, socket), do: {:noreply, socket}
  end

  defp crash_by_clause(conn, code) do
    {:ok, view, _html} = live_isolated(conn, CrashLive, session: %{"code" => code})
    Process.flag(:trap_exit, true)
    pid = view.pid
    ref = Process.monitor(pid)
    catch_exit(render_hook(view, "log_leak_probe_no_such_event", %{"sample" => code}))
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
  end

  defmodule CrashPlug do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    # Код из query и весь запрос — аргументами кадра, где не нашлось клаузы:
    # так их печатает строка ошибки Bandit (`Exception.format/3`).
    @impl true
    def call(conn, _opts) do
      conn = Plug.Conn.fetch_query_params(conn)
      crash(conn.query_params["b"], conn)
    end

    def crash(:never, _conn), do: :ok
  end

  defp bandit_crash(path) do
    pid = start_supervised!({Bandit, plug: CrashPlug, port: 0, ip: :loopback, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)

    response = Req.get!("http://127.0.0.1:#{port}#{path}", retry: false)
    assert response.status == 500
  end

  # ------------------------------------------------------------------- scan --

  # Иглы: окна по 8 байт каждого кода целиком и каждого текста — без окон,
  # общих с текстом ДРУГОГО билда той же формы (`neutral/1`: шапки экспорта,
  # «Siala Build Calculator», рамки лога `.билд` — общий шаблон, а не билд,
  # и «Calculat» нашёлся бы в каждом имени модуля), и id классов и фитов.
  defp needles(codes, texts, %Build{} = build, ruleset) do
    neutral = texts |> Enum.flat_map(&windows(neutral(&1, ruleset))) |> MapSet.new()

    windows =
      for text <- codes ++ texts,
          window <- windows(text),
          String.trim(window) != "",
          text in codes or not MapSet.member?(neutral, window),
          uniq: true,
          do: window

    if codes != [], do: assert(length(windows) >= byte_size(hd(codes)) - 7)

    # Вычитание шаблона не съело текст: у экспорта и лога остаётся больше
    # трети окон (замер: экспорт 2034 из 2882, лог 1023 из 2562).
    for text <- texts, byte_size(text) > 100 do
      own = text |> windows() |> Enum.count(&(not MapSet.member?(neutral, &1)))
      assert own * 3 > length(windows(text))
    end

    %{windows: windows, names: build_names(build, ruleset)}
  end

  # Текст той же формы о другом билде: экспорт пустого билда, другой лог.
  defp neutral("------" <> _ = _log, _ruleset),
    do: "../fixtures/game_logs/hnyupius.log" |> Path.expand(__DIR__) |> File.read!()

  defp neutral(text, ruleset) do
    if String.contains?(text, "LEVELING GUIDE") do
      empty = Build.new(ruleset_version: ruleset.version)
      Export.text(empty, ruleset, Rules.compute(empty, ruleset))
    else
      ""
    end
  end

  defp windows(text) when byte_size(text) < 8, do: [text]
  defp windows(text), do: for(at <- 0..(byte_size(text) - 8), do: binary_part(text, at, 8))

  # Следы раскодированного билда: id классов и фитов с подчёркиванием —
  # такие в логе не встречаются иначе как из самого билда.
  defp build_names(%Build{} = build, _ruleset) do
    classes = for class <- Enum.uniq(build.levels), do: Atom.to_string(class)

    feats =
      for {_level, slots} <- build.feats,
          {_slot, pick} <- slots,
          id = if(is_tuple(pick), do: elem(pick, 0), else: pick),
          do: Atom.to_string(id)

    Enum.filter(Enum.uniq(classes ++ feats), &String.contains?(&1, "_"))
  end

  # Находка — `{кусок, контекст}`: что нашлось и где.
  defp findings(log, %{windows: windows, names: names}) do
    pattern = :binary.compile_pattern(windows ++ names)

    log
    |> :binary.matches(pattern)
    |> Enum.map(fn {at, length} ->
      from = max(at - 60, 0)

      {binary_part(log, at, length),
       binary_part(log, from, min(at + length + 60, byte_size(log)) - from)}
    end)
  end

  # ---------------------------------------------------------------- builds --

  defp vanilla_build(version) do
    Build.new(
      ruleset_version: version,
      race: :human,
      alignment: :lawful_neutral,
      base_abilities: %{str: 16, dex: 14, con: 14, int: 14, wis: 10, cha: 8},
      levels: List.duplicate(:fighter, 20) ++ List.duplicate(:weapon_master, 20),
      ability_increases: Map.new([4, 8, 12, 16, 20, 24, 28, 32, 36, 40], &{&1, :str}),
      skills: %{1 => %{intimidate: 4}},
      feats: %{
        1 => %{:general => :dodge, {:class_bonus, :fighter} => {:weapon_focus, :longsword}},
        2 => %{{:class_bonus, :fighter} => :mobility},
        3 => %{:general => :expertise},
        4 => %{{:class_bonus, :fighter} => :spring_attack},
        6 => %{:general => :whirlwind_attack}
      }
    )
  end
end
