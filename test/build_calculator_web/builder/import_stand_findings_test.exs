defmodule BuildCalculatorWeb.Builder.ImportStandFindingsTest do
  @moduledoc """
  Task 4.36: the findings (I) of the reconciliation stand after task 4.33
  (`docs/ecb_reconcile.md`, sections «4.33» and «4.36») — where the import
  read the Epic Character Builders posts wrong or not at all, on the vanilla
  ruleset.

  🔴 Every fixture here is SYNTHETIC, written after the shape of real lines.
  The corpus has no licence and never enters the repository (VANILLA.md
  §3.7); `tools/vanilla_recon/` measures it locally.

  Each rule comes with its honesty, as in tasks 4.8 and 4.31: beside every
  form that now reads, a test of the nearby text that must NOT read, where
  reading it would be a guess.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Import

  setup do
    %{ruleset: Data.ruleset!("vanilla")}
  end

  defp picks(build),
    do: for({_level, _slot, feat, choice} <- Build.feat_picks(build, 41), do: {feat, choice})

  defp picked?(build, feat), do: Enum.any?(picks(build), &match?({^feat, _}, &1))
  defp takes(build, feat), do: Enum.count(picks(build), &match?({^feat, _}, &1))
  defp of_kind(result, kind), do: Enum.filter(result.issues, &(elem(&1, 0) == kind))

  # A Fighter ladder, `tail` for chosen levels.
  defp fighter(levels, tails, head \\ "Human, True Neutral") do
    ladder =
      for level <- 1..levels do
        "#{String.pad_leading(to_string(level), 2, "0")}: Fighter(#{level})" <>
          case Map.get(tails, level) do
            nil -> ""
            tail -> ": " <> tail
          end
      end

    head <> "\n" <> Enum.join(ladder, "\n") <> "\n"
  end

  defp saves(result), do: Enum.filter(result.source.totals, &(&1.id == :saves))

  defp rows(text, ruleset) do
    result = Import.parse(text, ruleset)
    {result, Import.comparison(result, Rules.compute(result.build, ruleset))}
  end

  describe "1. a bump on a level that grants none" do
    test "is not put into the build, and the level and the score are named", ctx do
      result = Import.parse(fighter(8, %{4 => "STR+1", 5 => "DEX+1", 8 => "STR+1"}), ctx.ruleset)

      assert result.build.ability_increases == %{4 => :str, 8 => :str}
      assert of_kind(result, :increase_off_level) == [{:increase_off_level, 5, :dex}]

      assert Rules.compute(result.build, ctx.ruleset).abilities.dex ==
               result.build.base_abilities.dex

      # Worded, and in the group the player reads for what did not come over.
      text = Import.issue_text({:increase_off_level, 5, :dex}, ctx.ruleset)
      assert text =~ "5"
      assert text =~ "DEX"
    end

    test "written out on the line under the level, the same", ctx do
      result = Import.parse(fighter(6, %{5 => "Dodge"}) <> "Con +1\n", ctx.ruleset)
      # The line is under the last level, 6.
      assert result.build.ability_increases == %{}
      assert of_kind(result, :increase_off_level) == [{:increase_off_level, 6, :con}]
    end

    test "NOT a bump off its level: one on a level that grants it says nothing", ctx do
      result = Import.parse(fighter(8, %{4 => "STR+1", 8 => "+1 Dex"}), ctx.ruleset)
      assert result.build.ability_increases == %{4 => :str, 8 => :dex}
      assert of_kind(result, :increase_off_level) == []
    end

    test "which levels grant one is the ruleset's, not a constant", ctx do
      ruleset =
        update_in(ctx.ruleset, [:epic, :ability_increase_levels], &MapSet.put(&1, 5))

      result = Import.parse(fighter(8, %{5 => "DEX+1"}), ruleset)
      assert result.build.ability_increases == %{5 => :dex}
      assert of_kind(result, :increase_off_level) == []
    end

    test "the level it missed is restored off the final score, as any unnamed one", ctx do
      text =
        fighter(8, %{5 => "DEX+1", 8 => "STR+1"}) <>
          "STR: 16 (17)\nDEX: 14 (15)\nCON: 14\nWIS: 10\nINT: 12\nCHA: 8\n"

      result = Import.parse(text, ctx.ruleset)

      assert result.build.ability_increases == %{4 => :dex, 8 => :str}
      assert of_kind(result, :increase_off_level) == [{:increase_off_level, 5, :dex}]
      assert [{:increases_restored, :dex, [4], 15}] = of_kind(result, :increases_restored)
    end
  end

  describe "2. the saves as a block: which column, which sign" do
    test "under `start/end` the final column — after a slash, in a bracket, after a dash",
         ctx do
      for {lines, want} <- [
            {"Fort 5/31\nReflex 1/20\nWill 1/24", "Fortitude: 31 / Reflex: 20 / Will: 24"},
            {"Fort: 3( 28)\nReflex: 2(18)\nWill: 3(33)", "Fortitude: 28 / Reflex: 18 / Will: 33"},
            {"Fortitude    4 - 23\nReflex    4 - 23\nWill    2 - 18",
             "Fortitude: 23 / Reflex: 23 / Will: 18"}
          ] do
        result = Import.parse("Saves ..start/end\n\n" <> lines <> "\n", ctx.ruleset)
        assert [%{value: ^want, form: :block}] = saves(result)
      end

      result =
        Import.parse(
          "Saving throws: starting - ending\nFortitude 4 - 23\nReflex 4 - 23\nWill 2 - 18\n",
          ctx.ruleset
        )

      assert [%{value: "Fortitude: 23 / Reflex: 23 / Will: 18"}] = saves(result)
    end

    test "a minus before the number is its sign; after the name it only parts them", ctx do
      result =
        Import.parse(
          "Saves ..start/end\nFort    -1/19\nReflex   1/21\nWill     2/21\n",
          ctx.ruleset
        )

      assert [%{value: "Fortitude: 19 / Reflex: 21 / Will: 21"}] = saves(result)

      result = Import.parse("Saves:\nFort -1\nRef: -2\nWill 3\n", ctx.ruleset)
      assert [%{value: "Fortitude: -1 / Reflex: -2 / Will: 3"}] = saves(result)
    end

    test "NOT a sign: `Fort-24`, `Fort - 24`; NOT the second column without `start/end`",
         ctx do
      result = Import.parse("Saves:\nFort-24\nRef - 22\nWill:33\n", ctx.ruleset)
      assert [%{value: "Fortitude: 24 / Reflex: 22 / Will: 33"}] = saves(result)

      # A slash under a caption that does not name the start and the end is
      # its second column, and the first is read.
      result = Import.parse("Saves:\nFort 24/27\nRef 25/28\nWill 24/27\n", ctx.ruleset)
      assert [%{value: "Fortitude: 24 / Reflex: 25 / Will: 24"}] = saves(result)

      # One number under `start/end` is the one read.
      result = Import.parse("Saves ..start/end\nFort: 20\nReflex: 21\nWill: 22\n", ctx.ruleset)
      assert [%{value: "Fortitude: 20 / Reflex: 21 / Will: 22"}] = saves(result)
    end

    test "`Saves start` is said to be the first level's, and not set against ours", ctx do
      {result, rows} =
        rows("01: Fighter(1)\nSaves start\nReflex 1\nFort 4\nWill -1\n", ctx.ruleset)

      assert [%{caveat: {:start, "Saves start"}}] = saves(result)
      row = Enum.find(rows, &(&1.label == "Saves start"))
      assert row.ours == "—"
      assert row.note =~ "Saves start"
    end

    test "NOT the start: `Saves ..start/end`, `Saving Throws (base)`, `Saves end`", ctx do
      for caption <- ["Saves ..start/end", "Saving Throws (base)", "Saves end"] do
        result = Import.parse(caption <> "\nFort 20\nReflex 21\nWill 22\n", ctx.ruleset)
        assert [%{caveat: nil}] = saves(result)
      end
    end
  end

  describe "3. the saves as a block: captions" do
    test "the columns named in words after the colon", ctx do
      for caption <- [
            "Saves: Normal [Raged]",
            "Saves: [Find a cloak of fortification if you fight casters]",
            "saves: buffed is with stat buffs. vs spells includes spellcraft"
          ] do
        result = Import.parse(caption <> "\n\nFort: 25 [28]\nReflex: 28\nWill: 19\n", ctx.ruleset)
        assert [%{form: :block, value: "Fortitude: 25 / Reflex: 28 / Will: 19"}] = saves(result)
      end
    end

    test "NOT a block: such a caption with no saves under it is the line of totals it was",
         ctx do
      result =
        Import.parse(
          "Saves: Reflex is low, but the immunity to fire will help\nThe rages are few a day.\n",
          ctx.ruleset
        )

      assert [
               %{
                 form: nil,
                 key: "Saves",
                 value: "Reflex is low, but the immunity to fire will help"
               }
             ] =
               Enum.map(saves(result), &Map.put_new(&1, :form, nil))

      assert Enum.any?(result.issues, &match?({:ignored_line, 2, _}, &1))
    end

    test "a remark in brackets between the caption and the saves", ctx do
      result =
        Import.parse(
          "Saves ..\n(All +4 Against spells)\nFort: 25.\nReflex: 15.\nWill: 18.\n",
          ctx.ruleset
        )

      assert [%{value: "Fortitude: 25 / Reflex: 15 / Will: 18"}] = saves(result)
      refute Enum.any?(result.issues, &match?({:ignored_line, _, _}, &1))
    end

    test "NOT two remarks, and NOT a remark after the first save", ctx do
      twice =
        Import.parse(
          "Saves ..\n(a remark)\n(another)\nFort: 25\nRef: 15\nWill: 18\n",
          ctx.ruleset
        )

      assert saves(twice) == []

      late = Import.parse("Saves:\nFort: 25\n(a remark)\nRef: 15\nWill: 18\n", ctx.ruleset)
      assert saves(late) == []
    end
  end

  describe "4. the saves as a block: what the caption says it is" do
    test "a shape named before the colon, the columns after it", ctx do
      text =
        "Saves while in Dragon Shape: (Spell save bonuses & feats)\nFort. 36 (44)\nRef. 33 (41)\nWill 39 (49)\n"

      assert [%{caveat: {:aside, :form, _}}] = saves(Import.parse(text, ctx.ruleset))

      # A header `X: (Y)` over the paragraph, the shape named before the colon.
      text =
        "Rakshasa form: (with barkskin, owl's insight)\nmax HP 520\nsaves:\nFort 32\nReflex 30\nWill 40\n"

      assert [%{caveat: {:aside, :form, _}}] = saves(Import.parse(text, ctx.ruleset))
    end

    test "NOT a shape: the race's own form; NOT a header: a total's own caption", ctx do
      text = "Human form: (no equipment)\nsaves:\nFort 28\nReflex 20\nWill 32\n"
      assert [%{caveat: nil}] = saves(Import.parse(text, ctx.ruleset))

      # `AB: (raging)` is a line of totals, not a rage over its paragraph.
      result = Import.parse("AB: (raging)\nHP: 400\n", ctx.ruleset)
      assert [%{caveat: nil}] = Enum.filter(result.source.totals, &(&1.id == :hp))
    end

    test "a buff that names a later column is not the block's", ctx do
      for {caption, lines} <- [
            {"Saves, buffed (vs. spells, buffed vs. spells):",
             "Fort: 24,26 (34,38)\nREF: 20, 22 (30,34)\nWill: 22,25 (32,37)"},
            {"Saves normal/buffed", "Fort 31/50\nRef  27/45\nWill 38/53"},
            {"Saves (vs spells)[Bard Song]",
             "Fort: 25 (34)[36]\nRefl: 19 (28)[30]\nWill: 30 (39)[41]"}
          ] do
        result = Import.parse(caption <> "\n" <> lines <> "\n", ctx.ruleset)
        assert [%{caveat: nil, legend: legend}] = saves(result)
        assert legend =~ "Saves"
      end
    end

    test "NOT when the text does not pair the names with the columns", ctx do
      # One bracket over one bracketed number: the whole block, or the bracket —
      # the text is the same, so the buff stands (and the saves are not compared).
      for {caption, lines} <- [
            {"Saves (Buffed)", "Fort 33 (41)\nRefl 25 (29)\nWill 33 (35)"},
            {"Saves while in rage", "FORT 39\nREFLEX 31\nWILL 26"}
          ] do
        result = Import.parse(caption <> "\n" <> lines <> "\n", ctx.ruleset)
        assert [%{caveat: {:aside, :buffed, _}} = total] = saves(result)
        refute Map.has_key?(total, :legend)
      end
    end

    test "a caption that names the columns is quoted beside the first one", ctx do
      {_result, rows} =
        rows(
          "01: Fighter(1)\nSaves (CoT Bonus)[vs. spells]:\nFort: 33 (46)[52]\nRefl: 27 (40)[46]\nWill: 24 (37)[43]\n",
          ctx.ruleset
        )

      row = Enum.find(rows, &String.starts_with?(&1.label, "Saves"))
      assert row.note =~ "Saves (CoT Bonus)[vs. spells]"
      refute row.ours == "—"
    end

    test "NOT quoted: one bracket over one column names no pairing", ctx do
      result =
        Import.parse(
          "Saves (vs spells):\nFort: 30 (40)\nRefl: 22 (32)\nWill: 24 (34)\n",
          ctx.ruleset
        )

      assert [total] = saves(result)
      refute Map.has_key?(total, :legend)
    end
  end

  describe "5. the ladder: feats under the level line" do
    test "a line of feats right under a level is that level's", ctx do
      text = """
      Human, True Neutral
      1. Fighter 1 Disc 4, Heal 4
      Luck of Heroes, Dodge
      2. Fighter 2 Disc 5
      Mobility
      """

      result = Import.parse(text, ctx.ruleset)
      assert length(result.build.levels) == 2
      assert picked?(result.build, :luck_of_heroes)
      assert picked?(result.build, :dodge)
      assert picked?(result.build, :mobility)
      refute Enum.any?(result.issues, &match?({:ignored_line, _, _}, &1))
    end

    test "NOT a remark, NOT across a blank line, NOT a name read by a guess", ctx do
      for below <- ["Knockdown is great for PvP", "\nDodge", "Luck of Heros"] do
        result =
          Import.parse("Human, True Neutral\n1. Fighter 1 Disc 4\n" <> below <> "\n", ctx.ruleset)

        assert picks(result.build) == []
        assert Enum.any?(result.issues, &match?({:ignored_line, _, _}, &1))
      end
    end

    test "under a level the ladder does not read, the line is still listed", ctx do
      # The second list is not the ladder: its lines and the one under them
      # are lines we did not use.
      text = fighter(2, %{}) <> "\n1. Wizard 1\nDodge\n"
      result = Import.parse(text, ctx.ruleset)
      assert Enum.any?(result.issues, &match?({:ignored_line, _, "Dodge"}, &1))
    end
  end

  describe "6. the ladder: the bump written into a feat's item" do
    test "after the feat's name — `+Dex`, `+Con 18`, `(+dex)`, `+1 Dex (17)`", ctx do
      tails = %{
        4 => "Power Attack +Dex",
        8 => "Cleave +Con 18",
        12 => "Dodge (+dex)",
        16 => "Mobility +1 Dex (17)"
      }

      result = Import.parse(fighter(16, tails), ctx.ruleset)
      assert result.build.ability_increases == %{4 => :dex, 8 => :con, 12 => :dex, 16 => :dex}

      for feat <- [:power_attack, :cleave, :dodge, :mobility],
          do: assert(picked?(result.build, feat))

      assert of_kind(result, :unknown_feat) == []
    end

    test "NOT a bump: `Great Dex +1 (23)`, `+2 Str` a class moved", ctx do
      result =
        Import.parse(
          fighter(22, %{21 => "Great Dex +1 (23)", 4 => "Dodge (+2 Str)"}),
          ctx.ruleset
        )

      assert result.build.ability_increases == %{}
      assert takes(result.build, :great_dexterity) == 1
    end

    test "the score before a feat: `CON(22)Epic…`, and grants after a score in brackets", ctx do
      tails = %{4 => "CON(16)Power Attack", 12 => "Dex 15 (Dodge, Mobility)"}
      result = Import.parse(fighter(12, tails), ctx.ruleset)

      assert result.build.ability_increases == %{4 => :con, 12 => :dex}
      assert picked?(result.build, :power_attack)
      assert picked?(result.build, :dodge)
      assert picked?(result.build, :mobility)
    end

    test "a feat's rank then the score: `Great Smiting 8 CHA(26)`; NOT a skill bought", ctx do
      result = Import.parse(fighter(8, %{8 => "Power Attack 2 CHA(16)"}), ctx.ruleset)
      assert result.build.ability_increases == %{8 => :cha}

      # `Tumble 4 Con 15`: the count before is a skill we know — two
      # purchases or a purchase and a score, not parted.
      result = Import.parse(fighter(8, %{8 => "Tumble 4 Con 15"}), ctx.ruleset)
      assert result.build.ability_increases == %{}
    end

    test "the score after the bump without brackets — `Wis=16`, `Dex = 19`", ctx do
      result =
        Import.parse(fighter(8, %{4 => "Wis=16", 8 => "Power Attack, Dex = 19"}), ctx.ruleset)

      assert result.build.ability_increases == %{4 => :wis, 8 => :dex}
      assert picked?(result.build, :power_attack)
    end

    test "NOT the bump: `(STR=16)` beside another, `Str = 20` on a level that grants none",
         ctx do
      result = Import.parse(fighter(8, %{4 => "CON+1, (STR=16)", 6 => "Str = 20"}), ctx.ruleset)
      assert result.build.ability_increases == %{4 => :con}
      assert of_kind(result, :increase_off_level) == []
    end
  end

  describe "7. the ladder: lists of increases" do
    test "`levels 4, 8 in Strength`, and a head on its own line", ctx do
      text = fighter(16, %{}) <> "Bumps: levels 4, 8 in Strength, levels 12 into Charisma\n"

      assert Import.parse(text, ctx.ruleset).build.ability_increases == %{
               4 => :str,
               8 => :str,
               12 => :cha
             }

      text = fighter(16, %{}) <> "Raise CON at:\nLevel 4; 8; 16\n"
      result = Import.parse(text, ctx.ruleset)
      assert result.build.ability_increases == %{4 => :con, 8 => :con, 16 => :con}
      refute Enum.any?(result.issues, &match?({:ignored_line, _, _}, &1))
    end

    test "`Increase Str- 4,8`, `Stats 4,8 Wisdom 12,16 Charisma`", ctx do
      text = fighter(16, %{}) <> "Increase Str- 4,8\nIncrease Con- 12\n"

      assert Import.parse(text, ctx.ruleset).build.ability_increases == %{
               4 => :str,
               8 => :str,
               12 => :con
             }

      text = fighter(16, %{}) <> "Stats 4,8 Wisdom 12,16 Charisma\n"

      assert Import.parse(text, ctx.ruleset).build.ability_increases ==
               %{4 => :wis, 8 => :wis, 12 => :cha, 16 => :cha}
    end

    test "NOT a list: a head no list follows, levels `in` no score", ctx do
      text = fighter(8, %{}) <> "Raise CON at:\nwhatever you like\n"
      result = Import.parse(text, ctx.ruleset)
      assert result.build.ability_increases == %{}
      assert Enum.any?(result.issues, &match?({:ignored_line, _, "Raise CON at:"}, &1))

      text = fighter(8, %{}) <> "Take levels 4, 8 in Fighter for the feats\n"
      assert Import.parse(text, ctx.ruleset).build.ability_increases == %{}

      # A level that grants none: the list is said to be unread, not placed.
      result = Import.parse(fighter(12, %{}) <> "Increase Dex- 4, 11\n", ctx.ruleset)
      assert result.build.ability_increases == %{}
      assert [{:increase_list_unread, [4, 11]}] = of_kind(result, :increase_list_unread)

      # Scores after the levels, but not a line of them.
      text = fighter(8, %{}) <> "I took 4, 8 Wisdom and more\n"
      assert Import.parse(text, ctx.ruleset).build.ability_increases == %{}
    end
  end

  describe "8. the ladder: tables and shorthand" do
    test "a tab parts the level's items; a skill bought before a feat is parted", ctx do
      text =
        "Human, True Neutral\n1\tFighter\tDodge\n2\tFighter\tDiscipline 1 Mobility\n3\tFighter\n4\tFighter\tPower Attack\tCon\n"

      result = Import.parse(text, ctx.ruleset)

      assert result.build.ability_increases == %{4 => :con}
      assert picked?(result.build, :mobility)
      assert result.build.skills[2] == %{discipline: 1}
      assert of_kind(result, :unknown_feat) == []
    end

    test "a skill bought, then a feat and the bump written out", ctx do
      result =
        Import.parse(fighter(4, %{4 => "Discipline 1 Power Attack Strength +1"}), ctx.ruleset)

      assert result.build.ability_increases == %{4 => :str}
      assert picked?(result.build, :power_attack)
      assert result.build.skills[4] == %{discipline: 1}
    end

    test "NOT parted: a skill we do not know, a tab where the class is", ctx do
      result = Import.parse(fighter(2, %{2 => "Intimiditate 2 Mobility"}), ctx.ruleset)
      assert [{:unknown_feat, 2, "Intimiditate 2 Mobility"}] = of_kind(result, :unknown_feat)

      # A tab between the class and its level: the plain reading stands.
      result = Import.parse("Human, True Neutral\n1 Fighter\t1\n2 Fighter\t2\n", ctx.ruleset)
      assert result.build.levels == [:fighter, :fighter]
    end

    test "a dash before the class's level parts it from the class: `Ftr -1-`", ctx do
      text = "Human, True Neutral\n(1) Ftr -1-\tDodge\n(2) Ftr -2-\tMobility\n"
      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter, :fighter]
      assert picked?(result.build, :dodge)
      assert picked?(result.build, :mobility)
    end

    # A Fighter's epic level has one slot Great Dexterity fits (the general
    # one): the take read is placed, or said to have no slot — never dropped.
    test "the next rank after a shortened name: `Great Dex II, III`", ctx do
      result =
        Import.parse(fighter(24, %{21 => "Great Dex I", 24 => "Great Dex II, III"}), ctx.ruleset)

      assert takes(result.build, :great_dexterity) == 2

      assert {:feat_no_slot, 24, :great_dexterity, {:no_free_slot, :great_dexterity}} in result.issues
    end

    test "NOT a rank: a numeral after a name that has none", ctx do
      result =
        Import.parse(fighter(24, %{21 => "Great Dex, II", 24 => "Dodge, III"}), ctx.ruleset)

      assert takes(result.build, :great_dexterity) == 1
      refute Enum.any?(result.issues, &match?({:feat_no_slot, _, :great_dexterity, _}, &1))
    end

    test "two names without a comma, each known for sure", ctx do
      result = Import.parse(fighter(24, %{21 => "Great Wis I Great Wis II"}), ctx.ruleset)
      assert takes(result.build, :great_wisdom) == 1
      assert {:feat_no_slot, 21, :great_wisdom, {:no_free_slot, :great_wisdom}} in result.issues
      assert of_kind(result, :unknown_feat) == []
    end

    test "NOT two names: one of them unknown", ctx do
      result = Import.parse(fighter(21, %{21 => "Great Wis I Xyzzy Plugh"}), ctx.ruleset)
      assert [{:unknown_feat, 21, "Great Wis I Xyzzy Plugh"}] = of_kind(result, :unknown_feat)
    end
  end

  describe "9. the sheet captioned by the last level" do
    @start "Starting Stats:\nSTR 16\nDEX 14\nCON 14\nWIS 10\nINT 12\nCHA 8\n"

    test "`Level 40 Stats:` is where the scores ended up", ctx do
      text =
        fighter(40, %{}) <>
          @start <> "\nLevel 40 Naked Stats:\nSTR 16\nDEX 24\nCON 14\nWIS 10\nINT 12\nCHA 8\n"

      result = Import.parse(text, ctx.ruleset)
      assert result.source.abilities["dex"] == %{start: 14, final: 24}
      assert [{:increases_restored, :dex, _, 24}] = of_kind(result, :increases_restored)
    end

    test "NOT the end: a level short of the cap", ctx do
      text =
        fighter(40, %{}) <>
          @start <> "\nLevel 20 Stats:\nSTR 16\nDEX 19\nCON 14\nWIS 10\nINT 12\nCHA 8\n"

      result = Import.parse(text, ctx.ruleset)
      assert result.source.abilities["dex"] == %{start: 14, final: nil}
      assert of_kind(result, :increases_restored) == []
    end
  end
end
