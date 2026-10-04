defmodule BuildCalculatorWeb.Builder.GameLogHostileTest do
  @moduledoc """
  The `.билд` log dialog is open to every player of the shard (task 4.39): no
  paste may make it work quadratically. Each form below is a line shape the
  log reader takes a path for — a line nobody reads, a level, its feats and
  skills, the skill totals, the header, the sheets, the equipped section, the
  marks after an item's name — repeated, and each is doubled twice: 8 000 →
  16 000 and 32 000 → 64 000 bytes (64 000 is the ceiling,
  `BuildCalculator.GameLog.max_bytes/0`, and the text is filled with whole
  repeats up to it, so nothing is cut). Doubling the text may about double
  the work; 2.6 times is the ceiling.

  What is measured is the whole of what the server does on «Разобрать»:
  `GameLogImport.parse/2` (which reads the text with `GameLog.parse/2`) and the
  dialog's report, `GameLogImportPanel.report/3`.

  ⚠️ The work is counted, not timed — the reductions of the process, less
  those of the form with no repeats at all (its head and tail alone: a level
  line or an equipped section builds the reader's dictionaries once, and that
  is not the text's work). A count moves only upwards under the tests running
  beside this one, so each is the least of three after one parse that is not
  counted (task 4.37, `import_hostile_test.exs`). A doubling is judged only
  where the smaller count is at least `@least_count`: below it a count is
  within the noise, and a form of spaces does very little work a byte.

  Checked when written: the same count over the reader of `04e15b5`, compiled
  beside the new one, fails 22 forms of these 30 — 3.9–4.0 for the patterns
  that backtracked over a run of spaces (a skill's name, the equipped marker,
  the marks after an item's name), 2.6–3.9 for the lists appended to at their
  end; the other eight read in linear time there too and stay as guards of
  their own paths. This test itself does not finish on that reader in its
  five minutes: 64 KB of `[CRAFT]` marks is 18 s a parse there. The reader of
  this task gives at most 2.15. The forms are the ones
  `tools/game_log/sweep.exs` found over some 80 000 (a start of a line × a
  repeat × a tail, two sizes), and their neighbours.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.{GameLogImport, GameLogImportPanel}

  @ceiling 2.6
  @sizes [{8_000, 16_000}, {32_000, 64_000}]
  @least_count 10_000

  @equip "=== Equipped: X ===\n"
  @slot @equip <> "[HEAD] X\n"
  @hand @equip <> "[RIGHTHAND] X (Longsword) [BaseItem:1]\n"
  @level "LEVEL 1: FIGHTER\n"

  # `{name, head, unit, tail}`: `head <> unit × N <> tail`, whole units only.
  @forms [
    {"«(» on every line", "", "(\n", ""},
    {"«x» on every line", "", "x\n", ""},
    {"level lines", "", @level, ""},
    {"a level: FEATS again and again", @level, "  FEATS: x\n", ""},
    {"a level: feats by commas", @level <> "  FEATS: ", "Dodge, ", ""},
    {"a level: feats that owe a choice", @level <> "  FEATS: ", "Weapon Focus, ", ""},
    {"a level: unknown feats", @level <> "  FEATS: ", "xyz, ", ""},
    {"a level: skills by commas", @level <> "  SKILLS: ", "a +1, ", ""},
    {"a level: spaces in a skill", @level <> "  SKILLS: Tumble", " ", "y]"},
    {"a level: U+180E in a skill", @level <> "  SKILLS: Tumble", "\u180E", "9"},
    {"skill totals line by line", "SKILLS WITH RANKS:\n", "Tumble 1\n", ""},
    {"skill totals: spaces", "SKILLS WITH RANKS:\nTumble", " ", " ==="},
    {"skill totals: U+180E", "SKILLS WITH RANKS:\nTumble", "\u180E", "x"},
    {"skill totals: unknown by commas", "SKILLS WITH RANKS:\nTumble 4, ", "a,", " +1"},
    {"header: unknown classes", "Current: ", "1 XYZ / ", ""},
    {"header: slashes", "Current: 1 ", "/", ", Dodge"},
    {"sheet: unknown labels", "(WHITE) ABILITIES: STR 16 ", "Foo 1 ", " (x)"},
    {"combat stats: pairs", "COMBAT STATS: AB 1 ", "Tumble 1, ", "==="},
    {"«===Equipped:» on one line", "", "===Equipped:", " +1"},
    {"equipped: slots", @equip, "[HEAD] x\n", ""},
    {"equipped: properties not ours", @slot, "[1] Cast Spell (x) 1\n", ""},
    {"equipped: properties before a slot", @equip, "[1] x\n", "[CRAFT]"},
    {"equipped: lines of no shape", @equip, "zzz\n", ""},
    {"equipped: [CRAFT] marks", @equip, "[CRAFT] ", ""},
    {"equipped: [BaseItem] marks", @equip <> "[HEAD] ", " [BaseItem:1]", "[CRAFT]"},
    {"equipped: spaces before «]»", @equip <> "[HEAD] x", " ", "y]"},
    {"equipped: unknown abilities", @slot, "[1] Ability Bonus (Foo) 1\n", ""},
    {"equipped: attack numbers in a hand", @hand, "[1] Attack Bonus (0) 1\n", ""},
    {"equipped: feats of an item", @slot, "[1] Bonus Feat (Dodge)\n", ""},
    {"letters on one line", "", "a", ""},
    # Task 4.40 (third pass): one paste is one character — the lines past the
    # dump read, the further dumps named one by one, and equipped sections past
    # the first, passed over.
    {"lines past the log read", @level <> "CHARACTER BUILD: x\n", "x\n", ""},
    {"logs after the log read", @level, "CHARACTER BUILD: x\n", ""},
    {"equipped sections after the first", @slot, "=== Equipped: x ===\n[HEAD] x\n", ""}
  ]

  @tag timeout: 300_000
  test "hostile pastes into the log dialog: doubling the text about doubles the work" do
    ruleset = Data.ruleset!("siala_41")
    window("LEVEL 1: FIGHTER\n  FEATS: Dodge\n", ruleset)

    judged =
      for {name, head, unit, tail} <- @forms do
        own = least_work(head <> tail, ruleset)

        pairs =
          for {small, large} <- @sizes,
              less = least_work(text(head, unit, tail, small), ruleset) - own,
              less >= @least_count do
            more = least_work(text(head, unit, tail, large), ruleset) - own
            {small, large, more / less}
          end

        {name, pairs}
      end

    unmeasured = for {name, []} <- judged, do: name
    assert unmeasured == [], "no measurable work at either size: #{inspect(unmeasured)}"

    grown =
      for {name, pairs} <- judged,
          {small, large, ratio} <- pairs,
          ratio > @ceiling,
          do: "#{name}, #{small} → #{large} bytes: ×#{Float.round(ratio, 2)}"

    assert grown == [], "work grew faster than the text:\n" <> Enum.join(grown, "\n")
  end

  defp text(head, unit, tail, size),
    do:
      head <>
        String.duplicate(unit, div(size - byte_size(head) - byte_size(tail), byte_size(unit))) <>
        tail

  defp window(text, ruleset),
    do: text |> GameLogImport.parse(ruleset) |> GameLogImportPanel.report(text, ruleset)

  # The least of three counts, after one that is not counted (see the moduledoc).
  defp least_work(text, ruleset) do
    work(text, ruleset)
    Enum.min(for _ <- 1..3, do: work(text, ruleset))
  end

  defp work(text, ruleset) do
    fn ->
      {:reductions, before} = Process.info(self(), :reductions)
      window(text, ruleset)
      {:reductions, after_window} = Process.info(self(), :reductions)
      after_window - before
    end
    |> Task.async()
    |> Task.await(:infinity)
  end
end
