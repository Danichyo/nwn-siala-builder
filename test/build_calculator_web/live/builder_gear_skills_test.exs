defmodule BuildCalculatorWeb.BuilderGearSkillsTest do
  @moduledoc """
  Прибавки к навыкам с вещей в конструкторе — задача 3.20: показ **и ввод**.

  ⚠️ До интерфейсного захода ядро считало прибавку, а вписать её можно было
  только руками собранной ссылкой: фича существовала в расчёте и была
  недостижима из интерфейса. Здесь обе половины — что вписанное видно и доезжает
  до значения навыка, и что вписать его можно в блоке.

  ⚠️ И это не «тест ради теста»: ветка разметки под прибавки рендерится только
  когда прибавка есть, а `Phoenix.LiveViewTest` — единственное, что вообще
  проходит по ней. Ассайн, который никто не отрисовал, ломается молча.

  Файл отдельный, а не дописан в `builder_live_test.exs`: тот огромный и его
  правят соседние задачи.
  """

  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.{Build, Gear}

  setup do
    ruleset = Data.ruleset!("siala_41")

    %Build{} =
      build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:fighter, 10),
        base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
        skills: %{1 => %{discipline: 4}}
      )

    %{ruleset: ruleset, build: build}
  end

  defp typed(%Build{} = build, skills), do: %Build{build | gear: Gear.new(skills: skills)}

  defp open_gear(view) do
    view |> element("#gear-toggle") |> render_click()
    view
  end

  defp put_number(view, skill, value) do
    view |> element("#gear-skills-form") |> render_change(%{"skill" => %{skill => value}})
    view
  end

  describe "показ вписанного" do
    test "вписанная прибавка стоит в своём поле", %{conn: conn, build: build} do
      code = Encoding.encode(typed(build, %{discipline: 50}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      assert has_element?(view, "#gear-skill-list")
      row = render(element(view, "#gear-skill-discipline"))
      assert row =~ "Discipline"
      assert has_element?(view, ~s(#gear-skill-input-discipline[value="50"]))
    end

    test "свёрнутая сводка называет навык и число, а не «не задано»", %{
      conn: conn,
      build: build
    } do
      code = Encoding.encode(typed(build, %{discipline: 50}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      summary = render(element(view, "#gear-summary"))

      refute summary =~ "не задано"
      assert summary =~ "Discipline +50"
    end

    # Ради этого всё и делается: прибавка доезжает до значения навыка в панели
    # итогов. 4 ранга + STR 16 (+3) + 50 = 57.
    test "прибавка доезжает до значения навыка в панели итогов", %{conn: conn, build: build} do
      code = Encoding.encode(typed(build, %{discipline: 50}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      row = render(element(view, "#stat-skill-discipline"))

      assert row =~ "(57)"

      # и разбор называет прибавку своей строкой, а не сливает её с чужой
      assert row =~ "вещи"
    end
  end

  describe "блок на пустом билде" do
    # ⚠️ Раньше здесь стояло `refute has_element?(view, "#gear-skills")` — «без
    # прибавок секции нет вовсе». Это и была дыра: блока нет, значит вписать
    # первую прибавку нечем. Теперь блок есть всегда, а «не занимает экран»
    # держит отсутствие СПИСКА и формы: одна строка с кнопкой.
    test "блок есть, списка строк нет", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)

      assert has_element?(view, "#gear-skills")
      assert has_element?(view, "#gear-skill-add-toggle")
      refute has_element?(view, "#gear-skill-list")
      refute has_element?(view, "#gear-skills-form")
    end

    # Все 28 навыков сеткой на каждый билд — простыня (CLAUDE.md §6), поэтому
    # список за кнопкой.
    test "поиск появляется только по нажатию «+ добавить»", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)
      refute has_element?(view, "#gear-skill-search")

      view |> element("#gear-skill-add-toggle") |> render_click()
      assert has_element?(view, "#gear-skill-search")
      assert has_element?(view, "#gear-skill-chip-discipline")
    end
  end

  describe "добавить, набрать, снять" do
    # ⚠️ Строка появляется БЕЗ числа, и это не полумера: ноль — не прибавка, и
    # писать его в билд значило бы объявить надетым то, чего нет.
    test "чип открывает строку, но прибавки не выдумывает", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)
      view |> element("#gear-skill-add-toggle") |> render_click()
      view |> element("#gear-skill-chip-discipline") |> render_click()

      # ⚠️ Задача 3.63: поле пустое, а не с литеральным «0» — иначе на телефоне
      # первый набранный символ приписывается к чужой цифре («6» → «60»).
      # Раньше здесь стояло `assert ...[value="0"]`.
      input = render(element(view, "#gear-skill-input-discipline"))
      refute input =~ ~s(value=")
      assert input =~ ~s(placeholder="0")

      assert render(element(view, "#gear-summary")) =~ "не задано"
      # 4 ранга + STR 16 (+3), без прибавки
      assert render(element(view, "#stat-skill-discipline")) =~ "(7)"
    end

    test "набранное число доезжает до значения навыка", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)
      view |> element("#gear-skill-add-toggle") |> render_click()
      view |> element("#gear-skill-chip-discipline") |> render_click()
      put_number(view, "discipline", "50")

      assert render(element(view, "#stat-skill-discipline")) =~ "(57)"
      assert render(element(view, "#gear-summary")) =~ "Discipline +50"
    end

    # Штраф вводится минусом — так же, как у AC и характеристик.
    test "минус проходит", %{conn: conn, build: build} do
      code = Encoding.encode(typed(build, %{discipline: 50}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)
      put_number(view, "discipline", "-4")

      assert render(element(view, "#gear-summary")) =~ "Discipline -4"
      # 4 ранга + STR +3 − 4 = 3
      assert render(element(view, "#stat-skill-discipline")) =~ "(3)"
    end

    # ⚠️ Строка НЕ исчезает от нуля: игрок стирает число, чтобы набрать другое,
    # и поле, пропавшее под пальцами, — поломка. В билде при этом ноля нет.
    test "обнулённая строка остаётся, а прибавка уходит", %{conn: conn, build: build} do
      code = Encoding.encode(typed(build, %{discipline: 50}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)
      put_number(view, "discipline", "0")

      assert has_element?(view, "#gear-skill-input-discipline")
      assert render(element(view, "#gear-summary")) =~ "не задано"
      assert render(element(view, "#stat-skill-discipline")) =~ "(7)"
    end

    test "«×» убирает и строку, и прибавку", %{conn: conn, build: build} do
      code = Encoding.encode(typed(build, %{discipline: 50}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)
      view |> element("#gear-skill-drop-discipline") |> render_click()

      refute has_element?(view, "#gear-skill-discipline")
      assert render(element(view, "#gear-summary")) =~ "не задано"
      assert render(element(view, "#stat-skill-discipline")) =~ "(7)"
    end

    # Вписанное из интерфейса переживает шаринг ссылкой само (уровень `0`
    # в таблице навыков кода) — кодек под это не правился.
    test "вписанное переживает ссылку", %{conn: conn, build: build} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)
      view |> element("#gear-skill-add-toggle") |> render_click()
      view |> element("#gear-skill-chip-discipline") |> render_click()
      put_number(view, "discipline", "50")

      path = assert_patch(view)
      {:ok, shared, _html} = live(conn, path)

      assert render(element(shared, "#stat-skill-discipline")) =~ "(57)"
      open_gear(shared)
      assert has_element?(shared, ~s(#gear-skill-input-discipline[value="50"]))
    end
  end

  describe "потолок называет себя" do
    test "введено больше потолка", %{conn: conn, build: build} do
      code = Encoding.encode(typed(build, %{discipline: 60}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      assert has_element?(view, "#gear-skills-capped")
      text = render(element(view, "#gear-skill-capped-discipline"))
      assert text =~ "Discipline"
      assert text =~ "больше потолка"
      assert text =~ "+50"
    end

    # ⚠️ Вторая половина подписи, как у сейвов со Spellcraft: потолок +50 общий
    # с бонусами Сиалы, поэтому срезать может и при вводе МЕНЬШЕ потолка.
    # Подпись обязана назвать второй источник, иначе объясняет срез не тем.
    #
    # Чистый воин 40-го уровня — человек, у него расовая прибавка к Discipline
    # (задача 3.12; ниже 40-го её нет вовсе). Число бонуса тест не называет:
    # оно из данных, и дублировать его здесь значило бы завести игровое число
    # в тесте веб-слоя.
    #
    # ⚠️ Источников в пуле СТАЛО ДВА (задача 3.35): расовый бонус и бонус за ТИП
    # оружия в руках. Здесь в руках клинок — он даёт щитовой AC, а не Дисциплину,
    # то есть срез устраивает по-прежнему расовый бонус в одиночку; парный кейс
    # с древковым оружием — сразу ниже, и без него подпись «бонусами Сиалы»
    # зеленела бы у кода, который по-прежнему видит только расовый.
    test "срезал общий кап вместе с бонусами Сиалы", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 40),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          skills: %{1 => %{discipline: 4}},
          # ⚠️ Меч в руках — условие расового бонуса (замер Dan 15.08.2026):
          # без него срезать было бы нечего, и кейс проверял бы отсутствие
          # подписи вместо её текста.
          gear:
            Gear.new(
              skills: %{discipline: 45},
              weapon: :longsword,
              feats: [:siala_blade_proficiency]
            )
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)

      text = render(element(view, "#gear-skill-capped-discipline"))
      assert text =~ "бонусами Сиалы"
      assert text =~ "+50"
    end

    # 🔴 Парный кейс: тот же билд БЕЗ расовой прибавки к Дисциплине (тёмный эльф
    # её не имеет) и с ДРЕВКОВЫМ оружием в руках. Срез теперь устраивает бонус за
    # тип оружия в одиночку — и подпись обязана его учесть, а не сказать
    # «введено больше потолка», обвинив введённое игроком число.
    test "срезал общий кап вместе с бонусом за тип оружия", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 40),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          skills: %{1 => %{discipline: 4}},
          gear:
            Gear.new(
              skills: %{discipline: 45},
              weapon: :spear,
              feats: [:siala_polearm_proficiency]
            )
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      open_gear(view)

      text = render(element(view, "#gear-skill-capped-discipline"))
      assert text =~ "бонусами Сиалы"
      assert text =~ "+50"
    end

    # Отрицательный контроль к обоим: под потолком подписи нет вовсе.
    test "под потолком подписи нет", %{conn: conn, build: build} do
      code = Encoding.encode(typed(build, %{discipline: 20}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      refute has_element?(view, "#gear-skills-capped")
      assert has_element?(view, "#gear-skill-discipline")
    end
  end

  describe "формы не стирают чужое" do
    # ⚠️ Правка любого другого поля блока НЕ должна стирать вписанные прибавки:
    # полей под них в общей форме нет, а `phx-change` переписывает весь набор.
    # Ровно на этом фиты с вещи (3.3) молча терялись от первого нажатия в CON.
    test "правка поля характеристик не стирает прибавки к навыкам", %{
      conn: conn,
      build: build
    } do
      code = Encoding.encode(typed(build, %{discipline: 50}))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      open_gear(view)

      view
      |> element("#gear-form")
      |> render_change(%{"ability" => %{"con" => "4"}, "ac" => %{}, "saves" => "0"})

      assert has_element?(view, "#gear-skill-discipline")
      assert render(element(view, "#stat-skill-discipline")) =~ "(57)"
    end

    # И обратная сторона той же ошибки: у навыков своя форма, и она не имеет
    # права стереть объявленный фит или введённые числа.
    test "правка поля навыка не стирает ни фит с вещи, ни характеристики", %{
      conn: conn,
      build: %Build{} = build
    } do
      geared = %Build{
        build
        | gear: Gear.new(skills: %{discipline: 50}, feats: [:toughness], abilities: %{con: 4})
      }

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(geared)}")

      open_gear(view)
      put_number(view, "discipline", "30")

      assert has_element?(view, "#gear-feat-toughness")
      assert render(element(view, "#stat-hp")) =~ "Toughness"
      assert has_element?(view, ~s(#gear-ability-input-con[value="4"]))
    end
  end
end
