defmodule BuildCalculatorWeb.VanillaBuildLiveTest do
  @moduledoc """
  Ванильный билд на конструкторе и экране просмотра — семь тестов, перенесённых
  задачей 4.2 из сиальских файлов БЕЗ правки ожиданий.

  До 4.2 сайт открывал ссылку с любым вкомпилированным ruleset'ом, и эти тесты
  рисовали ванильный билд на сиальском сайте. С 4.2 сайт — это редакция
  (`BuildCalculatorWeb.Edition`), и ссылку с чужим ruleset'ом встречает мостик
  (`edition_test.exs`): ванильный билд виден только ванильной редакцией. Сами
  тесты проверяют то же, что проверяли: разметку, которую решает ruleset
  (зоны «Вещей», поглощение, переключатель выданных фитов), а не сайт.

  Откуда взят каждый — у самого теста; на прежнем месте стоит указатель сюда.
  Там, где тест держался только на `refute`, добавлен положительный контроль
  на то, что проверяемый блок вообще открыт, — иначе `refute` на мостике
  вместо билда зеленел бы молча.

  ⚠️ `async: false` — `use_edition/1` меняет редакцию ПРИЛОЖЕНИЯ через
  `Application.put_env/3`; параллельный сосед в той же VM увидел бы чужой
  сайт (CLAUDE.md §7).
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculatorWeb.EditionHelpers

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.{Build, Gear}

  setup do
    use_edition(:vanilla)
  end

  # --- из `builder_named_items_test.exs` и `builder_mini_sets_test.exs` ---

  defp open_gear(conn, build) do
    {:ok, view, html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
    view |> element("#gear-toggle") |> render_click()
    {view, html}
  end

  # `builder_named_items_test.exs` → `fighter/2`: сиальский билд, которому
  # сменили ruleset на ванильный (сиальские записи вещей декодер выбросит).
  defp named_items_fighter do
    %Build{} =
      siala =
      Build.new(
        ruleset_version: "siala_41",
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 8},
        levels: List.duplicate(:fighter, 40),
        gear: Gear.new(named_items: 0, mini_sets: [])
      )

    %Build{siala | ruleset_version: "vanilla"}
  end

  # `builder_mini_sets_test.exs` → `elf([], false)`, тем же приёмом.
  defp mini_sets_elf do
    %Build{} =
      siala =
      Build.new(
        ruleset_version: "siala_41",
        race: :half_elf,
        alignment: :true_neutral,
        base_abilities: %{str: 16, dex: 14, con: 14, int: 12, wis: 12, cha: 10},
        levels: List.duplicate(:fighter, 39) ++ [:bard],
        gear:
          Gear.new(
            weapon: :longbow,
            feats: [
              :siala_blade_proficiency,
              :siala_polearm_proficiency,
              :siala_ranged_proficiency,
              :siala_axe_proficiency,
              :siala_hammer_proficiency
            ],
            mini_sets: [],
            named_items: 0
          )
      )

    %Build{siala | ruleset_version: "vanilla"}
  end

  describe "«Вещи»: сиальских зон у ванили нет" do
    # Из `builder_named_items_test.exs`, «поле ввода».
    # Та же ворота, что у зоны мини-сетов: у ванили ни таблицы процентов,
    # ни самой механики — зоны «Крафт» там нет вовсе.
    test "у ванили зоны «Крафт» нет", %{conn: conn} do
      {view, _html} = open_gear(conn, named_items_fighter())

      # Положительный контроль (4.2): блок «Вещи» открыт, а не встречен мостиком.
      assert has_element?(view, "#gear-zone-weapon")
      refute has_element?(view, "#gear-zone-craft")
      refute has_element?(view, "#gear-named-items-input")
    end

    # Из `builder_mini_sets_test.exs`, «зона и её органы управления».
    # Ванильному ruleset'у зона не достаётся вовсе: мини-сетов в NWN нет,
    # как нет ни расового бонуса шарда, ни бонуса за тип оружия
    # (`Rules.MiniSets.gaps/2` — там же довод, почему и оговорки там нет).
    test "у ванили зоны нет", %{conn: conn} do
      {view, _html} = open_gear(conn, mini_sets_elf())

      # Положительный контроль (4.2): блок «Вещи» открыт, а не встречен мостиком.
      assert has_element?(view, "#gear-zone-weapon")
      refute has_element?(view, "#gear-zone-mini-sets")
    end
  end

  # --- из `builder_live_test.exs` ---

  defp pop_terms(html, dom_id) do
    [raw] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("##{dom_id} .stat-pop-trigger")
      |> LazyHTML.attribute("data-pop-terms")

    Jason.decode!(raw)
  end

  describe "конструктор" do
    # Из `builder_live_test.exs`, «Резисты (поглощение стихийного урона) —
    # задача 3.211».
    # Ваниль: `Epic energy resistance` даёт 10 за взятие (Сиала — 15), и
    # никакого расового эффекта — системы нет вовсе. Живой контраст с числом
    # Сиалы, доказывающий, что подпись не зашита, а читает свой ruleset.
    test "ваниль: Epic energy resistance — 10 за взятие, эффекта расы нет", %{conn: conn} do
      vanilla = Data.ruleset!("vanilla")

      build =
        Build.new(
          ruleset_version: vanilla.version,
          race: :human,
          levels: List.duplicate(:fighter, 21),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )
        |> Build.put_feat(21, :general, :epic_energy_resistance, :fire)

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      html = render(element(view, "#stat-resist-fire"))
      doc = LazyHTML.from_fragment(html)
      assert doc |> LazyHTML.query(".v") |> LazyHTML.text() |> String.trim() == "10"

      assert pop_terms(html, "stat-resist-fire") == [
               %{"label" => "Epic energy resistance", "value" => "+10"}
             ]
    end

    # Из `builder_live_test.exs`, «export».
    # `vanilla`'s two-block shape never carried granted feats at all
    # (`leveling_guide/2` only ever reads `build.feats`) — CLAUDE.md §3: ваниль
    # байт в байт, переключателю в ней нечего переключать, так что он не
    # показывается вовсе, а не показывается и бездействует.
    test "у ванильного билда переключателя автоматических фитов нет вовсе", %{conn: conn} do
      ruleset = Data.ruleset!("vanilla")
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#export-button") |> render_click()

      assert has_element?(view, "#export-dialog")
      refute has_element?(view, "#export-granted-checkbox")
    end
  end

  # --- из `build_view_granted_toggle_test.exs` и `build_view_live_test.exs` ---

  defp open_with_granted(conn, path) do
    {:ok, view, _html} = live(conn, path)
    view |> element("#view-granted-checkbox") |> render_click()
    {:ok, view, render(view)}
  end

  describe "экран просмотра" do
    # Из `build_view_granted_toggle_test.exs`, «vanilla — расхождение
    # с наивной постановкой, объяснённое в модульдоке» (там же, п. 3, довод).
    test "чекбокс ЕСТЬ и работает для гида — vanilla-классы тоже выдают фиты", %{conn: conn} do
      ruleset = Data.ruleset!("vanilla")
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-granted-checkbox")
      refute has_element?(view, "#view-guide-level-1 .pick[data-granted='1']")

      view |> element("#view-granted-checkbox") |> render_click()

      assert has_element?(view, "#view-guide-level-1 .pick[data-granted='1']")
      assert render(element(view, "#view-guide-level-1")) =~ "Armor proficiency"
    end

    test "но текст не меняется — vanilla-формат никогда не нёс гранты (CLAUDE.md §3)", %{
      conn: conn
    } do
      ruleset = Data.ruleset!("vanilla")
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      view |> element("#show-text") |> render_click()
      before_click = render(element(view, "#view-export-text"))

      view |> element("#view-granted-checkbox") |> render_click()
      after_click = render(element(view, "#view-export-text"))

      assert before_click == after_click
      refute after_click =~ "Armor proficiency"
    end

    # Из `build_view_live_test.exs`, ««что делает фит» в гиде — задача 3.94».
    # Положительный контроль к тесту «на siala_41 Evasion помечен «Изменено
    # на Сиале»» (остался там): тот же фит, тот же билд, только ruleset — без
    # него «не помечен на vanilla» ничего бы не доказывал, кроме того, что на
    # siala_41 работает разметка вообще.
    test "на vanilla тот же Evasion НЕ помечен — Сиала его там не трогала", %{conn: conn} do
      ruleset = Data.ruleset!("vanilla")

      # Ванильный Rogue отдаёт Evasion на 2-м классовом уровне, не на 30-м.
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:rogue, 2))

      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#info-view-guide-level-2-granted")

      html = render(element(view, "#info-view-guide-level-2-granted"))
      assert html =~ "&quot;changed&quot;:false"
    end
  end
end
