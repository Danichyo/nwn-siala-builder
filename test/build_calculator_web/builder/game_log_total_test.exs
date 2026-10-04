defmodule BuildCalculatorWeb.Builder.GameLogTotalTest do
  @moduledoc """
  The `.билд` log dialog never raises, whatever binary it is given, and reads
  no more than its ceiling (task 4.39 — the text import's rules since 4.34,
  `import_total_test.exs`, brought to the second entrance). The dialog is open
  to every player on the shard; an exception there is the LiveView falling
  over. Each way it raised before has its pair — what is read, and what is
  not:

    * a paste over the ceiling (`GameLog.max_bytes/0`) was read whole, at any
      cost; now it is cut where a character begins (`{:text_clipped, bytes}`),
      and the rest is read — `BuildCalculator.Paste`, one copy with the text
      import;
    * bytes that are not UTF-8 raised in the first pattern; now they are
      replaced with `�` and counted (`{:invalid_utf8, count}`);
    * a digit of another script went from `\\d` to `String.to_integer/1` and
      raised (`LEVEL ٣: FIGHTER`, `AC Bonus ٣`); now `\\d` of every pattern
      whose digits become a number is ASCII;
    * a feat under `LEVEL 0` asked the slot model about a level that does not
      exist, and it raised; now such a feat is not placed, with its reason.

  Then a deterministic search over what else could: random bytes, random text
  from a pool of awkward code points and the log's own words, real logs cut at
  random bytes and with random bytes spliced in, pastes around the ceiling —
  through `GameLog.parse/2`, `GameLogImport.parse/2` and the dialog's report.
  Fixed seed, so a failure here fails again the same way.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, GameLog}
  alias BuildCalculatorWeb.Builder.{GameLogImport, GameLogImportPanel}

  @siala Data.ruleset!("siala_41")

  defp fixture(path), do: "../../fixtures/#{path}.log" |> Path.expand(__DIR__) |> File.read!()

  defp of_kind(issues, kind), do: Enum.filter(issues, &(elem(&1, 0) == kind))

  @ladder "LEVEL 1: FIGHTER\n  FEATS: Dodge\nLEVEL 2: FIGHTER\n  FEATS: Mobility\n"

  describe "the ceiling cuts where a character begins" do
    test "a paste cut inside `Ж` reads up to the cut and says so" do
      # 64 000 falls on the second byte of a `Ж` (two bytes in UTF-8).
      pad = GameLog.max_bytes() - byte_size(@ladder) - 1
      text = @ladder <> String.duplicate("a", pad) <> String.duplicate("Ж", 10)
      assert :binary.at(text, GameLog.max_bytes()) in 0x80..0xBF

      result = GameLogImport.parse(text, @siala)

      assert result.build.levels == [:fighter, :fighter]
      assert of_kind(result.issues, :text_clipped) == [{:text_clipped, GameLog.max_bytes()}]
      assert of_kind(result.issues, :invalid_utf8) == []
    end

    test "a real `.билд+` log with the chat after it is read whole, the chat is cut" do
      log = fixture("game_logs_plus/hnyupius")

      chat =
        String.duplicate("[CHAT WINDOW TEXT] [Fri Sep 18 00:19:04] [Talk] X: ну как?\n", 1200)

      assert byte_size(log <> chat) > GameLog.max_bytes()

      whole = GameLogImport.parse(log, @siala)
      clipped = GameLogImport.parse(log <> chat, @siala)

      assert clipped.build.levels == whole.build.levels
      assert clipped.build.gear == whole.build.gear
      assert of_kind(clipped.issues, :text_clipped) == [{:text_clipped, GameLog.max_bytes()}]
    end

    test "NOT read: what stands past the ceiling" do
      text = @ladder <> String.duplicate("x\n", 32_000) <> "LEVEL 3: FIGHTER\n"
      result = GameLogImport.parse(text, @siala)
      assert result.build.levels == [:fighter, :fighter]
    end

    test "NOT noted: a paste within the ceiling" do
      result = GameLogImport.parse(fixture("game_logs_plus/hnyupius"), @siala)
      assert of_kind(result.issues, :text_clipped) == []
    end

    test "the note names the ceiling and says what to do, and lands with what was not carried over" do
      text = GameLogImport.issue_text({:text_clipped, GameLog.max_bytes()}, @siala)
      assert text =~ "64000"
      assert text =~ "без чата"
      assert GameLogImport.issue_kind({:text_clipped, GameLog.max_bytes()}) == "Не перенесено"
    end
  end

  describe "bytes that are not UTF-8" do
    test "are replaced and counted; the lines around them read" do
      text = "LEVEL 1: FIGHTER\n" <> <<0xFF>> <> "\nLEVEL 2: FIGHTER\n"
      result = GameLogImport.parse(text, @siala)

      assert result.build.levels == [:fighter, :fighter]
      assert of_kind(result.issues, :invalid_utf8) == [{:invalid_utf8, 1}]
      assert GameLogImport.issue_text({:invalid_utf8, 1}, @siala) =~ "UTF-8"
    end

    test "NOT noted: a paste that is UTF-8, `�` of its own included" do
      result = GameLogImport.parse(@ladder <> "�\n", @siala)
      assert of_kind(result.issues, :invalid_utf8) == []
    end
  end

  describe "a digit of another script" do
    # `٣` is Arabic-Indic three: `\\d` of PCRE with Unicode properties took it,
    # `String.to_integer/1` did not.
    @equip "=== Equipped: X ===\n"

    for {where, text} <- [
          {"a level's number", "LEVEL ٣: FIGHTER\n"},
          {"an ability increase", "LEVEL 1: FIGHTER\n  ABILITY: +٣ STR\n"},
          {"a skill bought", "LEVEL 1: FIGHTER\n  SKILLS: Tumble +٣\n"},
          {"a skill total", "SKILLS WITH RANKS:\nTumble ٣\n"},
          {"a sheet", "(WHITE) ABILITIES: STR ١٦ DEX 14\n"},
          {"the header", "Current: ٣ FTR\n"},
          {"an AC bonus", @equip <> "[HEAD] X\n[1] AC Bonus ٣\n"},
          {"a base item", @equip <> "[RIGHTHAND] X (Longsword) [BaseItem:٣]\n"},
          {"a base AC", @equip <> "[CHEST] X [BaseAC:٣]\n"},
          {"a count", @equip <> "MINI SET PIECES: ٣\n"},
          {"a set", @equip <> "[HEAD] X\n[1] Use Item (Mini Set) [SetID:٣]\n"},
          {"a value", @equip <> "[HEAD] X\n[1] Skill Bonus (Tumble) ٣\n"}
        ] do
      test "is not a number in #{where} — and nothing raises on it" do
        result = GameLogImport.parse(unquote(text), @siala)
        assert %GameLog{} = result.log
      end
    end

    test "while ASCII digits read" do
      log = GameLog.parse("LEVEL 3: FIGHTER\n  SKILLS: Tumble +2\n", @siala)
      assert [%{level: 3, skills: [%{skill: :tumble, delta: 2}]}] = log.levels

      log = GameLog.parse("LEVEL ٣: FIGHTER\n  SKILLS: Tumble +2\n", @siala)
      assert log.levels == []
      assert {:unrecognized_line, "LEVEL ٣: FIGHTER"} in log.problems
    end
  end

  describe "`LEVEL 0` — a level that does not exist" do
    # Found by task 4.39 driving hostile logs through the whole dialog: the
    # slot model is asked only about levels from 1, and a feat printed under
    # `LEVEL 0` made `GameLogImport.parse/2` raise.
    test "its feats are not placed, and nothing raises" do
      result = GameLogImport.parse("LEVEL 0: FIGHTER\n  FEATS: Dodge\n", @siala)

      assert result.build.levels == [:fighter]
      assert result.build.feats == %{}
      assert {:feat_not_placed, 0, :dodge, {:no_free_slot, :dodge}} in result.issues
      assert {:level_out_of_sequence, 1, 0} in result.issues
    end

    test "while the same feat under `LEVEL 1` is placed" do
      result = GameLogImport.parse("LEVEL 1: FIGHTER\n  FEATS: Dodge\n", @siala)
      assert [:dodge] = result.build.feats |> Map.fetch!(1) |> Map.values()
    end
  end

  describe "a deterministic search for anything else that raises" do
    # Code points that took a reader by surprise before or might: digits of
    # other scripts, marks, spaces and joiners (U+180E is a space to a pattern
    # and not to `String.trim/1`), brackets of other kinds, letters that
    # change length with case, emoji, private use, Cyrillic.
    @awkward [
               0x0660,
               0x0663,
               0x06F0,
               0x0966,
               0xFF10,
               0x1D7CE,
               0x0301,
               0x200B,
               0x180E,
               0x00A0,
               0x3000,
               0x2028,
               0x0085,
               0xFEFF,
               0xFF08,
               0x3010,
               0x00AB,
               0x0130,
               0x1E9E,
               0x00DF,
               0x2163,
               0x1F600,
               0xE000,
               0x0416,
               0x0451
             ]
             |> Enum.map(&<<&1::utf8>>)

    @words ~w|( ) [ ] : , + - = === Equipped: LEVEL FEATS: SKILLS: ABILITY: STR DEX FIGHTER
              Dodge Tumble 0 1 9 16 40 [HEAD] [RIGHTHAND] [1] [CRAFT] [BaseItem: [BaseAC: AC Bonus
              Bonus Feat (Mini Set) [SetID: Current: FTR RACE: Dwarf ALIGNMENT: COMBAT STATS:
              SKILLS WITH RANKS: (WHITE) ABILITIES:| ++ [" ", "  ", "\n", "\t", "\r", "\u0001"]

    @tag timeout: 300_000
    test "random bytes, awkward text, cut logs, spliced logs, pastes at the ceiling" do
      :rand.seed(:exsss, {4, 39, 1})
      rulesets = [@siala, Data.ruleset!("vanilla")]

      logs =
        for path <- Path.wildcard(Path.expand("../../fixtures/game_logs*/*.log", __DIR__)),
            do: File.read!(path)

      awkward = fn ->
        for _ <- 1..:rand.uniform(160), into: "" do
          if :rand.uniform(3) == 1, do: Enum.random(@awkward), else: Enum.random(@words)
        end
      end

      texts =
        for(_ <- 1..80, do: bytes(:rand.uniform(200))) ++
          for(_ <- 1..120, do: awkward.()) ++
          for(
            _ <- 1..40,
            log = Enum.random(logs),
            do: binary_part(log, 0, :rand.uniform(byte_size(log)))
          ) ++
          for(_ <- 1..30, do: splice(Enum.random(logs), bytes(:rand.uniform(8)))) ++
          for(width <- [2, 3, 4], shift <- 0..3, do: at_ceiling(width, shift))

      raised =
        for(text <- texts, ruleset <- rulesets, do: {text, ruleset})
        |> Task.async_stream(
          fn {text, ruleset} ->
            try do
              GameLog.parse(text, ruleset)
              text |> GameLogImport.parse(ruleset) |> GameLogImportPanel.report(text, ruleset)
              nil
            rescue
              e -> {text, ruleset.version, Exception.message(e)}
            end
          end,
          timeout: :infinity
        )
        |> Enum.flat_map(fn {:ok, found} -> List.wrap(found) end)

      assert raised == [],
             "the log dialog raised on #{length(raised)} input(s), e.g. " <>
               inspect(hd(raised ++ [nil]), limit: 20, printable_limit: 120)
    end

    # Random bytes off the seeded generator, so the search repeats itself.
    defp bytes(count), do: for(_ <- 1..count, into: <<>>, do: <<:rand.uniform(256) - 1>>)

    defp splice(text, bytes) do
      at = :rand.uniform(byte_size(text) + 1) - 1
      binary_part(text, 0, at) <> bytes <> binary_part(text, at, byte_size(text) - at)
    end

    # A paste whose last character straddles the ceiling.
    defp at_ceiling(width, shift) do
      char = %{2 => "Ж", 3 => "«", 4 => "😀"} |> Map.fetch!(width)

      String.duplicate("a", shift) <>
        String.duplicate(char, div(GameLog.max_bytes() - shift, width) + 2)
    end
  end
end
