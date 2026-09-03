defmodule BuildCalculator.Rules.ComputeTest do
  @moduledoc """
  Table cases for `Rules.compute/2`.

  Every expected number is traceable: class BAB and saves come from the
  progression tables in `priv/rules/vanilla/classes.json` (transcribed off
  Fandom, `source.revid` cited per case), racial modifiers from `races.json`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Progression}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "base attack and saves" do
    # source: fandom class progression tables, row = class level
    #   fighter 1  revid 71988 -> 1/2/0/0      fighter 20 -> 20/12/6/6
    #   rogue 1    revid 71583 -> 0/0/2/0      rogue 20   -> 15/6/12/6
    #   wizard 1   revid 72067 -> 0/0/0/2      wizard 20  -> 10/6/6/12
    #   cleric 1   revid 71574 -> 0/2/0/2      bard 20    revid 71572 -> 15/6/12/12
    #   barbarian 1 revid 71571 -> 1/2/0/0     monk 20    revid 71589 -> 15/12/12/12
    test "single-class builds match the wiki row", %{ruleset: ruleset, vanilla: vanilla} do
      table = [
        {[:fighter], {1, 2, 0, 0}},
        {[:rogue], {0, 0, 2, 0}},
        {[:wizard], {0, 0, 0, 2}},
        {[:cleric], {0, 2, 0, 2}},
        {[:barbarian], {1, 2, 0, 0}},
        {List.duplicate(:fighter, 20), {20, 12, 6, 6}},
        {List.duplicate(:rogue, 20), {15, 6, 12, 6}},
        {List.duplicate(:wizard, 20), {10, 6, 6, 12}},
        {List.duplicate(:bard, 20), {15, 6, 12, 12}}
      ]

      for {levels, expected} <- table, rules <- [ruleset, vanilla] do
        stats = compute(rules, levels)

        assert {stats.base_attack, stats.base_fort, stats.base_ref, stats.base_will} == expected,
               "#{rules.version}: levels #{inspect(Enum.uniq(levels))} x#{length(levels)}"
      end
    end

    # source: siala_41/classes.json — monk carries {"what": "bab_progression",
    # "value": "high"}, status "verified". Vanilla monk is medium, 15 at class
    # level 20 (fandom "Monk" revid 71589); the shard raises it, and the shard
    # wins. The override arrives through the data layer, not through code.
    test "Siala's monk BAB override is applied", %{ruleset: ruleset, vanilla: vanilla} do
      assert vanilla.classes[:monk].bab_progression == "medium"
      assert ruleset.classes[:monk].bab_progression == "high"

      assert compute(vanilla, List.duplicate(:monk, 20)).base_attack == 15
      assert compute(ruleset, List.duplicate(:monk, 20)).base_attack == 20

      # saves are untouched — the shard restates no save progression
      siala = compute(ruleset, List.duplicate(:monk, 20))
      assert {siala.base_fort, siala.base_ref, siala.base_will} == {12, 12, 12}
    end

    # source: the same tables, summed per class — a multiclass character adds up
    # each class's own row, which is why the +2 for a class's first level repeats.
    #   fighter 4 -> 4/4/1/1, rogue 3 -> 2/1/3/1,
    #   wizard 3  -> 1/1/1/3, cleric 4 -> 3/4/1/4
    test "four classes add their own rows together", %{ruleset: ruleset} do
      levels =
        List.duplicate(:fighter, 4) ++
          List.duplicate(:rogue, 3) ++ List.duplicate(:wizard, 3) ++ List.duplicate(:cleric, 4)

      stats = compute(ruleset, levels)

      assert stats.character_level == 14
      assert stats.class_levels == %{fighter: 4, rogue: 3, wizard: 3, cleric: 4}
      assert stats.base_attack == 4 + 2 + 1 + 3
      assert stats.base_fort == 4 + 1 + 1 + 4
      assert stats.base_ref == 1 + 3 + 1 + 1
      assert stats.base_will == 1 + 1 + 3 + 4
    end

    test "an empty build is all zeroes, not a crash", %{ruleset: ruleset} do
      stats = compute(ruleset, [])

      assert stats.character_level == 0
      assert stats.base_attack == 0
      assert stats.hp == 0
      assert stats.gaps == []
    end
  end

  describe "ability modifiers" do
    # source: races.json — dwarf +2 CON / -2 CHA (fandom "Dwarf" revid 68574)
    test "racial modifiers land on the base scores", %{ruleset: ruleset} do
      build =
        Build.new(
          race: :dwarf,
          levels: [:fighter],
          base_abilities: %{str: 16, dex: 12, con: 14, int: 10, wis: 12, cha: 10}
        )

      stats = Rules.compute(build, ruleset)

      assert stats.abilities.con == 16
      assert stats.abilities.cha == 8
      assert stats.ability_modifiers.con == 3
      assert stats.ability_modifiers.cha == -1
    end

    test "the +1 on every fourth level applies only up to the level reached", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          ability_increases: %{4 => :str, 8 => :str, 12 => :str},
          base_abilities: %{str: 16, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      assert Rules.compute(build, ruleset).abilities.str == 18
      assert Rules.compute(Build.truncate(build, 4), ruleset).abilities.str == 17
    end

    test "modifiers floor rather than truncate", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: [:fighter],
          base_abilities: %{str: 9, dex: 8, con: 7, int: 10, wis: 11, cha: 12}
        )

      stats = Rules.compute(build, ruleset)

      assert stats.ability_modifiers.str == -1
      assert stats.ability_modifiers.dex == -1
      assert stats.ability_modifiers.con == -2
      assert stats.ability_modifiers.int == 0
      assert stats.ability_modifiers.wis == 0
      assert stats.ability_modifiers.cha == 1
    end
  end

  describe "hit points" do
    # source: fandom "Hit point" revid 62785 — constitution is applied per level
    # and adapts retroactively; there is a floor of one hit point per level.
    # Hit dice from classes.json: fighter d10, wizard d4, barbarian d12.
    # Assumption on record in ruleset.gaps: maximum hit die rolls, the convention
    # of the community build format and CBC.
    #
    # ⚠ Both rulesets, and the pair is the point (task 1.9). Vanilla is dice and
    # constitution alone; on Siala the Fighter is handed `Toughness` at his own
    # first class level (siala:Живучесть revid 16727), which is +1 hit point per
    # character level — the same ten levels are worth ten more — plus «Дух
    # Сиалы», a flat +20 every Siala character carries (task, волна 12,
    # 09.08.2026, GAME_CHECKS.md A1) that vanilla does not know about at all.
    # Asserting only the Siala number would pass just as well if either bonus
    # were hard-coded somewhere instead of read off the shard's data.
    test "hit die plus constitution, every level", %{ruleset: ruleset, vanilla: vanilla} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 10),
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 10}
        )

      assert Rules.compute(build, vanilla).hp == 10 * (10 + 2)
      assert Rules.compute(build, ruleset).hp == 10 * (10 + 2) + 10 + 20
    end

    test "multiclass hit points follow the class taken at each level", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      build =
        Build.new(
          levels: List.duplicate(:barbarian, 2) ++ List.duplicate(:wizard, 2),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      assert Rules.compute(build, vanilla).hp == 12 + 12 + 4 + 4

      # The Barbarian brings Toughness with him, and it pays on **every**
      # character level, the two wizard ones included: the source calls the
      # hit points retroactive. «Дух Сиалы» is the flat +20 beside it — once
      # for the whole build, not once per class.
      assert Rules.compute(build, ruleset).hp == 12 + 12 + 4 + 4 + 4 + 20
    end

    test "a level never yields less than one hit point", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:wizard, 3),
          base_abilities: %{str: 10, dex: 10, con: 3, int: 10, wis: 10, cha: 10}
        )

      # d4 with a -4 constitution modifier would be 0 per level, floored to 1;
      # «Дух Сиалы»'s flat +20 lands after the floor, same as Epic toughness
      # would — wizard grants no Toughness, so it is the only feat-shaped term
      # missing here.
      assert Rules.compute(build, ruleset).hp == 3 + 20
    end

    # Задача 3.37, табличный кейс на саму шкалу — по одной строке на каждую её
    # ступень и на её границы.
    #
    # source: `fandom:Red dragon disciple` (revid 71919) — колонка `Hit die`
    # таблицы прогрессии даёт d6 на классовых уровнях 1–3, d8 на 4–5, d10 на
    # 6–10, а bold-лейбл эпического раздела — d12 с 11-го. Ту же шкалу целиком
    # печатает вторая страница, `fandom:Hit die increase` (revid 67679):
    # «1 → d6, 4 → d8, 6 → d10, 11 → d12».
    #
    # ⚠️ Уровни 1–7 подтверждены арифметикой замера Dan (G2, ниже); 8–10 и 11+
    # держатся на этих двух страницах плюс на его же словах о 12 хитах
    # с 11-го уровня класса — два независимых источника, но не замер.
    #
    # ⚠️ 31 в таблице не случаен: `max_level` у РДД — 10, но это длина
    # неэпической таблицы, а не предел класса (CLAUDE.md §3), и на Сиале
    # престиж тянется до 31. Верхняя ступень обязана покрывать всё, что выше
    # неё, — иначе на 11-м уровне класса шкала кончилась бы.
    test "шкала хит-дайса РДД, ступень за ступенью", %{ruleset: ruleset, vanilla: vanilla} do
      table = [{1, 6}, {2, 6}, {3, 6}, {4, 8}, {5, 8}, {6, 10}, {10, 10}, {11, 12}, {31, 12}]

      for {class_level, die} <- table, rules <- [ruleset, vanilla] do
        assert Progression.hit_die(rules, :red_dragon_disciple, class_level) == {:ok, die},
               "#{rules.version}: РДД #{class_level}"
      end

      # ...и класс с одним числом отвечает им на любом уровне, включая эпические:
      # список из одной ступени и одно число — одно и то же утверждение.
      for class_level <- [1, 20, 41] do
        assert Progression.hit_die(ruleset, :fighter, class_level) == {:ok, 10}
      end
    end

    # 🔴 Задача 3.37, и это ЗАМЕР, а не наша арифметика: Dan создал персонажа
    # и прочитал оба числа с листа (`GAME_CHECKS.md` G2, 16.08.2026).
    #
    #   бард 6 / РДД 6, CON 18 (мод +4) → 148
    #   бард 6 / РДД 7, CON 20 (мод +5) → 175
    #
    # Раскладываются точно, без единой подгонки:
    #   148 = 36 (бард 6 × d6) + 44 (РДД: 6+6+6+8+8+10) + 48 (мод +4 × 12) + 20
    #   175 = 36 + 54 (то же плюс 10 за седьмой) + 65 (мод +5 × 13) + 20
    # где 20 — «Дух Сиалы». CON 20 на втором билде не введён, а получен: РДД
    # даёт +2 CON на своём 7-м уровне класса, и мод растёт с +4 до +5.
    #
    # ⚠️ Прирост +27 подтверждает РЕТРОАКТИВНОСТЬ телосложения: 15 за новый
    # уровень (хит-дайс 10 + мод 5) и 12 задним числом за прошлые двенадцать.
    # Без неё было бы +15.
    test "растущий хит-дайс РДД: оба числа с листа Dan сходятся точно", %{ruleset: ruleset} do
      six = List.duplicate(:bard, 6) ++ List.duplicate(:red_dragon_disciple, 6)
      seven = List.duplicate(:bard, 6) ++ List.duplicate(:red_dragon_disciple, 7)

      con_18 = %{str: 10, dex: 10, con: 18, int: 10, wis: 10, cha: 10}

      before = Rules.compute(Build.new(levels: six, base_abilities: con_18), ruleset)
      after_seventh = Rules.compute(Build.new(levels: seven, base_abilities: con_18), ruleset)

      assert before.abilities.con == 18
      assert before.hp == 148

      assert after_seventh.abilities.con == 20
      assert after_seventh.hp == 175

      assert after_seventh.hp - before.hp == 27
    end

    # ⚠️ Эпические уровни класса — та часть шкалы, которой замер не касался
    # (РДД 11+ дорог в прокачке): она стоит на колонке Fandom и на слове Dan.
    # Проверяется здесь потому, что `max_level` у РДД — 10, и это не предел
    # класса, а длина неэпической таблицы (CLAUDE.md §3): на Сиале престиж
    # тянется до 31, значит ступень «11+ → d12» обязана работать.
    test "ступень 11+ живёт на эпических уровнях класса", %{ruleset: ruleset} do
      ten = List.duplicate(:bard, 20) ++ List.duplicate(:red_dragon_disciple, 10)
      eleven = ten ++ [:red_dragon_disciple]

      # ⚠️ CON 8, а не 10: на седьмом уровне класса РДД сам поднимает
      # телосложение на +2 (`dragon_abilities`), и с базы 10 модификатор стал бы
      # +1 — прирост был бы 13, то есть хит-дайс пришлось бы вычислять
      # вычитанием. С базы 8 итог ровно 10, модификатор 0, и прирост — это
      # чистый хит-дайс одиннадцатого уровня класса.
      flat = %{str: 10, dex: 10, con: 8, int: 10, wis: 10, cha: 10}

      before = Rules.compute(Build.new(levels: ten, base_abilities: flat), ruleset)
      after_eleventh = Rules.compute(Build.new(levels: eleven, base_abilities: flat), ruleset)

      assert after_eleventh.abilities.con == 10

      # Ни бард, ни РДД не выдают Toughness, так что других слагаемых нет.
      assert after_eleventh.hp - before.hp == 12
    end

    # Та же честность, что была у РДД до 3.37, — теперь она проверяется на
    # ruleset'е, из которого факт ВЫНУТ, а не на корпусе: обеих форм хит-дайса
    # в данных нет ни у одного класса обоих ruleset'ов, и «непосчитанное
    # приходит nil» перестало бы быть под тестом вовсе.
    test "a class without a hit die yields nil, not a plausible number", %{ruleset: ruleset} do
      dieless =
        update_in(ruleset.classes[:red_dragon_disciple], fn class ->
          %{class | hit_die: nil, hit_die_by_class_level: nil}
        end)

      stats = compute(dieless, [:sorcerer, :red_dragon_disciple])

      assert stats.hp == nil
      assert {:missing_data, {:hit_die, :red_dragon_disciple}} in stats.gaps
      # the rest of the sheet still computes: sorcerer 1 -> will +2 (revid 71586)
      assert stats.base_will > 0
    end
  end

  # Task 3.6: the totals panel breaks HP down instead of only showing the
  # sum, and the breakdown has to be exact, not merely plausible.
  describe "hp_breakdown" do
    test "by-class dice, the CON term and a zero floor adjustment sum to hp", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:barbarian, 2) ++ List.duplicate(:wizard, 2),
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 10}
        )

      stats = Rules.compute(build, ruleset)

      assert stats.hp_breakdown.by_class == [
               %{
                 class: :barbarian,
                 levels: 2,
                 hit_dice: [%{die: 12, levels: 2}],
                 subtotal: 24
               },
               %{class: :wizard, levels: 2, hit_dice: [%{die: 4, levels: 2}], subtotal: 8}
             ]

      # CON 14 -> modifier +2, over the whole 4-level character.
      assert stats.hp_breakdown.con_term == 8

      # The Barbarian's free Toughness, named rather than folded in (task 1.9).
      assert stats.hp_breakdown.by_feat == [
               %{feat: :toughness, takes: 1, subtotal: 4, capped?: false}
             ]

      # «Дух Сиалы» — a fourth, separate bucket (task, волна 12): not a feat,
      # so it stays out of `by_feat` and carries its own name straight off the
      # ruleset fact rather than a feat id.
      assert stats.hp_breakdown.innate == %{id: :spirit_of_siala, ru: "Дух Сиалы", amount: 20}

      assert stats.hp_breakdown.floor_adjustment == 0

      assert Enum.sum(Enum.map(stats.hp_breakdown.by_class, & &1.subtotal)) +
               stats.hp_breakdown.con_term +
               Enum.sum(Enum.map(stats.hp_breakdown.by_feat, & &1.subtotal)) +
               stats.hp_breakdown.innate.amount +
               stats.hp_breakdown.floor_adjustment == stats.hp
    end

    # The exact fixture the floor exists for: d4 minus a −4 CON modifier is
    # 0 per level on paper, and every one of the three levels is quietly
    # bumped up to the floor of 1 instead. `floor_adjustment` is what names
    # that +3 instead of leaving "hit dice + CON" three points short of the
    # total right next to it.
    test "the one-hit-point floor shows up as its own named term, not a silent gap", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          levels: List.duplicate(:wizard, 3),
          base_abilities: %{str: 10, dex: 10, con: 3, int: 10, wis: 10, cha: 10}
        )

      stats = Rules.compute(build, ruleset)

      assert stats.hp == 3 + 20

      assert stats.hp_breakdown.by_class == [
               %{class: :wizard, levels: 3, hit_dice: [%{die: 4, levels: 3}], subtotal: 12}
             ]

      # CON 3 -> modifier -4, times 3 levels.
      assert stats.hp_breakdown.con_term == -12
      # «Дух Сиалы» lands after the floor, so it is no part of what the floor
      # absorbed — the residual is exactly the same 3 it was before the bonus
      # existed at all.
      assert stats.hp_breakdown.innate == %{id: :spirit_of_siala, ru: "Дух Сиалы", amount: 20}
      assert stats.hp_breakdown.floor_adjustment == 3

      assert 12 + -12 + 20 + 3 == stats.hp
    end

    test "an empty build breaks down to all zeroes, not nil and not a crash", %{ruleset: ruleset} do
      stats = compute(ruleset, [])

      assert stats.hp == 0

      # ⚠️ «Дух Сиалы» is `nil` here too, not `%{amount: 20, ...}` — a build
      # with zero levels is not a character yet (`Progression.innate_bonus/2`),
      # and the shard hands the bonus to characters, not to an empty ladder.
      assert stats.hp_breakdown == %{
               by_class: [],
               con_term: 0,
               by_feat: [],
               innate: nil,
               floor_adjustment: 0
             }
    end

    # A class with no hit die in the data refuses `hp` outright (the case
    # above) — the breakdown has to refuse right alongside it rather than
    # carry a half-computed structure nobody asked for. On a ruleset with the
    # fact taken out, for the same reason as the case above.
    test "hp_breakdown is nil exactly when hp is", %{ruleset: ruleset} do
      dieless =
        update_in(ruleset.classes[:red_dragon_disciple], fn class ->
          %{class | hit_die: nil, hit_die_by_class_level: nil}
        end)

      stats = compute(dieless, [:sorcerer, :red_dragon_disciple])

      assert stats.hp == nil
      assert stats.hp_breakdown == nil
    end

    # Задача 3.37. У 22 классов из 23 список из одной записи — то же самое
    # утверждение, что раньше делало одно число. У РДД записей столько, сколько
    # ступеней шкалы билд прошёл, и обе суммы обязаны сойтись: иначе разбор
    # печатает рядом с `subtotal` число, на которое тот не делится.
    test "hit_dice: список дайсов класса, а не одно число", %{ruleset: ruleset} do
      levels = List.duplicate(:bard, 6) ++ List.duplicate(:red_dragon_disciple, 7)

      stats =
        Rules.compute(
          Build.new(
            levels: levels,
            base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
          ),
          ruleset
        )

      assert stats.hp_breakdown.by_class == [
               %{class: :bard, levels: 6, hit_dice: [%{die: 6, levels: 6}], subtotal: 36},
               %{
                 class: :red_dragon_disciple,
                 levels: 7,
                 hit_dice: [
                   %{die: 6, levels: 3},
                   %{die: 8, levels: 2},
                   %{die: 10, levels: 2}
                 ],
                 subtotal: 54
               }
             ]

      for entry <- stats.hp_breakdown.by_class do
        assert Enum.sum(Enum.map(entry.hit_dice, & &1.levels)) == entry.levels
        assert Enum.sum(Enum.map(entry.hit_dice, &(&1.die * &1.levels))) == entry.subtotal
      end
    end

    # ⚠️ Дайс берётся от уровня КЛАССА, а не персонажа, и чередование — это
    # единственная форма билда, на которой эти два ответа расходятся: три
    # уровня РДД, взятые на 4-м, 6-м и 7-м уровнях персонажа, — всё ещё
    # первые три уровня класса, то есть d6 каждый.
    test "чередование классов не двигает шкалу: уровень класса, а не персонажа", %{
      ruleset: ruleset
    } do
      levels = [:bard, :bard, :bard, :red_dragon_disciple, :bard, :red_dragon_disciple]

      stats =
        Rules.compute(
          Build.new(
            levels: levels,
            base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
          ),
          ruleset
        )

      assert [_bard, rdd] = stats.hp_breakdown.by_class

      assert rdd == %{
               class: :red_dragon_disciple,
               levels: 2,
               hit_dice: [%{die: 6, levels: 2}],
               subtotal: 12
             }
    end
  end

  # Task 3.16: base attack, told per class rather than as one number.
  #
  # ⚠ Every case here compares the **whole term list literally**, and that is
  # the point rather than tidiness. The totals are summed *from* these rows
  # (one traversal, one truth — `Progression.base/2`), so «сумма термов равна
  # итогу» can never fail and proves nothing on its own; and a term worth `0`
  # — which this breakdown is full of, because a class past the counted window
  # contributes exactly zero — does not move a sum at all. Only naming each
  # row's six fields catches a corrupted one (HANDOFF, «сумма частей равна
  # итогу — не проверка»).
  describe "bab_breakdown" do
    # source: fandom progression tables, row = class level
    #   fighter 20 revid 71988 -> bab 20 (high, +1/level)
    #   wizard 20  revid 72067 -> bab 10 (low, +1/2)
    #   epic.json: level 40 -> +10 attack; Siala's 41st is odd -> +11
    #
    # 🔴 The pair of builds epic rule 2 exists for. Same twenty fighter levels
    # and same twenty wizard levels, opposite order, and the base attack differs
    # by ten: only the first twenty character levels feed it, so whichever class
    # came second contributed nothing at all (CLAUDE.md §3).
    test "the order the classes were taken in is visible term by term", %{ruleset: ruleset} do
      fighter_first =
        compute(ruleset, List.duplicate(:fighter, 20) ++ List.duplicate(:wizard, 20))

      wizard_first = compute(ruleset, List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20))

      assert fighter_first.base_attack == 30
      assert wizard_first.base_attack == 20

      assert fighter_first.bab_breakdown == %{
               by_class: [
                 %{
                   class: :fighter,
                   levels_counted: 20,
                   levels_taken: 20,
                   levels_ignored: 0,
                   progression: "high",
                   subtotal: 20
                 },
                 %{
                   class: :wizard,
                   levels_counted: 0,
                   levels_taken: 20,
                   levels_ignored: 20,
                   progression: "low",
                   subtotal: 0
                 }
               ],
               epic_term: 10,
               counted_levels: 20
             }

      assert wizard_first.bab_breakdown == %{
               by_class: [
                 %{
                   class: :wizard,
                   levels_counted: 20,
                   levels_taken: 20,
                   levels_ignored: 0,
                   progression: "low",
                   subtotal: 10
                 },
                 %{
                   class: :fighter,
                   levels_counted: 0,
                   levels_taken: 20,
                   levels_ignored: 20,
                   progression: "high",
                   subtotal: 0
                 }
               ],
               epic_term: 10,
               counted_levels: 20
             }
    end

    # source: fighter 10 revid 71988 -> 10; cleric 10 revid 71574 -> 7
    #   (medium, div(10 * 3, 4)); rogue's sixteen levels are all past twenty.
    #
    # 🔴 The case task 3.16 was written around: BAB 28 = 17 from the counted
    # levels + 11 epic, and the rogue gave **zero**. A row reading «Rogue × 16»
    # would contradict the number standing beside it.
    test "a class taken entirely past the window is named with a zero, not dropped", %{
      ruleset: ruleset
    } do
      stats =
        compute(
          ruleset,
          List.duplicate(:fighter, 10) ++
            List.duplicate(:cleric, 15) ++ List.duplicate(:rogue, 16)
        )

      assert stats.character_level == 41
      assert stats.base_attack == 28
      assert stats.base_attack_at_20 == 17

      assert stats.bab_breakdown.by_class == [
               %{
                 class: :fighter,
                 levels_counted: 10,
                 levels_taken: 10,
                 levels_ignored: 0,
                 progression: "high",
                 subtotal: 10
               },
               %{
                 class: :cleric,
                 levels_counted: 10,
                 levels_taken: 15,
                 levels_ignored: 5,
                 progression: "medium",
                 subtotal: 7
               },
               %{
                 class: :rogue,
                 levels_counted: 0,
                 levels_taken: 16,
                 levels_ignored: 16,
                 progression: "medium",
                 subtotal: 0
               }
             ]

      assert stats.bab_breakdown.epic_term == 11
    end

    # source: siala_41/classes.json — monk carries {"what": "bab_progression",
    # "value": "high"}. The breakdown must report what was **actually computed
    # for this ruleset**, label included, or it explains the number with the
    # wrong table: vanilla's monk is medium and worth 15 at class level 20.
    test "Siala's monk override shows up in the label and in the subtotal", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      levels = List.duplicate(:monk, 20)

      assert [%{progression: "high", subtotal: 20}] =
               compute(ruleset, levels).bab_breakdown.by_class

      assert [%{progression: "medium", subtotal: 15}] =
               compute(vanilla, levels).bab_breakdown.by_class
    end

    # Boundary levels, in one table: 1 (nothing counted away, no epic), 20 (the
    # window exactly filled), 21 (the first level that falls outside it and the
    # first epic attack bonus) and 41 (Siala's cap, odd, so +11 attack and the
    # last class level thrown away).
    #
    # source: fandom "Fighter" revid 71988 (high, +1/level);
    #   priv/rules/vanilla/epic.json — odd levels 21…41 grant +1 attack each.
    test "the window boundaries are 1, 20, 21 and 41", %{ruleset: ruleset} do
      table = [
        {1, 1, 0, 0, 1},
        {20, 20, 0, 0, 20},
        {21, 20, 1, 1, 21},
        {41, 20, 21, 11, 31}
      ]

      for {level, counted, ignored, epic, total} <- table do
        stats = compute(ruleset, List.duplicate(:fighter, level))

        assert stats.bab_breakdown.by_class == [
                 %{
                   class: :fighter,
                   levels_counted: counted,
                   levels_taken: level,
                   levels_ignored: ignored,
                   progression: "high",
                   subtotal: counted
                 }
               ],
               "fighter #{level}"

        assert stats.bab_breakdown.epic_term == epic, "fighter #{level} epic"
        assert stats.base_attack == total, "fighter #{level} total"
      end
    end

    # source: fighter 4 -> 4; dwarven_defender 10 revid 71576 -> 10 (high);
    #   weapon_master 6 revid 71993 -> 6 (high); rogue's seventeen are past 20.
    #   4 + 10 + 6 = 20 counted levels, +11 epic at level 41.
    test "four classes at the cap: every one named, whether it counted or not", %{
      ruleset: ruleset
    } do
      stats =
        compute(
          ruleset,
          List.duplicate(:fighter, 4) ++
            List.duplicate(:dwarven_defender, 10) ++
            List.duplicate(:weapon_master, 10) ++ List.duplicate(:rogue, 17)
        )

      assert stats.character_level == 41
      assert stats.base_attack == 31

      assert Enum.map(stats.bab_breakdown.by_class, &{&1.class, &1.levels_counted, &1.subtotal}) ==
               [
                 {:fighter, 4, 4},
                 {:dwarven_defender, 10, 10},
                 # ⚠ Only six of its ten levels landed inside the window, and the
                 # term says so rather than claiming ten (`levels_ignored: 4`).
                 {:weapon_master, 6, 6},
                 {:rogue, 0, 0}
               ]

      assert Enum.map(stats.bab_breakdown.by_class, & &1.levels_ignored) == [0, 0, 4, 17]

      # Every class the build ever took has a row, in the order it was first
      # taken — the same order `hp_breakdown` and the build's own title use.
      assert Enum.map(stats.bab_breakdown.by_class, & &1.class) ==
               [:fighter, :dwarven_defender, :weapon_master, :rogue]
    end

    # `levels_counted + levels_ignored == levels_taken` and `sum + epic ==
    # base_attack`, over a corpus rather than one build. ⚠ The second is a
    # **contract statement**, not a corruption detector — the totals are summed
    # from these very rows — and it is asserted because the whole web layer is
    # built on it: a caption whose parts do not add up to the number beside them
    # is worse than no caption. The corruption detectors are the literal term
    # lists above.
    test "the three level counts agree and the terms reconstruct base_attack", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      corpus = [
        [],
        [:fighter],
        List.duplicate(:monk, 41),
        List.duplicate(:sorcerer, 20) ++ List.duplicate(:pale_master, 10),
        List.duplicate(:rogue, 30) ++ List.duplicate(:fighter, 11),
        List.duplicate(:bard, 7) ++
          List.duplicate(:shadowdancer, 10) ++
          List.duplicate(:rogue, 14) ++ List.duplicate(:harper_scout, 5)
      ]

      for levels <- corpus, rules <- [ruleset, vanilla] do
        stats = compute(rules, levels)
        breakdown = stats.bab_breakdown
        subtotals = for %{subtotal: n} <- breakdown.by_class, is_integer(n), do: n

        assert Enum.sum(subtotals) + breakdown.epic_term == stats.base_attack,
               "#{rules.version}: #{inspect(Enum.uniq(levels))}"

        for term <- breakdown.by_class do
          assert term.levels_counted + term.levels_ignored == term.levels_taken,
                 "#{rules.version}: #{term.class} in #{inspect(Enum.uniq(levels))}"
        end

        # Counted levels never exceed the window, and they add up to whatever
        # part of the ladder fits inside it — the statement that catches a
        # window read from the wrong place.
        assert Enum.sum(Enum.map(breakdown.by_class, & &1.levels_counted)) ==
                 min(stats.character_level, breakdown.counted_levels)

        assert Enum.sum(Enum.map(breakdown.by_class, & &1.levels_taken)) ==
                 stats.character_level
      end
    end

    test "an empty build breaks down to an empty list, not nil", %{ruleset: ruleset} do
      assert compute(ruleset, []).bab_breakdown == %{
               by_class: [],
               epic_term: 0,
               counted_levels: 20
             }
    end

    # ⚠ `subtotal: nil`, never `0`. A prestige class levelled past the end of
    # its own progression table (reachable by hand-editing a shared link — the
    # class cap refuses it in the constructor) leaves the total short by an
    # unknown amount, and a confident zero would hide exactly that. The gap
    # names the missing row beside it.
    test "a class whose progression table has no such row admits it instead of guessing", %{
      ruleset: ruleset
    } do
      # Weapon Master's table stops at class level 10 (`max_level`), so asking
      # for 15 has no honest answer.
      stats = compute(ruleset, List.duplicate(:weapon_master, 15))

      assert [%{class: :weapon_master, levels_counted: 15, subtotal: nil}] =
               stats.bab_breakdown.by_class

      assert {:missing_data, {:class_progression, :weapon_master, 15}} in stats.gaps

      # Positive control: the same class inside its table is a plain number, so
      # the `nil` above is about the missing row and not about the class.
      assert [%{class: :weapon_master, subtotal: 10}] =
               compute(ruleset, List.duplicate(:weapon_master, 10)).bab_breakdown.by_class
    end
  end

  # The saves, told per class rather than as one «база» number — the same job
  # task 3.16 did for base attack, and named there as the next thing to do.
  #
  # ⚠ Every case compares the **whole term list literally**, for the three
  # reasons the base-attack breakdown records: the totals are summed from these
  # very rows, so «Σ термов == итог» can never fail; a term worth `0` moves no
  # sum at all and this breakdown is full of them; and there are now three
  # numbers per row, so two of them could be swapped with the third and every
  # per-save sum would still balance.
  describe "save_breakdown" do
    # source: fandom "Base save" (revid 71553): «primary saving throws (high
    # saves) go up +2 at class level 1 and +1 at each even class level, while
    # other saving throws (low saves) go up +1 every third class level», table
    # rows "High saves" / "Low saves" — 20 levels of a high save is +12, of a low
    # one +6. Class labels: fighter fort primary (revid 71988), wizard will
    # primary (revid 72067).
    #
    # 🔴 The pair of builds epic rule 2 exists for, on the other stat. `Wizard 20
    # → Fighter 20` has the saves of a **wizard** — Will 12 and nothing from
    # twenty levels of fighter, so its Fortitude is a wizard's 6 — and reversing
    # the order swaps that around. The caption used to read «база 6» and left the
    # player to guess whose six it was.
    test "the order the classes were taken in is visible save by save", %{ruleset: ruleset} do
      fighter_first =
        compute(ruleset, List.duplicate(:fighter, 20) ++ List.duplicate(:wizard, 20))

      wizard_first = compute(ruleset, List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20))

      assert {fighter_first.base_fort, fighter_first.base_ref, fighter_first.base_will} ==
               {22, 16, 16}

      assert {wizard_first.base_fort, wizard_first.base_ref, wizard_first.base_will} ==
               {16, 16, 22}

      assert fighter_first.save_breakdown == %{
               by_class: [
                 %{
                   class: :fighter,
                   levels_counted: 20,
                   levels_taken: 20,
                   levels_ignored: 0,
                   progressions: %{fort: "good", ref: "poor", will: "poor"},
                   subtotals: %{fort: 12, ref: 6, will: 6}
                 },
                 %{
                   class: :wizard,
                   levels_counted: 0,
                   levels_taken: 20,
                   levels_ignored: 20,
                   progressions: %{fort: "poor", ref: "poor", will: "good"},
                   subtotals: %{fort: 0, ref: 0, will: 0}
                 }
               ],
               epic_term: 10,
               counted_levels: 20
             }

      assert wizard_first.save_breakdown == %{
               by_class: [
                 %{
                   class: :wizard,
                   levels_counted: 20,
                   levels_taken: 20,
                   levels_ignored: 0,
                   progressions: %{fort: "poor", ref: "poor", will: "good"},
                   subtotals: %{fort: 6, ref: 6, will: 12}
                 },
                 %{
                   class: :fighter,
                   levels_counted: 0,
                   levels_taken: 20,
                   levels_ignored: 20,
                   progressions: %{fort: "good", ref: "poor", will: "poor"},
                   subtotals: %{fort: 0, ref: 0, will: 0}
                 }
               ],
               epic_term: 10,
               counted_levels: 20
             }
    end

    # source: fighter 10 revid 71988 -> 10/7/3/3 (fort primary);
    #   cleric 10 revid 71574 -> 7/7/3/7 (fort and will primary);
    #   rogue's sixteen levels are all past twenty (ref primary, worth nothing
    #   here). bab/fort/ref/will.
    #
    # 🔴 The same build task 3.16 used for base attack, so the two breakdowns of
    # one panel can be read side by side: BAB 28 with the rogue at zero, and
    # Fort 24 = 7 + 7 + 0 + 10 epic with the rogue at zero on all three saves.
    test "a class taken entirely past the window is named with zeroes, not dropped", %{
      ruleset: ruleset
    } do
      stats =
        compute(
          ruleset,
          List.duplicate(:fighter, 10) ++
            List.duplicate(:cleric, 15) ++ List.duplicate(:rogue, 16)
        )

      assert stats.character_level == 41
      assert {stats.base_fort, stats.base_ref, stats.base_will} == {24, 16, 20}

      assert stats.save_breakdown.by_class == [
               %{
                 class: :fighter,
                 levels_counted: 10,
                 levels_taken: 10,
                 levels_ignored: 0,
                 progressions: %{fort: "good", ref: "poor", will: "poor"},
                 subtotals: %{fort: 7, ref: 3, will: 3}
               },
               %{
                 class: :cleric,
                 levels_counted: 10,
                 levels_taken: 15,
                 levels_ignored: 5,
                 progressions: %{fort: "good", ref: "poor", will: "good"},
                 subtotals: %{fort: 7, ref: 3, will: 7}
               },
               %{
                 class: :rogue,
                 levels_counted: 0,
                 levels_taken: 16,
                 levels_ignored: 16,
                 progressions: %{fort: "poor", ref: "good", will: "poor"},
                 subtotals: %{fort: 0, ref: 0, will: 0}
               }
             ]

      # ⚠ Ten, not eleven: epic saves go up on even character levels and epic
      # attack on odd ones, so the very same build carries +10 here and +11
      # there. Copying the attack term into the saves would be wrong by exactly
      # one at the cap (`Rules.Epic`, epic.json).
      assert stats.save_breakdown.epic_term == 10
      assert stats.bab_breakdown.epic_term == 11
    end

    # source: priv/rules/vanilla/epic.json — even character levels 22…40 give +1
    # to all three saves (10 by level 40); level 41 is odd, so Siala's cap adds
    # nothing to the saves while adding a +1 to attack.
    #
    # The boundaries in one table, and the pair 40/41 is the whole point: BAB
    # gains its eleventh point on the 41st and the saves do not.
    test "the window and the epic term at 1, 20, 21, 22, 40 and 41", %{ruleset: ruleset} do
      # {character level, counted, ignored, epic saves, epic attack, base fort}
      table = [
        {1, 1, 0, 0, 0, 2},
        {20, 20, 0, 0, 0, 12},
        {21, 20, 1, 0, 1, 12},
        {22, 20, 2, 1, 1, 13},
        {40, 20, 20, 10, 10, 22},
        {41, 20, 21, 10, 11, 22}
      ]

      for {level, counted, ignored, epic_save, epic_attack, fort} <- table do
        stats = compute(ruleset, List.duplicate(:fighter, level))

        assert stats.save_breakdown.by_class == [
                 %{
                   class: :fighter,
                   levels_counted: counted,
                   levels_taken: level,
                   levels_ignored: ignored,
                   progressions: %{fort: "good", ref: "poor", will: "poor"},
                   subtotals: %{
                     fort: 2 + div(counted, 2),
                     ref: div(counted, 3),
                     will: div(counted, 3)
                   }
                 }
               ],
               "fighter #{level}"

        assert stats.save_breakdown.epic_term == epic_save, "fighter #{level} epic saves"
        assert stats.bab_breakdown.epic_term == epic_attack, "fighter #{level} epic attack"
        assert stats.base_fort == fort, "fighter #{level} fort"
      end
    end

    # source: fighter 4 -> 4/1/1; dwarven_defender 10 revid 71576 -> 7/3/7 (fort
    #   and will primary); weapon_master 6 revid 71993 -> 2/5/2 (ref primary);
    #   rogue's seventeen are past 20. 4 + 10 + 6 = 20 counted levels.
    test "four classes at the cap: every one named on every save", %{ruleset: ruleset} do
      stats =
        compute(
          ruleset,
          List.duplicate(:fighter, 4) ++
            List.duplicate(:dwarven_defender, 10) ++
            List.duplicate(:weapon_master, 10) ++ List.duplicate(:rogue, 17)
        )

      assert stats.character_level == 41

      assert Enum.map(stats.save_breakdown.by_class, &{&1.class, &1.levels_counted, &1.subtotals}) ==
               [
                 {:fighter, 4, %{fort: 4, ref: 1, will: 1}},
                 {:dwarven_defender, 10, %{fort: 7, ref: 3, will: 7}},
                 # ⚠ Six of its ten levels landed inside the window, and the row
                 # says so rather than claiming ten.
                 {:weapon_master, 6, %{fort: 2, ref: 5, will: 2}},
                 {:rogue, 0, %{fort: 0, ref: 0, will: 0}}
               ]

      assert Enum.map(stats.save_breakdown.by_class, & &1.levels_ignored) == [0, 0, 4, 17]

      # 13 + 10 epic, 9 + 10, 10 + 10 — the terms above, summed.
      assert {stats.base_fort, stats.base_ref, stats.base_will} == {23, 19, 20}
    end

    # source: fandom "Base save", section "Multiclassing benefits", its own two
    # examples word for word: «the base fortitude save of a 10/10
    # fighter/barbarian» is +14 and «an 8/6/6 fighter/barbarian/ranger» is +16,
    # against a single class's ceiling of +12.
    #
    # ⚠ This is why the per-class breakdown of a save teaches something its
    # base-attack twin cannot. Base attack is nearly linear in levels, so a
    # multiclass build only ever loses; a save gains **+2 for every class's own
    # first level**, so three classes beat one — and one number labelled «база»
    # said nothing about where that came from.
    test "the +2 a class's first level grants is visible per class", %{ruleset: ruleset} do
      single = compute(ruleset, List.duplicate(:fighter, 20))
      two = compute(ruleset, List.duplicate(:fighter, 10) ++ List.duplicate(:barbarian, 10))

      three =
        compute(
          ruleset,
          List.duplicate(:fighter, 8) ++
            List.duplicate(:barbarian, 6) ++ List.duplicate(:ranger, 6)
        )

      assert single.base_fort == 12
      assert two.base_fort == 14
      assert three.base_fort == 16

      assert Enum.map(two.save_breakdown.by_class, &{&1.class, &1.subtotals.fort}) ==
               [{:fighter, 7}, {:barbarian, 7}]

      assert Enum.map(three.save_breakdown.by_class, &{&1.class, &1.subtotals.fort}) ==
               [{:fighter, 6}, {:barbarian, 5}, {:ranger, 5}]
    end

    # ⚠ There is no shard override to show here, unlike base attack (Siala moves
    # the monk from medium to high), and that is a fact about the data rather
    # than a hole in this test: not one of the 23 classes carries a `saves`
    # change in `siala_41/classes.json`. This test is the sentinel for the day
    # one does — the breakdown has to explain the number by the ruleset it was
    # computed with, and if a shard label ever diverges the fixture below stops
    # being true and somebody has to look.
    test "both rulesets carry the same save labels — and say so out loud", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      diverging =
        for {id, class} <- Enum.sort(ruleset.classes),
            vanilla_class = vanilla.classes[id],
            class.save_progressions != vanilla_class.save_progressions,
            do: {id, class.save_progressions, vanilla_class.save_progressions}

      assert diverging == [],
             """
             У этих классов метки сейвов на Сиале отличаются от ванильных. Само по
             себе это законно (шард переписывает классы), но разбор сейвов обязан
             объяснять число по ТОМУ ruleset'у, по которому оно посчитано, —
             проверьте, что `save_breakdown` показывает сиальское, и заведите
             кейс, как у монаха с BAB.

             #{inspect(diverging, pretty: true)}
             """

      # Положительный контроль к пустому списку выше: метки вообще есть, и они
      # доезжают до разбора, а не читаются нулём.
      assert [%{progressions: %{fort: "good", ref: "good", will: "good"}}] =
               compute(ruleset, List.duplicate(:monk, 20)).save_breakdown.by_class

      # И у монаха, у которого шард переписал BAB, сейвы остались ванильными —
      # ровно то, что говорит `siala_41/classes.json`.
      assert compute(ruleset, List.duplicate(:monk, 20)).save_breakdown ==
               compute(vanilla, List.duplicate(:monk, 20)).save_breakdown
    end

    # `levels_counted + levels_ignored == levels_taken`, the three saves'
    # subtotals reconstructing the three totals, and the two breakdowns of one
    # build agreeing about its classes — over a corpus rather than one build.
    #
    # ⚠ The reconstruction is a **contract statement**, not a corruption
    # detector: the totals are summed from these very rows. It is asserted
    # because the whole web layer stands on it — a caption whose parts do not add
    # up to the number beside them is worse than no caption. The detectors are
    # the literal lists above.
    test "the counts agree, the subtotals reconstruct the saves, and the two breakdowns match", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      corpus = [
        [],
        [:fighter],
        List.duplicate(:monk, 41),
        List.duplicate(:sorcerer, 20) ++ List.duplicate(:pale_master, 10),
        List.duplicate(:rogue, 30) ++ List.duplicate(:fighter, 11),
        List.duplicate(:bard, 7) ++
          List.duplicate(:shadowdancer, 10) ++
          List.duplicate(:rogue, 14) ++ List.duplicate(:harper_scout, 5)
      ]

      for levels <- corpus, rules <- [ruleset, vanilla] do
        stats = compute(rules, levels)
        breakdown = stats.save_breakdown
        where = "#{rules.version}: #{inspect(Enum.uniq(levels))}"

        for {save, total} <- [
              {:fort, stats.base_fort},
              {:ref, stats.base_ref},
              {:will, stats.base_will}
            ] do
          subtotals =
            for term <- breakdown.by_class,
                n = Map.fetch!(term.subtotals, save),
                is_integer(n),
                do: n

          assert Enum.sum(subtotals) + breakdown.epic_term == total, "#{where} #{save}"
        end

        for term <- breakdown.by_class do
          assert term.levels_counted + term.levels_ignored == term.levels_taken,
                 "#{where} #{term.class}"
        end

        assert Enum.sum(Enum.map(breakdown.by_class, & &1.levels_counted)) ==
                 min(stats.character_level, breakdown.counted_levels),
               where

        # One traversal, two breakdowns: a build cannot be told that its rogue
        # gave nothing to attack while giving something to Fortitude.
        assert Enum.map(
                 breakdown.by_class,
                 &Map.take(&1, [:class, :levels_counted, :levels_taken])
               ) ==
                 Enum.map(
                   stats.bab_breakdown.by_class,
                   &Map.take(&1, [:class, :levels_counted, :levels_taken])
                 ),
               where

        assert breakdown.counted_levels == stats.bab_breakdown.counted_levels, where
      end
    end

    test "an empty build breaks down to an empty list, not nil", %{ruleset: ruleset} do
      assert compute(ruleset, []).save_breakdown == %{
               by_class: [],
               epic_term: 0,
               counted_levels: 20
             }
    end

    # ⚠ `nil` per save, never `0`, and all three at once: fort, ref and will are
    # read out of one row of the progression table, so a row that cannot be read
    # is three unknowns rather than one. The gap names the missing row.
    test "an unreadable progression row is three nils and a gap, not three zeroes", %{
      ruleset: ruleset
    } do
      # Weapon Master's table stops at class level 10 (`max_level`), so asking
      # for 15 has no honest answer — the same build the base-attack breakdown
      # uses for this, so the two agree about what is unknown.
      stats = compute(ruleset, List.duplicate(:weapon_master, 15))

      assert [
               %{
                 class: :weapon_master,
                 levels_counted: 15,
                 subtotals: %{fort: nil, ref: nil, will: nil}
               }
             ] = stats.save_breakdown.by_class

      assert {:missing_data, {:class_progression, :weapon_master, 15}} in stats.gaps

      # Positive control: inside its table the same class is three plain numbers,
      # so the nils above are about the missing row and not about the class.
      assert [%{subtotals: %{fort: 3, ref: 7, will: 3}}] =
               compute(ruleset, List.duplicate(:weapon_master, 10)).save_breakdown.by_class
    end
  end

  describe "attack bonus and armour class" do
    test "attack bonus is base attack plus strength", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 10),
          base_abilities: %{str: 18, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      stats = Rules.compute(build, ruleset)

      assert stats.base_attack == 10
      assert stats.attack_bonus == 14
    end

    test "naked armour class is the ruleset base plus dexterity", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: [:rogue],
          base_abilities: %{str: 10, dex: 18, con: 10, int: 10, wis: 10, cha: 10}
        )

      assert Rules.compute(build, ruleset).ac_naked == ruleset.base_ac + 4
    end
  end

  describe "saves" do
    test "each save adds its governing ability modifier", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 10, dex: 14, con: 16, int: 10, wis: 8, cha: 10}
        )

      stats = Rules.compute(build, ruleset)

      # base 12/6/6 (fandom "Fighter" revid 71988) + CON 3 / DEX 2 / WIS -1
      assert {stats.fort, stats.ref, stats.will} == {15, 8, 5}
    end

    # source: fandom "Spellcraft" revid 68572 — +1 to every saving throw per 5
    # ranks. CLAUDE.md §3 calls this "заметный вклад, который игроки не считают",
    # which is why it is a term of its own rather than folded into the totals.
    test "Spellcraft ranks add to all three saves", %{ruleset: ruleset} do
      naked = Build.new(levels: List.duplicate(:wizard, 20))
      learned = %{naked | skills: %{20 => %{spellcraft: 23}}}

      before = Rules.compute(naked, ruleset)
      after_ = Rules.compute(learned, ruleset)

      assert before.skill_save_bonus == 0
      # 23 ranks -> +4, on each of the three
      assert after_.skill_save_bonus == 4
      assert after_.save_bonus == %{fort: 4, ref: 4, will: 4}

      assert {after_.fort - before.fort, after_.ref - before.ref, after_.will - before.will} ==
               {4, 4, 4}

      # ...and the base saves are untouched: this is a bonus, not progression
      assert {after_.base_fort, after_.base_ref, after_.base_will} ==
               {before.base_fort, before.base_ref, before.base_will}
    end

    # source: siala_41/overrides.json → stat_caps.saving_throw_bonus (+20) and
    # _vanilla_constants_confirmed.skill_save_bonus.counts_toward_cap
    # (`source: user`). One ceiling over both sources — clipping them separately
    # would let a build carry +40 while every source says +20.
    test "gear and Spellcraft share one +20 ceiling", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:wizard, 20),
          skills: %{20 => %{spellcraft: 40}},
          gear: BuildCalculator.Rules.Gear.new(saves: 15)
        )

      stats = Rules.compute(build, ruleset)

      # 40 ranks -> +8 from the skill, +15 typed, 23 asked for, 20 allowed
      assert stats.skill_save_bonus == 8
      assert stats.gear_save_bonus == 15
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 20}
      # ⚠️ Three flags (task 1.12a), not one shared `:saving_throws` — both
      # sources here are save-agnostic, so all three legitimately hit the
      # ceiling together; a build with a save-specific source (`Iron will`)
      # could cap only one.
      assert :fort_save in stats.capped
      assert :ref_save in stats.capped
      assert :will_save in stats.capped
      assert stats.will == stats.base_will + 20
    end

    # The bonus is not flat in either ruleset — vanilla gives it against spells
    # only and Siala takes it off area spells besides. Showing it flat is Дан's
    # decision; saying nothing about it would not be (CLAUDE.md §3).
    test "the flat Spellcraft bonus admits it is not flat", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:wizard, 20), skills: %{20 => %{spellcraft: 10}})

      assert {:not_modelled, {:save_bonus_scope, :spellcraft}} in Rules.compute(build, ruleset).gaps
    end

    # Fewer than five ranks buy nothing, so there is nothing to caveat either.
    test "no bonus, no caveat", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:wizard, 20), skills: %{20 => %{spellcraft: 4}})
      stats = Rules.compute(build, ruleset)

      assert stats.skill_save_bonus == 0
      refute {:not_modelled, {:save_bonus_scope, :spellcraft}} in stats.gaps
    end
  end

  # source: siala_41/skills.json → global.multiclass_stealth_penalty (Скрытность
  # revid 19465). The only rule about skills that depends on the shape of the
  # whole build, so it belongs to the computed stats and not to a class record.
  describe "skill modifiers" do
    test "a fourth class costs Hide and Move Silently a point a level", %{ruleset: ruleset} do
      levels =
        List.duplicate(:rogue, 20) ++
          List.duplicate(:shadowdancer, 10) ++
          List.duplicate(:ranger, 5) ++ List.duplicate(:fighter, 5)

      stats = Rules.compute(Build.new(levels: levels), ruleset)

      assert stats.skill_modifiers == %{hide: -5, move_silently: -5}
    end

    test "a build of three classes has none", %{ruleset: ruleset} do
      levels =
        List.duplicate(:rogue, 20) ++
          List.duplicate(:shadowdancer, 10) ++ List.duplicate(:fighter, 10)

      assert Rules.compute(Build.new(levels: levels), ruleset).skill_modifiers == %{}
    end
  end

  # ⚠️ Штраф со шмота — не «отсутствие бонуса», а своё слагаемое со знаком.
  # Fandom «Ability cap» (revid 68173) описывает ровно эту ситуацию — «при STR,
  # сниженной на −2, предметы дадут не больше +10 чистыми», — значит минус в
  # игре есть, и он обязан доезжать до HP, AB и сейвов. Форма его отбрасывала:
  # `max(0)` превращал введённое `−4` в ноль, и считался билд, которого никто
  # не вводил.
  describe "gear penalties" do
    # 20 уровней Fighter, hit die 10, CON 10 → ровно 200 HP до вещей.
    # −4 CON это −2 к модификатору, то есть −2 HP на КАЖДОМ уровне: −40.
    # Тот же каскад, что у бонуса, только в другую сторону (CLAUDE.md §6).
    # 200 из хит-дайсов плюс 20 от Toughness, который Сиала выдаёт воину даром
    # (задача 1.9), плюс 20 от «Духа Сиалы» — флэт, который вещи не двигают
    # ни в одну сторону (задача, волна 12): фиты и Дух Сиалы стоят своими
    # слагаемыми и не сдвигаются от вещей, а ±4 CON по-прежнему двигают
    # по ±2 на каждом из 20 уровней.
    test "a CON penalty comes off every level's hit points", %{ruleset: ruleset} do
      naked = fighter_20()

      assert Rules.compute(naked, ruleset).hp == 220 + 20
      assert Rules.compute(with_gear(naked, abilities: %{con: -4}), ruleset).hp == 180 + 20
      assert Rules.compute(with_gear(naked, abilities: %{con: 4}), ruleset).hp == 260 + 20
    end

    # Fighter 20 — base attack 20, STR 10 без вещей. −4 STR это −2 к модификатору
    # и −2 к атаке; база при этом не двигается, штраф бьёт по бонусной части.
    test "a STR penalty comes off the attack bonus and leaves the base alone", %{
      ruleset: ruleset
    } do
      stats = Rules.compute(with_gear(fighter_20(), abilities: %{str: -4}), ruleset)

      assert stats.base_attack == 20
      assert stats.gear_attack_bonus == -2
      assert stats.attack_bonus == 18
    end

    # Fighter 20: base fort 12. −4 CON это −2, минус ещё −3 введённых в сейвы.
    test "penalties reach the saving throws from both places", %{ruleset: ruleset} do
      stats = Rules.compute(with_gear(fighter_20(), abilities: %{con: -4}, saves: -3), ruleset)

      assert stats.base_fort == 12
      assert stats.gear_save_bonus == -3
      assert stats.save_bonus == %{fort: -3, ref: -3, will: -3}
      assert stats.fort == 12 - 2 - 3
    end

    # Главное про штраф: он не должен молча исчезнуть. Раньше исчезал.
    test "a penalty survives the trip through the core", %{ruleset: ruleset} do
      stats = Rules.compute(with_gear(fighter_20(), abilities: %{con: -4}), ruleset)

      assert stats.gear_ability_bonuses.con == -4
      assert stats.abilities.con == 6
      assert stats.ability_modifiers.con == -2

      # Ничего не срезано: срезать нечего, потолок описан для бонуса.
      assert stats.capped == []
    end

    # Потолок односторонний, и это не недоделка: источник называет ceiling для
    # бонуса («This limit is a bonus of +12») и не называет пола. Зеркалить его
    # в −12 значило бы выдумать игровое число (CLAUDE.md §3, правило 1).
    test "the ceiling clips the bonus and never the penalty", %{ruleset: ruleset} do
      cap = ruleset.gear.ability_bonus_cap

      over = Rules.compute(with_gear(fighter_20(), abilities: %{con: cap + 8}), ruleset)
      under = Rules.compute(with_gear(fighter_20(), abilities: %{con: -(cap + 8)}), ruleset)

      assert over.gear_ability_bonuses.con == cap
      assert :gear_abilities in over.capped

      assert under.gear_ability_bonuses.con == -(cap + 8)
      assert under.capped == []
    end

    # ⚠️ Тест перевёрнут 22.08.2026 (задача 3.77). Здесь стояло «оговорка вики
    # про то, что штраф понижает сам потолок, не смоделирована — и сказано
    # об этом вслух», с `assert … in ruleset.gaps`.
    #
    # 🔴 Оговорка снята решением Dan, и не отмахиванием: взаимодействие
    # НЕВЫРАЗИМО в нашей форме ввода. Источник описывает штраф и прибавку
    # на ОДНУ характеристику из разных источников, а в «Вещах» на характеристику
    # приходится ровно одно число, и означает оно НЕТТО — игрок с кольцом +12
    # и проклятием −2 впишет +10 и получит верный ответ. Два других источника
    # штрафа мимо по словам самого источника: истинные расовые модификаторы
    # в потолок не входят, а заклинание — бафф (решение Dan 10.08.2026).
    #
    # ⚠️ Проверяется ОТСУТСТВИЕ, а рядом — что сам потолок цел: тест выше
    # («the ceiling clips the bonus and never the penalty») не тронут ни строкой,
    # то есть снято признание, а не механика.
    test "the ceiling's own caveat is no longer a declared gap", %{ruleset: ruleset} do
      refute {:not_modelled, :ability_cap_penalty_interaction} in ruleset.gaps

      # Положительный контроль: список гэпов не опустел вообще.
      assert ruleset.gaps != []
    end

    # «Голым» значит голым: ни бонус, ни штраф со шмота в `ac_naked` не входят,
    # включая DEX без его прибавки (CLAUDE.md §6).
    test "ac_naked ignores gear in both directions", %{ruleset: ruleset} do
      naked = fighter_20(%{str: 10, dex: 14, con: 10, int: 10, wis: 10, cha: 10})

      assert Rules.compute(naked, ruleset).ac_naked == ruleset.base_ac + 2

      for bonus <- [-4, 12] do
        stats = Rules.compute(with_gear(naked, abilities: %{dex: bonus}), ruleset)
        assert stats.ac_naked == ruleset.base_ac + 2
      end

      assert Rules.compute(with_gear(naked, abilities: %{dex: -4}), ruleset).ac_geared ==
               ruleset.base_ac + 0
    end

    test "an AC entry may go below zero and is simply summed", %{ruleset: ruleset} do
      stats = Rules.compute(with_gear(fighter_20(), ac: %{armor: 8, deflection: -2}), ruleset)

      assert stats.ac_gear_bonus == 6
      assert stats.ac_geared == ruleset.base_ac + 6
    end

    # Решение Dan 03.08.2026: общего потолка у AC нет — типы складываются, как
    # и складывались, — а у одного типа, «уклонения», он есть и равен +20.
    # Потолок лежит в данных (`stat_caps.dodge_ac`), не константой здесь.
    test "dodge AC is clipped at its ceiling and says so", %{ruleset: ruleset} do
      cap = ruleset.stat_caps.dodge_ac
      stats = Rules.compute(with_gear(fighter_20(), ac: %{dodge: cap + 5}), ruleset)

      assert stats.ac_gear_bonus == cap
      assert stats.ac_capped_types == [:dodge]
      assert :gear_ac in stats.capped
    end

    # Положительный контроль к предыдущему: `assert` на срез зеленел бы и у
    # реализации, которая режет вообще всё. Четыре остальных типа потолка не
    # имеют, и вместе они уходят далеко за +20 без единой пометки.
    test "the other AC types have no ceiling of their own", %{ruleset: ruleset} do
      over = ruleset.stat_caps.dodge_ac + 5
      ac = %{armor: over, shield: over, deflection: over, natural: over}
      stats = Rules.compute(with_gear(fighter_20(), ac: ac), ruleset)

      assert stats.ac_gear_bonus == over * 4
      assert stats.ac_capped_types == []
      refute :gear_ac in stats.capped
    end
  end

  describe "deltas" do
    # CLAUDE.md §5: the delta is the difference of two full computations, never a
    # separate incremental algorithm.
    test "preview_level_up/3 is compute/2 run twice", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 3))

      %{before: before_stats, after: after_stats} =
        Rules.preview_level_up(build, :wizard, ruleset)

      assert before_stats == Rules.compute(build, ruleset)
      assert after_stats == Rules.compute(Build.add_level(build, :wizard), ruleset)
      # wizard 1 adds +2 will and no base attack (revid 72067)
      assert after_stats.base_will - before_stats.base_will == 2
      assert after_stats.base_attack == before_stats.base_attack
    end

    test "truncate/2 drops every decision made above the level", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 5),
          ability_increases: %{4 => :str},
          feats: %{1 => %{general: :toughness}, 3 => %{general: :dodge}},
          skills: %{1 => %{discipline: 4}, 5 => %{discipline: 1}}
        )

      earlier = Build.truncate(build, 2)

      assert earlier.levels == [:fighter, :fighter]
      assert earlier.ability_increases == %{}
      assert earlier.feats == %{1 => %{general: :toughness}}
      assert earlier.skills == %{1 => %{discipline: 4}}

      # and the stats are those of a build that only ever had those two levels
      equivalent =
        Build.new(levels: [:fighter, :fighter], skills: %{1 => %{discipline: 4}})

      assert Rules.compute(earlier, ruleset) == Rules.compute(equivalent, ruleset)
    end
  end

  defp compute(ruleset, levels), do: Rules.compute(Build.new(levels: levels), ruleset)

  defp fighter_20(abilities \\ %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}) do
    Build.new(levels: List.duplicate(:fighter, 20), base_abilities: abilities)
  end

  defp with_gear(%Build{} = build, fields),
    do: %Build{build | gear: BuildCalculator.Rules.Gear.new(fields)}
end
