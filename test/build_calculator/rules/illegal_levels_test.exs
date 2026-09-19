defmodule BuildCalculator.Rules.IllegalLevelsTest do
  @moduledoc """
  `Rules.illegal_class_levels/2` and `Rules.illegal_feats/2` — replaying a
  build's own ladder against itself, as it stands right now.

  Задача 1.3: `handle_event("clear_slot", …)` used to remove a feat and
  recompute the build's numbers without ever asking whether the levels that
  needed that feat still qualify. This is the mechanism both the constructor
  and `BuildCalculatorWeb.Builder.Import` share to answer that question — see
  `builder_live_test.exs` for the same scenarios driven through the DOM.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  setup_all do
    %{ruleset: Data.ruleset!()}
  end

  # Дословный билд, легальный целиком: Fighter 1–9 набирает все шесть фитов,
  # которые требует Weapon Master (`dodge`, `mobility`, `expertise`,
  # `spring_attack`, `weapon_focus`, `whirlwind_attack`) плюс `Intimidate` 4,
  # затем три уровня самого класса.
  defp weapon_master_build(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:fighter, 9) ++ List.duplicate(:weapon_master, 3),
      base_abilities: %{str: 14, dex: 14, con: 12, int: 14, wis: 10, cha: 8},
      skills: %{1 => %{intimidate: 4}},
      feats: %{
        1 => %{:general => :dodge, {:class_bonus, :fighter} => :weapon_focus},
        2 => %{{:class_bonus, :fighter} => :mobility},
        3 => %{:general => :expertise},
        4 => %{{:class_bonus, :fighter} => :spring_attack},
        6 => %{:general => :whirlwind_attack}
      }
    )
  end

  describe "illegal_class_levels/2" do
    # Положительный контроль — обязателен рядом с `refute`/пустым списком
    # (AGENT_QUEUE, «пустые проверки»): доказывает, что билд вообще способен
    # выйти легальным, а не что проверка ничего не видит.
    test "a build that still earns every level it holds reports nothing", %{ruleset: ruleset} do
      assert Rules.illegal_class_levels(weapon_master_build(ruleset), ruleset) == []
    end

    # Вопрос Dan, дословно: снять один из фитов Weapon Master и посмотреть,
    # что будет с уже взятыми уровнями. `weapon_focus` не нужен ни одному
    # другому фиту в этом наборе, поэтому единственная причина, которая
    # обязана появиться, — собственное требование класса.
    test "clearing a feat the class itself required marks every level it granted, not just the first",
         %{ruleset: ruleset} do
      %Build{} = build = weapon_master_build(ruleset)
      without_weapon_focus = %Build{build | feats: %{build.feats | 1 => %{general: :dodge}}}

      assert Rules.illegal_class_levels(without_weapon_focus, ruleset) == [
               {10, :weapon_master, {:requires_feat, :weapon_focus}},
               {11, :weapon_master, {:requires_feat, :weapon_focus}},
               {12, :weapon_master, {:requires_feat, :weapon_focus}}
             ]

      # Снятый фит сам по себе не отмечает свой собственный уровень — только
      # то, что от него зависело.
      refute Enum.any?(
               Rules.illegal_class_levels(without_weapon_focus, ruleset),
               &match?({1, _, _}, &1)
             )
    end

    test "a race swap marks the Dwarven Defender levels it invalidates", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 7) ++ List.duplicate(:dwarven_defender, 2),
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8},
          feats: %{1 => %{:general => :dodge, {:class_bonus, :fighter} => :toughness}}
        )

      assert Rules.illegal_class_levels(build, ruleset) == []

      human = %Build{build | race: :human}

      assert Rules.illegal_class_levels(human, ruleset) == [
               {8, :dwarven_defender, {:requires_race, [:dwarf]}},
               {9, :dwarven_defender, {:requires_race, [:dwarf]}}
             ]
    end

    test "an alignment swap marks Monk levels — the restriction is a separate field, not `requirements`",
         %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: [:monk, :monk, :monk],
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 14, cha: 8}
        )

      assert Rules.illegal_class_levels(build, ruleset) == []

      chaotic = %Build{build | alignment: :chaotic_good}

      assert Rules.illegal_class_levels(chaotic, ruleset) == [
               {1, :monk, {:requires_alignment, %{require: ["lawful"]}}},
               {2, :monk, {:requires_alignment, %{require: ["lawful"]}}},
               {3, :monk, {:requires_alignment, %{require: ["lawful"]}}}
             ]
    end

    # ⚠️ Регрессия на самое дорогое: если бы `stats` считался от ЦЕЛОГО билда
    # (как раньше делал `Rules.validate_level_up/3`, который эта функция
    # сознательно не переиспользует — см. её докстрок), финальный BAB
    # двадцатиоднолетнего персонажа (21) перекрыл бы требование Dwarven
    # Defender (BAB 7) на любом уровне, включая самый первый — билд читался
    # бы легальным ДО того, как BAB 7 вообще был достигнут.
    test "stats are scoped to the level being checked, not to the whole build", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: [:fighter, :dwarven_defender] ++ List.duplicate(:fighter, 19),
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8},
          feats: %{1 => %{:general => :dodge, {:class_bonus, :fighter} => :toughness}}
        )

      assert Build.character_level(build) == 21
      assert Rules.compute(build, ruleset).base_attack == 21

      assert {2, :dwarven_defender, {:requires_bab, 7}} in Rules.illegal_class_levels(
               build,
               ruleset
             )

      # The trap this pins: the OLD call pattern (`Rules.validate_level_up/3`,
      # stats off the whole build) reads this exact level as fine.
      assert Rules.validate_level_up(build, %{class: :dwarven_defender, at: 2}, ruleset) == :ok
    end
  end

  describe "illegal_feats/2" do
    test "a feat that still holds its ground reports nothing", %{ruleset: ruleset} do
      assert Rules.illegal_feats(weapon_master_build(ruleset), ruleset) == []
    end

    # CLAUDE.md §6's scenario, and the reason a class-only replay is not
    # enough: no class `requirements` block anywhere uses `abilities`, only
    # feats do (`priv/rules/vanilla/classes.json`), so an ability threshold
    # pulled out from under a feat is invisible unless feats are replayed too.
    test "clearing the ability increase a later feat's threshold depended on marks that feat",
         %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 6),
          base_abilities: %{str: 10, dex: 12, con: 10, int: 10, wis: 10, cha: 8},
          ability_increases: %{4 => :dex},
          feats: %{6 => %{general: :dodge}}
        )

      assert Rules.illegal_feats(build, ruleset) == []

      without_increase = %Build{build | ability_increases: %{}}

      assert Rules.illegal_feats(without_increase, ruleset) == [
               {6, :general, :dodge, {:requires_ability, :dex, 13}}
             ]
    end
  end

  # Задача 3.84. Сценарий Dan дословно (24.08.2026): поднял уровни, не заполняя
  # фиты; взял `Blind fight` на позднем уровне; вернулся к незаполненным фитам
  # на РАННИХ уровнях и взял `Blind fight` ещё раз. Лестница показала
  # `Blind fight ×2` у фита, который берётся однажды, и не пометила ни одного
  # уровня.
  #
  # 🔴 До правки ядро ЗНАЛО про дубль и молчало: `FeatChoices.reasons/3` отвечал
  # `[already_taken: :blind_fight]`, а `illegal_feats/2` спрашивал только
  # пререквизиты (`validate_feat/3`) и отдавал `[]`.
  describe "illegal_feats/2: неповторяемый фит, взятый дважды" do
    # Ровно девять уровней воина: `Blind fight` не требует ничего, поэтому
    # единственная причина, которая вправе здесь появиться, — сам дубль.
    defp nine_fighters(ruleset) do
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :lawful_good,
        levels: List.duplicate(:fighter, 9),
        base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8}
      )
    end

    test "обвиняется ПОЗДНИЙ уровень, ранний чист", %{ruleset: ruleset} do
      base = nine_fighters(ruleset)

      # Положительный контроль: одно взятие обвинением не становится — значит
      # то, что найдено ниже, найдено за второе взятие, а не за сам фит.
      once = Build.put_feat(base, 6, :general, :blind_fight)
      assert Rules.illegal_feats(once, ruleset) == []

      # Порядок правок Dan: сперва поздний уровень, потом ранний.
      dup =
        base
        |> Build.put_feat(6, :general, :blind_fight)
        |> Build.put_feat(3, :general, :blind_fight)

      assert Rules.illegal_feats(dup, ruleset) ==
               [{6, :general, :blind_fight, {:already_taken, :blind_fight}}]
    end

    # ⚠️ Обратный порядок правок — контроль на то, что ответ зависит от УРОВНЕЙ,
    # а не от того, в каком порядке игрок щёлкал. Билд-то получается тот же
    # самый, но `Build.put_feat/4` — не единственный путь записи, и тест,
    # проверяющий только один порядок, зеленел бы и у кода, который помнит
    # последовательность правок.
    test "обратный порядок правок даёт тот же ответ", %{ruleset: ruleset} do
      reversed =
        nine_fighters(ruleset)
        |> Build.put_feat(3, :general, :blind_fight)
        |> Build.put_feat(6, :general, :blind_fight)

      assert Rules.illegal_feats(reversed, ruleset) ==
               [{6, :general, :blind_fight, {:already_taken, :blind_fight}}]
    end

    # 🔴 Следствие, принятое владельцем ЗАРАНЕЕ, а не обнаруженное потом
    # (Dan, 24.08.2026: «следствие устраивает, ловить»): `Toughness`, взятый
    # слотом на 1-м уровне у класса, который выдаёт его даром, — это слот,
    # потраченный впустую, и теперь он назван. Закрывает открытый вопрос
    # CLAUDE.md §9 «Ловить ли это».
    test "Toughness слотом там, где класс выдаёт его даром", %{ruleset: ruleset} do
      granting =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: [:fighter]
        )

      assert Rules.illegal_feats(Build.put_feat(granting, 1, :general, :toughness), ruleset) ==
               [{1, :general, :toughness, {:already_taken, :toughness}}]

      # Отрицательный контроль: класс, который `Toughness` НЕ выдаёт, тот же
      # слот принимает молча. Порознь `assert` выше зеленел бы и у кода,
      # который обвиняет `Toughness` всегда.
      wizard =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: [:wizard]
        )

      assert Rules.illegal_feats(Build.put_feat(wizard, 1, :general, :toughness), ruleset) == []
    end

    # ⚠️ Единственная голова `validate_feat_pick/3`, которую поставленный пик
    # НЕ получает: «выбор не записан» — это про нашу запись, а не про
    # персонажа (`Rules.placed_pick_exemptions/1`). Билд с `Weapon focus` без
    # названного оружия законен, и вставленный текстом он ровно такой.
    test "пик без записанного выбора обвинением не становится", %{ruleset: ruleset} do
      base =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 3),
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8}
        )

      bare = Build.put_feat(base, 1, :general, :weapon_focus)

      assert Rules.illegal_feats(bare, ruleset) == []

      # Положительный контроль в том же тесте: тот же фит с ЗАПИСАННЫМ выбором,
      # взятый дважды на одно оружие, обвиняется — значит выше молчит именно
      # оговорка про запись, а не проверка целиком.
      twice =
        base
        |> Build.put_feat(1, :general, :weapon_focus, :longsword)
        |> Build.put_feat(3, :general, :weapon_focus, :longsword)

      assert {3, :general, :weapon_focus, {:choice_already_taken, :weapon_focus, :longsword}} in Rules.illegal_feats(
               twice,
               ruleset
             )
    end
  end
end
