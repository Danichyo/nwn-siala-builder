defmodule BuildCalculatorWeb.Builder.ImportEcbTest do
  @moduledoc """
  Task 4.8: the text CBC prints and the shapes the Epic Character Builders
  archive writes, read on the vanilla ruleset — the edition that shows the
  import (VANILLA.md §1).

  🔴 Every fixture here is SYNTHETIC, written after the shape of real lines.
  The corpus the shapes were measured on has no licence and never enters the
  repository (VANILLA.md §3.7); `tools/vanilla_recon/` measures it locally.

  The four groups follow the task: a second numbered list must not overwrite
  the ladder (1), roman ranks and CBC's reminders (2), the header's own
  numbers (3), the tolerance edits of `docs/VANILLA_SPLIT.md` §7.4 (4) — and
  after them, the honesty each tolerance must not cost.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Import

  setup do
    %{ruleset: Data.ruleset!("vanilla")}
  end

  defp picks(build),
    do: for({_level, _slot, feat, choice} <- Build.feat_picks(build, 40), do: {feat, choice})

  defp picked?(build, feat), do: Enum.any?(picks(build), &match?({^feat, _}, &1))
  defp of_kind(result, kind), do: Enum.filter(result.issues, &(elem(&1, 0) == kind))

  describe "1. a second numbered list does not overwrite the ladder" do
    test "CBC's per-level skill chart is read as skills, and the ladder stays", ctx do
      text = """
      Human, Lawful Neutral
      LEVELING GUIDE
      01: Rogue(1): Dodge
      02: Rogue(2)
      03: Rogue(3): Mobility
      Skills by level guide
      01: Hide(4), Tumble(4), Move Silently(4), Save(20),
      02: Hide(1), Tumble(1), Save(25),
      03: Hide(1), UMD(2), Save(27),
      """

      result = Import.parse(text, ctx.ruleset)

      # Before task 4.8 the chart's `01:`…`03:` replaced the ladder's own lines,
      # and `Hide` did not read as a class: zero levels.
      assert result.build.levels == [:rogue, :rogue, :rogue]

      assert result.build.skills == %{
               1 => %{hide: 4, tumble: 4, move_silently: 4},
               2 => %{hide: 1, tumble: 1},
               3 => %{hide: 1, use_magic_device: 2}
             }

      # `Save(N)` — the points CBC carries on — is the format's word, not a skill.
      assert of_kind(result, :unknown_skill) == []
      assert of_kind(result, :unknown_class) == []
    end

    test "the chart reads as skills with no header over it, by its own lines", ctx do
      text = """
      01: Fighter(1): Power Attack
      02: Fighter(2): Cleave
      01: Discipline(4), Spot(2), Save(6)
      02: Discipline(1), Save(8)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter, :fighter]
      assert result.build.skills == %{1 => %{discipline: 4, spot: 2}, 2 => %{discipline: 1}}
    end

    test "a numbered list further down is not read into the ladder — it is listed", ctx do
      text = """
      01: Fighter(1): Power Attack
      02: Fighter(2)
      Two questions about this build:
      1. Why no Cleave?
      2. Is Dodge worth it?
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter, :fighter]
      assert {:ignored_line, 4, "1. Why no Cleave?"} in result.issues
      assert {:ignored_line, 5, "2. Is Dodge worth it?"} in result.issues
    end

    test "of two ladders the one naming more classes is read; the other is listed", ctx do
      text = """
      1. Buff before a fight
      2. Stay at range
      01: Wizard(1)
      02: Wizard(2)
      03: Wizard(3)
      Variant:
      01: Sorcerer(1)
      02: Sorcerer(2)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:wizard, :wizard, :wizard]
      assert {:ignored_line, 1, "1. Buff before a fight"} in result.issues
      assert {:ignored_line, 7, "01: Sorcerer(1)"} in result.issues
      assert {:ignored_line, 8, "02: Sorcerer(2)"} in result.issues
    end

    test "a stray numbered line neither cuts the ladder nor starts it", ctx do
      # `4 Intimidate` between levels 2 and 3 is a note; `0 leftover` above
      # the ladder is a count. Neither names a class or continues the count.
      text = """
      0 leftover
      01: Fighter(1): Power Attack
      02: Fighter(2)
      4 Intimidate
      03: Fighter(3): Cleave
      04: Fighter(4)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == List.duplicate(:fighter, 4)
      assert {:ignored_line, 1, "0 leftover"} in result.issues
      assert {:ignored_line, 4, "4 Intimidate"} in result.issues
      assert of_kind(result, :level_gap) == []
    end

    test "a level line with a bump in brackets is still a level, not a skill line", ctx do
      # `+1 (16)` before a bracket used to mark a line as skill purchases.
      text = """
      01: Monk: Dodge
      02: Monk:
      03: Monk: Weapon Finesse
      04: Monk: Int +1 (16)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == List.duplicate(:monk, 4)
      assert result.build.ability_increases == %{4 => :int}
      assert result.build.skills == %{}
    end

    test "a skill the chart repeats on every level is reported once", ctx do
      text = """
      01: Bard(1)
      02: Bard(2)
      03: Bard(3)
      01: Perform(4), Spcr(4), Save(10)
      02: Perform(1), Spcr(1), Save(12)
      03: Perform(1), Spcr(1), Save(14)
      """

      result = Import.parse(text, ctx.ruleset)

      assert of_kind(result, :unknown_skill) == [{:unknown_skill, 1, "Spcr"}]
      assert Build.skill_ranks(result.build, :perform, 3) == 6
    end
  end

  describe "2. roman ranks and CBC's reminders" do
    test "a roman rank reads as the feat it ranks — one more take each time", ctx do
      ladder =
        for level <- 1..24 do
          tail =
            case level do
              21 -> ": Great Strength I, (STR=17)"
              22 -> ": Epic Toughness I"
              24 -> ": STR+1, Great Strength II, Epic Toughness II, (STR=19)"
              _ -> ""
            end

          "#{String.pad_leading(to_string(level), 2, "0")}: Fighter(#{level})#{tail}"
        end

      text = "Human, True Neutral\n" <> Enum.join(ladder, "\n")

      result = Import.parse(text, ctx.ruleset)

      assert length(result.build.levels) == 24
      assert Enum.count(picks(result.build), &match?({:great_strength, _}, &1)) == 2
      assert Enum.count(picks(result.build), &match?({:epic_toughness, _}, &1)) == 2
      assert result.build.ability_increases[24] == :str

      # Positive control on the noise: nothing above was reported unread —
      # neither `Great Strength I` nor CBC's `(STR=19)`.
      assert of_kind(result, :unknown_feat) == []
    end

    test "what a class hands over, as CBC prints it, is left out and eats no neighbour", ctx do
      text = """
      Human, Lawful Neutral
      01: Monk(1): Dodge, M: (Cleave, Evasion, Improved Unarmed Strike, Stunning Fist)
      02: Monk(2): {Deflect Arrows}
      03: Monk(3): Mobility {Discipline 4, Spot 2}, (DEX=16)
      04: Monk(4): DEX+1, (DEX=17)
      05: Monk(5)
      06: Monk(6): Weapon Finesse, Ro: (Evasion), P: (Smite Evil)
      """

      result = Import.parse(text, ctx.ruleset)

      assert picked?(result.build, :dodge)
      assert picked?(result.build, :mobility)
      assert picked?(result.build, :weapon_finesse)
      assert result.build.ability_increases == %{4 => :dex}

      # The reminders are not picks and not complaints.
      refute picked?(result.build, :cleave)
      refute picked?(result.build, :stunning_fist)
      assert of_kind(result, :unknown_feat) == []
    end

    test "an alignment restriction is named as one, and no alignment is picked", ctx do
      for line <- ["Human, any neutral", "Human\nAlignment: Any non-lawful, non-evil"] do
        result = Import.parse(line <> "\n01: Druid(1)\n", ctx.ruleset)

        assert result.build.race == :human, line
        assert result.build.alignment == nil, line
        assert [{:alignment_restriction, _text}] = of_kind(result, :alignment_restriction)
        assert of_kind(result, :unknown_alignment) == [], line
      end

      # Positive control: the same labelled line with an alignment in it.
      result = Import.parse("Human\nAlignment: Lawful Good\n01: Paladin(1)\n", ctx.ruleset)
      assert result.build.alignment == :lawful_good
    end

    test "a choice after a colon, and the community's word-by-word shorthand", ctx do
      text = """
      01: Fighter(1): Weapon Focus: Warhammer, Power Attack
      02: Fighter(2): Imp Crit: Longsword
      03: Fighter(3): Weap. Spec: Warhammer
      """

      result = Import.parse(text, ctx.ruleset)

      assert {:weapon_focus, :warhammer} in picks(result.build)
      assert {:improved_critical, :longsword} in picks(result.build)
      assert {:weapon_specialization, :warhammer} in picks(result.build)
      assert of_kind(result, :unknown_feat) == []
    end
  end

  describe "3. the header's own numbers" do
    defp saves_row(text, ruleset) do
      result = Import.parse(text, ruleset)
      stats = Rules.compute(result.build, ruleset)
      {Import.comparison(result, stats), stats}
    end

    @sheet """
    Human, Lawful Neutral
    STR: 14
    DEX: 14
    CON: 14
    WIS: 8
    INT: 10
    CHA: 8
    01: Fighter(1)
    """

    test "the saves are set beside ours in the order the caption names them", ctx do
      {rows, stats} =
        saves_row(@sheet <> "Saving Throws (Fortitude/Will/Reflex): 4/-1/2\n", ctx.ruleset)

      # The test means something only if Reflex and Will differ.
      assert stats.ref != stats.will

      row = Enum.find(rows, &String.starts_with?(&1.label, "Saving Throws"))
      assert row.ours == labeled(fort: stats.fort, will: stats.will, ref: stats.ref)

      {rows, _} =
        saves_row(@sheet <> "Saving Throws (Fortitude/Reflex/Will): 4/2/-1\n", ctx.ruleset)

      row = Enum.find(rows, &String.starts_with?(&1.label, "Saving Throws"))
      assert row.ours == labeled(fort: stats.fort, ref: stats.ref, will: stats.will)
    end

    test "with no names in the caption, the value's own names give the order", ctx do
      {rows, stats} =
        saves_row(@sheet <> "Saving throws: Will -1, Fortitude 4, Reflex 2\n", ctx.ruleset)

      row = Enum.find(rows, &(&1.label == "Saving throws"))
      assert row.ours == labeled(will: stats.will, fort: stats.fort, ref: stats.ref)
    end

    test "`Abilities:` is not the attack bonus; `,` and `[` do not hide a caption", ctx do
      text = """
      Abilities: 14/14/14/8/10/8
      AB, melee: +5
      AC [naked]: 12
      01: Fighter(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert [%{id: :ab, key: "AB, melee"}] = Enum.filter(result.source.totals, &(&1.id == :ab))
      assert Enum.any?(result.source.totals, &match?(%{id: :ac, key: "AC [naked]"}, &1))
      refute Enum.any?(result.source.totals, &(&1.key == "Abilities"))
    end

    test "a caption that narrows the number is not the total", ctx do
      text = """
      Saving Throws (Fortitude/Reflex/Will): 4/2/-1
      Saves vs spells: +9
      Saving Throw bonuses: Fear +2
      01: Fighter(1)
      """

      saves = Import.parse(text, ctx.ruleset).source.totals |> Enum.filter(&(&1.id == :saves))

      assert [%{key: "Saving Throws (Fortitude/Reflex/Will)"}] = saves
    end

    defp signed(value) when value >= 0, do: "+#{value}"
    defp signed(value), do: Integer.to_string(value)

    # Task 4.40: each of ours carries its name, joined to its number by a
    # no-break space — `Fort +4 / Will -1 / Ref +2` in the caption's order.
    defp labeled(saves) do
      names = %{fort: "Fort", ref: "Ref", will: "Will"}
      Enum.map_join(saves, " / ", fn {save, value} -> "#{names[save]}\u00A0#{signed(value)}" end)
    end
  end

  describe "4. tolerance — docs/VANILLA_SPLIT.md §7.4" do
    test "every way a level is numbered reads", ctx do
      shapes = [
        {"1-", fn n, class -> "#{n}-#{class}(#{n})" end},
        {"01 ", fn n, class -> "#{pad(n)} #{class}" end},
        {"Lvl 1", fn n, class -> "Lvl #{n} #{class}" end},
        {"(01)", fn n, class -> "(#{pad(n)}) #{class}" end},
        {"Level 1", fn n, class -> "Level #{n}: #{class}" end},
        {"01 -", fn n, class -> "#{pad(n)} - #{class}" end},
        {"[01]", fn n, class -> "[#{pad(n)}] #{class}" end}
      ]

      for {name, line} <- shapes do
        text =
          [{1, "Fighter"}, {2, "Fighter"}, {3, "Wizard"}]
          |> Enum.map_join("\n", fn {n, class} -> line.(n, class) end)

        result = Import.parse(text, ctx.ruleset)

        assert result.build.levels == [:fighter, :fighter, :wizard],
               "#{name}: #{inspect(result.issues)}"
      end
    end

    test "`Race:` and `Alignment:` on lines of their own — first, not a title", ctx do
      text = """
      RACE: Dwarf
      ALIGNMENT: Lawful Good
      01: Fighter(1)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.race == :dwarf
      assert result.build.alignment == :lawful_good
      assert result.title == nil

      # Without the colon, when what follows is a race.
      assert Import.parse("Race Elf\n01: Wizard(1)\n", ctx.ruleset).build.race == :elf
    end

    test "a class with its own level written bare — `Fighter 1:`, `Rogue1 -`", ctx do
      text = """
      01: Fighter 1: Power Attack
      02: Fighter 2
      03: Rogue1 - Dodge
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter, :fighter, :rogue]
      assert picked?(result.build, :power_attack)
      assert picked?(result.build, :dodge)
    end

    test "`STR 16` without a colon, and the scores on one line", ctx do
      for sheet <- [
            "STR 16\nDEX 14\nCON 14\nWIS 10\nINT 12\nCHA 8",
            "Str - 16\nDexterity 14 (18)\nCon 14\nWis 10\nInt 12\nCha 8",
            "Str 16, Dex 14, Con 14, Wis 10, Int 12, Cha 8"
          ] do
        result =
          Import.parse("Human, Lawful Neutral\n" <> sheet <> "\n01: Fighter(1)\n", ctx.ruleset)

        assert result.build.base_abilities == %{
                 str: 16,
                 dex: 14,
                 con: 14,
                 wis: 10,
                 int: 12,
                 cha: 8
               },
               sheet
      end
    end

    test "of several score sheets, the first full one is the start", ctx do
      sheet = fn str -> "STR: #{str}\nDEX: 14\nCON: 14\nWIS: 10\nINT: 12\nCHA: 8" end

      # The start, then the end: the first full sheet.
      text =
        "Human, Lawful Neutral\n" <>
          sheet.(16) <> "\n01: Fighter(1)\nFinal stats:\n" <> sheet.(30)

      assert Import.parse(text, ctx.ruleset).build.base_abilities.str == 16

      # A shape's three scores first, then the character's full sheet: the full one.
      text =
        "Human, Lawful Neutral\nThe shape has these stats:\nSTR: 40\nDEX: 20\nCON: 30\nMy stats:\n" <>
          sheet.(12) <> "\n01: Druid(1)"

      assert Import.parse(text, ctx.ruleset).build.base_abilities == %{
               str: 12,
               dex: 14,
               con: 14,
               wis: 10,
               int: 12,
               cha: 8
             }
    end

    defp pad(n), do: String.pad_leading(to_string(n), 2, "0")
  end

  describe "honesty, which the tolerance above must not cost" do
    test "a class the author renamed is not read as the nearest one", ctx do
      # `Champion of` starts Champion of Torm; `Kord` does not end it.
      text = """
      01: Barbarian(1)
      02: Champion of Kord(1)
      03: Barbarian(2)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:barbarian]
      assert {:unknown_class, 2, "Champion of Kord"} in result.issues
      assert {:ladder_stopped, 1} in result.issues
    end

    # ⚠️ Task 4.31 reads the running totals (section 5 below); what stays
    # honest is that the line is never read as its FIRST class — the level
    # took Monk here, where the first name is Fighter.
    test "a ladder of running totals is not read as the first class, level after level", ctx do
      text = """
      1 Fighter1
      2 Fighter1/Monk1
      3 Fighter2/Monk1
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter, :monk, :fighter]
      assert of_kind(result, :unknown_class) == []
    end

    # ⚠️ Task 4.31: the misspelt feat is read now — as a guess the player is
    # told about. The class is what this test is about, and it stands.
    test "inside the ladder, a class followed by a misspelt feat is that class", ctx do
      text = """
      01 Monk Dodge
      02 Monk
      03 Monk Lighning Reflexes
      04 Monk
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == List.duplicate(:monk, 4)

      assert [{:feats_guessed, [{"Lighning Reflexes", :lightning_reflexes, 3}]}] =
               of_kind(result, :feats_guessed)

      # Positive control: a name one typo from no feat at all is still reported.
      unknown = Import.parse(String.replace(text, "Lighning Reflexes", "Frobnicate"), ctx.ruleset)
      assert unknown.build.levels == List.duplicate(:monk, 4)
      assert {:unknown_feat, 3, "Frobnicate"} in unknown.issues
      assert of_kind(unknown, :feats_guessed) == []
    end

    test "prose that starts with a class's name is not a ladder by itself", ctx do
      result = Import.parse("1. Paladin levels give Divine Grace early\n", ctx.ruleset)

      assert result.build.levels == []
    end

    test "a ladder that ends is not a gap — the numbered line after it is listed", ctx do
      text = """
      01: Cleric(1)
      02: Cleric(2)
      43 Concentration
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:cleric, :cleric]
      assert of_kind(result, :level_gap) == []
      assert {:ignored_line, 3, "43 Concentration"} in result.issues
    end

    test "a gap inside a ladder that goes on is still a gap", ctx do
      text = """
      01: Cleric(1)
      03: Cleric(2)
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:cleric]
      assert {:level_gap, 2, 3} in result.issues
    end

    test "a two-letter word is a guess only written as an abbreviation", ctx do
      guessed = Import.parse("01 SD Dodge\n02 SD\n", ctx.ruleset)
      assert guessed.build.levels == [:shadowdancer, :shadowdancer]
      assert [{:class_guessed, 1, "SD", :shadowdancer}] = of_kind(guessed, :class_guessed)

      refute Import.parse("2. Is Dodge worth it?\n", ctx.ruleset).build.levels != []
    end
  end
end
