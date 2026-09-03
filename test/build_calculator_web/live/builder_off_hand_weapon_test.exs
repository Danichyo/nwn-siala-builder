defmodule BuildCalculatorWeb.BuilderOffHandWeaponTest do
  @moduledoc """
  Вторая рука в конструкторе — задача 3.132.

  Dan, 28.08.2026: «многие билды берут 2 оружия вместо щита или двуручки …
  Можем ввести вторую руку? с возможностью выбрать оружие вместо щита и его
  attack bonus». Значит проверять надо: что оружие второй руки можно
  ВЫБРАТЬ отдельно от главной, что оно даёт СВОЁ число AB (не подмешивается
  в главное), что щит и второе оружие исключают друг друга разными фразами,
  и что число атак второй руки — своя строка «Атак второй руки», а не хвост
  через слеш у «Атак / раунд» (задача 3.133, замечание 1 — Dan не разобрал
  старую слитую форму «4/1»).

  ⚠️ Форма файла — у `builder_gear_weapon_test.exs`, зеркалящего блок главной
  руки: тот же приём стрима, тот же путь клика через `element/2` по DOM-id
  (`Phoenix.LiveViewTest` не собирает параметры иначе, чем `phx-value-*`).
  """

  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  setup do
    ruleset = Data.ruleset!("siala_41")

    # Воин 20 с ОБОИМИ владениями (клинковым и молотами) в бонусных слотах —
    # без них ни катана, ни булава не предлагались бы вовсе, а задача не про
    # владение. STR 18 — то же число, которым уже проверено ядро
    # (`dual_wield_test.exs`), чтобы отчётные числа теста были сверяемы.
    %Build{} =
      build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:fighter, 20),
        base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
        feats: %{
          1 => %{
            :general => :siala_blade_proficiency,
            {:class_bonus, :fighter} => :siala_hammer_proficiency
          }
        },
        gear: Gear.new(weapon: :katana)
      )

    %{ruleset: ruleset, build: build}
  end

  defp open_gear(view) do
    view |> element("#gear-toggle") |> render_click()
    view
  end

  defp open_off_picker(view) do
    view |> open_gear() |> element("#gear-off-weapon-add-toggle") |> render_click()
    view
  end

  defp search_off(view, query) do
    view |> element("#gear-off-weapon-search-form") |> render_change(%{"q" => query})
    view
  end

  defp open(conn, build), do: live(conn, ~p"/?b=#{Encoding.encode(build)}")

  describe "выбор оружия второй руки" do
    test "клик по оружию кладёт его во ВТОРУЮ руку и не трогает главную", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, build)

      view |> open_off_picker() |> search_off("mace")

      assert has_element?(view, "#gear-off-weapon-mace")
      view |> element("#gear-off-weapon-mace") |> render_click()

      assert has_element?(view, "#gear-off-weapon-row-mace")
      assert render(element(view, "#gear-off-weapon-row-mace")) =~ "Mace"

      # Главная рука осталась катаной — обе руки независимы.
      assert has_element?(view, "#gear-weapon-row-katana")

      # Повторный клик снимает — тот же обработчик на «взять» и «снять».
      view |> element("#gear-off-weapon-mace") |> render_click()
      refute has_element?(view, "#gear-off-weapon-row-mace")
    end

    test "кнопка «снять» убирает оружие второй руки, число остаётся", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      gear = %Gear{base_gear | off_hand_weapon: :mace, off_hand_weapon_attack: 2}
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)
      assert has_element?(view, "#gear-off-weapon-row-mace")

      view |> element("#gear-off-weapon-drop") |> render_click()
      refute has_element?(view, "#gear-off-weapon-row-mace")

      assert render(element(view, "#gear-off-weapon-attack-input")) =~ ~s(value="2")
    end

    test "список фильтруется фитами владения так же, как у главной руки", %{
      conn: conn,
      ruleset: ruleset
    } do
      without_hammer =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :siala_blade_proficiency}},
          gear: Gear.new(weapon: :katana)
        )

      {:ok, view, _html} = open(conn, without_hammer)
      view |> open_off_picker() |> search_off("mace")

      assert render(element(view, "#gear-off-weapon-mace")) =~ "Владение молотами"
      assert render(element(view, "#gear-off-weapon-mace")) =~ "disabled"
    end
  end

  describe "числа второй руки — своя строка AB, а не подмешаны в главную" do
    test "усиление второй руки поднимает СВОЮ строку в «Итого», а не главный AB", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, build)

      # До второго оружия строки «AB второй руки» нет вовсе — вторая рука
      # без оружия у персонажа не бывает (не «AB 0», а отсутствие строки).
      # Строка живёт в панели «Итого», не в блоке «Вещи» — открывать его
      # не нужно, чтобы её увидеть или не увидеть.
      refute has_element?(view, "#stat-off_hand_ab")

      before_main = render(element(view, "#stat-attack_bonus"))

      # ⚠️ `open_off_picker/1` сам открывает блок «Вещи» — второй вызов
      # `open_gear/1` здесь переключил бы его обратно в закрытое состояние.
      view |> open_off_picker() |> search_off("mace")
      view |> element("#gear-off-weapon-mace") |> render_click()

      # Главная рука не сдвинулась хотя бы от ПОЯВЛЕНИЯ второй...
      assert render(element(view, "#stat-attack_bonus")) != before_main

      # ...а сдвинулась именно потому, что появился штраф стиля — а не
      # потому, что усиление второй руки подмешалось в главное число.
      #
      # ⚠️ Задача 3.134: число уехало из `#gear-form` в свою форму рядом
      # с оружием второй руки (`#gear-off-weapon-attack-form`) — зеркало
      # правки главной руки, `phx-change="gear_off_weapon_attack"` читает
      # РОВНО `params["attack"]`, без вложенного ключа `weapon`.
      view
      |> element("#gear-off-weapon-attack-form")
      |> render_change(%{"attack" => "7"})

      assert has_element?(view, "#stat-off_hand_ab")
      assert render(element(view, "#stat-off_hand_ab")) =~ "AB второй руки"

      # 7 не попало в главную руку.
      refute render(element(view, "#stat-attack_bonus")) =~ "+37"
    end

    test "снятие оружия второй руки убирает строку «AB второй руки» из «Итого»", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      gear = %Gear{base_gear | off_hand_weapon: :mace}
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)
      assert has_element?(view, "#stat-off_hand_ab")

      view |> element("#gear-off-weapon-drop") |> render_click()
      refute has_element?(view, "#stat-off_hand_ab")
    end
  end

  # 🔴 Зеркало проверки из `builder_gear_weapon_test.exs` (задача 3.134):
  # AB второй руки переехал в свою форму рядом с самим оружием второй руки,
  # и до правки `handle_event("gear", …)` любая правка характеристики
  # стёрла бы его молча вместе с главной рукой — обе руки читались из
  # ОДНОГО общего `params["weapon"]`.
  describe "формы не стирают чужое (задача 3.134)" do
    test "правка характеристики в #gear-form не стирает AB второй руки", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      gear = %Gear{base_gear | off_hand_weapon: :mace, off_hand_weapon_attack: 7}
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)

      view
      |> element("#gear-form")
      |> render_change(%{"ability" => %{"str" => "4"}})

      assert render(element(view, "#gear-off-weapon-attack-input")) =~ ~s(value="7")
    end

    test "правка AB второй руки не стирает характеристики #gear-form", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      gear = %Gear{base_gear | off_hand_weapon: :mace, abilities: %{str: 4}}
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)

      view
      |> element("#gear-off-weapon-attack-form")
      |> render_change(%{"attack" => "7"})

      assert render(element(view, "#gear-ability-input-str")) =~ ~s(value="4")
    end
  end

  # 🔴 Задача 3.133 (замечание 1 к 3.132, Dan): «показывает 4/1, но в
  # реальности это 4 атаки основной рукой и одна атака второй» — слеш
  # подписи («Атак **/** раунд») и слеш значения («4**/**1») читались одним
  # и тем же способом и значили разное. Число второй руки больше не делит
  # значение слешем — у него своя строка, «Атак второй руки».
  describe "атаки второй руки — своя строка (задача 3.133)" do
    # ⚠️ Строка панели по-прежнему называется «Атак / раунд» — слеш остаётся
    # в САМОЙ ПОДПИСИ, поэтому проверять надо ЗНАЧЕНИЕ (`.v`), а не всю
    # строку: `render(element(...)) =~ "/"` зеленел бы и без правки вовсе,
    # потому что слеш и так печатается в лейбле.
    defp attacks_value(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#stat-attacks_per_round .v")
      |> LazyHTML.text()
      |> String.trim()
    end

    defp off_hand_attacks_value(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#stat-off_hand_apr .v")
      |> LazyHTML.text()
      |> String.trim()
    end

    test "«Атак / раунд» остаётся одним числом, «Атак второй руки» — своя строка", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      alone = %Build{build | gear: %Gear{base_gear | off_hand_weapon: nil}}
      {:ok, view, _html} = open(conn, alone)

      alone_stats = Rules.compute(alone, Data.ruleset!("siala_41"))
      refute attacks_value(view) =~ "/"
      assert attacks_value(view) == "#{alone_stats.attacks_per_round}"
      refute has_element?(view, "#stat-off_hand_apr")

      dual = %Build{build | gear: %Gear{base_gear | off_hand_weapon: :mace}}
      {:ok, view2, _html} = open(conn, dual)

      dual_stats = Rules.compute(dual, Data.ruleset!("siala_41"))

      # Главная рука по-прежнему без слеша и без второго числа внутри —
      # ровно то, чего Dan не увидел в старой форме.
      refute attacks_value(view2) =~ "/"
      assert attacks_value(view2) == "#{dual_stats.attacks_per_round}"

      assert has_element?(view2, "#stat-off_hand_apr")
      assert off_hand_attacks_value(view2) == "#{dual_stats.off_hand.attacks_per_round}"
    end
  end

  describe "взаимное исключение со щитом — фразы разные (задача 3.132)" do
    test "щит становится нелегальным, когда во второй руке оружие, и фраза своя", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      shielded = %Build{build | gear: %Gear{base_gear | worn: %{shield: :large}}}
      {:ok, view, _html} = open(conn, shielded)

      # Со щитом и без второго оружия — щит легален, строки претензии нет.
      # ⚠️ Открывать блок «Вещи» здесь ЕЩЁ не нужно: `#gear-worn-illegal-*`
      # живёт внутри него, а его отсутствие уже проверяет следующая строка —
      # `refute has_element?` истинен и на закрытом блоке, и это не то же
      # самое, что «претензии нет», поэтому блок открывается ниже, ОДИН раз,
      # через `open_off_picker/1` (второй `open_gear/1` здесь переключил бы
      # его обратно в закрытое состояние).
      view |> open_off_picker() |> search_off("mace")
      refute has_element?(view, "#gear-worn-illegal-shield-large")

      view |> element("#gear-off-weapon-mace") |> render_click()

      assert has_element?(view, "#gear-worn-illegal-shield-large")

      # ⚠️ Фраза читается у ядра (`Rules.Vocabulary`/`Labels.reason/2`) — не
      # придумана здесь. И это ДРУГАЯ фраза, чем у двуручного оружия
      # (следующий тест), а не общий текст на оба случая: субъект другой
      # («вторая рука» против «оружие занимает обе руки»).
      assert render(element(view, "#gear-worn-illegal-shield-large")) =~
               "Mace занимает вторую руку"

      refute render(element(view, "#gear-worn-illegal-shield-large")) =~ "занимает обе руки"
    end

    test "щит отказан ДВУРУЧНЫМ оружием другой фразой, чем вторым оружием", %{
      conn: conn,
      ruleset: ruleset
    } do
      two_handed =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :siala_blade_proficiency}},
          gear: Gear.new(weapon: :greatsword, worn: %{shield: :large})
        )

      {:ok, view, _html} = open(conn, two_handed)
      open_gear(view)

      assert has_element?(view, "#gear-worn-illegal-shield-large")

      assert render(element(view, "#gear-worn-illegal-shield-large")) =~
               "Greatsword занимает обе руки"

      refute render(element(view, "#gear-worn-illegal-shield-large")) =~ "занимает вторую руку"
    end

    # 🔴 Развязка бага «причина вешалась на главную руку»: у главной руки
    # катана легальна (владение есть), у второй — булава без владения
    # молотами. Список `Rules.illegal_gear_weapon/2` несёт ОДНУ запись
    # (только про булаву), и до правки `GearPanel` брал `List.first/1` без
    # разбора руки — здесь это дало бы главной руке чужой отказ.
    test "недоступность второй руки не приписывается главной", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :siala_blade_proficiency}},
          gear: Gear.new(weapon: :katana, off_hand_weapon: :mace)
        )

      {:ok, view, _html} = open(conn, build)
      open_gear(view)

      # Главная рука — без претензии вовсе.
      assert has_element?(view, "#gear-weapon-row-katana")
      refute has_element?(view, "#gear-weapon-bad")

      # Вторая — со своей, и претензия про молоты, а не про клинки.
      assert has_element?(view, "#gear-off-weapon-row-mace")
      assert render(element(view, "#gear-off-weapon-bad")) =~ "Владение молотами"
    end
  end

  describe "ссылка" do
    test "оружие второй руки и его число переживают шаринг", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      gear = %Gear{base_gear | off_hand_weapon: :mace, off_hand_weapon_attack: 2}
      code = Encoding.encode(%Build{build | gear: gear})

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      open_gear(view)

      assert has_element?(view, "#gear-off-weapon-row-mace")
      assert render(element(view, "#gear-off-weapon-attack-input")) =~ ~s(value="2")
    end

    test "«Сбросить вещи» убирает и вторую руку", %{
      conn: conn,
      build: %Build{gear: %Gear{} = base_gear} = build
    } do
      gear = %Gear{base_gear | off_hand_weapon: :mace, off_hand_weapon_attack: 2}
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)
      view |> element("#gear-clear") |> render_click()

      refute has_element?(view, "#gear-off-weapon-row-mace")
    end
  end
end
