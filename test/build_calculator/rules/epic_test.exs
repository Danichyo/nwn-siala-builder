defmodule BuildCalculator.Rules.EpicTest do
  @moduledoc """
  The epic rules (21+), where the calculator is easiest to get quietly wrong.

  Every number here comes from `priv/rules/vanilla/epic.json` (parsed off Fandom)
  or from `priv/rules/siala_41/overrides.json`; none is invented.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Epic}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "class levels taken after character level 20" do
    # source: fandom "Base attack" revid 54725, quoted verbatim in
    # epic.json/epic_attack_bonus.class_order_raw:
    # "a character taking 20 fighter levels then 20 wizard levels would have a
    #  base attack of 30 (and four attacks per round), while a character taking
    #  20 wizard levels then 20 fighter levels would have a base attack of 20
    #  (and two attacks per round)."
    test "Fighter 20 -> Wizard 20 gives base attack 30 and 4 attacks", %{siala: ruleset} do
      stats = compute(ruleset, List.duplicate(:fighter, 20) ++ List.duplicate(:wizard, 20))

      assert stats.character_level == 40
      assert stats.base_attack == 30
      assert stats.attacks_per_round == 4
      # 20 from the fighter levels that count, +10 epic
      assert stats.base_attack_at_20 == 20
      assert stats.epic_attack_bonus == 10
    end

    test "Wizard 20 -> Fighter 20 gives base attack 20 and 2 attacks", %{siala: ruleset} do
      stats = compute(ruleset, List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20))

      assert stats.character_level == 40
      assert stats.base_attack == 20
      assert stats.attacks_per_round == 2
      # 10 from the wizard levels that count, +10 epic; the fighter levels give nothing
      assert stats.base_attack_at_20 == 10
      assert stats.epic_attack_bonus == 10
    end

    # source: epic.json/epic_save_bonus.multiclass_raw — "To receive the base save
    # benefits of multiclassing, the additional classes must be taken prior to
    # character level 21." A class picked up in the epics does not even grant the
    # +2 its own first level would normally give.
    test "a class taken in the epics adds nothing to base saves", %{siala: ruleset} do
      wizard_only = compute(ruleset, List.duplicate(:wizard, 21))
      with_fighter = compute(ruleset, List.duplicate(:wizard, 20) ++ [:fighter])

      assert wizard_only.base_fort == with_fighter.base_fort
      assert wizard_only.base_ref == with_fighter.base_ref
      assert wizard_only.base_will == with_fighter.base_will
    end

    # source: fandom "Fighter" revid 71988 / "Wizard" revid 72067, progression
    # tables at class level 20: fighter 12/6/6, wizard 6/6/12.
    test "base saves at level 40 are the level-20 split plus +10", %{siala: ruleset} do
      fighter_first =
        compute(ruleset, List.duplicate(:fighter, 20) ++ List.duplicate(:wizard, 20))

      wizard_first = compute(ruleset, List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20))

      assert {fighter_first.base_fort, fighter_first.base_ref, fighter_first.base_will} ==
               {22, 16, 16}

      assert {wizard_first.base_fort, wizard_first.base_ref, wizard_first.base_will} ==
               {16, 16, 22}
    end
  end

  describe "epic bonus tables" do
    # source: epic.json/epic_attack_bonus.table — +1 on every odd level from 21,
    # reaching +10 at 39. epic_save_bonus.table — +1 to all three saves on every
    # even level from 22, reaching +10 at 40.
    test "odd levels raise attack, even levels raise saves", %{siala: ruleset} do
      table = [
        {20, 0, 0},
        {21, 1, 0},
        {22, 1, 1},
        {23, 2, 1},
        {24, 2, 2},
        {30, 5, 5},
        {39, 10, 9},
        {40, 10, 10}
      ]

      for {level, attack, save} <- table do
        assert Epic.attack_bonus(ruleset, level) == attack, "attack bonus at level #{level}"
        assert Epic.save_bonus(ruleset, level) == save, "save bonus at level #{level}"
      end
    end

    # source: siala_41/overrides.json epic.level_41_behaviour — grants
    # {base_attack: 1, saves: 0}; source kind "user" (Dan), Fandom's tables stop
    # at 40. Level 41 is odd, so it behaves like a vanilla epic odd level.
    test "Siala's level 41 gives +11 attack and leaves saves at +10", %{siala: ruleset} do
      assert Epic.attack_bonus(ruleset, 41) == 11
      assert Epic.save_bonus(ruleset, 41) == 10

      stats = compute(ruleset, List.duplicate(:fighter, 41))
      assert stats.epic_attack_bonus == 11
      assert stats.epic_save_bonus == 10
      # 20 from the fighter levels that count; levels 21..41 add only the epic bonus
      assert stats.base_attack == 31
    end

    test "vanilla stops at 40 and knows nothing of level 41", %{vanilla: ruleset} do
      assert ruleset.level_cap == 40
      assert Epic.attack_bonus(ruleset, 40) == 10
      assert Epic.attack_bonus(ruleset, 41) == 10
      assert Epic.save_bonus(ruleset, 40) == 10
    end
  end

  describe "attacks per round" do
    # source: epic.json/attacks_per_round — "a character's maximum number of
    # attacks is determined by his or her BAB at character level 20", confirmed
    # by three separate Fandom pages.
    test "the epic bonus never adds an attack", %{siala: ruleset} do
      at_20 = compute(ruleset, List.duplicate(:fighter, 20))
      at_41 = compute(ruleset, List.duplicate(:fighter, 41))

      assert at_20.attacks_per_round == 4
      assert at_41.attacks_per_round == 4
      assert at_41.base_attack > at_20.base_attack
    end

    # source: fandom "Attacks per round" revid 52042, BAB column of the table
    test "attacks follow the base attack a build actually has", %{siala: ruleset} do
      # rogue 10 -> BAB 7 (fandom "Rogue" revid 71583) -> 2 attacks
      assert compute(ruleset, List.duplicate(:rogue, 10)).attacks_per_round == 2
      # wizard 20 -> BAB 10 -> 2 attacks
      assert compute(ruleset, List.duplicate(:wizard, 20)).attacks_per_round == 2
      # fighter 6 -> BAB 6 -> 2 attacks; fighter 5 -> BAB 5 -> 1
      assert compute(ruleset, List.duplicate(:fighter, 6)).attacks_per_round == 2
      assert compute(ruleset, List.duplicate(:fighter, 5)).attacks_per_round == 1
    end

    # source: siala_41/classes.json — arcane_archer change "extra_attacks",
    # status "verified": «за каждые 10 уровней класс получает одну
    # дополнительную атаку (максимум 3 за 30 уровней в классе)». Прямо
    # противоречит ванильному «атаки фиксируются BAB'ом на 20-м», и с задачи
    # 3.72 это правило применяется, а не лежит оговоркой.
    #
    # ⚠️ Здесь стоял тест «модификатор, который нельзя вычислить, становится
    # гэпом»: условия правила лежали прозой, ядро их не читало, и Лучник-маг 30
    # показывал столько же атак, сколько лучник без единого уровня в классе.
    # Условия стали записями данных — падать этому тесту было правильно.
    #
    # Полный разбор правила и его условий — `AttackModifiersTest`; здесь только
    # то, ради чего этот файл существует: эпик ванильной клятве не изменяет,
    # а шард её ломает.
    test "the shard's Arcane Archer adds attacks the vanilla freeze forbids", %{siala: ruleset} do
      stats = compute(ruleset, List.duplicate(:fighter, 10) ++ List.duplicate(:arcane_archer, 10))

      # BAB 20 на 20-м уровне даёт 4 атаки по таблице; десять уровней класса —
      # пятую.
      assert stats.base_attack_at_20 == 20
      assert stats.attacks_per_round == 5

      assert stats.attacks_per_round_terms == [
               %{source: {:class, :arcane_archer}, kind: :extra_attacks, attacks: 1}
             ]

      # И оговорки за это больше не платится: правило посчитано, значит про него
      # нечего confess. Список гэпов билда при этом не пуст и пустым быть
      # не обязан — взятие переписанного шардом класса само по себе гэп.
      refute Enum.any?(stats.gaps, &match?({:not_modelled, {:extra_attacks, _}}, &1))
      refute {:not_modelled, {:class_change, :arcane_archer, "extra_attacks"}} in ruleset.gaps
    end

    test "vanilla carries no attack modifiers at all", %{vanilla: ruleset} do
      assert ruleset.attack_modifiers == []

      # И число у ванили ровно табличное: слой пуст, значит складывать не с чем.
      stats = compute(ruleset, List.duplicate(:fighter, 10) ++ List.duplicate(:arcane_archer, 10))
      assert stats.attacks_per_round == 4
      assert stats.attacks_per_round_terms == []
    end
  end

  describe "counted levels" do
    test "come from the ruleset, not a literal", %{siala: siala, vanilla: vanilla} do
      assert Epic.counted_levels(siala) == 20
      assert Epic.counted_levels(vanilla) == 20
      assert siala.epic_starts_at == 21
    end

    test "epic_level?/2 follows the ruleset threshold", %{siala: ruleset} do
      refute Epic.epic_level?(ruleset, 20)
      assert Epic.epic_level?(ruleset, 21)
    end
  end

  defp compute(ruleset, levels) do
    Rules.compute(Build.new(levels: levels), ruleset)
  end
end
