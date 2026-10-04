defmodule BuildCalculatorWeb.Builder.ImportOneReadingTest do
  @moduledoc """
  Task 4.34, part 2: readings the import kept in two copies, and the copies
  had drifted apart (found by task 4.32) — now one source each, and the
  reading chosen is argued at the source:

    * the word that names a score — `Names.ability_word?/1`;
    * a bracket in a race's or an alignment's text — `Names.drop_brackets/1`;
    * the words of skill points carried on — `LevelTail`'s `@unspent_words`;
    * the names of the saves — `Names.save_name/1`;

  and two readings the same task corrected while making the reader linear:
  the brackets of a header line split by position (`Header`), and how deep
  one item of a level is read (`LevelTail`'s `@item_depth`).

  Every reading has its pair: what now reads, and the nearby text that must
  not. 🔴 The fixtures are SYNTHETIC, written after the shape of real lines.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Import
  alias BuildCalculatorWeb.Builder.Import.Names

  setup do
    %{ruleset: Data.ruleset!("vanilla")}
  end

  defp picks(build),
    do: for({_level, _slot, feat, choice} <- Build.feat_picks(build, 40), do: {feat, choice})

  defp picked?(build, feat), do: Enum.any?(picks(build), &match?({^feat, _}, &1))
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

  describe "(a) the word of a score — `Names.ability_word?/1`" do
    test "`(Chr=16)` is the score after the bump, as `(Cha=16)` is — a note", ctx do
      # CBC writes the bump as `CHA+1` and the score it made as `(CHA=16)`;
      # before 4.34 `(Chr=16)` was taken for the bump itself.
      read = fn note ->
        fighter(4, %{4 => "CHA+1, Power Attack, " <> note}) |> Import.parse(ctx.ruleset)
      end

      for note <- ["(Cha=16)", "(Chr=16)", "(Charisma = 16)"] do
        result = read.(note)
        assert result.build.ability_increases == %{4 => :cha}, note
        assert picked?(result.build, :power_attack), note
        assert of_kind(result, :unknown_feat) == [], note
      end

      # Without the bump written out, neither note is taken for it.
      [cha, chr] =
        for note <- ["(Cha=16)", "(Chr=16)"] do
          fighter(4, %{4 => "Power Attack " <> note}) |> Import.parse(ctx.ruleset)
        end

      assert cha.build == chr.build
      assert cha.build.ability_increases == %{}
      assert of_kind(chr, :increases_unnamed) == [{:increases_unnamed, [4]}]
    end

    test "NOT a score: a word that only begins like one — `(Intimidate = 4)`", ctx do
      # `int…` made it a note of Intelligence before 4.34, and it vanished.
      result =
        fighter(4, %{4 => "CHA+1, Power Attack (Intimidate = 4)"}) |> Import.parse(ctx.ruleset)

      assert picked?(result.build, :power_attack)

      assert of_kind(result, :feat_qualifier_dropped) == [
               {:feat_qualifier_dropped, 4, :power_attack, "Intimidate"}
             ]
    end

    test "a score written into a feat's item parts off it — `Chr 15` as `Cha 15`", ctx do
      # On a level that grants the bump, the score parted off is the bump.
      [cha, chr] =
        for score <- ["Cha 15", "Chr 15"] do
          fighter(4, %{4 => "Power Attack " <> score}) |> Import.parse(ctx.ruleset)
        end

      assert chr.build.ability_increases == %{4 => :cha}
      assert picked?(chr.build, :power_attack)
      assert cha.build == chr.build
    end

    test "a feat's name read past the score it left — `Great Charisma I Chr 18`", ctx do
      index = Names.indexes(ctx.ruleset)
      assert Names.feat_by_name(index, "Great Charisma I Chr 18") == {:ok, :great_charisma}
      assert Names.feat_by_name(index, "Great Charisma I Cha 18") == {:ok, :great_charisma}
      # A word that names no score is no score's tail.
      assert Names.feat_by_name(index, "Great Charisma I Charm 18") == :error
    end

    test "a list of increases names the score by the same word — and not by another", ctx do
      text = fighter(8, %{}) <> "Bump Chr at levels 4, 8\n"
      result = Import.parse(text, ctx.ruleset)
      assert result.build.ability_increases == %{4 => :cha, 8 => :cha}

      text = fighter(8, %{}) <> "Bump Charm at levels 4, 8\n"
      result = Import.parse(text, ctx.ruleset)
      assert result.build.ability_increases == %{}
    end
  end

  describe "(b) a bracket in a race's or an alignment's text — `Names.drop_brackets/1`" do
    test "a bracket that never closes runs to the end — for the alignment too", ctx do
      result = Import.parse("Race: Human\nAlignment: Lawful Good (the paladin\n", ctx.ruleset)
      assert result.build.alignment == :lawful_good

      # A square bracket is a bracket for the race too.
      result = Import.parse("Race: Human [for the skill points]\n", ctx.ruleset)
      assert result.build.race == :human
    end

    test "NOT an alignment: everything in the unclosed bracket — `(Lawful Good`", ctx do
      result = Import.parse("Race: Human\nAlignment: (Lawful Good\n", ctx.ruleset)
      assert result.build.alignment == nil
      assert result.build.race == :human
    end
  end

  describe "(c) skill points carried on — one list, `@unspent_words`" do
    test "`free 4 points` is passed over like `save 4 points`", ctx do
      for phrase <- ["save 4 points", "free 4 points", "left 2 pts", "Free(20)", "Bank 4"] do
        result = fighter(2, %{2 => "Cleave, " <> phrase}) |> Import.parse(ctx.ruleset)
        assert picked?(result.build, :cleave), phrase
        assert of_kind(result, :unknown_feat) == [], phrase
      end
    end

    test "NOT carried points: `Free Feat`, `s* Improved Combat Casting`", ctx do
      # `free`, `s`, `left`, `remaining` open other things too: without a
      # count right after them they are not carried points.
      result = fighter(2, %{2 => "Free Feat, choose what you like"}) |> Import.parse(ctx.ruleset)
      assert {:unknown_feat, 2, "Free Feat"} in result.issues

      result = fighter(1, %{1 => "s* Improved Combat Casting"}) |> Import.parse(ctx.ruleset)
      assert {:unknown_feat, 1, "s Improved Combat Casting"} in result.issues
    end
  end

  describe "(d) the names of the saves — `Names.save_name/1`" do
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

    defp saves_ours(text, ruleset) do
      result = Import.parse(text, ruleset)
      stats = Rules.compute(result.build, ruleset)
      row = Enum.find(Import.comparison(result, stats), &(&1.label == "Saves"))
      {row, stats}
    end

    defp signed(n) when n >= 0, do: "+#{n}"
    defp signed(n), do: Integer.to_string(n)

    # Task 4.40: ours with the saves' names, `Will -1 / Fort +4 / Ref +2`.
    defp labeled(saves) do
      names = %{fort: "Fort", ref: "Ref", will: "Will"}
      Enum.map_join(saves, " / ", fn {save, n} -> "#{names[save]}\u00A0#{signed(n)}" end)
    end

    test "`Saves: Wil 16, For 21, Refl 33` is set against ours as Will/Fort/Ref", ctx do
      {row, stats} = saves_ours(@sheet <> "Saves: Wil -1, For 4, Refl 2\n", ctx.ruleset)

      # The test means something only if the three differ.
      assert Enum.uniq([stats.fort, stats.ref, stats.will]) |> length() == 3
      assert row.ours == labeled(will: stats.will, fort: stats.fort, ref: stats.ref)
    end

    test "NOT an order: the saves named not all three — Fort/Ref/Will stands", ctx do
      {row, stats} = saves_ours(@sheet <> "Saves: Wil -1, For 4, 2\n", ctx.ruleset)
      assert row.ours == labeled(fort: stats.fort, ref: stats.ref, will: stats.will)
    end

    test "the block of saves reads the same names", ctx do
      text = @sheet <> "Saving Throws:\nWil: 16\nFor: 21\nRefl: 33\n"
      result = Import.parse(text, ctx.ruleset)
      assert [%{value: "Will: 16 / Fortitude: 21 / Reflex: 33"}] = result.source.totals
    end
  end

  describe "a header line split by position — `Header`'s brackets" do
    test "digits between brackets are read as written — `(x)1(y)0(z)`", ctx do
      # The brackets used to be masked with `\\u0001`-number markers and put
      # back by search; `(x)1(y)0(z)` spells a marker, and the bracket came
      # back in the wrong place: the part was no bracket any more, and the
      # line lost its alignment.
      result = Import.parse("Human, (x)1(y)0(z), Lawful Good\n", ctx.ruleset)
      assert result.build.race == :human
      assert result.build.alignment == :lawful_good
    end

    test "NOT split: a separator inside a bracket — `Human: (Quick, Skill)`", ctx do
      result =
        Import.parse(
          "Human: (Quick to Master, Skill Affinity: Listen), Neutral Good\n",
          ctx.ruleset
        )

      assert result.build.race == :human
      assert result.build.alignment == :neutral_good
    end
  end

  describe "how deep one item is read — `@item_depth`" do
    test "an item two levels down reads whole — `(Extend Spell Str 15)`", ctx do
      # The bracket opened, then the score parted off: the deepest a post of
      # the corpus goes.
      result = fighter(6, %{6 => "(Extend Spell Str 15)"}) |> Import.parse(ctx.ruleset)
      assert picked?(result.build, :extend_spell)
      assert of_kind(result, :unknown_feat) == []
    end

    test "NOT read level by level past eight: scores glued without commas", ctx do
      # Each level read what was left again: a paste of them took minutes.
      # Past eight levels the rest is read as it stands — a name we do not
      # know, said so.
      glued = String.duplicate("Str 16 ", 40) <> ")"
      result = fighter(1, %{1 => "Dodge, " <> glued}) |> Import.parse(ctx.ruleset)

      assert picked?(result.build, :dodge)
      assert [{:unknown_feat, 1, rest}] = of_kind(result, :unknown_feat)
      assert String.starts_with?(rest, "Str 16 Str 16")
    end
  end
end
