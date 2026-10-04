defmodule BuildCalculatorWeb.Builder.ImportHostileTest do
  @moduledoc """
  The import is a public input on the vanilla edition (task 4.34): no paste may
  make it read quadratically. Each form below once did — a run of brackets that
  never close, a flood of short lines, a line of spaces, a level of scores —
  and each is doubled here twice: 1 000 → 2 000 and 8 000 → 16 000 bytes.
  Doubling the text may about double the work; 2.6 times is the ceiling.

  ⚠️ The work is counted, not timed: reductions of the process that parses,
  less those of parsing nothing (building the dictionaries). Reductions do not
  move with the machine — measured, one text parsed five times in fresh
  processes differs by under 0.1 % — but they can move with the tests running
  beside this one, and only upwards (see `least_work/2`), so each is the least
  of three counts. The ceiling can then sit close to the linear 2.0 and a
  quadratic read (4.0) still fails it by far.

  Why two sizes. The larger one sees what grows with the number of lines and
  brackets: each of them reading the rest of the text again. The smaller one
  sees one regex backtracking over a run of spaces, which the larger one
  cannot: PCRE gives such a call up at its match limit — measured, 4 000
  spaces give `{:error, :match_limit}`, and `Regex.run/3` says `nil` and
  nothing else — so past a few thousand bytes every such call costs the same,
  seconds of it, and the count grows no faster than the text. At 2 000 bytes
  the call still finishes.

  What the count does not see at all is the copying of a list appended to at
  its end (`++`): that is caught by the time guard of
  `tools/vanilla_recon/import_equivalence.exs`, 64 KB and a wide margin, not
  by a timer here.

  The forms after `one long number in brackets` are the shapes task 4.36 reads
  anew: a caption naming its columns, a remark, a list's head, lines under a
  level, a table of tabs, ranks after a shortened name, bumps and skills
  written into a feat's item, two names without a comma.

  Checked when written, with the import of `e5134db`: every form of the
  first 27 fails. At 8 000 → 16 000 bytes twenty-four give 3.4 to 4.0 and one
  does not finish 16 000 bytes in three minutes; the other two — spaces inside
  a line, a level with spaces in its class — give 2.1 there, and 7.9 and 8.2
  at 1 000 → 2 000. The import of `2a80fef` (task 4.34, part 1) gives at most
  2.05 on those; the forms after them were found by part 2 — the masking of
  brackets that part kept for equal output, and a search of 85 000 forms at
  the level of `parse/2` — and `2a80fef` fails each of them.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Import

  @ceiling 2.6

  # Below PCRE's match limit, and well above it (see the moduledoc).
  @sizes [{1_000, 2_000}, {8_000, 16_000}]

  # `{name, head, unit, tail}`: `head <> unit × N <> tail`, whole units only, so
  # the text ends the same way at every size; a unit `{open, close}` is nested,
  # `head <> open × N <> tail <> close × N`.
  @forms [
    {"«(» that never closes", "", "(", ""},
    {"«[» that never closes", "", "[", ""},
    {"«()» one line", "", "()", ""},
    {"«(a)» one line", "", "(a)", ""},
    {"score sheets a line apart", "", "Str 16\nx\n", ""},
    {"a race line and brackets", "Race: Human ", "(", ""},
    {"a title and brackets", "Build - Fighter(40) ", "(", ""},
    {"a domain and brackets", "01: Cleric(1): Domain ", "(", ""},
    {"an unknown feat and brackets", "01: Fighter(1): Xyz", "(", ""},
    {"an unknown feat and numbers", "01: Fighter(1): Xyz", " 1", ""},
    {"a level of words", "01: ", "foo ", ""},
    {"a class and words of apostrophes", "01: Fighter ", "' ", "Xyzzy"},
    {"a running split", "01: ", "Fighter1/", ""},
    {"a score sheet and a long word", "Str 16 ", "a", ""},
    {"spaces inside a line", "a", " ", "b"},
    {"spaces before a colon", "a", " ", ":b"},
    {"a title and spaces", "Build - Fighter(40)", " ", "x"},
    {"a level with spaces in its class", "01: Fighter", " ", "(1): Dodge"},
    {"domains and spaces", "Domains: a", " ", "b"},
    {"skills and spaces", "SKILLS\nTumble", " ", "4"},
    {"dots inside a line", "a", ".", "b"},
    {"a level of dots", "01: Fighter(1): a", ".", "b"},
    {"nested brackets on a level", "01: Fighter(1): ", "(", "x"},
    {"a level of scores", "01: Fighter(1): ", "Str 16 ", "x"},
    {"a level of scores and a colon", "01: Fighter(1): ", "Str 16 ", "x: y"},
    {"a level of scores and a comma in brackets", "01: Fighter(1): ", "Str 16 ", "(a, b: c)"},
    {"letter sheets", "", "S: 8\nD: 16\nC: 14\nW: 15\nI: 14\nCH: 8\n", ""},
    # Task 4.34, part 2.
    {"brackets around `\\u0001`", "a, ", "(\u0001)", ""},
    {"«(a)0» one line", "", "(a)0", ""},
    {"a level of scores and a closing bracket", "01: Fighter(1): ", "Str 16 ", ")"},
    {"a level of notes «Str=16»", "01: Fighter(1): ", "Str=16 ", ":"},
    {"brackets inside brackets on a level", "01: Fighter(1): ", {"(", ")"}, "Dodge"},
    {"brackets inside brackets with a comma", "01: Fighter(1): ", {"(a, ", ")"}, "Dodge"},
    {"one long number in brackets", "01: Fighter(1): Tumble(", "9", ")"},
    # Task 4.36: the shapes it reads anew.
    {"a saves caption of brackets and slashes", "Saves: ", "(a)/",
     "\nFort 1 (2)\nRef 2 (3)\nWill 3 (4)\n"},
    {"a save's line of brackets", "Saves:\nFort 1", " (1)", "\nRef 2\nWill 3\n"},
    {"a saves caption of words and a block", "Saves: ", "a ", "\nFort 1\nRef 2\nWill 3\n"},
    {"an increase's head and spaces", "Raise CON at", " ", "x"},
    {"a level with lines under it", "", "01: Fighter(1)\nDodge\n", ""},
    {"a table of tabs", "", "01\tFighter\tDodge\t\n", ""},
    {"a level of ranks after a shortened name", "01: Fighter(21): Great Dex I", ", II", ""},
    {"a level of bumps after feats", "01: Fighter(4): ", "Dodge +Dex, ", ""},
    {"a level of skills before feats", "01: Fighter(1): ", "Discipline 1 Dodge, ", ""},
    {"a level of two names without a comma", "01: Fighter(1): ", "Great Wis I Great Wis II, ",
     ""},
    {"a level of shorthand and scores", "01: Fighter(1): ", "GRT WIS 17 ", ""},
    {"a list of increases after a dash", "Increase Str- ", "4,", "8"},
    {"a line of levels and scores", "Stats ", "4,8 Wisdom ", ""}
  ]

  @tag timeout: 300_000
  test "hostile pastes: doubling the text about doubles the work" do
    ruleset = Data.ruleset!("vanilla")
    Import.parse("01: Fighter(1)\n", ruleset)
    nothing = least_work("", ruleset)

    grown =
      for {name, head, unit, tail} <- @forms,
          {small, large} <- @sizes,
          ratio =
            (least_work(text(head, unit, tail, large), ruleset) - nothing) /
              (least_work(text(head, unit, tail, small), ruleset) - nothing),
          ratio > @ceiling,
          do: "#{name}, #{small} → #{large} bytes: ×#{Float.round(ratio, 2)}"

    assert grown == [], "work grew faster than the text:\n" <> Enum.join(grown, "\n")
  end

  defp text(head, {open, close}, tail, size) do
    count = div(size - byte_size(head) - byte_size(tail), byte_size(open) + byte_size(close))
    head <> String.duplicate(open, count) <> tail <> String.duplicate(close, count)
  end

  defp text(head, unit, tail, size),
    do:
      head <>
        String.duplicate(unit, div(size - byte_size(head) - byte_size(tail), byte_size(unit))) <>
        tail

  # The least of three counts, after one parse that is not counted. The count
  # is steady when the test runs alone, and in the full `mix test` it once came
  # out ×3.0 for a form that gives ×2.0 alone (task 4.37, coordinator's run).
  # What disturbs it only ever adds: a pattern compiled on its first use
  # (`Import.Rx` keeps it in `:persistent_term`), a garbage collection forced
  # on every process when two tests store the same pattern at once. So the
  # least of a few counts is the work of the text itself, and a quadratic read
  # (×4.0) still fails the ceiling by far.
  defp least_work(text, ruleset) do
    Import.parse(text, ruleset)
    Enum.min(for _ <- 1..3, do: work(text, ruleset))
  end

  defp work(text, ruleset) do
    fn ->
      {:reductions, before} = Process.info(self(), :reductions)
      Import.parse(text, ruleset)
      {:reductions, after_parse} = Process.info(self(), :reductions)
      after_parse - before
    end
    |> Task.async()
    |> Task.await(:infinity)
  end
end
