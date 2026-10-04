defmodule BuildCalculatorWeb.BuilderSlotByValueTest do
  @moduledoc """
  Задача 4.59, часть 1, конструктор: значение фита выбирается вторым шагом, уже
  после слота, а бонусный слот класса бывает уже ПО ЗНАЧЕНИЮ
  (`FeatSlots.choice_refusals/4`: `bonus_for_only`, `bonus_for_except`).

  Носитель — эльф, волшебник 1 → воин 9 → Тайный лучник 14: 24-й уровень даёт
  общий эпический слот и бонусный слот лучника, а бонусный слот лучника берёт
  Epic weapon focus только с луком (`vanilla/feat_bonus_slot_values.json`,
  `cls_feat_archer.2da`). Фокус на длинный меч у билда есть, значит Epic weapon
  focus (longsword) законен — в общем слоте.

  Клик по фиту без чипа слота выбирает самый узкий слот по фиту (бонусный
  раньше общего); до задачи второй шаг спрашивал значения у этого одного слота,
  и длинный меч стоял среди недоступных с причиной «нужен общий слот», хотя
  общий слот уровня свободен, — выйти можно было только отменой и чипом.
  Теперь значение ложится в самый узкий свободный слот уровня, который берёт
  пару, и шаг называет этот слот над значением. Чип слота закрепляет слот:
  выбор через чип по-прежнему про один слот.

  Редакция — умолчательная (Сиала); ваниль та же по правилу (запись ванильная),
  её держат модульные тесты `slot_by_value_test.exs`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Ids, Rules}
  alias BuildCalculator.Rules.Build

  setup do
    %{ruleset: Data.ruleset!(Data.default_version())}
  end

  # По одному левелапу, как игрок (CLAUDE.md §3): каждый уровень и каждый пик
  # проходят проверку ядра на том, что набрано до них.
  defp level_up!(ruleset, steps, fields) do
    Enum.reduce(steps, Build.new(fields), fn {class, picks}, build ->
      level = Build.character_level(build) + 1
      assert Rules.validate_level_up(build, class, ruleset) == :ok
      build = Build.add_level(build, class)

      Enum.reduce(picks, build, fn {slot, feat, choice}, build ->
        pick = %{feat: feat, at: level, slot: slot, choice: choice}
        assert Rules.validate_feat_pick(build, pick, ruleset) == :ok
        Build.put_feat(build, level, slot, feat, choice)
      end)
    end)
  end

  # Сиала: владения оружием — пять фитов «Системы оружия», их берёт бонусный
  # слот воина (CLAUDE.md §6).
  defp archer(ruleset) do
    head = [
      {:wizard, [{:general, :point_blank_shot, nil}]},
      {:fighter, [{{:class_bonus, :fighter}, :siala_ranged_proficiency, nil}]},
      {:fighter,
       [
         {:general, :weapon_focus, :longbow},
         {{:class_bonus, :fighter}, :siala_blade_proficiency, nil}
       ]},
      {:fighter, []},
      {:fighter, [{{:class_bonus, :fighter}, :weapon_focus, :longsword}]}
    ]

    steps =
      head ++
        List.duplicate({:fighter, []}, 10 - length(head)) ++
        List.duplicate({:arcane_archer, []}, 14)

    level_up!(ruleset, steps,
      ruleset_version: ruleset.version,
      race: :elf,
      alignment: :chaotic_good,
      base_abilities: %{str: 14, dex: 18, con: 12, int: 14, wis: 8, cha: 8}
    )
  end

  defp open(conn, %Build{} = build, level),
    do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=#{level}")

  @bonus Ids.slot_dom_id({:class_bonus, :arcane_archer})

  test "носитель: на 24-м общий и бонусный слот лучника, пару берёт только общий", %{
    ruleset: ruleset
  } do
    build = archer(ruleset)

    assert Enum.map(Rules.FeatSlots.at(build, ruleset, 24), & &1.id) == [
             :general,
             {:class_bonus, :arcane_archer}
           ]

    pick = %{feat: :epic_weapon_focus, choice: :longsword, at: 24}

    assert Rules.validate_feat_pick(build, Map.put(pick, :slot, :general), ruleset) == :ok

    assert Rules.validate_feat_pick(
             build,
             Map.put(pick, :slot, {:class_bonus, :arcane_archer}),
             ruleset
           ) == {:error, [{:not_in_class_bonus_slot, :arcane_archer}]}
  end

  test "без чипа: длинный меч доступен, ложится в общий слот, ⚠ нет", %{
    conn: conn,
    ruleset: ruleset
  } do
    {:ok, view, _html} = open(conn, archer(ruleset), 24)

    view |> element("#feat-ok-epic_weapon_focus") |> render_click()

    # Лук — в слот, который назвал первый шаг (бонусный лучника, самый узкий);
    # длинный меч — кнопкой, под подписью общего слота, а не среди недоступных.
    assert has_element?(view, "#feat-choice-values #feat-choice-longbow")
    assert has_element?(view, "#feat-choice-slot-general #feat-choice-longsword")
    refute has_element?(view, "#feat-choice-no-longsword")

    # Подсказка говорит про оба слота, группа — какой из них.
    assert render(element(view, "#feat-choice-hint")) =~ "или в слот, названный над значением"
    assert render(element(view, "#feat-choice-slot-general")) =~ "В слот «Общий"

    view |> element("#feat-choice-longsword") |> render_click()

    refute has_element?(view, "#feat-choice")
    assert has_element?(view, "#slot-chip-general[data-filled='1']")
    refute has_element?(view, "#slot-chip-#{@bonus}[data-filled='1']")
    assert render(element(view, "#slot-chip-general")) =~ "Epic weapon focus (Longsword)"
    refute has_element?(view, "#level-24[data-illegal='1']")
  end

  test "без чипа: лук по-прежнему ложится в бонусный слот лучника", %{
    conn: conn,
    ruleset: ruleset
  } do
    {:ok, view, _html} = open(conn, archer(ruleset), 24)

    view |> element("#feat-ok-epic_weapon_focus") |> render_click()
    view |> element("#feat-choice-longbow") |> render_click()

    assert has_element?(view, "#slot-chip-#{@bonus}[data-filled='1']")
    refute has_element?(view, "#slot-chip-general[data-filled='1']")
    refute has_element?(view, "#level-24[data-illegal='1']")
  end

  test "чип бонусного слота закрепляет слот: длинный меч недоступен с причиной", %{
    conn: conn,
    ruleset: ruleset
  } do
    {:ok, view, _html} = open(conn, archer(ruleset), 24)

    view |> element("#slot-filter-#{@bonus}") |> render_click()
    view |> element("#feat-ok-epic_weapon_focus") |> render_click()

    assert has_element?(view, "#feat-choice-longbow")
    refute has_element?(view, "#feat-choice-slot-general")
    assert render(element(view, "#feat-choice-no-longsword")) =~ "нужен общий слот"
    refute render(element(view, "#feat-choice-hint")) =~ "названный над значением"
  end

  test "общий слот занят: длинный меч недоступен с причиной бонусного слота", %{
    conn: conn,
    ruleset: ruleset
  } do
    build = archer(ruleset) |> Build.put_feat(24, :general, :epic_prowess, nil)
    {:ok, view, _html} = open(conn, build, 24)

    view |> element("#feat-ok-epic_weapon_focus") |> render_click()

    assert has_element?(view, "#feat-choice-longbow")
    refute has_element?(view, "#feat-choice-slot-general")
    assert render(element(view, "#feat-choice-no-longsword")) =~ "нужен общий слот"
  end
end
