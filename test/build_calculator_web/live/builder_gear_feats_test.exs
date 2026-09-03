defmodule BuildCalculatorWeb.BuilderGearFeatsTest do
  @moduledoc """
  Фиты с вещи в конструкторе — задача 3.3: показ **и выбор**.

  ⚠️ До интерфейсного захода ядро считало прибавки, а единственным способом
  объявить фит была руками собранная ссылка: фича существовала в расчёте и была
  недостижима из интерфейса. Здесь проверяется обе половины — что объявленное
  видно (без этого ссылка применяет прибавки, которых нигде нет на экране) и что
  объявить его можно кликом.

  Файл отдельный, а не дописан в `builder_live_test.exs`: тот на 200+ КБ и его
  правят соседние задачи.
  """

  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.{Build, Gear}

  # 11 уровней, значит активный — 12-й, а это уровень общего слота фита (3, 6, 9,
  # 12 …). Нужно ровно для двух тестов, где секция фитов сцены участвует как
  # ВТОРАЯ половина утверждения: на уровне без слотов её поиска нет вовсе, и
  # «в секции фитов не предлагается» не значило бы там ничего.
  setup do
    ruleset = Data.ruleset!("siala_41")

    %Build{} =
      build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:wizard, 11),
        base_abilities: %{str: 10, dex: 12, con: 14, int: 16, wis: 10, cha: 8}
      )

    %{ruleset: ruleset, build: build}
  end

  defp declared(%Build{} = build, feats), do: %Build{build | gear: Gear.new(feats: feats)}

  defp open_gear(view) do
    view |> element("#gear-toggle") |> render_click()
    view
  end

  defp open_picker(view) do
    view |> open_gear() |> element("#gear-feat-add-toggle") |> render_click()
    view
  end

  defp search(view, query) do
    view |> element("#gear-feat-search-form") |> render_change(%{"q" => query})
    view
  end

  describe "показ объявленного" do
    test "объявленные фиты названы поимённо", %{conn: conn, build: build} do
      code = Encoding.encode(declared(build, [:toughness, :alertness]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      assert has_element?(view, "#gear-feat-list")
      assert render(element(view, "#gear-feat-toughness")) =~ "Toughness"
      assert render(element(view, "#gear-feat-alertness")) =~ "Alertness"
    end

    test "свёрнутая сводка блока не говорит «не задано», когда объявление есть", %{
      conn: conn,
      build: build
    } do
      code = Encoding.encode(declared(build, [:toughness]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      refute render(element(view, "#gear-summary")) =~ "не задано"
    end

    # Прибавка объявленного фита доезжает до панели итогов и названа там своим
    # именем — то же требование, что у любого другого слагаемого.
    test "прибавка названа в разборе HP", %{conn: conn, build: build} do
      code = Encoding.encode(declared(build, [:toughness]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      assert render(element(view, "#stat-hp")) =~ "Toughness"
    end

    # 🔴 Задача 3.97, заход 1: запись объявления бывает парой `{feat_id, choice}`,
    # и показ значения — заход 2. Здесь проверяется ровно то, что заход 1 обещал:
    # страница от такой записи не ломается и фит с неё виден. До правки
    # `gear_feat_rows/2` отдал бы кортеж в `to_string/1` и уронил бы страницу —
    # а до 3.97 такая ссылка открывалась (декодер значение срезал), то есть без
    # этой защиты заход 1 был бы регрессом на правленой руками ссылке.
    #
    # ⚠️ Утверждение выбрано так, чтобы пережить заход 2: «строка есть и названа
    # именем фита» останется правдой и когда рядом появится значение.
    test "объявление со значением показывается и не роняет страницу", %{
      conn: conn,
      build: build
    } do
      code = Encoding.encode(declared(build, [{:skill_focus, :discipline}]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      assert render(element(view, "#gear-feat-skill_focus")) =~ "Skill focus"

      # Свёрнутая сводка считает пару ОДНИМ объявлением, а не двумя и не нулём.
      assert render(element(view, "#gear-summary")) =~ "фиты: 1"
    end

    # Ссылка, выпущенная до того, как шард отключил фит, показывается с причиной,
    # а не молча (`Rules.illegal_gear_feats/2`).
    test "отключённый шардом фит показан с причиной", %{conn: conn, build: build} do
      code = Encoding.encode(declared(build, [:devastating_critical]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      assert has_element?(view, "#gear-feat-bad-devastating_critical")
    end
  end

  # AGENT_QUEUE.md 3.53: the same `game_icon/1` component that already fills
  # the feat list and the level-up slot chips (3.50, 3.54) — 3.50 left this
  # block out on purpose, calling it "cheap to add later with the same
  # component if wanted". Both surfaces get it: the declared list (what is
  # already worn) and the picker (what could be worn next).
  describe "иконка у фита с вещи — задача 3.53" do
    test "объявленный фит с артом показывает его, а без арта — запасной глиф", %{
      conn: conn,
      build: build
    } do
      code = Encoding.encode(declared(build, [:toughness, :weapon_focus]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      assert has_element?(view, "#gear-feat-toughness .game-icon img")
      refute has_element?(view, "#gear-feat-toughness .game-icon i")

      # `weapon_focus` — один из 23 фитов без арта на Fandom (3.50), не дыра
      # в данных: запасной вариант тот же ✦/★, что и везде, где он есть.
      refute has_element?(view, "#gear-feat-weapon_focus .game-icon img")
      assert has_element?(view, "#gear-feat-weapon_focus .game-icon i")
    end

    test "то же в поиске: у строки с артом — картинка, без арта — глиф", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("toughn")
      assert has_element?(view, "#gear-pick-toughness .game-icon img")

      search(view, "weapon focus")
      refute has_element?(view, "#gear-pick-weapon_focus .game-icon img")
      assert has_element?(view, "#gear-pick-weapon_focus .game-icon i")
    end
  end

  describe "блок на пустом билде" do
    # ⚠️ Раньше здесь стояло `refute has_element?(view, "#gear-feats")` — «без
    # объявлений секции нет вовсе». Это и была дыра: блока нет, значит объявить
    # первый фит нечем. Теперь блок есть всегда, а «не занимает экран» держит
    # отсутствие СПИСКА: одна строка с кнопкой вместо пустой рамки со списком.
    test "блок есть, списка строк нет", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)

      assert has_element?(view, "#gear-feats")
      assert has_element?(view, "#gear-feat-add-toggle")
      refute has_element?(view, "#gear-feat-list")
      assert render(element(view, "#gear-summary")) =~ "не задано"
    end

    # Поиск и выдача — за кнопкой, а не на экране всегда: словарь фитов в сотни
    # строк в узкой колонке (и в мобильной шторке) не читается.
    test "поиск появляется только по нажатию «+ добавить»", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)
      refute has_element?(view, "#gear-feat-search")

      view |> element("#gear-feat-add-toggle") |> render_click()
      assert has_element?(view, "#gear-feat-search")
      assert has_element?(view, "#gear-feat-options")
    end
  end

  describe "добавить и снять" do
    test "фит добавляется кликом и прибавка доезжает до HP", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      refute render(element(view, "#stat-hp")) =~ "Toughness"
      refute has_element?(view, "#gear-cascade-hp")

      view |> open_picker() |> search("toughn")
      assert has_element?(view, "#gear-pick-toughness")

      view |> element("#gear-pick-toughness") |> render_click()

      assert has_element?(view, "#gear-feat-toughness")
      assert render(element(view, "#stat-hp")) =~ "Toughness"

      # и число сдвинулось: каскад «было → стало» строит разность двух полных
      # `Rules.compute`, поэтому его строка появляется только если HP изменились
      assert has_element?(view, "#gear-cascade-hp")

      # ⚠️ И поиск остался открыт с набранным запросом: добавление правит билд,
      # то есть идёт через `push_patch`, а тот возвращается в `handle_params`.
      # Стоило бы забыванию состояния блока попасть в общую воронку правок —
      # и список захлопывался бы после КАЖДОГО добавления.
      assert has_element?(view, ~s(#gear-feat-search[value="toughn"]))
      assert has_element?(view, "#gear-pick-toughness")
    end

    test "фит снимается кликом по «×» у своей строки", %{conn: conn, build: build} do
      code = Encoding.encode(declared(build, [:toughness]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)
      assert has_element?(view, "#gear-feat-toughness")

      view |> element("#gear-feat-drop-toughness") |> render_click()

      refute has_element?(view, "#gear-feat-toughness")
      refute render(element(view, "#stat-hp")) =~ "Toughness"
    end

    # ⚠️ Снятие обязано работать и у объявления, которое ядро отбивает: иначе
    # билд из ссылки, выпущенной до отключения фита шардом, нечем починить.
    test "снимается и отбитое ядром объявление", %{conn: conn, build: build} do
      code = Encoding.encode(declared(build, [:devastating_critical]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)
      assert has_element?(view, "#gear-feat-devastating_critical")

      view |> element("#gear-feat-drop-devastating_critical") |> render_click()

      refute has_element?(view, "#gear-feat-devastating_critical")
    end

    # Ради этого фича и нужна: добавленное из интерфейса переживает шаринг
    # ссылкой само, кодек под это не правился (псевдо-слот `"gear"`, уровень 0).
    test "добавленное переживает ссылку", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("alertn")
      view |> element("#gear-pick-alertness") |> render_click()

      path = assert_patch(view)
      {:ok, shared, _html} = live(conn, path)

      open_gear(shared)
      assert has_element?(shared, "#gear-feat-alertness")
    end
  end

  describe "пул — не то же, что принимает слот" do
    # ⚠️ Самое наглядное место всей задачи. `Riding Sprint` не берётся при росте
    # персонажа НИ ОДНИМ слотом (`{:not_selectable_at_level_up, …}`) и приходит
    # только с предмета — значит в этом блоке он обязан предлагаться. Пул,
    # собранный фильтром «что примет слот», был бы неверен ровно на нём.
    test "фит, который слотом не берётся вовсе, здесь предлагается", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("riding")

      assert has_element?(view, "#gear-pick-riding_sprint")
      refute has_element?(view, "#gear-pick-riding_sprint[disabled]")

      view |> element("#gear-pick-riding_sprint") |> render_click()
      assert has_element?(view, "#gear-feat-riding_sprint")
    end

    # Положительный контроль к предыдущему: тот же фит в секции фитов сцены
    # стоит в НЕДОСТУПНЫХ. Без этой половины «предлагается в вещах» ничего не
    # доказывает — может, он и слотом берётся.
    test "тот же фит в секции фитов недоступен", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#feat-search-form") |> render_change(%{"q" => "riding sprint"})

      assert has_element?(view, "#feat-no-riding_sprint")
      refute has_element?(view, "#feat-ok-riding_sprint")
    end

    # Отключённое шардом не прячем, а показываем с причиной (CLAUDE.md §6), и
    # клик по нему ничего не добавляет.
    test "отключённый шардом фит виден с причиной и не добавляется", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("devastating")

      row = render(element(view, "#gear-pick-devastating_critical"))
      assert row =~ "отключён"
      assert has_element?(view, "#gear-pick-devastating_critical[disabled]")
      refute has_element?(view, "#gear-feat-devastating_critical")
    end
  end

  describe "поиск" do
    # Тот же нечёткий поиск, что в секции фитов (`Builder.Fuzzy`), а не второй
    # свой: `pwatk` находит Power Attack.
    test "обрывки находят фит", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("pwatk")

      assert has_element?(view, "#gear-pick-power_attack")
    end

    # Русское написание — поисковый алиас, а не название (CLAUDE.md §4), и строка
    # объясняет, почему она нашлась по кириллице.
    test "русский алиас находит и объясняет себя", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("живуч")

      row = render(element(view, "#gear-pick-toughness"))
      assert row =~ "Toughness"
      assert row =~ "Живучесть"
    end

    test "хвост выдачи назван числом, а не обрезан молча", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker()

      # без запроса словарь заведомо длиннее выдачи
      assert has_element?(view, "#gear-feat-more")

      # а точный запрос хвост убирает
      search(view, "toughness")
      refute has_element?(view, "#gear-feat-more")
    end

    test "запрос, под который ничего нет, говорит об этом", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("zzzqqq")

      assert has_element?(view, "#gear-feat-none")
      refute has_element?(view, "#gear-feat-more")
    end

    # ⚠️ Выдача — стрим, а стрим сам ничего не убирает: без `reset: true` строки
    # прошлого запроса остаются в DOM, и уточнённый поиск показывает то, что ему
    # уже не подходит. Проверяется именно СУЖЕНИЕМ, а не первым показом — на
    # первом показе разницы не видно вовсе.
    test "уточнённый запрос убирает чужие строки", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("toughn")
      assert has_element?(view, "#gear-pick-toughness")

      search(view, "alertn")
      assert has_element?(view, "#gear-pick-alertness")
      refute has_element?(view, "#gear-pick-toughness")
    end

    # И вторая половина того же: контейнер, убранный из DOM и вернувшийся,
    # обязан снова быть полным.
    test "выдача возвращается после свернуть → развернуть", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("toughn")
      assert has_element?(view, "#gear-pick-toughness")

      view |> element("#gear-feat-add-toggle") |> render_click()
      refute has_element?(view, "#gear-pick-toughness")

      view |> element("#gear-feat-add-toggle") |> render_click()
      assert has_element?(view, "#gear-pick-toughness")
    end
  end

  # Открытый поиск и набранный запрос принадлежат билду, который на экране: у
  # другого билда они не объясняют ничего. Ссылка заменяет билд целиком.
  test "поиск закрывается, когда билд пришёл по ссылке", %{conn: conn, build: build} do
    {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

    view |> open_picker() |> search("toughn")
    assert has_element?(view, "#gear-feat-search")

    other = Encoding.encode(declared(build, [:alertness]))
    render_patch(view, ~p"/?b=#{other}")

    # блок остаётся раскрытым — сам он состояние не билда, а экрана
    refute has_element?(view, "#gear-feat-search")
    assert has_element?(view, "#gear-feat-alertness")
  end

  # ⚠️ Оговорка у слота (задача 3.3, правка 09.08.2026): фит уже есть с вещи,
  # слот его не усилит — не отказ, а строка рядом. До этой задачи такое
  # состояние игрок не мог создать сам, теперь может, и текст обязан читаться
  # верно именно в этом случае.
  test "фит, надетый из блока «Вещи», получает оговорку в секции фитов", %{
    conn: conn,
    build: build
  } do
    {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

    view |> element("#feat-search-form") |> render_change(%{"q" => "alertness"})
    refute has_element?(view, "#feat-gear-alertness")

    view |> open_picker() |> search("alertn")
    view |> element("#gear-pick-alertness") |> render_click()

    view |> element("#feat-search-form") |> render_change(%{"q" => "alertness"})

    caveat = render(element(view, "#feat-gear-alertness"))
    assert caveat =~ "уже есть с вещи"

    # и строка осталась кнопкой: предмет снимается, слот нет
    assert has_element?(view, "#feat-ok-alertness")
  end

  # Задача 3.97, заход 2: второй шаг у фита с вещи, который берётся С
  # ЗНАЧЕНИЕМ. Ядро (заход 1) уже умеет всё, здесь проверяется только то, что
  # интерфейс это показывает и позволяет выбрать.
  describe "второй шаг: значение фита с вещи" do
    test "объявление без значения ждёт выбора и несёт оговорку в пробелах", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("skill focus")
      refute has_element?(view, "#gear-pick-epic_skill_focus[disabled]")
      view |> element("#gear-pick-skill_focus") |> render_click()

      assert has_element?(view, "#gear-feat-skill_focus")
      assert has_element?(view, "#gear-feat-pending-skill_focus")
      assert has_element?(view, "#gear-feat-choice-skill_focus-discipline")
      assert has_element?(view, "#gear-feat-choice-skill_focus-spot")

      view |> element("#gaps-toggle") |> render_click()

      assert render(element(view, "#gaps-body")) =~
               "с чем именно он взят, вещь не говорит"
    end

    test "выбор значения записывает пару, снимает голую запись и доезжает до значения навыка",
         %{conn: conn, build: %Build{} = build} do
      build = %Build{build | skills: %{1 => %{discipline: 4}}}
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert render(element(view, "#stat-skill-discipline")) =~ "(4)"

      view |> open_picker() |> search("skill focus")
      view |> element("#gear-pick-skill_focus") |> render_click()
      view |> element("#gear-feat-choice-skill_focus-discipline") |> render_click()

      refute has_element?(view, "#gear-feat-pending-skill_focus")
      assert render(element(view, "#gear-feat-entry-skill_focus-discipline")) =~ "Discipline"

      # +3 от Skill focus: 4 ранга + 3 = 7 (задача 3.92, тот же расчёт для
      # вещи, что и для слота).
      assert render(element(view, "#stat-skill-discipline")) =~ "(7)"

      view |> element("#gaps-toggle") |> render_click()

      refute render(element(view, "#gaps-body")) =~
               "с чем именно он взят, вещь не говорит"
    end

    # Решение Дана: «разные значения — разные записи». Список объявленного —
    # список пар, а не чипов по id, и повтор фита в нём законен.
    test "один фит объявляется дважды с разными значениями — обе записи видны и обе считаются",
         %{conn: conn, build: build} do
      code = Encoding.encode(declared(build, [{:skill_focus, :discipline}]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)
      assert render(element(view, "#gear-feat-entry-skill_focus-discipline")) =~ "Discipline"

      # Тот же фит снова — с добавляющего списка, второй записью: Discipline
      # уже занята ЭТИМ ЖЕ фитом и не предлагается снова, Spot — свободен.
      # ⚠️ Панель «Вещи» уже открыта строкой выше — `open_picker/1` сама
      # открывает её (и снова закрыла бы уже открытую), поэтому здесь только
      # его вторая половина.
      view |> element("#gear-feat-add-toggle") |> render_click()
      search(view, "skill focus")
      view |> element("#gear-pick-skill_focus") |> render_click()
      refute has_element?(view, "#gear-feat-choice-skill_focus-discipline")
      view |> element("#gear-feat-choice-skill_focus-spot") |> render_click()

      assert render(element(view, "#gear-feat-entry-skill_focus-discipline")) =~ "Discipline"
      assert render(element(view, "#gear-feat-entry-skill_focus-spot")) =~ "Spot"

      # Сводка считает пары, а не имена: два объявления, а не одно.
      assert render(element(view, "#gear-summary")) =~ "фиты: 2"
    end

    test "снятие одной записи не трогает соседнюю запись того же фита", %{
      conn: conn,
      build: build
    } do
      code =
        Encoding.encode(declared(build, [{:skill_focus, :discipline}, {:skill_focus, :spot}]))

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      open_gear(view)

      view |> element("#gear-feat-drop-skill_focus-discipline") |> render_click()

      refute has_element?(view, "#gear-feat-entry-skill_focus-discipline")
      assert has_element?(view, "#gear-feat-entry-skill_focus-spot")

      # Строка фита осталась: у него ещё есть живая запись.
      assert has_element?(view, "#gear-feat-skill_focus")
    end

    # Старая ссылка несёт голый id (см. заход 1) — она обязана открыться и
    # предложить довыбрать значение, а не отказаться его показывать.
    test "старая ссылка без значения открывается и предлагает довыбрать", %{
      conn: conn,
      build: build
    } do
      code = Encoding.encode(declared(build, [:weapon_focus]))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      assert has_element?(view, "#gear-feat-weapon_focus")
      assert has_element?(view, "#gear-feat-pending-weapon_focus")
    end

    # Кейс Z1, 25.08.2026 (Dan): «подобные вещи бывают, бывают даже с epic
    # spell focus. Для такого фита с вещи нам не нужно требовать предыдущие
    # фиты на focus и greater focus». Волшебник без единого `Spell focus` —
    # все 8 школ обязаны быть предложены, а не сужены до пустого списка.
    test "Epic spell focus с вещи предлагает все 8 школ без базового Spell focus", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("epic spell focus")
      view |> element("#gear-pick-epic_spell_focus") |> render_click()

      values = render(element(view, "#gear-feat-choice-values-epic_spell_focus"))

      for school <- ~w(Evocation Abjuration Illusion Necromancy Conjuration Enchantment
                        Transmutation Divination) do
        assert values =~ school, "expected #{school} to be offered"
      end

      refute has_element?(view, "#gear-feat-choice-blocked-epic_spell_focus")
    end

    # Положительный контроль к предыдущему: тот же волшебник, тот же фит,
    # СЛОТОВЫЙ маршрут — там `same_choice_as` действует, и без `Spell focus`
    # список закрыт. Без этой половины «в вещах предлагается всё» ничего не
    # доказывает — может, и слотом тоже.
    test "тот же волшебник слотом получает Epic spell focus недоступным", %{
      conn: conn,
      build: build
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#feat-search-form") |> render_change(%{"q" => "epic spell focus"})

      assert has_element?(view, "#feat-no-epic_spell_focus")
      refute has_element?(view, "#feat-ok-epic_spell_focus")
    end

    # `epic_energy_resistance` — единственный фит с `distinct?: false`
    # (§ «Правила, которые здесь легко нарушить», п.3): ядро само НЕ мешает
    # повторить то же значение, но `Gear.feats` уникален по паре, и повторная
    # запись того же значения не добавит вторую копию, а сотрёт первую. Это
    # свойство ФОРМЫ ХРАНЕНИЯ, и веб обязан его показать причиной, а не
    # спрятать значение и не дать кнопке молча стереть уже объявленное.
    test "epic_energy_resistance: повтор значения показан с причиной, а не спрятан и не стирает",
         %{conn: conn, build: build} do
      code =
        Encoding.encode(
          declared(build, [{:epic_energy_resistance, :fire}, :epic_energy_resistance])
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      open_gear(view)

      assert has_element?(view, "#gear-feat-entry-epic_energy_resistance-fire")
      assert has_element?(view, "#gear-feat-pending-epic_energy_resistance")

      blocked = render(element(view, "#gear-feat-choice-blocked-epic_energy_resistance"))
      assert blocked =~ "Fire"
      refute has_element?(view, "#gear-feat-choice-epic_energy_resistance-fire")

      # А непересекающееся значение доступно и добавляет вторую прибавку,
      # не трогая первую.
      view |> element("#gear-feat-choice-epic_energy_resistance-cold") |> render_click()

      assert has_element?(view, "#gear-feat-entry-epic_energy_resistance-fire")
      assert has_element?(view, "#gear-feat-entry-epic_energy_resistance-cold")
    end

    test "поиск сужает список значений до совпадающих", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> open_picker() |> search("skill focus")
      view |> element("#gear-pick-skill_focus") |> render_click()

      assert has_element?(view, "#gear-feat-choice-skill_focus-spot")

      view
      |> element("#gear-feat-choice-search-form-skill_focus")
      |> render_change(%{"feat" => "skill_focus", "q" => "disc"})

      assert has_element?(view, "#gear-feat-choice-skill_focus-discipline")
      refute has_element?(view, "#gear-feat-choice-skill_focus-spot")
    end
  end
end
