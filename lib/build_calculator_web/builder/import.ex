defmodule BuildCalculatorWeb.Builder.Import do
  @moduledoc """
  Somebody else's build, out of the community's text block.

  The other half of `BuildCalculatorWeb.Builder.Export`: the Epic Character
  Builders posting format (CLAUDE.md §3) — in practice the text block
  Kamiryn's CBC prints — is what forums and Discord actually exchange, so a
  player who found a build there must be able to paste it and open it here.

  Two properties matter more than how much of the text is understood.

  ## Tolerance

  Nobody formats the block the same way. Case, spacing, `01:` versus `1.`,
  `1 -`, `Lvl 1`, `Level 1`, `(01)` or `[01]`; a class written `Fighter(1)`,
  `Fighter 1` or `Fighter1`; `STR 16` without a colon; `Race:` and
  `Alignment:` on lines of their own; community class shorthand (`WM`, `DD`,
  `CoT`), Siala's Russian race names, Discord quote markers and code fences,
  prose paragraphs in the middle — all of it is normal, and all of it has to
  survive. Every name is resolved through an index built from the ruleset
  itself: the English name, the shard's Russian name, the wiki alias
  (`ruleset.name_map`), any of those with the spaces taken out (`Shadow
  dancer`), a mechanically derived acronym (`ITWF`, `UMD`), and — for classes
  and skills — a unique prefix (`Sorc`, `Tum`). Nothing here carries a hand
  written synonym table, and a key two entries answer to is reported as
  ambiguous rather than guessed.

  A level's feat list is cut apart by `BuildCalculator.FeatListTokenizer` —
  the same longest-match reader the wiki's build pages and the shard's `.билд`
  log go through — so a roman rank (`Great Strength II`, `Epic Toughness IV`)
  reads as the feat it ranks, and a comma inside a name does not split it.

  What CBC prints around the decisions is recognised and left out, because it
  is the source's own arithmetic or its own reminder, never a decision: the
  score after a bump (`(STR=16)`, `Dex+1(20)`), what a class hands over by
  itself (`{Evasion}`, `Ro: (Evasion)`), a note in brackets (`RDD (+1 AC)`)
  and the points a skill chart carries on to the next level (`Save(8)`).

  ## Honesty

  Whatever did not parse is **reported, never invented** (CLAUDE.md §3). The
  result carries an `issues` list beside the build and the interface shows it
  before the player accepts the import. Four consequences are worth naming:

    * **The ladder is one numbered list.** A post carries several — the
      ladder, CBC's per-level skill chart, a variant, a numbered list of notes
      in a reply — and a later one must not overwrite levels an earlier one
      gave (task 4.8: the skill chart used to wipe a whole ladder). A list
      restarts where its numbers stop rising; the list with the most class
      lines is the ladder, a skill chart is read as skills, and every other
      numbered line is listed as skipped rather than dropped.
    * **A line the reader cannot parse stops the ladder** instead of letting
      the levels after it slide up one. Order decides base attack and saves past
      character level 20 outright, so a build with one level missing is not
      "almost right", it is a different character.
    * **The class split in the header never becomes levels.** `Fighter(10),
      Wizard(20)` states totals, not order, and `Fighter 20 → Wizard 20` is not
      the same build as the reverse. Without a ladder the levels stay empty and
      the header split is shown for the player to rebuild from. A ladder that
      writes running totals (`Fighter1/Monk1`) is read only against itself
      (task 4.31): the level took the class whose count grew by one, and a line
      whose counts do not follow the ladder read so far stops it.
    * **A guess is said.** A misspelt or shortened name (`Luck of Heros`,
      `GRT DEX`, `Hafling`), increases restored from the scores a post prints
      at the end, a race picked from several by the author's own word — each is
      a reading the player is told about (task 4.31), never a silent one.
    * **The `SKILLS` totals are not imported.** A rank is priced and capped by
      the level it was bought at, and the totals block does not say which level
      that was. Only a per-level guide — ours, or CBC's skill chart — can be
      read back.

  An alignment *restriction* (`Any non-lawful`) is not an alignment: it is
  named as such, and the choice is left to the player.

  ## The source's own numbers are not the build's

  `Hitpoints`, `AB`, `AC` and the rest of the header are somebody else's
  arithmetic, usually with gear and buffs folded in. They are carried in
  `source.totals` so the player can compare them against ours, and they never
  reach the build — mixing a foreign result into our own calculation is exactly
  the confident lie this project is built to avoid. The saves are set beside
  ours in the order the source's own caption names them: CBC for 1.69 prints
  Fortitude/Will/Reflex, CBC for EE Fortitude/Reflex/Will (VANILLA.md §3.7).

  ## Where things are (task 4.32)

  The module was one file of 5220 lines. Its sections became the modules
  `BuildCalculatorWeb.Builder.Import.*`, and this one stayed the facade:
  `parse/2`, `issue_text/2`, `issue_kind/1`, `issue_forms/0` and
  `comparison/2` are everything a caller outside uses, and everything it
  may use — a part's public functions are its interface to the other
  parts, not an API. The parts, in the order a paste goes through them:

    * `Scan` — the text clamped and cut into lines, and the state one pass
      over them keeps;
    * `Lines` — which shape each line is (`classify_line/3` asks them in
      order), and the small shapes nobody else owns: section headers, the
      `SKILLS` totals, a list of increases, a `Domains:` line;
    * `Header` — the title and the class split it states, the race and the
      alignment, wherever the post writes them;
    * `Sheets` — the numbers a post prints: the score sheet, whose start is
      read into the build, and the totals and saves, kept for comparison;
    * `Ladder` — the numbered lines, where a level line's class ends, and
      which numbered list is the ladder;
    * `LevelTail` — one level's contents: the bump, skill purchases, notes;
    * `FeatList` — the feat names of one level, their ranks and choices;
    * `Names` — every dictionary a name is resolved through (classes,
      feats, skills, races, alignments, scores, choice values), and the
      guesses at typos and shorthand;
    * `Assembly` — the build put together out of what was read, and what
      the text says about itself and about the rules;
    * `Issues` — the wording of every issue and its group;
    * `Comparison` — the source's totals beside ours.
  """

  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Import.{Comparison, Issues}

  import BuildCalculatorWeb.Builder.Import.Assembly, only: [assemble: 4]
  import BuildCalculatorWeb.Builder.Import.Lines, only: [classify: 3, flush_head: 1]
  import BuildCalculatorWeb.Builder.Import.Names, only: [indexes: 1]

  import BuildCalculatorWeb.Builder.Import.Scan,
    only: [empty_scan: 0, finish: 1, lines: 1, paragraphs: 3, paste: 1]

  import BuildCalculatorWeb.Builder.Import.Sheets,
    only: [flush_block: 1, flush_letters: 1, rolled_marker: 1, sheet_read: 1]

  @typedoc "A machine-readable note about something the text did not give us."
  @type issue :: tuple()

  @type result :: %{
          build: Build.t(),
          title: String.t() | nil,
          read: map(),
          issues: [issue()],
          source: map()
        }

  @doc """
  Reads a text block into a build, plus everything that did not read.

  Never raises and never returns an error: an unreadable paste is an empty build
  with a list of issues saying so, which is what the interface has to show
  anyway.
  """
  @spec parse(term(), map()) :: result()
  def parse(text, ruleset) when is_binary(text) do
    {body, notes} = paste(text)
    index = indexes(ruleset)

    scan =
      body
      |> lines()
      |> Enum.with_index()
      |> Enum.reduce(empty_scan(), fn {{number, line}, position}, scan ->
        %{scan | position: position}
        |> paragraphs(number, line)
        |> classify({number, line}, index)
        |> Map.merge(%{last_line: line, last_number: number})
      end)
      |> flush_letters()
      |> flush_block()
      |> flush_head()
      |> sheet_read()
      |> finish()

    assemble(%{scan | rolled: rolled_marker(body)}, ruleset, index, notes)
  end

  def parse(_text, ruleset), do: parse("", ruleset)

  @doc """
  One issue, in Russian.

  Same register as `Labels.gap/2`: what the reader could not do is said plainly
  and the source's own text is quoted, so the player can see whether it is their
  paste or our dictionary that came up short.
  """
  @spec issue_text(issue(), map()) :: String.t()
  defdelegate issue_text(issue, ruleset), to: Issues

  @doc """
  Short name of an issue family, for grouping the list.

  The move `Gaps.family/1` makes, for the same reason: a flat list of thirty
  notes is read by nobody, and the groups answer different questions — what
  the dictionary did not know, what the format cannot carry, and what the
  source contradicts about itself.

  The family is decided by the issue's shape (`Issues.issue_family/1`), and
  only its title goes through `gettext` (task 4.8): an import issue added for
  the vanilla edition may not bring a Russian title into the English site.
  """
  @spec issue_kind(issue()) :: String.t()
  defdelegate issue_kind(issue), to: Issues

  @doc """
  Every issue shape this module can produce, filled with sample values.

  A guard for the tests, in the spirit of `labels_test.exs`: an issue nobody
  worded renders through `inspect/1` and the interface shows a player a tuple.
  The list is the contract — an issue the reader is taught to produce has to
  be added here too, and the test fails until it has Russian wording.
  """
  @spec issue_forms() :: [issue()]
  defdelegate issue_forms(), to: Issues

  @doc """
  The source's own totals beside ours, row by row.

  The header of somebody else's block is their arithmetic — usually with gear
  and buffs in it — so it is never imported (see the moduledoc). Showing it next
  to what we computed is the useful half: a wild disagreement is how a player
  finds out the build was posted wearing its equipment, and a small one is how
  they find out that one of us is wrong.

  ⚠️ The saves come in the order the source's caption names them (task 4.8).
  CBC for 1.69 prints `Saving Throws (Fortitude/Will/Reflex)`, CBC for EE
  `(Fortitude/Reflex/Will)`, and 136 of the 157 corpus builds with a saves line
  use the first — set beside our Fort/Ref/Will, Reflex and Will would disagree
  on nearly every build that is in fact right.
  """
  @spec comparison(result(), map()) :: [
          %{label: String.t(), source: String.t(), ours: String.t()}
        ]
  defdelegate comparison(result, stats), to: Comparison
end
