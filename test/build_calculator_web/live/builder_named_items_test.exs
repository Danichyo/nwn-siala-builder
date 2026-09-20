defmodule BuildCalculatorWeb.BuilderNamedItemsTest do
  @moduledoc """
  Крафтовые (именные) и уникальные вещи — второй вход таблицы процентов
  к HP, задача 3.186. Живёт в зоне мини-сетов блока «Вещи»
  (`Builder.GearPanel.gear_mini_sets/3`), но своим полем ввода.

  ⚠️ Арифметика `Ctotal`/процента/обрыва здесь НЕ переоткрывается — она
  под `test/build_calculator/rules/gear_hit_points_test.exs`. Здесь только
  то, что зона показывает и что её поле ввода делает с билдом: видимость,
  доезд до ссылки, пара «HP голым / в экипировке», терм в разборе HP и
  сводка предупреждений `#gear-issues`.
  """

  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, GearHitPoints}

  setup do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  # Человек 40-го уровня без единого фита владения и без оружия в руках:
  # HP от именных вещей не зависит ни от расы, ни от оружия, ни от группы
  # классов (Ctotal читает только `Gear.named_items` и `Gear.mini_sets`),
  # поэтому самый простой билд, дающий число HP, — достаточный контроль.
  defp fighter(named, sets \\ []) do
    Build.new(
      ruleset_version: "siala_41",
      race: :human,
      alignment: :true_neutral,
      base_abilities: %{str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 8},
      levels: List.duplicate(:fighter, 40),
      gear: Gear.new(named_items: named, mini_sets: sets)
    )
  end

  defp open(conn, build) do
    {:ok, view, html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
    view |> element("#gear-toggle") |> render_click()
    {view, html}
  end

  # Код билда из адреса, который LiveView запатчил, — та же дорога, которой
  # пользуется `builder_live_test.exs` и `builder_mini_sets_test.exs`.
  defp code_from_path(path) do
    [_, code] = Regex.run(~r/[?&]b=([A-Za-z0-9._-]+)/, path)
    code
  end

  describe "поле ввода" do
    # Просьба Dan 12.09.2026: «отделить крафт от мини-сетов, сделать крафту
    # такой же по размеру заголовок, заголовок можно просто "Крафт"»;
    # подсказка «дают процент к HP вместе с кусками мини-сетов…» снята им же,
    # подпись поля — «Количество крафтовых вещей».
    test "своя зона «Крафт» рядом с мини-сетами, без подсказки", %{conn: conn} do
      {view, _html} = open(conn, fighter(0))

      assert has_element?(view, "#gear-zone-craft .gear-zone-kicker", "Крафт")
      assert has_element?(view, "#gear-zone-craft #gear-named-items-input")
      assert has_element?(view, "#gear-named-items-cell .gear-k", "Количество крафтовых вещей")
      refute has_element?(view, "#gear-zone-mini-sets #gear-named-items")
      refute has_element?(view, "#gear-named-items-rule")
      refute render(view) =~ "артефактные сеты не считаются"
    end

    # Та же ворота, что у зоны мини-сетов: у ванили ни таблицы процентов,
    # ни самой механики — зоны «Крафт» там нет вовсе.
    test "у ванили зоны «Крафт» нет", %{conn: conn} do
      %Build{} = siala = fighter(0)
      build = %Build{siala | ruleset_version: "vanilla"}
      {view, _html} = open(conn, build)

      refute has_element?(view, "#gear-zone-craft")
      refute has_element?(view, "#gear-named-items-input")
    end

    test "видно в зоне «Крафт», потолок печатает число из данных", %{
      conn: conn,
      ruleset: ruleset
    } do
      {view, _html} = open(conn, fighter(0))

      assert has_element?(view, "#gear-named-items-input")

      cap = GearHitPoints.named_item_slots(ruleset)
      assert is_integer(cap) and cap > 0

      html = render(element(view, "#gear-named-items-input"))
      assert html =~ ~s(max="#{cap}")
      assert html =~ ~s(min="0")
    end

    test "ввод пишет в билд и доезжает до адресной строки", %{conn: conn} do
      {view, _html} = open(conn, fighter(0))

      view
      |> element("#gear-named-items-form")
      |> render_change(%{"count" => "3"})

      path = assert_patch(view)
      assert {:ok, %{build: %Build{} = build}} = Encoding.decode(code_from_path(path))
      assert build.gear.named_items == 3

      # И по этому адресу поле открывается с тем же числом — то есть
      # именными вещами можно ПОДЕЛИТЬСЯ.
      {:ok, reopened, _html} = live(conn, path)
      reopened |> element("#gear-toggle") |> render_click()
      assert render(element(reopened, "#gear-named-items-input")) =~ ~s(value="3")
    end

    # Та же форма ввода, что у остальных чисел «Вещей» (CLAUDE.md §6,
    # «билд без вещей — то состояние, в котором открывается КАЖДАЯ уже
    # расшаренная ссылка»): отрицательное режется в ноль, а не проезжает.
    test "отрицательное режется в ноль, как у прочих чисел вещей", %{conn: conn} do
      {view, _html} = open(conn, fighter(0))

      view
      |> element("#gear-named-items-form")
      |> render_change(%{"count" => "-4"})

      path = assert_patch(view)
      assert {:ok, %{build: %Build{} = build}} = Encoding.decode(code_from_path(path))
      assert build.gear.named_items == 0
    end

    test "без единой вещи сводки процента нет", %{conn: conn} do
      {view, _html} = open(conn, fighter(0))

      refute has_element?(view, "#gear-named-items-bonus")
    end

    # Сводка называет ОБЩЕЕ число (куски + именные вместе), а не только
    # именные, — у HP один `Ctotal` на оба входа.
    test "сводка называет общий счёт и процент этой строки таблицы", %{conn: conn} do
      {view, _html} = open(conn, fighter(2))

      summary = render(element(view, "#gear-named-items-bonus"))
      assert summary =~ "2"
      assert summary =~ "21%"

      refute has_element?(view, "#gear-named-items-cutoff")
    end

    test "куски мини-сета входят в тот же общий счёт", %{conn: conn} do
      {view, _html} = open(conn, fighter(1, [2]))

      summary = render(element(view, "#gear-named-items-bonus"))
      # 1 именная + 2 куска одного набора = Ctotal 3 → 28 %.
      assert summary =~ "3"
      assert summary =~ "28%"
    end
  end

  describe "обрыв на одиннадцатой вещи" do
    # 🔴 Обрыв не набирается ОДНИМИ именными вещами: у поля свой потолок
    # слотов (10), ровно равный верхней границе таблицы, и клип срабатывает
    # РАНЬШЕ, чем счёт долетает до одиннадцати (`GearHitPoints.named_items/2`
    # клипает вход потолком слотов ДО сложения с кусками). Обрыв — это всегда
    # СМЕСЬ входов, ровно как в `gear_hit_points_test.exs`, «обрыв набирается
    # и смесью входов»: девять кусков одного набора плюс две именные вещи.
    test "поле само называет обрыв рядом с собой", %{conn: conn} do
      {view, _html} = open(conn, fighter(2, [9]))

      summary = render(element(view, "#gear-named-items-bonus"))
      assert summary =~ "11"
      assert summary =~ "0%"

      note = render(element(view, "#gear-named-items-cutoff"))
      assert note =~ "11"
    end

    test "на десяти вещах обрыва нет", %{conn: conn} do
      {view, _html} = open(conn, fighter(1, [9]))

      refute has_element?(view, "#gear-named-items-cutoff")
      assert render(element(view, "#gear-named-items-bonus")) =~ "105%"
    end
  end

  describe "#gear-issues называет обрыв своим разрядом" do
    test "запись появляется ровно при обрыве и исчезает на десяти", %{conn: conn} do
      {view, _html} = open(conn, fighter(2, [9]))

      assert has_element?(view, "#gear-issue-capped-named-items-hp-cutoff")

      {view10, _html} = open(conn, fighter(1, [9]))
      refute has_element?(view10, "#gear-issue-capped-named-items-hp-cutoff")
    end

    test "клик по находке ведёт к полю ввода", %{conn: conn} do
      {view, _html} = open(conn, fighter(2, [9]))

      view |> element("#gear-issue-capped-named-items-hp-cutoff") |> render_click()

      assert has_element?(view, "#gear-body")
      assert_push_event(view, "scroll_to_section", %{id: "gear-named-items"})
    end
  end

  describe "пара «HP голым / HP в экипировке» на панели итогов" do
    test "у билда без вещей оба числа равны", %{conn: conn} do
      {view, _html} = open(conn, fighter(0))

      naked = render(element(view, "#stat-hp_naked"))
      geared = render(element(view, "#stat-hp"))

      digits = ~r/\d+/
      assert Regex.run(digits, naked) == Regex.run(digits, geared)
    end

    test "с именными вещами HP в экипировке больше голого", %{conn: conn, ruleset: ruleset} do
      build = fighter(2)
      {view, _html} = open(conn, build)

      stats = Rules.compute(build, ruleset)
      assert stats.hp > stats.hp_naked

      assert render(element(view, "#stat-hp_naked")) =~ Integer.to_string(stats.hp_naked)
      assert render(element(view, "#stat-hp")) =~ Integer.to_string(stats.hp)
    end
  end

  describe "терм в разборе HP" do
    test "с именными вещами терм есть и называет процент", %{conn: conn} do
      {view, _html} = open(conn, fighter(2))

      terms = pop_terms(render(element(view, "#stat-hp")), "stat-hp")
      term = Enum.find(terms, &(&1["label"] =~ "Мини-сеты и крафтовые вещи"))

      refute is_nil(term)
      assert term["label"] =~ "×2"
      assert term["label"] =~ "21%"
      assert term["value"] =~ "+"
    end

    test "без вещей терма нет вовсе", %{conn: conn} do
      {view, _html} = open(conn, fighter(0))

      terms = pop_terms(render(element(view, "#stat-hp")), "stat-hp")
      refute Enum.any?(terms, &(&1["label"] =~ "Мини-сеты"))
    end

    # 🔴 При обрыве терм ОСТАЁТСЯ и называет причину нуля — молчание здесь
    # выглядело бы как потерянные сотни HP, а не как правило игры.
    test "при обрыве терм называет причину и стоит нулём", %{conn: conn, ruleset: ruleset} do
      build = fighter(2, [9])
      {view, _html} = open(conn, build)

      stats = Rules.compute(build, ruleset)
      assert stats.hp == stats.hp_naked

      terms = pop_terms(render(element(view, "#stat-hp")), "stat-hp")
      term = Enum.find(terms, &(&1["label"] =~ "Мини-сеты и крафтовые вещи"))

      refute is_nil(term)
      assert term["label"] =~ "обнуляется"
      assert term["value"] == "+0"

      # И сумма термов по-прежнему сходится со своим итогом (CLAUDE.md §6).
      total =
        terms
        |> Enum.map(fn %{"value" => v} -> v |> String.replace("+", "") |> String.to_integer() end)
        |> Enum.sum()

      assert total == stats.hp
    end
  end

  # `data-pop-terms` несёт JSON-разбор поп-апа (задача 3.13) — тот же
  # хелпер, что в `builder_live_test.exs`.
  defp pop_terms(html, dom_id) do
    [raw] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("##{dom_id} .stat-pop-trigger")
      |> LazyHTML.attribute("data-pop-terms")

    Jason.decode!(raw)
  end
end
