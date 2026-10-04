defmodule BuildCalculatorWeb.Builder.ImportTotalTest do
  @moduledoc """
  `Import.parse/2` never raises, whatever binary it is given (task 4.34, part
  2): on the vanilla edition the import is a public input, and an exception
  there is the LiveView falling over. Three ways it raised before, each with
  its pair — what is read, and what is not:

    * a paste over the ceiling cut inside a character — the cut is where a
      character begins (`Scan.paste/1`);
    * bytes that are not UTF-8 — replaced with `�` and counted
      (`{:invalid_utf8, count}`), the rest read;
    * a digit of another script — `\\d` of the reader's patterns is ASCII
      (`Import.Rx`), and `String.to_integer/1` is never handed `٣`.

  Then a deterministic search over what else could: random bytes, random
  text from a pool of awkward code points, synthetic ladders cut at random
  bytes, pastes around the ceiling. Fixed seed, so a failure here fails
  again the same way.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Import
  alias BuildCalculatorWeb.Builder.Import.Scan

  setup do
    %{ruleset: Data.ruleset!("vanilla")}
  end

  defp of_kind(result, kind), do: Enum.filter(result.issues, &(elem(&1, 0) == kind))

  @ladder "Human, True Neutral\n01: Fighter(1): Dodge\n02: Fighter(2): Cleave\n"

  describe "the ceiling cuts where a character begins" do
    test "a paste cut inside `«` reads up to the cut and says so", ctx do
      # 64 000 falls on the second byte of a `«` (two bytes in UTF-8).
      pad = Scan.max_bytes() - byte_size(@ladder) - 1
      text = @ladder <> String.duplicate("a", pad) <> String.duplicate("«", 10)
      assert :binary.at(text, Scan.max_bytes()) in 0x80..0xBF

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter, :fighter]
      assert of_kind(result, :text_clipped) == [{:text_clipped, Scan.max_bytes()}]
      assert of_kind(result, :invalid_utf8) == []
    end

    test "NOT read: what stands past the ceiling", ctx do
      text = @ladder <> String.duplicate("«\n", 32_000) <> "03: Fighter(3): Dodge\n"
      result = Import.parse(text, ctx.ruleset)
      assert result.build.levels == [:fighter, :fighter]
    end
  end

  describe "bytes that are not UTF-8" do
    test "are replaced and counted; the lines around them read", ctx do
      text =
        "Human, True Neutral\n01: Fighter(1): Dodge\n" <> <<0xFF>> <> "\n02: Fighter(2): Cleave\n"

      result = Import.parse(text, ctx.ruleset)

      assert result.build.levels == [:fighter, :fighter]
      assert of_kind(result, :invalid_utf8) == [{:invalid_utf8, 1}]
      assert Import.issue_text({:invalid_utf8, 1}, ctx.ruleset) =~ "1"
    end

    test "NOT noted: a paste that is UTF-8, `�` of its own included", ctx do
      result = Import.parse(@ladder <> "�\n", ctx.ruleset)
      assert of_kind(result, :invalid_utf8) == []
    end
  end

  describe "a digit of another script" do
    test "is not a number — and nothing raises on it", ctx do
      # `٣` is Arabic-Indic three: `\\d` of PCRE with Unicode properties took
      # it, `String.to_integer/1` did not.
      result = Import.parse("Human, True Neutral\n01: Fighter(٣): Dodge\nSTR: ١٦\n", ctx.ruleset)
      refute Map.has_key?(result.source.abilities, "str")
    end

    test "while ASCII digits read", ctx do
      result = Import.parse("Human, True Neutral\n01: Fighter(1): Dodge\nSTR: 16\n", ctx.ruleset)
      assert %{start: 16} = result.source.abilities["str"]
    end
  end

  describe "a deterministic search for anything else that raises" do
    # Code points that took a reader by surprise before or might: digits of
    # other scripts, marks, spaces and joiners, brackets of other kinds,
    # letters that change length with case, emoji, private use.
    @awkward [
               0x0660,
               0x0669,
               0x06F0,
               0x0966,
               0xFF10,
               0x1D7CE,
               0x0301,
               0x200B,
               0x200D,
               0x00A0,
               0x3000,
               0x2028,
               0x0085,
               0xFEFF,
               0xFF08,
               0x3010,
               0x00AB,
               0x2013,
               0x0130,
               0x1E9E,
               0x00DF,
               0xFB00,
               0x2163,
               0x1F600,
               0x1F1FA,
               0xE000,
               0x0410,
               0x0627,
               0x1100,
               0x00B2
             ]
             |> Enum.map(&<<&1::utf8>>)

    @ascii ~w|( ) [ ] { } : ; , . - / + = * # " ' 0 1 9 12 16 20 40 Str Dex Fighter Monk Human
              Race Alignment Saves Fort Ref Will HP AC BAB SKILLS 01: Level Cleric Domain Save Free| ++
             [" ", "  ", "\n", "\t", "\u0001"]

    test "random bytes, awkward text, cut ladders, pastes at the ceiling" do
      :rand.seed(:exsss, {4, 34, 2})
      rulesets = [Data.ruleset!("vanilla"), Data.ruleset!("siala_41")]

      ladder =
        for(
          level <- 1..40,
          into: "Human, Lawful Good\nSTR: 16\nDEX: 14\n",
          do: "#{level}: Fighter(#{level}): Dodge, Str 16\n"
        )

      awkward = fn ->
        for _ <- 1..:rand.uniform(120), into: "" do
          if :rand.uniform(2) == 1, do: Enum.random(@awkward), else: Enum.random(@ascii)
        end
      end

      texts =
        for(_ <- 1..80, do: bytes(:rand.uniform(200))) ++
          for(_ <- 1..80, do: awkward.()) ++
          for(_ <- 1..40, do: binary_part(ladder, 0, :rand.uniform(byte_size(ladder)))) ++
          for(_ <- 1..20, do: splice(ladder, bytes(:rand.uniform(8)))) ++
          for(width <- [2, 3, 4], shift <- 0..3, do: at_ceiling(width, shift))

      raised =
        for(text <- texts, ruleset <- rulesets, do: {text, ruleset})
        |> Task.async_stream(
          fn {text, ruleset} ->
            try do
              Import.parse(text, ruleset)
              nil
            rescue
              e -> {text, ruleset.version, Exception.message(e)}
            end
          end,
          timeout: :infinity
        )
        |> Enum.flat_map(fn {:ok, found} -> List.wrap(found) end)

      assert raised == [],
             "parse/2 raised on #{length(raised)} input(s), e.g. #{inspect(hd(raised ++ [nil]), limit: 20, printable_limit: 120)}"
    end

    # Random bytes off the seeded generator, so the search repeats itself.
    defp bytes(count), do: for(_ <- 1..count, into: <<>>, do: <<:rand.uniform(256) - 1>>)

    defp splice(text, bytes) do
      at = :rand.uniform(byte_size(text) + 1) - 1
      binary_part(text, 0, at) <> bytes <> binary_part(text, at, byte_size(text) - at)
    end

    # A paste whose last character straddles the ceiling.
    defp at_ceiling(width, shift) do
      char = %{2 => "é", 3 => "«", 4 => "😀"} |> Map.fetch!(width)

      String.duplicate("a", shift) <>
        String.duplicate(char, div(Scan.max_bytes() - shift, width) + 2)
    end
  end
end
