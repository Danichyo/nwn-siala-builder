defmodule BuildCalculatorWeb.BuilderGameLogImportTest do
  @moduledoc """
  Task 3.111, second pass: the constructor's own paste-a-log dialog.

  `BuildCalculatorWeb.Builder.GameLogImportTest` already pins the parsing and
  assembly by itself; this file pins the other half the task asked for —
  "интерфейс куда лог вставлять" — end to end, through the same two-step
  dialog the text importer already uses (paste, see the report, accept).

  File kept separate from `builder_live_test.exs` for the same reason
  `builder_gear_feats_test.exs` already is: that file is 200+ KB and gets
  edited by neighbouring tasks.
  """

  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp fixture(name) do
    "../../fixtures/game_logs/#{name}.log" |> Path.expand(__DIR__) |> File.read!()
  end

  defp paste(view, text) do
    view
    |> form("#game-log-import-form", %{"game_log_import" => %{"text" => text}})
    |> render_submit()
  end

  describe "the dialog" do
    test "is closed until asked for, and shows the beta notice before anything is pasted", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#game-log-import-dialog[hidden]")
      view |> element("#game-log-import-button") |> render_click()
      refute has_element?(view, "#game-log-import-dialog[hidden]")

      # Видна ДО вставки — просьба Dan дословная, «могут быть проблемы с
      # переносом» — а не спрятана за разбором.
      assert has_element?(view, "#game-log-import-beta-notice")
      refute has_element?(view, "#game-log-import-report")

      # Задача 3.174: тоже видна ДО вставки, тем же приёмом, что и бета-
      # уведомление рядом, — иначе игрок узнаёт про кодировку только после
      # того, как пустые строки уже приехали в разборе.
      encoding_notice = render(element(view, "#game-log-import-encoding-notice"))
      assert encoding_notice =~ "windows-1251"

      # Ориентир для игрока, а не требование к точным границам вставки
      # (CLAUDE.md: «вставьте блок целиком, лишнее мы отбросим»).
      hint = render(element(view, "#game-log-import-hint"))
      assert hint =~ "Command detected"
      assert hint =~ "Build sent to"
    end

    test "nothing is applied until a report exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      assert has_element?(view, "#game-log-import-apply[disabled]")

      paste(view, fixture("hnyupius"))

      refute has_element?(view, "#game-log-import-apply[disabled]")

      # Билд-конструктор ничего не тронут, пока не нажали «Открыть».
      assert render(element(view, "#character-level")) =~ "0"
    end

    test "closes on its own close button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      refute has_element?(view, "#game-log-import-dialog[hidden]")

      view |> element("#game-log-import-close") |> render_click()
      assert has_element?(view, "#game-log-import-dialog[hidden]")
    end
  end

  describe "all six real dumps read into a report" do
    for {name, levels, split_ids} <- [
          {"brunna", "40", ["split-wizard", "split-pale_master"]},
          {"hnyupius", "40", ["split-fighter", "split-dwarven_defender", "split-weapon_master"]},
          {"moxie", "41", ["split-monk", "split-cleric", "split-rogue", "split-ranger"]},
          {"babuka", "41", ["split-barbarian", "split-fighter", "split-weapon_master"]},
          {"frah_hall", "41", ["split-sorcerer", "split-wizard", "split-druid", "split-bard"]},
          {"froim", "41", ["split-paladin", "split-ranger", "split-rogue", "split-fighter"]}
        ] do
      test "#{name}.log parses, reports, and applies into the ladder", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/")

        view |> element("#game-log-import-button") |> render_click()
        paste(view, fixture(unquote(name)))

        assert has_element?(view, "#game-log-import-report")
        assert render(element(view, "#game-log-import-read-levels")) =~ unquote(levels)

        # ⚠️ Здесь стояло: «Единственный систематический пробел на каждой
        # из трёх фикстур — отключённое на Сиале ванильное владение простым
        # оружием — назван словами, а не проглочен», и проверялось слово
        # «отключён». Пробел был НАШЕЙ ошибкой, а не дефектом лога, и закрыт
        # 26.08.2026 (задача 3.112): шард фит не выключал. Осталось то, чего
        # лог правда не несёт, — мировоззрение; оно и проверяется, чтобы
        # блок отчёта не превратился в необязательный.
        issues = render(element(view, "#game-log-import-issues"))
        assert issues =~ "мировоззрение"
        refute issues =~ "отключён"

        view |> element("#game-log-import-apply") |> render_click()

        assert has_element?(view, "#game-log-import-dialog[hidden]")
        assert render(element(view, "#character-level")) =~ unquote(levels)

        for split_id <- unquote(split_ids) do
          assert has_element?(view, "##{split_id}")
        end
      end
    end
  end

  describe "hnyupius.log: order survives the trip through the dialog" do
    test "Fighter's 10th level still lands at character level 21 once applied", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture("hnyupius"))
      view |> element("#game-log-import-apply") |> render_click()

      # Открывает уровень 21 (следующий свободный после переноса), где стоит
      # именно Fighter — то, что доказывает: лестница не съехала.
      view |> element("#level-21") |> render_click()
      assert render(element(view, "#character-level")) =~ "40"
      assert has_element?(view, "#split-fighter")
    end
  end

  # Задача 3.221, часть C. Обе клаузы `*_import_apply` сведены в одну функцию
  # (`BuilderLive.apply_imported/5`), и она гасит `:feat_choice` — как все
  # прочие пути замены билда (`load_code`, `go_to_level`, `reset`, `put_feat`).
  #
  # ⚠️ **Этот тест зелёный и ДО правки, и это сказано вслух, а не спрятано.**
  # Панель сама закрывается, когда её уровень разошёлся с активным
  # (`assign_choice_panel/1` сверяет `level: ^active`), а все шестнадцать
  # фикстур `.билд` несут 14–40 уровней и приземляют игрока далеко от уровня,
  # где он открывал выбор. Живой тупик воспроизводится на ТЕКСТОВОМ импорте,
  # где длину вставленного билда задаёт сам тест
  # (`builder_live_import_test.exs`, «применённый импорт закрывает второй шаг»).
  # Здесь держится второй конец того же правила: придёт короткий лог — и оно
  # уже написано.
  describe "применённый импорт закрывает второй шаг выбора фита (3.221)" do
    test "открытый выбор параметра не переживает применение лога", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      view |> element("#feat-ok-spell_focus") |> render_click()
      assert has_element?(view, "#feat-choice")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture("hnyupius"))
      view |> element("#game-log-import-apply") |> render_click()

      refute has_element?(view, "#feat-choice")

      # ...и список фитов не заперт панелью, которой больше нет.
      view |> element("#level-1") |> render_click()
      assert has_element?(view, "#feat-lists")
    end
  end

  describe "hnyupius_alignment.log: ALIGNMENT: reaches the build header (task 3.173)" do
    test "the report has nothing left to complain about, and alignment shows in the header", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture("hnyupius_alignment"))

      assert render(element(view, "#game-log-import-read-levels")) =~ "40"

      # The same character as `hnyupius.log` (see that fixture's own
      # `test/fixtures/game_logs/README.md` row) used to leave exactly one
      # issue behind — "мировоззрение" — the one thing the old dump could
      # not carry. This is the first fixture where reading the line closes
      # it: nothing left in `groups` at all, so the report shows the
      # "nothing left to complain about" line instead of the issues block.
      refute has_element?(view, "#game-log-import-issues")
      assert has_element?(view, "#game-log-import-clean")

      view |> element("#game-log-import-apply") |> render_click()

      assert has_element?(view, "#game-log-import-dialog[hidden]")
      assert render(element(view, "#character-level")) =~ "40"

      # The header (`#class-split`, `Labels.race_ru/2 · Labels.alignment_name/1`)
      # is where a player actually SEES the alignment that reached the build —
      # `build.alignment == :lawful_good` alone would not tell us the wiring
      # from `GameLogImport` through `put_build/2` to the template is intact.
      header = render(element(view, "#class-split"))
      assert header =~ "Lawful Good"
      refute header =~ "мировоззрение не выбрано"
    end
  end

  describe "the beta notice's own wording" do
    test "names the feature as beta before the player pastes anything", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      notice = render(element(view, "#game-log-import-beta-notice"))
      assert notice =~ "бета" or notice =~ "Бета"
    end
  end

  describe "garbage input stays honest, never applies a phantom build" do
    test "a paste with nothing recognisable leaves apply disabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, "просто какой-то текст без структуры лога")

      assert has_element?(view, "#game-log-import-report")
      assert has_element?(view, "#game-log-import-apply[disabled]")
    end
  end

  describe "экипировка из `.билд+` — задача 3.187" do
    defp fixture_plus(name) do
      "../../fixtures/game_logs_plus/#{name}.log" |> Path.expand(__DIR__) |> File.read!()
    end

    # `.билд` (шестнадцать старых фикстур) не несёт раздела `=== Equipped`
    # вовсе — блок обязан отсутствовать целиком, а не показываться пустым.
    test "у обычного .билд блока экипировки нет вовсе", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture("hnyupius"))

      refute has_element?(view, "#game-log-import-gear")
    end

    test "Хнюпиус: применённое видно тремя зонами, а причины — по-русски с примером строки", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("hnyupius"))

      assert has_element?(view, "#game-log-import-gear")
      assert has_element?(view, "#game-log-import-gear-applied")

      # 3.215: каждая зона — одна строка через запятую (репорт Dan 18.09.2026),
      # порядок пунктов — как печатает панель (характеристики и AC по id).
      abilities = render(element(view, "#game-log-import-gear-applied-abilities"))
      assert abilities =~ "CON"
      assert abilities =~ "+15"
      assert abilities =~ "CON +15, DEX +6, STR +13, WIS +10"

      saves = render(element(view, "#game-log-import-gear-applied-saves"))
      assert saves =~ "ко всем"
      assert saves =~ "+16"
      assert saves =~ "Fort"
      assert saves =~ "+12"
      assert saves =~ "ко всем +16, Fort +12, Will +3"

      ac = render(element(view, "#game-log-import-gear-applied-ac"))
      assert ac =~ "+6"
      assert ac =~ "Броня +6, Отклонение +5, Уклонение +4, Природный +5, Щит +5"

      skills = render(element(view, "#game-log-import-gear-applied-skills"))
      assert skills =~ "Discipline"
      assert skills =~ "Concentration +10, Discipline +19, Heal (skill) +16, Listen +23, Spot +22"

      # 3.214: имена через запятую, а не подряд («Blind fightCleave…» — репорт
      # Dan 18.09.2026). `Epic toughness` дважды — два взятия с сапог (3.204).
      # (3.215 растянула тот же разделитель на все зоны блока.)
      #
      # 🔴 3.224: два взятия печатаются «×2», а не именем дважды подряд —
      # то же слово, каким их называет блок «Вещи» и разбор резиста. Имя,
      # повторённое через запятую, читалось как сбой отчёта.
      feats = render(element(view, "#game-log-import-gear-applied-feats"))
      assert feats =~ "Cleave"
      assert feats =~ "Blind fight, Cleave, Epic toughness ×2"
      refute feats =~ "Epic toughness, Epic toughness"

      # «Не наше» — счётчик, свёрнутый.
      not_ours = render(element(view, "#game-log-import-gear-not-ours"))
      assert not_ours =~ "Не наше"
      assert not_ours =~ "<summary"

      # «Не сложить» — причина по-русски и пример строки лога. После третьего
      # поколения печати (задача 3.213) здесь осталась ОДНА строка на все
      # четыре лога, и она про фит, чей аргумент число урона.
      unresolved = render(element(view, "#game-log-import-gear-unresolved"))
      assert unresolved =~ "Фит не найден"
      assert unresolved =~ "Sneak Attack"

      # 🔴 Задача 3.204: строк «Повтор фита с вещи» здесь больше НЕТ, и это
      # проверяется, а не подразумевается. `Epic Toughness II` и `III` с сапог
      # теперь два взятия, а `II` с пояса — тот же фит; обе строки читаются,
      # и ни одна не просит сервер о доработке.
      refute unresolved =~ "Повтор фита с вещи"

      feats_applied = render(element(view, "#game-log-import-gear-applied-feats"))
      assert feats_applied =~ "Epic Toughness" or feats_applied =~ "Epic toughness"
    end

    test "применённое читает build.gear, а не пересчитывает сумму вторым проходом", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("hnyupius"))
      view |> element("#game-log-import-apply") |> render_click()

      # Открыто в конструкторе — блок «Вещи» несёт ту же сумму.
      view |> element("#gear-toggle") |> render_click()
      assert render(element(view, "#gear-ability-input-con")) =~ ~s(value="15")
      assert render(element(view, "#gear-saves-input")) =~ ~s(value="16")
      assert render(element(view, "#gear-save-fort-input")) =~ ~s(value="12")
    end

    for name <- ~w(brunna moxie bor) do
      test "#{name}.log: экипировка читается без падения", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/")

        view |> element("#game-log-import-button") |> render_click()
        paste(view, fixture_plus(unquote(name)))

        assert has_element?(view, "#game-log-import-gear")
        assert has_element?(view, "#game-log-import-gear-applied")
      end
    end
  end

  # Оружие, щит, куски и крафт ложатся сами (задача 3.206), доспех и тип AC
  # в `ARMS` — тоже (задача 3.213), и в «не сложить» про них ни строки.
  describe "экипировка из `.билд+`: серверных просьб не осталось" do
    test "Хнюпиус: руки, мини-сеты и щит в «применено», серверу про них не пишем",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("hnyupius"))

      hands = render(element(view, "#game-log-import-gear-applied-hands"))
      assert hands =~ "В руке"
      assert hands =~ "Bastard sword"
      assert hands =~ "+6"
      assert hands =~ "Вторая рука"
      assert hands =~ "Tower shield"

      # 3.215: одна строка, между руками запятая, внутри пункта двоеточие.
      assert hands =~ "В руке: Bastard sword +6, Вторая рука: Tower shield"

      mini = render(element(view, "#game-log-import-gear-applied-mini-sets"))
      assert mini =~ "3 + 2 + 2 = 7 кусков"

      ac = render(element(view, "#game-log-import-gear-applied-ac"))
      assert ac =~ "Щит"

      refute has_element?(view, "#game-log-import-gear-applied-named-items")
      refute has_element?(view, "#game-log-import-gear-notes")

      unresolved = render(element(view, "#game-log-import-gear-unresolved"))
      refute unresolved =~ "Мини-сеты"
      refute unresolved =~ "Крафтовые вещи"
      refute unresolved =~ "Оружие в руки не надето"
      refute unresolved =~ "Тип AC не назван"
      assert unresolved =~ "Sneak Attack"

      # `Quality` ушёл в «не наше», а не в «не сложить».
      assert render(element(view, "#game-log-import-gear-not-ours")) =~ "Quality"
    end

    # Доспех — своя строка (задача 3.213): имя из лога («Нагрудник Призрака»)
    # + английское имя у нас («Full plate»), и БЕЗ оговорки — лог назвал
    # `[BaseAC:8]`, значит `reason` у записи `nil`.
    test "Хнюпиус: доспех показан именем из лога и нашим английским именем, без оговорки",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("hnyupius"))

      worn = render(element(view, "#game-log-import-gear-applied-worn"))
      assert worn =~ "Доспех"
      assert worn =~ "Нагрудник Призрака"
      assert worn =~ "Full plate"
      refute worn =~ "<em"
    end

    # Роба с базой 0 — ЗНАЧАЩЕЕ «доспеха нет», не отсутствие ответа: CLAUDE.md
    # §3, слово Dan 19.08.2026, монашеский AC-бонус её не гасит.
    test "Мокси: роба с базой 0 показана как надетый предмет, а не молчанием", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("moxie"))

      worn = render(element(view, "#game-log-import-gear-applied-worn"))
      assert worn =~ "Одеяние Света Сагры"
      assert worn =~ "None, clothing"
      refute worn =~ "<em"
    end

    test "Хнюпиус: открыт в конструкторе — оружие, щит и куски в блоке «Вещи»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("hnyupius"))
      view |> element("#game-log-import-apply") |> render_click()

      view |> element("#gear-toggle") |> render_click()
      gear = render(element(view, "#gear-panel"))
      assert gear =~ "Bastard sword"
      assert gear =~ "Tower shield"
      assert render(element(view, "#gear-ability-input-con")) =~ ~s(value="15")

      # Доспех — задача 3.213, п. 5: выбран в зоне «Защита», а не только назван
      # в отчёте, и AC в экипировке — 63 (сходится с движком, `AU1`-соседний
      # тест `gear_import_engine_test.exs`).
      assert has_element?(view, "#gear-worn-armor-full_plate[selected]")
      assert render(element(view, "#stat-ac_geared")) =~ "63"
    end

    test "Бор: куски из шапки без номеров — число есть, оговорка названа", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("bor"))

      assert render(element(view, "#game-log-import-gear-applied-mini-sets")) =~ "4 куска"

      notes = render(element(view, "#game-log-import-gear-notes"))
      assert notes =~ "сервер насчитал 4 куска"
      assert notes =~ "записано одним набором"

      refute has_element?(view, "#game-log-import-gear-unresolved")
    end

    test "Брунна: крафтовые вещи по шапке и поимённо", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("brunna"))

      named = render(element(view, "#game-log-import-gear-applied-named-items"))
      assert named =~ "6"
      assert named =~ "Серебряное кольцо с изумрудом"

      assert render(element(view, "#game-log-import-gear-applied-hands")) =~ "Magic staff"
      refute has_element?(view, "#game-log-import-gear-notes")
    end
  end

  describe "поглощение стихий — задача 3.211" do
    # Хнюпиус (кейс `AV1`): на мече `Damage Resistance (Fire) 15` и
    # `(Cold) 15` — обе строки лога видны в «применено», по одной на
    # прочитанную строку (не по одной на стихию).
    test "Хнюпиус: Fire 15 и Cold 15 видны в «применено»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("hnyupius"))

      resistances = render(element(view, "#game-log-import-gear-applied-resistances"))
      assert resistances =~ "Fire 15"
      assert resistances =~ "Cold 15"

      # 3.215: одна строка через запятую; без знака `+` у числа граница
      # между «15» и «Fire» держалась бы только на пробеле.
      assert resistances =~ "Cold 15, Fire 15"
      refute resistances =~ "не вошла"
    end

    # Физическое поглощение — «решением не считаем», и с задачи 3.211 причина
    # видна В САМОЙ СТРОКЕ «не наше», а не только в данных ядра
    # (`gear_import_engine_test.exs` уже проверяет `report.not_ours` — здесь
    # проверяется, что веб-слой её действительно показывает).
    test "Брунна: физическое поглощение в «не наше» с причиной решения", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("brunna"))

      not_ours = render(element(view, "#game-log-import-gear-not-ours"))
      assert not_ours =~ "Damage Resistance (Bludgeoning)"
      assert not_ours =~ "поглощение физического урона не считаем"
    end

    # Мокси: божественный урон — «не наша механика», ДРУГОЙ фразой, чем
    # физическое поглощение (не наше решение — просто игра его не поглощает).
    test "Мокси: божественный урон — «не наша механика», а не решение", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("moxie"))

      not_ours = render(element(view, "#game-log-import-gear-not-ours"))
      assert not_ours =~ "Damage Resistance (Divine)"
      assert not_ours =~ "не наша механика (divine)"
    end

    # Сквозная проверка: применённое число доезжает до «Вещей» конструктора
    # И до итогов панели, ровно теми числами, что называет кейс `AV1`
    # (Dan 18.09.2026): «У Хнюпиуса действительно 45 от огня и 30 от всего
    # остального».
    test "Хнюпиус: применено в «Вещи», и итог сходится с замером AV1 — Fire 45, Cold 30", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture_plus("hnyupius"))
      view |> element("#game-log-import-apply") |> render_click()

      view |> element("#gear-toggle") |> render_click()
      assert render(element(view, "#gear-resist-input-fire")) =~ ~s(value="15")
      assert render(element(view, "#gear-resist-input-cold")) =~ ~s(value="15")

      fire = render(element(view, "#stat-resist-fire")) |> LazyHTML.from_fragment()
      assert fire |> LazyHTML.query(".v") |> LazyHTML.text() |> String.trim() == "45"

      cold = render(element(view, "#stat-resist-cold")) |> LazyHTML.from_fragment()
      assert cold |> LazyHTML.query(".v") |> LazyHTML.text() |> String.trim() == "30"
    end
  end

  # Задача 3.213, п. 2 постановки: на всех четырёх поставляемых логах причина
  # `GearImport.worn_reason()` — `nil` (§: базу третье поколение печатает
  # всегда), и путь с оговоркой проверяется inline-фрагментом старого
  # формата — тем же приёмом, каким `game_log_equipment_test.exs` держит
  # живой формы прежних поколений, не файлами.
  describe "доспех без [BaseAC] — старая форма печати, оговорка через gettext" do
    # Тот же минимальный `.билд+`, каким `game_log_equipment_test.exs`
    # держит живыми формы прежних поколений печати.
    @minimal """
    [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] Command detected: .билд+
    ------------------------------------------------
        CHARACTER BUILD: Тест
        Current: 1 FTR
    ------------------------------------------------

    CURRENT ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
    COMBAT STATS: AB 1 AC 10 Fort 2 Refl 1 Will 1
    SKILLS WITH RANKS:
      Discipline 4

    (WHITE) ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
    RACE: Human

    ------------------------------------------------
    LEVEL 1: FIGHTER
      FEATS: Toughness
    ------------------------------------------------

    [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] Build sent to! Тест
    [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] === Equipped: Тест ===
    """

    test "предмет надет, а [BaseAC] лог не печатает — строка есть, с оговоркой по-русски",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      text = @minimal <> "[CHEST] Нагрудник Призрака\n  [1] AC Bonus (0) 6\n"

      view |> element("#game-log-import-button") |> render_click()
      paste(view, text)

      worn = render(element(view, "#game-log-import-gear-applied-worn"))
      assert worn =~ "Нагрудник Призрака"
      assert worn =~ "<em"

      # Не английский msgid и не сырой тапл — переведённая строка, и она
      # называет ИМЕННО эту причину (старый лог), а не «доспеха нет».
      assert worn =~ "не печатает"
      refute worn =~ "armour"
      refute worn =~ "{:armor_base_not_printed"
    end
  end
end
