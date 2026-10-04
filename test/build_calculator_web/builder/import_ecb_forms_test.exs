defmodule BuildCalculatorWeb.Builder.ImportEcbFormsTest do
  @moduledoc """
  Task 4.31: the second pass over the Epic Character Builders archive — the
  forms the reconciliation stand of task 4.9 (`docs/ecb_reconcile.md`, kind
  (I)) found the import reading wrong or not at all, on the vanilla ruleset.

  🔴 Every fixture here is SYNTHETIC, written after the shape of real lines.
  The corpus has no licence and never enters the repository (VANILLA.md
  §3.7); `tools/vanilla_recon/` measures it locally.

  Each tolerance comes with its honesty: beside every form that now reads, a
  test of the nearby text that must NOT read, where reading it would be a
  guess — and a guess that does read is one the player is told about.
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
  defp takes(build, feat), do: Enum.count(picks(build), &match?({^feat, _}, &1))
  defp of_kind(result, kind), do: Enum.filter(result.issues, &(elem(&1, 0) == kind))

  defp guesses(result) do
    case of_kind(result, :feats_guessed) do
      [{:feats_guessed, list}] ->
        Enum.map(list, fn {text, reading, _level} -> {text, reading} end)

      [] ->
        []
    end
  end

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

  @sheet "STR: 16\nDEX: 14\nCON: 14\nWIS: 10\nINT: 12\nCHA: 8\n"

  describe "1. feat names written the way posts write them" do
    test "a misspelt name reads as a guess — one note for the whole build", ctx do
      text =
        fighter(24, %{
          1 => "Luck of Heros, Lighting Reflex",
          3 => "Iron Willl",
          6 => "Lighting Reflex",
          21 => "Armour Skin"
        })

      result = Import.parse(text, ctx.ruleset)

      assert picked?(result.build, :luck_of_heroes)
      assert picked?(result.build, :lightning_reflexes)
      assert picked?(result.build, :iron_will)
      assert picked?(result.build, :armor_skin)

      # One note, and each spelling once in it — `Lighting Reflex` was written
      # on two levels and is one guess.
      assert [{:feats_guessed, _}] = of_kind(result, :feats_guessed)

      assert guesses(result) == [
               {"Luck of Heros", :luck_of_heroes},
               {"Lighting Reflex", :lightning_reflexes},
               {"Iron Willl", :iron_will},
               {"Armour Skin", :armor_skin}
             ]

      assert Import.issue_kind(hd(of_kind(result, :feats_guessed))) ==
               Import.issue_kind({:class_guessed, 1, "Ftr", :fighter})

      assert of_kind(result, :unknown_feat) == []
    end

    test "Great <ability> the community's way", ctx do
      written = [
        {"GRT DEX I", :great_dexterity},
        {"Grt Dex II", :great_dexterity},
        {"GrWis", :great_wisdom},
        {"GTR CHA", :great_charisma},
        {"Great Chr", :great_charisma},
        {"GrDEX 22", :great_dexterity},
        {"Greater Wisdom", :great_wisdom},
        {"Greater Int", :great_intelligence},
        {"Great Inteelligence", :great_intelligence}
      ]

      # One on a level, on levels with an epic general slot.
      tails =
        written
        |> Enum.map(&elem(&1, 0))
        |> Enum.zip([21, 24, 27, 30, 33, 36, 39, 40, 38])
        |> Map.new(fn {t, l} -> {l, t} end)

      result = Import.parse(fighter(40, tails), ctx.ruleset)

      assert Enum.sort(guesses(result)) == Enum.sort(written)
      assert of_kind(result, :unknown_feat) == []
    end

    test "run together or marked up — `*ironwll*`, `#great wisdom I (WIS 21)#`", ctx do
      result =
        Import.parse(
          fighter(24, %{21 => "*ironwll*", 24 => "#great wisdom I (WIS 21)#"}),
          ctx.ruleset
        )

      assert picked?(result.build, :iron_will)
      assert picked?(result.build, :great_wisdom)
      assert of_kind(result, :unknown_feat) == []
      # The score after the feat is the source's arithmetic, not a choice lost.
      assert of_kind(result, :feat_qualifier_dropped) == []
    end

    test "NOT read: letters in order that make another word, or a stray letter", ctx do
      # `Stun` and `Song` are letters of Stonecunning in order, `DRII` of
      # Darkvision; `G.Cleave` is Great Cleave and `I.Evasion` Improved
      # Evasion — not Cleave and Evasion with a stray letter. None of these
      # may become a feat by the guess.
      result =
        Import.parse(
          fighter(2, %{1 => "Stun, Song, DRII", 2 => "G.Cleave, I.Evasion"}),
          ctx.ruleset
        )

      refute picked?(result.build, :stonecunning)
      refute picked?(result.build, :darkvision)
      refute picked?(result.build, :cleave)
      refute picked?(result.build, :evasion)
      assert guesses(result) == []
      assert length(of_kind(result, :unknown_feat)) == 5
    end

    test "`LoH`: the one of two a slot takes, as a guess — but not on a Paladin's level", ctx do
      result = Import.parse(fighter(1, %{1 => "LoH"}), ctx.ruleset)

      assert picked?(result.build, :luck_of_heroes)
      assert guesses(result) == [{"LoH", :luck_of_heroes}]

      # On a Paladin's level the same letters may be Lay on Hands, which the
      # class hands over: refused as ambiguous, not tossed for.
      paladin = Import.parse("Human, Lawful Good\n01: Paladin(1): LoH\n", ctx.ruleset)

      refute picked?(paladin.build, :luck_of_heroes)
      assert [{:ambiguous_feat, 1, "LoH", _}] = of_kind(paladin, :ambiguous_feat)
    end

    test "NOT guessed: two letters (`WS`), and a name a skill answers to (`MS`)", ctx do
      result = Import.parse(fighter(4, %{4 => "WS, MS"}), ctx.ruleset)

      refute picked?(result.build, :weapon_specialization)
      refute picked?(result.build, :maximize_spell)
      assert guesses(result) == []
    end

    test "a shorthand two feats share is settled by the choice written with it", ctx do
      # `ESF` is Epic Skill Focus and Epic Spell Focus; only the first takes Spot.
      result = Import.parse(fighter(21, %{21 => "ESF: Spot"}), ctx.ruleset)

      assert {:epic_skill_focus, :spot} in picks(result.build)
      assert guesses(result) == []
    end

    test "a value in another word form — `Electricity`, `Daggers` — as a guess", ctx do
      result =
        Import.parse(
          fighter(2, %{1 => "Resist Energy (Electricity)", 2 => "Weapon Focus (Daggers)"}),
          ctx.ruleset
        )

      assert {:resist_energy, :electrical} in picks(result.build)
      assert {:weapon_focus, :dagger} in picks(result.build)

      assert guesses(result) == [
               {"Electricity", {:resist_energy, :electrical}},
               {"Daggers", {:weapon_focus, :dagger}}
             ]
    end

    test "NOT a value: one with more written after it, or a typo inside the stem", ctx do
      result =
        Import.parse(
          fighter(2, %{1 => "Weapon Focus (Rapier Dex)", 2 => "Spell Focus (Evokation)"}),
          ctx.ruleset
        )

      assert {:feat_choice_unknown, 1, :weapon_focus, "Rapier Dex"} in result.issues
      assert {:feat_choice_unknown, 2, :spell_focus, "Evokation"} in result.issues
      assert guesses(result) == []
    end

    test "`Great Wisdom I & II` is two takes; a bare numeral with nothing before it is not",
         ctx do
      # Level 22 is a Fighter's epic bonus level as well as a general one's
      # neighbour: whatever the slots, the text asked for two takes.
      result = Import.parse(fighter(24, %{21 => "Great Wisdom I & II (WIS 22)"}), ctx.ruleset)

      assert takes(result.build, :great_wisdom) +
               Enum.count(result.issues, &match?({:feat_no_slot, 21, :great_wisdom, _}, &1)) == 2

      lone = Import.parse(fighter(24, %{21 => "Dodge, II"}), ctx.ruleset)
      assert takes(lone.build, :dodge) == 1
      assert of_kind(lone, :unknown_feat) == []
    end

    test "which slot the author meant is passed over, not read as the choice", ctx do
      result =
        Import.parse(
          fighter(24, %{21 => "(Bonus Feat): Epic Toughness", 24 => "CFeat: Armor Skin"}),
          ctx.ruleset
        )

      assert picked?(result.build, :epic_toughness)
      assert picked?(result.build, :armor_skin)
      assert of_kind(result, :feat_qualifier_dropped) == []
    end
  end

  describe "2. the ability increase on the level line" do
    test "a bump written out beats a score read off a bare name or a bracket", ctx do
      text =
        fighter(36, %{
          32 => "STR (31), CHA (8), CON +1 (21)",
          36 => "Great Charisma III (CHA 23), WIS +1 (WIS 22)"
        })

      result = Import.parse(text, ctx.ruleset)

      assert result.build.ability_increases[32] == :con
      assert result.build.ability_increases[36] == :wis
    end

    test "a score written into a feat's item: the bump on a bump level, a note elsewhere", ctx do
      result =
        Import.parse(
          fighter(14, %{12 => "Extend Spell Str 15", 14 => "Rapid Shot Wis 21"}),
          ctx.ruleset
        )

      assert result.build.ability_increases[12] == :str
      assert picked?(result.build, :extend_spell)
      refute Map.has_key?(result.build.ability_increases, 14)
      assert picked?(result.build, :rapid_shot)
      assert of_kind(result, :unknown_feat) == []
    end

    test "NOT a score: a count beside a skill bought — `Tumble 4 Con 5`", ctx do
      result = Import.parse(fighter(4, %{4 => "Tumble 4 Con 5"}), ctx.ruleset)
      refute result.build.ability_increases[4] == :con
    end

    test "a bump alone on the line right under its level is that level's", ctx do
      text = fighter(4, %{4 => "Great Cleave"}) <> "Con +1\n"
      assert Import.parse(text, ctx.ruleset).build.ability_increases == %{4 => :con}

      # Not under a level line: the next paragraph, listed as unused.
      apart = fighter(4, %{}) <> "Some notes\nCon +1\n"
      result = Import.parse(apart, ctx.ruleset)
      assert result.build.ability_increases == %{}
      assert Enum.any?(result.issues, &match?({:ignored_line, _, "Con +1"}, &1))
    end

    test "a list of increases apart from the ladder fills the levels it names", ctx do
      text = fighter(12, %{}) <> "Bump strength at levels: 4, 8\nBoost Dex at lvls 12\n"

      assert Import.parse(text, ctx.ruleset).build.ability_increases == %{
               4 => :str,
               8 => :str,
               12 => :dex
             }

      # A list that names a level granting no increase is not one — and a
      # feat taken at a level is not an increase at all.
      odd = fighter(12, %{}) <> "Raise Strength at levels 4, 9\n"
      result = Import.parse(odd, ctx.ruleset)
      assert result.build.ability_increases == %{}
      assert {:increase_list_unread, [4, 9]} in result.issues

      feat = fighter(28, %{}) <> "Great Charisma at lvl 27, 28\n"
      assert Import.parse(feat, ctx.ruleset).build.ability_increases == %{}
    end

    test "the unnamed increases, restored when the printed end leaves one answer", ctx do
      sheet = "STR: 16\nDEX: 14 (17)\nCON: 14\nWIS: 10\nINT: 12\nCHA: 8\n"
      result = Import.parse(fighter(12, %{}, "Human, True Neutral\n" <> sheet), ctx.ruleset)

      assert result.build.ability_increases == %{4 => :dex, 8 => :dex, 12 => :dex}
      assert [{:increases_restored, :dex, [4, 8, 12], 17}] = of_kind(result, :increases_restored)
    end

    test "NOT restored: two scores short, an end too far, no end at all", ctx do
      two = "STR: 16 (18)\nDEX: 14 (15)\nCON: 14\nWIS: 10\nINT: 12\nCHA: 8\n"
      result = Import.parse(fighter(12, %{}, "Human, True Neutral\n" <> two), ctx.ruleset)
      assert result.build.ability_increases == %{}

      assert [{:increases_unplaced, [4, 8, 12], %{str: 2, dex: 1}}] =
               of_kind(result, :increases_unplaced)

      # Four points above ours for three levels: gear, or a feat we did not read.
      far = "STR: 16\nDEX: 14 (18)\nCON: 14\nWIS: 10\nINT: 12\nCHA: 8\n"
      result = Import.parse(fighter(12, %{}, "Human, True Neutral\n" <> far), ctx.ruleset)
      assert result.build.ability_increases == %{}
      assert of_kind(result, :increases_unplaced) != []

      bare = Import.parse(fighter(8, %{}, "Human, True Neutral\n" <> @sheet), ctx.ruleset)
      assert [{:increases_unnamed, [4, 8]}] = of_kind(bare, :increases_unnamed)
    end
  end

  describe "3. score sheets" do
    defp base(text, ruleset),
      do: Import.parse(text <> "01: Fighter(1)\n", ruleset).build.base_abilities

    @want %{str: 14, dex: 18, con: 10, wis: 8, int: 14, cha: 12}

    test "one line under a caption, letters, a point-buy sum", ctx do
      assert base(
               "Human, True Neutral\nStarting Characteristics: STR:14, DEX:18, CON:10, WIS:8 , INT:14, CHA:12\n",
               ctx.ruleset
             ) ==
               @want

      letters = "Human, True Neutral\nS: 14\nD: 18 to 30\nC: 10\nW: 8\nI: 14\nCH: 12\n"
      assert base(letters, ctx.ruleset) == @want

      # From the point-buy minimum the first result is the start, a last one
      # the end — `DEX 8 + 6 +4/2 = 18 + 2 RDD = 20`.
      sums =
        "Human, True Neutral\nSTR 8+6 = 14\nDEX 8 + 6 +4/2 = 18 + 2 RDD = 20\nCON 10\nWIS 8\nINT 8 + 6 = 14\nCHA 8 + 4 = 12\n"

      assert base(sums, ctx.ruleset) == @want

      assert Import.parse(sums <> "01: Fighter(1)\n", ctx.ruleset).source.abilities["dex"] ==
               %{start: 18, final: 20}
    end

    test "NOT a sheet: a run of letters that stops short — listed, not swallowed", ctx do
      result = Import.parse("S: 14\nD: 18\nC: 10\n01: Fighter(1)\n", ctx.ruleset)

      assert result.source.abilities == %{}
      assert {:ignored_line, 1, "S: 14"} in result.issues
    end

    test "the start, wherever the post puts it", ctx do
      final = "FINAL BUILD\nABILITIES:\nStr: 30\nDex: 20\nCon: 12\nWis: 8\nInt: 14\nCha: 12\n"
      start = "STARTING ABILITIES:\nStr: 14\nDex: 18\nCon: 10\nWis: 8\nInt: 14\nCha: 12\n"
      assert base("Human\n" <> final <> start, ctx.ruleset) == @want

      columns =
        "Human\n" <>
          Enum.map_join(
            [
              {"Str", 26, 14},
              {"Dex", 18, 18},
              {"Con", 10, 10},
              {"Wis", 8, 8},
              {"Int", 14, 14},
              {"Cha", 12, 12}
            ],
            "\n",
            fn {a, final, start} -> "#{a}: #{final}     #{a}: #{start} (base 08+06)" end
          ) <> "\n"

      assert base(columns, ctx.ruleset) == @want

      # A sheet of single numbers captioned as the end is where the scores
      # ended up — never the start.
      ended = Import.parse("Human\nFinal stats:\n" <> @sheet <> "01: Fighter(1)\n", ctx.ruleset)
      assert ended.source.abilities == %{}
      assert {:abilities_missing} in ended.issues
    end

    test "the end written after the start: `/`, `->`, `to`, and a bracket of points spent", ctx do
      text =
        "Human\nStr 14 (6) to 26\nDex 16/28\nCon: 10 -> 12\nWis 8\nInt 14 (6)\nCha 12\n01: Fighter(1)\n"

      result = Import.parse(text, ctx.ruleset)

      assert result.source.abilities["str"] == %{start: 14, final: 26}
      assert result.source.abilities["dex"] == %{start: 16, final: 28}
      assert result.source.abilities["con"] == %{start: 10, final: 12}
      # `(6)` below the start is the points spent, not where INT ended up.
      assert result.source.abilities["int"] == %{start: 14, final: nil}
    end
  end

  describe "4. the race" do
    test "CBC's race line, and a race among the other parts of a line", ctx do
      for {line, race} <- [
            {"Human: (Quick to Master)", :human},
            {"Halfling: (Fearless, Good Aim, Lucky, Skill Affinity: Listen, Small Stature)",
             :halfling},
            {"Halfling:Any non Lawful", :halfling},
            {"Non-Evil, Human", :human},
            {"Lawful, Non-Evil, Human", :human},
            {"Human :Bard(23), Druid(15), Monk(2),", :human},
            {"Barbarian16, Ranger21, Assassin3, Human", :human},
            {"Cleric19/Bard20/Shadowdancer1, Human", :human},
            {"Elf Lawful Good", :elf},
            {"Human Any Chaotic", :human},
            {"Half elf of any non lawful alignment.", :half_elf},
            {"Human*, Lawful Neutral", :human},
            {"Race: Human / Alignment: Lawful Good", :human},
            {"Race\t\tHuman\t\t\tAlignment\tLawful Neutral", :human},
            {"Race - Elf. Subrace - Drow. Alignment - Neutral Evil", :elf},
            {"The EDR SCV ED Guy Halfling Bard 7 / Shadowdancer 26 / RDD 7", :halfling}
          ] do
        result = Import.parse("Intro\n" <> line <> "\n01: Fighter(1)\n", ctx.ruleset)
        assert result.build.race == race, "не прочиталось: #{line}"
      end
    end

    test "a misspelt race on a line that says `Race` — as a guess", ctx do
      result = Import.parse("Race: Hafling (he's small but quick)\n01: Rogue(1)\n", ctx.ruleset)

      assert result.build.race == :halfling
      assert [{:race_guessed, _, :halfling}] = of_kind(result, :race_guessed)

      # Out of a line that does not say it is the race, a near name is not one.
      prose = Import.parse("Intro\nHumam, Lawful Good\n01: Rogue(1)\n", ctx.ruleset)
      assert prose.build.race == nil
    end

    test "races to pick from: the author's pick, a sheet's caption, or nobody's", ctx do
      chosen =
        Import.parse("Race: Human or Elf (I choose human here)\n01: Rogue(1)\n", ctx.ruleset)

      assert chosen.build.race == :human
      assert [{:race_chosen, _, :human, [:human, :elf]}] = of_kind(chosen, :race_chosen)

      open = "Race: Human (for the extra skills) or Elf (for higher Dex)\n"
      nobody = Import.parse(open <> "01: Rogue(1)\n", ctx.ruleset)
      assert nobody.build.race == nil
      assert [{:race_alternatives, _, [:human, :elf]}] = of_kind(nobody, :race_alternatives)

      sheet = Import.parse(open <> "Human Stats\n" <> @sheet <> "01: Rogue(1)\n", ctx.ruleset)
      assert sheet.build.race == :human
      assert [{:race_by_sheet, _, :human, "Human Stats"}] = of_kind(sheet, :race_by_sheet)
      assert of_kind(sheet, :race_alternatives) == []
    end

    test "NOT a race: an adjective, prose, or a name beside something that is no class", ctx do
      for line <- [
            "Race: Elven Girl",
            "It plays well as human, and even better",
            "Halfling Daggermaster"
          ] do
        assert Import.parse("Intro\n" <> line <> "\n01: Rogue(1)\n", ctx.ruleset).build.race ==
                 nil,
               line
      end
    end
  end

  describe "5. the ladder's lines" do
    test "the class's level after a slash — `Wizard/9  Toughness`", ctx do
      text = "1  Wizard/1  Spell Penetration\n2  Wizard/2\n3  Wizard/3  Toughness\n"
      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:wizard, :wizard, :wizard]
      assert picked?(result.build, :toughness)
      assert of_kind(result, :unknown_feat) == []
    end

    test "running totals: the class whose count grew by one", ctx do
      text = """
      1 - rogue 1 (expertise)
      2 - rogue 2
      3 - rogue 2/shadowdancer 1 (hide in plain sight)
      4 - rogue 3/shadowdancer 1
      5 - brd 1/rogue 3/shadowdancer 1
      """

      result = Import.parse(text, ctx.ruleset)
      assert result.build.levels == [:rogue, :rogue, :shadowdancer, :rogue, :bard]
    end

    test "NOT read: a running total whose counts do not follow — the ladder stops", ctx do
      text = """
      1 - rogue 1
      2 - rogue 2
      3 - rogue 2/shadowdancer 2
      4 - rogue 3/shadowdancer 2
      """

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:rogue, :rogue]
      assert {:ladder_stopped, 2} in result.issues
    end

    test "a Cleric's domains as CBC prints them, and on the class's first level", ctx do
      cbc =
        Import.parse(
          "Human, Lawful Good\n01: Cleric(1): Dodge, Domain War, Domain Trickery\n",
          ctx.ruleset
        )

      assert cbc.build.class_choices == %{cleric: [:war, :trickery]}

      bracket = Import.parse("1 - Monk 1\n2 - Cleric 1 [Trickery, War]\n", ctx.ruleset)
      assert bracket.build.class_choices == %{cleric: [:trickery, :war]}

      line =
        Import.parse("Domains: Strength and Heal (recommended)\n01: Cleric(1)\n", ctx.ruleset)

      assert line.build.class_choices == %{cleric: [:strength, :healing]}
    end

    test "NOT a domain: a bare word on a later level, a line we cannot read whole", ctx do
      later =
        Import.parse(
          "01: Cleric(1): Domain War, Domain Magic\n02: Cleric(2): Strength\n",
          ctx.ruleset
        )

      assert later.build.class_choices == %{cleric: [:war, :magic]}

      unread = Import.parse("Domains: Air, Your Choice\n01: Cleric(1)\n", ctx.ruleset)
      assert unread.build.class_choices == %{}
      assert [{:class_choice_unread, _}] = of_kind(unread, :class_choice_unread)
    end
  end

  describe "6. the source's own numbers" do
    defp rows(text, ruleset) do
      result = Import.parse(text, ruleset)
      {result, Import.comparison(result, Rules.compute(result.build, ruleset))}
    end

    test "a caption that only says which total it is — `Base Max HP`, `Max HP`, `Naked AC`",
         ctx do
      {result, _} = rows("Base Max HP: 484\nNaked AC: 30\n01: Fighter(1)\n", ctx.ruleset)

      assert [%{id: :hp, key: "Base Max HP"}] = Enum.filter(result.source.totals, &(&1.id == :hp))
      assert [%{id: :ac}] = Enum.filter(result.source.totals, &(&1.id == :ac))
    end

    test "a companion's hit points are shown as its own, not set against ours", ctx do
      text = """
      01: Druid(1)
      HP: 12

      Animal Companion

      Ebon Panther
      AB: 27/22/17
      HP: 151
      Evasion

      The Power of Stealth
      AC: 18
      """

      {result, rows} = rows(text, ctx.ruleset)

      companion = Enum.find(rows, &(&1.source == "151"))
      assert companion.ours == "—"
      assert companion.note =~ "Animal Companion"

      # Positive control: the build's own row, and the one after the section.
      assert Enum.find(rows, &(&1.source == "12")).note == nil
      assert Enum.find(rows, &(&1.source == "18")).note == nil
      assert Enum.count(result.source.totals, &(Map.get(&1, :caveat) != nil)) == 2
    end

    test "buffs and a shape are said; a header saying the numbers are naked is not", ctx do
      # A header over its own paragraph, as posts write it; a line that only
      # mentions buffs in the middle of a list is no header over the numbers.
      text = """
      01: Fighter(1)

      With no buffs:
      HP: 12

      With buffs:
      HP: 20

      Cons:
      Spell buffs easy to dispel
      AC: 30
      """

      {_, rows} = rows(text, ctx.ruleset)

      assert Enum.find(rows, &(&1.source == "12")).note == nil
      assert Enum.find(rows, &(&1.source == "20")).note =~ "With buffs"
      assert Enum.find(rows, &(&1.source == "30")).note == nil
    end

    test "hit points the post says were rolled", ctx do
      text =
        "01: Fighter(1)\nHit Points: 9\nLevel 1\nHitpoint dice: 8\nLevel 2\nHitpoint dice: 4\n"

      {_, rows} = rows(text, ctx.ruleset)
      assert Enum.find(rows, &(&1.source == "9")).note =~ "Hitpoint dice: 8"

      # One such line is not a list of rolls.
      {_, rows} = rows("01: Fighter(1)\nHit Points: 9\nHitpoint dice: 8\n", ctx.ruleset)
      assert Enum.find(rows, &(&1.source == "9")).note == nil
    end

    test "the saves as three lines under their caption", ctx do
      text =
        "01: Fighter(1)\nSaving Throws:\nFortitude: 23\nReflex: 22 (+6 against spells)\nWill: 33\n"

      {result, rows} = rows(text, ctx.ruleset)

      assert [%{id: :saves, form: :block, value: "Fortitude: 23 / Reflex: 22 / Will: 33"}] =
               Enum.filter(result.source.totals, &(&1.id == :saves))

      stats = Rules.compute(result.build, ctx.ruleset)
      row = Enum.find(rows, &(&1.label == "Saving Throws"))

      assert row.ours ==
               "Fort\u00A0+#{stats.fort} / Ref\u00A0+#{stats.ref} / Will\u00A0+#{stats.will}"

      refute Enum.any?(result.issues, &match?({:ignored_line, _, _}, &1))
    end

    test "NOT a block: a sum inside it, or three lines with no caption", ctx do
      summed =
        Import.parse(
          "01: Fighter(1)\nSaves:\nFort: 20 + 3 = 23\nRef: 22\nWill: 33\n",
          ctx.ruleset
        )

      assert Enum.filter(summed.source.totals, &(&1.id == :saves)) == []
      assert Enum.any?(summed.issues, &match?({:ignored_line, _, "Saves:"}, &1))

      bare =
        Import.parse(
          "01: Fighter(1)\nFinal Stats\nFortitude: 23\nReflex: 22\nWill: 33\n",
          ctx.ruleset
        )

      assert Enum.filter(bare.source.totals, &(&1.id == :saves)) == []
    end
  end

  describe "7. forms the corpus showed while the stand was rebased" do
    defp sheet_of(text, ruleset),
      do: Import.parse(text <> "01: Fighter(1)\n", ruleset).build.base_abilities

    test "a feat and its choice with nothing between — `WF Heavy Crossbow`, `EWF Shortsword`",
         ctx do
      tails = %{2 => "WF Heavy Crossbow", 4 => "WS Heavy Crossbow", 21 => "EWF Shortsword"}
      result = Import.parse(fighter(24, tails), ctx.ruleset)

      assert {:weapon_focus, :heavy_crossbow} in picks(result.build)
      assert {:weapon_specialization, :heavy_crossbow} in picks(result.build)
      assert {:epic_weapon_focus, :shortsword} in picks(result.build)
      # The value settled `WF` (Weapon Focus, Weapon Finesse) and `WS` for sure.
      assert guesses(result) == []

      # NOT a choice: words after the name that are no value of it.
      prose = Import.parse(fighter(2, %{2 => "WF Something Else"}), ctx.ruleset)
      refute picked?(prose.build, :weapon_focus)
    end

    test "a word written twice, a longer ending: `Grt Dex Dex I`, `Blind Fighting`", ctx do
      result =
        Import.parse(fighter(24, %{1 => "Blind Fighting", 21 => "Grt Dex Dex I"}), ctx.ruleset)

      assert picked?(result.build, :blind_fight)
      assert picked?(result.build, :great_dexterity)
    end

    test "the score first — `(17 Char)` — and `Ability: Str (str16)`, `Chr (chr18)`", ctx do
      tails = %{
        4 => "(17 Char)",
        7 => "(16 Str)",
        8 => "Feat: Knockdown Ability: Str (str17)",
        12 => "Ability Chr (chr18)"
      }

      result = Import.parse(fighter(12, tails), ctx.ruleset)

      assert result.build.ability_increases == %{4 => :cha, 8 => :str, 12 => :cha}
      assert picked?(result.build, :knockdown)
      assert of_kind(result, :unknown_feat) == []
    end

    test "the number first — `14 STR` — as a whole sheet only", ctx do
      text = "Human\nStats:\n14 STR\n18 DEX\n10 CON\n14 INT\n8 WIS\n12 CHA\n"
      assert sheet_of(text, ctx.ruleset) == %{str: 14, dex: 18, con: 10, wis: 8, int: 14, cha: 12}

      # Three lines, not all six scores: `14 Int` may be fourteen ranks of Intimidate.
      short = Import.parse("14 STR\n18 DEX\n14 Int\n01: Fighter(1)\n", ctx.ruleset)
      assert short.source.abilities == %{}
    end

    test "a point-buy sheet from a race's minimum; a sum from ten elsewhere is where it started",
         ctx do
      dwarf =
        "Dwarf\nSTR 8+6 +4/2 = 16\nDEX 8 + 6 = 14\nCON 10 + 4 = 14\nINT 8 + 6 = 14\nWIS 8\nCHA 6\n01: Fighter(1)\n"

      assert Import.parse(dwarf, ctx.ruleset).source.abilities["con"] == %{start: 14, final: nil}

      grown = "Human\nSTR 16\nDEX 14\nCON 14\nINT 10 + 3 = 13\nWIS 10\nCHA 8\n01: Fighter(1)\n"
      assert Import.parse(grown, ctx.ruleset).source.abilities["int"] == %{start: 10, final: 13}
    end

    test "a misspelt score's name reads; a sheet short of some scores says so", ctx do
      typo =
        "Human\nStrenght: 14\nDexterity: 18\nConstitution: 10\nWisdom: 8\nIntelligence: 14\nCharisma: 12\n"

      assert sheet_of(typo, ctx.ruleset) == %{str: 14, dex: 18, con: 10, wis: 8, int: 14, cha: 12}

      short = Import.parse("Human\nSTR 14\nDEX 18\nINT 14\n01: Fighter(1)\n", ctx.ruleset)
      assert [{:abilities_partial, [:con, :wis, :cha]}] = of_kind(short, :abilities_partial)
    end

    test "the race and the alignment on the label's line — `Race: Human - Lawful good -`", ctx do
      result = Import.parse("Race: Human - Lawful good -\n01: Rogue(1)\n", ctx.ruleset)

      assert result.build.race == :human
      assert result.build.alignment == :lawful_good
    end

    test "running totals with a shorthand the counts confirm — `brd 2/rdd 1/wm 1`", ctx do
      text = """
      1 bard
      2 bard
      3 bard 2/rdd 1
      4 brd 2/rdd 1/wm 1
      5 brd 3/rdd 1/wm 1
      """

      assert Import.parse(text, ctx.ruleset).build.levels ==
               [:bard, :bard, :red_dragon_disciple, :weapon_master, :bard]
    end

    test "a class's choice named as one of its kind — `Domain (magic)`, `School (divination)`",
         ctx do
      text =
        "01: Cleric(1): Domain (magic), Domain (healing)\n02: Wizard(1): School (divination)\n"

      assert Import.parse(text, ctx.ruleset).build.class_choices ==
               %{cleric: [:magic, :healing], wizard: [:divination]}
    end

    test "`Base Attack` stays the base attack — the qualifier is tried after the key", ctx do
      result = Import.parse("Base Attack: 21\n01: Fighter(1)\n", ctx.ruleset)
      assert [%{id: :bab, key: "Base Attack"}] = result.source.totals
    end

    test "the race's own shape is the character's — `Dwarven Form` puts nothing aside", ctx do
      text = """
      Dwarf, Lawful Good
      01: Fighter(1)

      Dwarven Form

      Max HP: 12

      Risen Lord Form:
      Max HP: 30
      """

      result = Import.parse(text, ctx.ruleset)
      rows = Import.comparison(result, Rules.compute(result.build, ctx.ruleset))

      assert Enum.find(rows, &(&1.source == "12")).note == nil
      assert Enum.find(rows, &(&1.source == "30")).note =~ "Risen Lord Form"
    end

    test "a block captioned `start/end` gives the end", ctx do
      text = "01: Fighter(1)\nSaves ..start/end\nFort: 3( 28)\nReflex: 2(18)\nWill: 3(33)\n"

      assert [%{value: "Fortitude: 28 / Reflex: 18 / Will: 33"}] =
               Enum.filter(Import.parse(text, ctx.ruleset).source.totals, &(&1.id == :saves))
    end
  end
end
