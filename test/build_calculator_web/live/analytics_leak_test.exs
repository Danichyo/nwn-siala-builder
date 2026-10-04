defmodule BuildCalculatorWeb.AnalyticsLeakTest do
  @moduledoc """
  🔴 Сторож задачи 4.54: **ни одного билда в данных аналитики**.

  Тест проходит по ВСЕМ маршрутам LiveView (список берётся из роутера, а не
  пишется руками) и по ВСЕМ событиям калькулятора с настоящими длинными
  кодами билдов — Сиалы (билд Dan, 40 уровней, Fighter / Dwarven Defender /
  Weapon Master) и ванили (Fighter 20 / Weapon Master 20). Код лежит везде,
  куда его кладёт игрок: в пути (`/b/<код>`), в query (`?b=`, `/builds/new?b=`),
  в адресе страницы-источника, в чужих параметрах (`fbclid`, `utm_medium`).
  Затем в каждой записанной строке обеих таблиц ищутся:

    * каждый код целиком и любой его кусок от 8 знаков (все окна длиной 8 —
      любой более длинный кусок содержит хотя бы одно);
    * текст импорта и лога `.билд` — окнами по 8 байт;
    * имена и id классов, фитов и расы билдов (английские и русские), имя
      файла экспорта, имя сохранённого билда — без учёта регистра;
    * параметры пути: id сохранённого билда и группы, токен входа, ключ
      короткой ссылки.

  Находок — ноль. **Положительный контроль** — дважды:

    * то, что ОБЯЗАНО записаться, записалось: шаблон каждого маршрута, хост
      источника, `utm_source`, имя каждого события. Подмена шаблона путём
      роняет тест здесь (шаблона в строках нет), даже если путь отбила
      проверка формы страницы;
    * подложенная мимо проверок утечка (кусок кода в `page` и в `utm_term`,
      имя класса в имени события) находится той же функцией поиска.

  ⚠️ `async: false` — тест включает спрятанный на Сиале импорт текста
  (`Application.put_env/3`, `:import_ui`) и поднимает ванильную редакцию
  (`use_edition/1`): параллельный сосед увидел бы чужую шапку (CLAUDE.md §7).
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import BuildCalculatorWeb.EditionHelpers
  import Phoenix.LiveViewTest

  alias BuildCalculator.Accounts.Scope

  alias BuildCalculator.{
    AccountsFixtures,
    Data,
    Encoding,
    LibraryFixtures,
    Repo,
    Rules,
    ShortLinks
  }

  alias BuildCalculator.Analytics
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Export

  @dan_code "../../fixtures/dan_build_2026-09-13.code"
            |> Path.expand(__DIR__)
            |> File.read!()
            |> String.trim()

  @log "../../fixtures/game_logs/hela.log" |> Path.expand(__DIR__) |> File.read!()

  # Маршрут, который при монтировании уводит на другой (`push_navigate`
  # в `mount/3`) и потому посещением не бывает по построению: посещение пишет
  # страница, куда увели (`/users/settings`).
  @redirecting ["/users/settings/confirm-email/:token"]

  describe "Сиала" do
    setup do
      use_edition(:siala)
      Application.put_env(:build_calculator, :import_ui, true)
      :ok
    end

    test "все маршруты и события — ни кода, ни его кусков, ни имён", %{conn: conn} do
      {:ok, %{build: build, ruleset: ruleset}} = Encoding.decode(@dan_code)

      fixture = %{
        ruleset: ruleset,
        build: build,
        code: @dan_code,
        # 19 уровней — левелап до последнего неэпического; 40 из 41 — до капа.
        code_before_epic: build |> Build.truncate(19) |> Encoding.encode(),
        code_before_cap: @dan_code,
        pick_epic: "#class-card-fighter",
        pick_cap: "#class-card-fighter",
        log: @log
      }

      found = walk(conn, fixture)

      assert_coverage(found, Analytics.events())
      assert scan(needles(fixture, found)) == []
    end
  end

  describe "ваниль" do
    setup do
      use_edition(:vanilla)
      :ok
    end

    test "все маршруты и события — ни кода, ни его кусков, ни имён", %{conn: conn} do
      ruleset = Data.ruleset!("vanilla")
      build = vanilla_build(ruleset.version)

      fixture = %{
        ruleset: ruleset,
        build: build,
        code: Encoding.encode(build),
        code_before_epic: build |> Build.truncate(19) |> Encoding.encode(),
        code_before_cap: build |> Build.truncate(39) |> Encoding.encode(),
        pick_epic: "#class-card-fighter",
        pick_cap: "#class-card-weapon_master",
        # Лога `.билд` у ванили нет (флаг `game_log_import_ui` выключен).
        log: nil
      }

      found = walk(conn, fixture)

      assert_coverage(found, Analytics.events() -- [:game_log_imported])
      assert scan(needles(fixture, found)) == []
    end
  end

  describe "положительный контроль поиска" do
    test "подложенная мимо проверок утечка находится" do
      code = @dan_code
      {:ok, %{build: build, ruleset: ruleset}} = Encoding.decode(code)
      {day, visitor} = Analytics.visitor({203, 0, 113, 7}, "UA")
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Мимо `record_visit/1`: та отбила бы путь по форме страницы.
      Repo.insert_all(Analytics.Visit, [
        %{
          day: day,
          edition: "siala",
          page: "/b/" <> binary_part(code, 0, 60),
          visitor: visitor,
          utm_term: binary_part(code, 300, 8),
          inserted_at: now
        }
      ])

      Repo.insert_all(Analytics.Event, [
        %{day: day, edition: "siala", name: "opened_fighter", inserted_at: now}
      ])

      fixture = %{
        ruleset: ruleset,
        build: build,
        code: code,
        code_before_epic: code,
        code_before_cap: code,
        log: nil
      }

      findings = scan(needles(fixture, %{texts: [], names: []}))
      columns = findings |> Enum.map(fn {table, column, _value, _needle} -> {table, column} end)

      assert {"visits", "page"} in columns
      assert {"visits", "utm_term"} in columns
      assert {"events", "name"} in columns
    end
  end

  # ------------------------------------------------------------------ walk --

  # Обход: каждый маршрут LiveView и каждое событие. Возвращает тексты,
  # ушедшие на сервер (импорт, лог), и имена, которые на экране видны.
  defp walk(conn, fixture) do
    %{code: code} = fixture
    user = AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)
    signed_in = log_in_user(conn, user)
    saved = LibraryFixtures.build_fixture(scope, %{code: code, name: "Probe save"})
    group = AccountsFixtures.group_fixture(scope)
    {:ok, %{key: key}} = ShortLinks.shorten(code)

    {token, _hashed} =
      AccountsFixtures.generate_user_magic_link_token(AccountsFixtures.user_fixture())

    # Источник с кодом в пути и query: остаться должен только хост.
    guest =
      put_connect_params(conn, %{
        "_analytics_ref" => "https://www.forum.example/t/42?b=#{code}##{code}",
        "_analytics_nav" => "navigate"
      })

    # Конструктор по ссылке: «открыт по ссылке» и «экспорт скачан».
    {:ok, builder, _html} =
      live(guest, "/?b=#{code}&l=5&utm_source=discord&utm_medium=#{code}&fbclid=#{code}")

    builder |> element("#export-download-analytics") |> render_hook("analytics_export_downloaded")

    # Просмотр по ссылке и по короткой ссылке.
    {:ok, view, _html} = live(guest, "/b/#{code}?utm_campaign=launch")
    view |> element("#view-download-analytics") |> render_hook("analytics_export_downloaded")

    short = get(conn, "/s/#{key}")
    assert redirected_to(short) == "/b/#{code}"
    {:ok, _view, _html} = live(guest, redirected_to(short))

    # Левелапы до последнего неэпического уровня и до капа.
    {:ok, epic, _html} = live(guest, "/?b=#{fixture.code_before_epic}")
    epic |> element(fixture.pick_epic) |> render_click()

    {:ok, cap, _html} = live(guest, "/?b=#{fixture.code_before_cap}")
    cap |> element(fixture.pick_cap) |> render_click()

    # Импорт текста — экспорт этого же билда.
    stats = Rules.compute(fixture.build, fixture.ruleset)
    export = Export.text(fixture.build, fixture.ruleset, stats)
    {:ok, importer, _html} = live(guest, "/")
    importer |> element("#import-button") |> render_click()

    importer
    |> form("#import-form", %{"import" => %{"text" => export}})
    |> render_submit()

    importer |> element("#import-apply") |> render_click()

    # Лог `.билд` — где он есть.
    if fixture.log do
      {:ok, logger, _html} = live(guest, "/")
      logger |> element("#game-log-import-button") |> render_click()

      logger
      |> form("#game-log-import-form", %{"game_log_import" => %{"text" => fixture.log}})
      |> render_submit()

      logger |> element("#game-log-import-apply") |> render_click()
    end

    # Остальные маршруты: гость и вошедший.
    for path <- [
          "/sources",
          "/library",
          "/users/register",
          "/users/log-in",
          "/users/log-in/#{token}"
        ] do
      visit(conn, path)
    end

    for path <- [
          "/builds/#{saved.id}",
          "/builds/new?b=#{code}",
          "/builds/#{saved.id}/edit",
          "/library/mine",
          "/library/group/#{group.id}",
          "/groups",
          "/groups/#{group.id}",
          "/users/settings",
          "/users/settings/confirm-email/#{code}"
        ] do
      visit(signed_in, path)
    end

    %{
      # Параметры пути — тоже не шаблон: id сохранённого билда и группы,
      # токен входа, ключ короткой ссылки.
      texts:
        Enum.reject([export, fixture.log], &is_nil/1) ++
          Enum.map([saved.id, group.id, token, key], &to_string/1),
      names: [saved.name, Export.file_name(fixture.build, fixture.ruleset, stats)]
    }
  end

  defp visit(conn, path) do
    case live(conn, path) do
      {:ok, _view, _html} ->
        :ok

      {:error, {kind, _}} = redirect when kind in [:redirect, :live_redirect] ->
        case follow_redirect(redirect, conn) do
          {:ok, _view, _html} -> :ok
          {:ok, %Plug.Conn{} = landed} -> {:ok, _view, _html} = live(landed)
        end
    end
  end

  # ------------------------------------------------------- positive control --

  defp assert_coverage(_found, expected_events) do
    visits = Repo.all(Analytics.Visit)
    events = Repo.all(Analytics.Event)

    pages = visits |> Enum.map(& &1.page) |> MapSet.new()

    templates =
      for %{plug: Phoenix.LiveView.Plug, path: path} <-
            Phoenix.Router.routes(BuildCalculatorWeb.Router),
          path not in @redirecting,
          into: MapSet.new(),
          do: path

    assert MapSet.subset?(templates, pages),
           "не записан шаблон: #{inspect(MapSet.difference(templates, pages) |> Enum.sort())}"

    assert "forum.example" in Enum.map(visits, & &1.referrer_host)
    assert "discord" in Enum.map(visits, & &1.utm_source)
    assert "launch" in Enum.map(visits, & &1.utm_campaign)

    names = events |> Enum.map(& &1.name) |> MapSet.new()

    for event <- expected_events do
      assert Atom.to_string(event) in names, "нет события #{event}: #{inspect(Enum.sort(names))}"
    end
  end

  # ------------------------------------------------------------------- scan --

  defp needles(fixture, found) do
    codes =
      Enum.uniq([fixture.code, fixture.code_before_epic, fixture.code_before_cap])

    windows =
      for text <- codes ++ found.texts,
          window <- windows(text, 8),
          String.trim(window) != "",
          uniq: true,
          do: window

    names =
      (names_of(fixture.ruleset, fixture.build) ++ found.names)
      |> Enum.map(&String.downcase/1)
      |> Enum.filter(&(String.length(&1) >= 4))
      |> Enum.uniq()

    # Поиск, которому нечего искать, зеленеет сам: окна покрывают каждый код,
    # имена — хотя бы классы билда.
    assert length(windows) >= byte_size(fixture.code) - 7
    assert Enum.all?(Enum.uniq(fixture.build.levels), &(Atom.to_string(&1) in names))

    %{windows: windows, names: names}
  end

  defp windows(text, size) when byte_size(text) < size, do: [text]

  defp windows(text, size) do
    for at <- 0..(byte_size(text) - size), do: binary_part(text, at, size)
  end

  defp names_of(ruleset, %Build{} = build) do
    classes =
      for class <- Enum.uniq(build.levels),
          record = ruleset.classes[class],
          name <- [Atom.to_string(class), record.name, record[:ru]],
          is_binary(name),
          do: name

    race = ruleset.races[build.race]
    races = Enum.filter([Atom.to_string(build.race), race.name, race[:ru]], &is_binary/1)

    feats =
      for {_level, slots} <- build.feats,
          {_slot, pick} <- slots,
          feat =
            (case pick do
               {id, _choice} -> id
               id -> id
             end),
          record = ruleset.feats[feat],
          name <- [Atom.to_string(feat), record.name, record[:ru]],
          is_binary(name),
          do: name

    classes ++ races ++ feats
  end

  # Каждая строка обеих таблиц, каждая колонка — текстом.
  defp scan(%{windows: windows, names: names}) do
    window_pattern = :binary.compile_pattern(windows)
    name_pattern = if names == [], do: nil, else: :binary.compile_pattern(names)

    for table <- ["visits", "events"],
        %{columns: columns, rows: rows} = Repo.query!("SELECT * FROM analytics.#{table}"),
        row <- rows,
        {column, value} <- Enum.zip(columns, row),
        value != nil,
        text = text(value),
        needle =
          hit(text, window_pattern) || (name_pattern && hit(String.downcase(text), name_pattern)),
        do: {table, column, text, needle}
  end

  defp hit(text, pattern) do
    case :binary.match(text, pattern) do
      {at, length} -> binary_part(text, at, length)
      :nomatch -> nil
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(%Date{} = value), do: Date.to_iso8601(value)
  defp text(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp text(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp text(value), do: to_string(value)

  # ---------------------------------------------------------------- builds --

  # Ванильный длинный билд с эпиком: Fighter 20 → Weapon Master 20, легальный
  # на ванили (тот же, что «типичный» у `en_guard_test.exs`).
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
