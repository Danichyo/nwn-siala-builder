defmodule BuildCalculator.GameLog do
  @moduledoc """
  Reads the shard's `.билд` chat dump into a structure — nothing more.

  Task 3.111, first pass of two. The shard added a chat command that prints a
  full character report to the client log: race, ability scores (twice — once
  "white", i.e. without worn items, once "current", with them), combat totals,
  skill totals, and a level-by-level ladder with the class taken, the `+1` to
  an ability every fourth level, the feats gained, and the skill ranks bought.
  Fifteen real dumps (`test/fixtures/game_logs/`, sent by Dan 26–28.08.2026)
  are the only known examples of the format. See
  `@header_class_abbreviations`'s own provenance list below for exactly which
  dump taught this module what, dump by dump; this paragraph only covers the
  shapes big enough to need their own note in prose.

  The fourth (task 3.116) and fifth (task 3.118) dumps are what taught this
  module that the client's own naming can differ from the wiki's for the
  same feat — see `feat_spelling_aliases/0` below and
  `BuildCalculator.FeatListTokenizer`'s own `read_rank/1`. The sixth
  (task 3.119) turned one particular shape of that mismatch — a feat name
  carrying the wiki's own "(feat)" disambiguation suffix, which nobody
  typing a build reproduces — from three one-off aliases into a general
  rule: see `feat_dictionary/1`'s own note. The seventh (task 3.121,
  `aley.log`) is the first build under the level cap — confirming this
  module is not secretly tied to 40/41 levels — and adds a FOURTH way an
  argument rides along with a feat's name, a colon rather than a comma or a
  parenthesis: see `favored_enemy_aliases/1` below.

  ✅ **Starting with the eighth, every dump has been one of
  `docs/log_coverage.md`'s own ten-build plan** (task 3.131) rather than sent
  as "whatever build a player already had" — all eight of the plan's REQUIRED
  builds landed the same day, closing the class-abbreviation table entirely
  (`@header_class_abbreviations`'s own note). Three of those eight
  (`elith.log`, `timonall.log`, `hana.log`), independently, are the only
  dumps so far to show the `SKILLS WITH RANKS:` block simply absent — every
  other block each fixture carries is present, and the block sits in its
  usual place (between `COMBAT STATS:` and `(WHITE) ABILITIES:` on every
  fixture that carries it at all) as a clean blank line rather than a ragged
  cut, so the reading taken here is that the client omits the block outright
  when a character has spent zero skill points total, not that the paste
  lost it — see `put_skill_totals/3` below for the disambiguation this
  forced. `timonall.log`, `trina.log`, `nicha.log` and `hana.log` are also,
  on top of their own header spellings, built on the shard with no gear at
  all — see `BuildCalculatorWeb.Builder.GameLogImportTest`'s own note on
  what that makes possible that no earlier fixture could check, and on a
  point-buy finding that fell out of checking it. `hela.log` carries a
  genuine, still-open data gap of its own (`granted_feats` missing two of
  Red Dragon Disciple's three `Hit Die Increase` prints) — see that same
  test file's own describe block for the one issue this module correctly
  raises rather than swallows.

  🎉 **The sixteenth (task 3.173, `hnyupius_alignment.log`, 03.09.2026) closes
  the last hole this format was known to leave: the shard started printing
  an `ALIGNMENT:` line right under `RACE:`.** It is the same character as
  the fourth dump (`hnyupius.log`), re-pulled after the shard change rather
  than a new build — the old dump is kept as its own fixture on purpose,
  precisely because it is the regression that an `ALIGNMENT:`-less dump
  still reads exactly as it always did. See `put_alignment/2` below for why
  a missing line is not `{:missing_field, …}` the way a missing race is,
  and for the one spelling this format has not shown yet (True/bare
  Neutral, `GAME_CHECKS.md`).

  ## What this module is not

  It does **not** build a `BuildCalculator.Rules.Build`. Turning this structure
  into one — deciding which of a level's feats were *chosen* versus *handed
  over by a class or race* (CLAUDE.md §6: "получишь бесплатно — не трать
  слот"), filling slots, wiring up a LiveView import button — is task 3.111's
  second pass. This pass answers a narrower question on purpose: **can the
  text be read at all, completely and honestly**, which is worth knowing on
  its own even if the second pass never ships. It is also what makes a
  by-hand comparison against the game's own printed numbers possible later —
  `COMBAT STATS` came out of the engine, not off a wiki page somebody's
  arithmetic could be wrong on.

  ## The three traps that break a naive comma-split

  1. **A feat's own name can contain a comma.** `Energy Resistance, Fire I` is
     one feat, not two — same problem `WikiBuildPage` solved for the wiki's
     build pages, same fix: `BuildCalculator.FeatListTokenizer` walks the text
     from the front and matches the **longest** dictionary entry at each
     position, so `energy resistance, fire` (the whole phrase, comma
     included) is found before the comma is ever treated as a separator. That
     module is shared rather than reimplemented — see its own moduledoc for
     why a second implementation would have been the mistake, not a shortcut.
  2. **Not everything in a `FEATS:` line is a feat.** «Дух Сиалы» is
     `ruleset.innate_hp_bonus`, a flat HP bonus every character carries,
     deliberately kept out of `ruleset.feats` so it cannot be picked, required,
     or duplicated like one (CLAUDE.md §3). The engine still prints it in the
     feat list because to the *character sheet* it looks like one. Two more
     shapes are the same kind of impostor and are recognised the same way,
     never mapped onto a feat id: `Epic Character` (character level 21) and
     `Epic <ClassName>` (that *class's own* levels crossed its epic
     threshold — 21 for a base class, 11 for a prestige one, CLAUDE.md §3).
     Domain grants (`War Domain Powers`) are a fourth shape, recognised the
     same way but by a looser pattern rather than a fixed dictionary entry,
     since the domain name is not ours to enumerate here.
  3. **A level mixes what the class handed over for free with what the player
     chose.** `Toughness` on a fighter's first level, `Defensive awareness`
     on a Dwarven Defender's — automatic, unearned by a slot. This pass does
     **not** try to tell the two apart (that needs `Rules.FeatSlots` and a
     `Build`, i.e. the second pass); every name in the line is read and kept,
     resolved where the dictionary knows it, reported where it does not.

  ## Honesty

  Nothing recognisable is ever dropped. A line, a feat name, a skill name, an
  ability abbreviation the tables below do not know about is carried into
  `problems` with enough context to find it in the source text, rather than
  silently vanishing — the same discipline `BuildCalculator.Wiki.ClassPage`
  and `WikiBuildPage` apply to wiki text, aimed at a new source. An unread
  token is never a reason to stop: 3.111's own assignment is explicit that a
  build with one strange feat name out of forty is more useful than no
  parser at all, so a single bad token becomes one entry in `problems`, not a
  raised exception. Nothing here raises on bad input, ever — a dump that
  reads badly is a mostly-empty struct with `problems` explaining why.

  ## What "white" and "current" abilities are, and are not

  `CURRENT ABILITIES` / `COMBAT STATS` / `SKILLS WITH RANKS` are the character
  **as worn** — gear included. `(WHITE) ABILITIES` is the same character
  **without** gear. Neither is the point buy: Dan measured that a level-40
  Dwarven Defender's `(WHITE)` scores do not reduce to a 30-point budget by
  any of four tried readings (race modifiers out, level-up `+1`s out, or
  both), and decided the calculator should not try to guess the point buy
  back out of a finished sheet at all — a player re-enters it by hand on
  import. This module still reads all four blocks faithfully regardless: they
  are what lets a future check compare this project's own calculation against
  the numbers the game engine printed, which is the reason task 3.111 keeps
  parsing and importing as two separate passes in the first place.

  ## The header count is a checksum, not a source

  `Current: 10 FTR / 23 DD / 7 WM` is a per-class tally in shorthand; the
  ladder itself, written out in full class names, is what the levels actually
  are. `checksum/1` compares the two and reports every disagreement — it does
  not correct one from the other, because a real disagreement (wrong parse,
  or the game printing something this module misread) needs to be visible,
  not silently resolved in either direction.

  ⚠️ The trap CLAUDE.md's own epic-level rule predicts and one fixture
  exercises directly: a class's *n*-th level does not have to be taken on
  character level *n* — Hnyupius's tenth Fighter level is `LEVEL 21: FIGHTER`,
  taken well into the epics, after ten Dwarven Defender levels and a level of
  Weapon Master came between it and Fighter's ninth. The checksum still comes
  out even (ten Fighter levels total) because it tallies the class column,
  never the character-level column — but the **order** the ladder is read in
  must survive untouched, because CLAUDE.md §3 makes order load-bearing for
  base attack and saves past character level 20. `levels` is therefore a
  plain list in encounter order with an explicit `:level` field on each entry
  — never reindexed, sorted, or collapsed by class — precisely so a level
  taken out of the class's own numeric order (like this one) cannot get lost
  or silently moved.
  """

  alias BuildCalculator.FeatListTokenizer
  alias BuildCalculator.Ids

  @typedoc "One resolved-or-not token off a `FEATS:` line."
  @type feat_entry :: %{
          kind: :feat | :special | :unknown,
          id: term(),
          raw: String.t(),
          argument: String.t() | nil,
          rank: String.t() | nil
        }

  @typedoc "One resolved-or-not `Name +N` token off a `SKILLS:` line."
  @type skill_delta :: %{skill: atom() | nil, name: String.t(), delta: integer() | nil}

  @typedoc "One resolved-or-not `Name N` token off the `SKILLS WITH RANKS:` block."
  @type skill_total :: %{skill: atom() | nil, name: String.t(), ranks: integer() | nil}

  @typedoc "One `LEVEL N: CLASS` block."
  @type level_entry :: %{
          level: pos_integer(),
          class: atom() | nil,
          class_raw: String.t(),
          ability_increase: %{ability: atom() | nil, raw: String.t(), amount: integer()} | nil,
          feats: [feat_entry()],
          skills: [skill_delta()]
        }

  @typedoc "A machine-readable note about something the text did not give up cleanly."
  @type problem :: tuple()

  @type t :: %__MODULE__{}

  defstruct name: nil,
            race: nil,
            race_raw: nil,
            alignment: nil,
            alignment_raw: nil,
            header_classes: [],
            white_abilities: %{},
            current_abilities: %{},
            combat_stats: %{},
            skills_with_ranks: [],
            levels: [],
            problems: []

  # -------------------------------------------------------------- entry point --

  @doc """
  Parses one `.билд` chat dump against `ruleset`.

  Never raises: a dump that reads badly is a mostly-empty struct with
  `problems` explaining why, the same failure shape every other reader in this
  project uses (`BuildCalculatorWeb.Builder.Import.parse/2`,
  `WikiBuildPage.parse/2`).
  """
  @spec parse(String.t(), map()) :: t()
  def parse(text, ruleset) when is_binary(text) do
    lines = text |> String.replace("\r\n", "\n") |> String.split("\n")

    scan = Enum.reduce(lines, empty_scan(), &scan_line(&2, &1))

    # Seeded with `scan.problems`, not an empty list: unrecognised lines,
    # duplicate fields and fields written before any `LEVEL` was seen are all
    # found *during* the scan above, and would otherwise be computed and then
    # silently thrown away here.
    %__MODULE__{problems: scan.problems}
    |> put_name(scan)
    |> put_header_classes(scan, ruleset)
    |> put_race(scan, ruleset)
    |> put_alignment(scan)
    |> put_ability_block(scan.white_raw, :white_abilities, "(WHITE) ABILITIES")
    |> put_ability_block(scan.current_raw, :current_abilities, "CURRENT ABILITIES")
    |> put_combat_stats(scan)
    |> put_skill_totals(scan, ruleset)
    |> put_levels(scan, ruleset)
    |> put_checksum_problems()
    |> put_level_sequence_problems()
  end

  def parse(_text, _ruleset), do: %__MODULE__{problems: [{:not_a_string}]}

  # ------------------------------------------------------------------- scan --
  #
  # A single left-to-right pass builds a scan of *raw* text, line shapes only —
  # nothing is resolved against the ruleset here. Resolution happens once, in
  # the `put_*` functions below, so every "this name is unknown" decision is
  # made in exactly one place per field instead of being duplicated between a
  # scanning pass and a resolving pass.

  # The game's own chat-log wrapper: the command echo, the two acknowledgement
  # lines, and the trailing "Build sent to! <name>". None of it carries build
  # information, so it is recognised and dropped here rather than reported —
  # the same distinction `Import.skip_line?/1` draws between decoration and
  # content for a forum paste.
  @boilerplate "[CHAT WINDOW TEXT]"
  @divider ~r/^-{5,}$/

  defp empty_scan do
    %{
      name: nil,
      header_classes_raw: [],
      race_raw: nil,
      alignment_raw: nil,
      white_raw: nil,
      current_raw: nil,
      combat_raw: nil,
      collecting_totals?: false,
      skills_header_seen?: false,
      skill_totals_raw: [],
      current_level: nil,
      level_entries: [],
      problems: []
    }
  end

  defp scan_line(scan, raw_line) do
    line = String.trim_trailing(raw_line)
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        %{scan | collecting_totals?: false}

      String.starts_with?(trimmed, @boilerplate) ->
        scan

      Regex.match?(@divider, trimmed) ->
        scan

      m = Regex.run(~r/^\s*CHARACTER BUILD:\s*(.+)$/u, line) ->
        [_, name] = m
        %{scan | name: name}

      m = Regex.run(~r/^\s*Current:\s*(.+)$/u, line) ->
        [_, tail] = m
        %{scan | header_classes_raw: header_pairs(tail)}

      m = Regex.run(~r/^RACE:\s*(.+)$/u, line) ->
        [_, race] = m
        %{scan | race_raw: race}

      # Task 3.173 (03.09.2026): the shard started printing this line right
      # under `RACE:` — the last hole `docs/log_coverage.md`'s own plan
      # left, alignment, is a class requirement `illegal_class_levels/2`
      # re-checks on EVERY level a class was taken on (not just the first —
      # CLAUDE.md §3, "правка раннего уровня перепроверяет поздние"), and
      # `nil` loses to any such requirement. On the one fixture that
      # exercises this (`hnyupius_alignment.log`, a Dwarven Defender build,
      # "lawful" required) that is not a rounding error: 46 illegal levels
      # with `alignment: nil`, zero once this line is read.
      m = Regex.run(~r/^ALIGNMENT:\s*(.+)$/u, line) ->
        [_, alignment] = m
        %{scan | alignment_raw: alignment}

      m = Regex.run(~r/^\(WHITE\) ABILITIES:\s*(.+)$/u, line) ->
        [_, tail] = m
        %{scan | white_raw: tail}

      m = Regex.run(~r/^CURRENT ABILITIES:\s*(.+)$/u, line) ->
        [_, tail] = m
        %{scan | current_raw: tail}

      m = Regex.run(~r/^COMBAT STATS:\s*(.+)$/u, line) ->
        [_, tail] = m
        %{scan | combat_raw: tail}

      Regex.match?(~r/^SKILLS WITH RANKS:\s*$/u, line) ->
        # `skills_header_seen?` records that this LINE existed, separately
        # from `skill_totals_raw` staying `[]` — the only way `put_skill_totals/3`
        # below can tell "the client printed the header and then nothing" from
        # "the client never printed the header at all" apart, since both leave
        # the same empty list otherwise.
        %{scan | collecting_totals?: true, skills_header_seen?: true}

      scan.collecting_totals? ->
        %{scan | skill_totals_raw: scan.skill_totals_raw ++ [trimmed]}

      m = Regex.run(~r/^LEVEL\s+(\d+):\s*(.+)$/u, line) ->
        [_, level, class_raw] = m
        open_level(scan, to_int(level), class_raw)

      m = Regex.run(~r/^\s*ABILITY:\s*\+(\d+)\s+([A-Za-z]+)\s*$/u, line) ->
        [_, amount, label] = m
        update_level(scan, :ability_raw, {to_int(amount), label})

      m = Regex.run(~r/^\s*FEATS:\s*(.+)$/u, line) ->
        [_, tail] = m
        update_level(scan, :feats_raw, tail)

      m = Regex.run(~r/^\s*SKILLS:\s*(.+)$/u, line) ->
        [_, tail] = m
        update_level(scan, :skills_raw, tail)

      true ->
        %{scan | problems: scan.problems ++ [{:unrecognized_line, line}]}
    end
  end

  defp open_level(scan, level, class_raw) do
    entry = %{
      level: level,
      class_raw: class_raw,
      ability_raw: nil,
      feats_raw: nil,
      skills_raw: nil
    }

    %{scan | current_level: level, level_entries: scan.level_entries ++ [entry]}
  end

  defp update_level(%{current_level: nil} = scan, field, _value) do
    %{scan | problems: scan.problems ++ [{:field_before_any_level, field}]}
  end

  defp update_level(scan, field, value) do
    {entries, problems} =
      set_last(scan.level_entries, field, value, scan.current_level, scan.problems)

    %{scan | level_entries: entries, problems: problems}
  end

  # Duplicates within one level are not expected on any fixture seen so far,
  # but silently letting the second occurrence overwrite the first would be
  # exactly the "lost a line and nobody noticed" failure this module exists to
  # avoid — so it is kept as a reported problem instead, and the first
  # occurrence wins. `entries` is never empty here in practice (a `field` is
  # only ever set right after `open_level/3` appended one), but the catch-all
  # keeps the promise that this module never raises even if that invariant is
  # ever broken by a format change.
  defp set_last(entries, field, value, level, problems) do
    case List.last(entries) do
      %{^field => nil} = last ->
        {List.replace_at(entries, -1, Map.put(last, field, value)), problems}

      %{} ->
        {entries, problems ++ [{:duplicate_field, level, field}]}

      nil ->
        {entries, problems ++ [{:field_before_any_level, field}]}
    end
  end

  # `Current: 10 FTR / 23 DD / 7 WM` → `[{"FTR", 10}, {"DD", 23}, {"WM", 7}]`,
  # raw — resolution against the abbreviation table happens in `put_header_classes/3`.
  defp header_pairs(tail) do
    tail
    |> String.split("/")
    |> Enum.map(fn segment ->
      case Regex.run(~r/^\s*(\d+)\s+([A-Za-zА-Яа-я]+)\s*$/u, segment) do
        [_, count, abbrev] -> {abbrev, to_int(count)}
        _ -> {:unparsed, String.trim(segment)}
      end
    end)
  end

  # ------------------------------------------------------------- resolution --

  defp put_name(struct, %{name: nil}), do: add_problem(struct, {:missing_field, :name})
  defp put_name(struct, %{name: name}), do: %{struct | name: name}

  # Observed spellings only, one dump each — never a derived scheme.
  # `Fighter` alone is a single word and `Labels.class_short/2` would print
  # it back whole rather than as `FTR`, so there is no formula here to
  # extend from, only more logs to read. A SHORTENED spelling this table has
  # not seen is reported, never guessed — CLAUDE.md's rule against
  # extrapolating a pattern from a handful of examples applies exactly as
  # much to a three-letter code as to a game mechanic. Not every key is
  # actually short (`frah_hall.log`'s own "2 Bard" — the header only
  # abbreviates when it bothers to) or even-cased the same way
  # (`timonall.log`'s own "10 CoT" against every other short code's ALL
  # CAPS) — `String.downcase/1` (`header_pairs/1`) makes case irrelevant to
  # the lookup, so neither shape needed a code change, only the note.
  #
  # ✅ COMPLETE as of 28.08.2026 — all 23 classes have an observed spelling,
  # `docs/log_coverage.md`'s own plan (task 3.123) closed end to end across
  # fifteen dumps. Provenance, one line per dump:
  #
  #   26.08.2026, dump 1-3: table seeded, 15 of 23 classes
  #   27.08.2026, dump 4 (task 3.116): "barb"
  #   27.08.2026, dump 5 (task 3.118): "sorc" / "dru" / "bard"
  #   27.08.2026, dump 6 (task 3.119): "pal"
  #   28.08.2026, dump 7 (task 3.121, `aley.log`): "hs"
  #   28.08.2026, dump 8  (`elith.log`,    `Current: 1 SORC / 10 RNG / 14 AA`):  "aa"
  #   28.08.2026, dump 9  (`boido.log`,    `Current: 7 FTR / 8 BG`):             "bg"
  #   28.08.2026, dump 10 (`nathan.log`,   `Current: 5 ROG / 9 ASS`):            "ass"
  #   28.08.2026, dump 11 (`timonall.log`, `Current: 8 FTR / 10 CoT`):           "cot"
  #   28.08.2026, dump 12 (`trina.log`,    `Current: 5 FTR / 10 PDK`):           "pdk"
  #   28.08.2026, dump 13 (`hela.log`,     `Current: 2 FTR / 7 SORC / 10 RDD`): "rdd"
  #   28.08.2026, dump 14 (`nicha.log`,    `Current: 10 ROG / 2 Bard / 12 SD`):  "sd"
  #   28.08.2026, dump 15 (`hana.log`,     `Current: 6 DRU / 10 SHIF`):          "shif"
  #
  # Dumps 8-15 are `docs/log_coverage.md`'s own ten-build plan (Build 1 through
  # Build 8, taken in order — the last two of the plan's ten, Harper Scout and
  # Monk deeper, were bonus builds never requested) rather than sent as an
  # existing character's build, so they are the first logs this table did not
  # simply happen to receive.
  #
  # ⚠️ **Dump 13 started life outside this table's own test suite, and it is
  # worth knowing why.** `hela.log` was FIRST measured by a different,
  # concurrent task (the point-buy investigation CLAUDE.md §3 and §9
  # describe) directly with Dan, and only written up as CLAUDE.md prose —
  # "rdd" briefly rested on that report rather than a file this module's own
  # tests could rerun. The dump itself arrived as a fixture shortly after
  # (task 3.131's own correction), and it is read exactly like the other
  # fourteen now — `test/fixtures/game_logs/hela.log`, `GameLogTest` runs
  # this table against it same as any other. Left as a note rather than
  # deleted: the gap between "Dan observed it" and "this table's own tests
  # can prove it" was real for a while, and the fix was landing the file,
  # not just trusting the report.
  #
  # ⚠️ Collision discipline, checked ON EVERY ADDITION above, not once at the
  # start: a new key must not already sit in this table under a different
  # class, and no OTHER class's own full name (`class_dictionary/1`'s own
  # source, EN or RU) may normalise to it either — run by code
  # (`ProbeAbbrev`-style script over `ruleset.classes`, both rulesets), never
  # by eye. The one hit found across every run so far is `bard`'s own full
  # name landing on its own existing "bard" key, which is correct behaviour,
  # not a collision.
  @header_class_abbreviations %{
    "ftr" => :fighter,
    "dd" => :dwarven_defender,
    "wm" => :weapon_master,
    "mnk" => :monk,
    "clr" => :cleric,
    "rog" => :rogue,
    "rng" => :ranger,
    "wiz" => :wizard,
    "barb" => :barbarian,
    "pm" => :pale_master,
    "sorc" => :sorcerer,
    "dru" => :druid,
    "bard" => :bard,
    "pal" => :paladin,
    "hs" => :harper_scout,
    "aa" => :arcane_archer,
    "bg" => :blackguard,
    "ass" => :assassin,
    "cot" => :champion_of_torm,
    "pdk" => :purple_dragon_knight,
    "rdd" => :red_dragon_disciple,
    "sd" => :shadowdancer,
    "shif" => :shifter
  }

  defp put_header_classes(struct, %{header_classes_raw: []}, _ruleset),
    do: add_problem(struct, {:missing_field, :header_classes})

  # `frah_hall.log`'s own "Bard" already proved the header sometimes prints a
  # class's FULL name instead of shortening it — task 3.119 (27.08.2026)
  # generalises that: every class's full name is checked too, off the exact
  # same `class_dictionary/1` the ladder's own `LEVEL N: CLASS` lines already
  # resolve through (below), not a second table typed out by hand. This is
  # derivation, not guessing — `ruleset.classes[id].name` is the one place a
  # class's own English name already lives — and it does not touch the
  # shortened-spelling table above at all: a THREE-LETTER code this project
  # has not observed yet is still reported, never invented from the full
  # name (CLAUDE.md's rule stays exactly as strict for those). Checked by
  # hand (task 3.119) that no class's full name collides with an existing
  # abbreviation under a different id — "bard" is the one case where both
  # tables answer the same key, and they agree.
  defp put_header_classes(struct, %{header_classes_raw: pairs}, ruleset) do
    full_names = class_dictionary(ruleset)

    {resolved, problems} =
      Enum.map_reduce(pairs, [], fn
        {:unparsed, text}, problems ->
          {%{raw: text, count: nil, class: nil}, problems ++ [{:unparsed_header_segment, text}]}

        {abbrev, count}, problems ->
          key = normalize(abbrev)
          id = Map.get(@header_class_abbreviations, key) || Map.get(full_names, key)

          case id do
            nil ->
              {%{raw: abbrev, count: count, class: nil},
               problems ++ [{:unresolved_header_class, abbrev}]}

            id ->
              {%{raw: abbrev, count: count, class: id}, problems}
          end
      end)

    %{struct | header_classes: resolved, problems: struct.problems ++ problems}
  end

  defp put_race(struct, %{race_raw: nil}, _ruleset),
    do: add_problem(struct, {:missing_field, :race})

  defp put_race(struct, %{race_raw: raw}, ruleset) do
    wanted = String.downcase(raw)

    found =
      Enum.find_value(ruleset.races, fn {id, race} ->
        String.downcase(race.name) == wanted && id
      end)

    struct = %{struct | race_raw: raw, race: found}
    if found, do: struct, else: add_problem(struct, {:unresolved_race, raw})
  end

  # Unlike race, an absent `ALIGNMENT:` line is NOT `{:missing_field, …}` —
  # it is not a required field the way race is. All fifteen fixtures sent
  # before the shard added this line read cleanly with no such line at all,
  # and that has to stay true (`GameLogImportTest`'s own regression on every
  # one of them). `BuildCalculatorWeb.Builder.GameLogImport` is the layer
  # that turns "we do not know" into something the player sees
  # (`{:alignment_unavailable}`), same as it already reads `race: nil` —
  # this module just never claims to know something the text did not say.
  #
  # Resolved against `Ids.alignments/0`, never a literal name typed here —
  # same whitelist rule `put_race/3` follows against `ruleset.races`
  # (AGENTS.md: no `String.to_atom/1` on outside text), just against the
  # fixed nine-word vocabulary `Rules.LevelUp` itself reads rather than
  # against ruleset data, because alignment is not ruleset data
  # (`Ids`'s own moduledoc).
  #
  # ⚠️ Only "Lawful Good" has ever been observed. Whether the client spells
  # the middle row "True Neutral" (as `Ids.alignments/0` names it) or bare
  # "Neutral" is an open question — see `GAME_CHECKS.md`. Guessing wrong
  # here would silently mis-file a build's alignment; an unmatched value
  # instead becomes `{:unresolved_alignment, raw}` and `alignment` stays
  # `nil`, same shape `put_race/3` uses for a race that fails to resolve.
  defp put_alignment(struct, %{alignment_raw: nil}), do: struct

  defp put_alignment(struct, %{alignment_raw: raw}) do
    wanted = String.downcase(raw)

    found =
      Enum.find_value(Ids.alignments(), fn {id, name} ->
        String.downcase(name) == wanted && id
      end)

    struct = %{struct | alignment_raw: raw, alignment: found}
    if found, do: struct, else: add_problem(struct, {:unresolved_alignment, raw})
  end

  @ability_codes %{
    "str" => :str,
    "dex" => :dex,
    "con" => :con,
    "int" => :int,
    "wis" => :wis,
    "cha" => :cha
  }
  @ability_keys @ability_codes |> Map.values() |> Enum.sort()

  defp put_ability_block(struct, nil, field, label) do
    struct |> Map.put(field, %{}) |> add_problem({:missing_field, label})
  end

  defp put_ability_block(struct, raw, field, label) do
    {scores, unresolved} = resolve_labels(raw, @ability_codes)
    problems = Enum.map(unresolved, &{:unresolved_ability_label, label, &1})
    struct = struct |> Map.put(field, scores) |> add_problems(problems)

    missing = @ability_keys -- Map.keys(scores)

    if missing == [],
      do: struct,
      else: add_problem(struct, {:incomplete_ability_block, label, missing})
  end

  @combat_stat_codes %{
    "ab" => :ab,
    "ac" => :ac,
    "fort" => :fort,
    "refl" => :refl,
    "will" => :will
  }
  @combat_stat_keys @combat_stat_codes |> Map.values() |> Enum.sort()

  defp put_combat_stats(struct, %{combat_raw: nil}),
    do: add_problem(struct, {:missing_field, :combat_stats})

  defp put_combat_stats(struct, %{combat_raw: raw}) do
    {stats, unresolved} = resolve_labels(raw, @combat_stat_codes)
    problems = Enum.map(unresolved, &{:unresolved_combat_stat_label, &1})
    struct = struct |> Map.put(:combat_stats, stats) |> add_problems(problems)

    missing = @combat_stat_keys -- Map.keys(stats)
    if missing == [], do: struct, else: add_problem(struct, {:incomplete_combat_stats, missing})
  end

  # `STR 20 DEX 12 CON 26 …` and `AB 54 AC 60 Fort 59 …` share one shape: a run
  # of `<Label> <integer>` pairs. One reader for both, parameterised by which
  # labels are expected, so the two blocks cannot silently drift into two
  # slightly different parsers. Returns the resolved scores plus the raw
  # labels that did not resolve — a label a caller reports with its own tag
  # rather than one this function would have to guess a name for.
  defp resolve_labels(text, table) do
    ~r/([A-Za-z]{2,6})\s+(-?\d+)/u
    |> Regex.scan(text)
    |> Enum.reduce({%{}, []}, fn [_, label, number], {scores, unresolved} ->
      case Map.get(table, String.downcase(label)) do
        nil -> {scores, unresolved ++ [label]}
        key -> {Map.put(scores, key, to_int(number)), unresolved}
      end
    end)
  end

  # A character who never spent a skill point is not a hole in the reading —
  # NWN's own level-up wizard never forces a player to spend skill points the
  # way it forces the ability-score point buy (CLAUDE.md §3's "надо всегда
  # принудительно потратить" is about ability scores only), so an empty block
  # is a legal character, not a defect. `elith.log` (task 3.131, eighth dump)
  # is the fixture this reading is measured against: the header line itself
  # never appears anywhere in the text (`skills_header_seen?: false`), every
  # OTHER block that fixture carries is present, and the block's usual slot
  # (between `COMBAT STATS:` and `(WHITE) ABILITIES:` on every one of the
  # first seven fixtures) is a clean blank line rather than a ragged one — the
  # shape a copy-paste truncation would leave instead, not what "the client
  # simply did not print this section" leaves.
  defp put_skill_totals(struct, %{skill_totals_raw: [], skills_header_seen?: false}, _ruleset),
    do: struct

  # The one shape kept as a problem rather than folded into the silence
  # above: the header line WAS printed and nothing followed it. No fixture
  # has shown this yet, and it is deliberately not assumed to mean the same
  # thing as the header never appearing at all — a header the client bothered
  # to print, with an empty list under it, is a fact this module has no
  # story for, and guessing "same as absent" would be exactly the kind of
  # invented reading CLAUDE.md warns against for a game mechanic.
  defp put_skill_totals(struct, %{skill_totals_raw: [], skills_header_seen?: true}, _ruleset),
    do: add_problem(struct, {:empty_skill_totals})

  defp put_skill_totals(struct, %{skill_totals_raw: lines}, ruleset) do
    dictionary = skill_dictionary(ruleset)

    {totals, problems} =
      lines
      |> Enum.join(", ")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map_reduce([], fn segment, problems ->
        case Regex.run(~r/^(.+?)\s+(\d+)$/u, segment) do
          [_, name, ranks] ->
            skill = Map.get(dictionary, normalize(name))
            entry = %{skill: skill, name: String.trim(name), ranks: to_int(ranks)}
            problems = if skill, do: problems, else: problems ++ [{:unresolved_skill_total, name}]
            {entry, problems}

          _ ->
            {%{skill: nil, name: segment, ranks: nil},
             problems ++ [{:unparsed_skill_total, segment}]}
        end
      end)

    struct |> Map.put(:skills_with_ranks, totals) |> add_problems(problems)
  end

  # -------------------------------------------------------------- the ladder --

  defp put_levels(struct, %{level_entries: []}, _ruleset),
    do: add_problem(struct, {:missing_field, :levels})

  defp put_levels(struct, %{level_entries: raw_entries}, ruleset) do
    class_table = class_dictionary(ruleset)
    feat_dictionary = feat_dictionary(ruleset)
    skill_dictionary = skill_dictionary(ruleset)

    {levels, problems} =
      Enum.map_reduce(raw_entries, [], fn raw, problems ->
        resolve_level(raw, class_table, feat_dictionary, skill_dictionary, problems)
      end)

    struct |> Map.put(:levels, levels) |> add_problems(problems)
  end

  defp resolve_level(raw, class_table, feat_dictionary, skill_dictionary, problems) do
    {class, problems} = resolve_class(raw.class_raw, class_table, raw.level, problems)
    {ability_increase, problems} = resolve_ability_increase(raw.ability_raw, raw.level, problems)
    {feats, problems} = resolve_feats(raw.feats_raw, feat_dictionary, raw.level, problems)

    {skills, problems} =
      resolve_skill_deltas(raw.skills_raw, skill_dictionary, raw.level, problems)

    entry = %{
      level: raw.level,
      class: class,
      class_raw: raw.class_raw,
      ability_increase: ability_increase,
      feats: feats,
      skills: skills
    }

    {entry, problems}
  end

  defp resolve_class(class_raw, class_table, level, problems) do
    case Map.get(class_table, normalize(class_raw)) do
      nil -> {nil, problems ++ [{:unresolved_class, level, class_raw}]}
      id -> {id, problems}
    end
  end

  defp resolve_ability_increase(nil, _level, problems), do: {nil, problems}

  defp resolve_ability_increase({amount, label}, level, problems) do
    ability = Map.get(@ability_codes, String.downcase(label))

    problems =
      if ability, do: problems, else: problems ++ [{:unresolved_ability_increase, level, label}]

    problems =
      if amount == 1,
        do: problems,
        else: problems ++ [{:unexpected_ability_increase_amount, level, amount}]

    {%{ability: ability, raw: label, amount: amount}, problems}
  end

  defp resolve_feats(nil, _dictionary, _level, problems), do: {[], problems}

  defp resolve_feats(text, dictionary, level, problems) do
    entries =
      text
      |> normalize()
      |> String.replace(~r/\s+/u, " ")
      |> FeatListTokenizer.tokenize(dictionary)
      |> Enum.map(&classify_feat_entry/1)

    unresolved = for %{kind: :unknown, raw: raw} <- entries, do: {:unresolved_feat, level, raw}
    {entries, problems ++ unresolved}
  end

  # A dictionary hit whose value already names the argument — the element
  # folded into which alias matched (`feat_spelling_aliases/0`'s "Energy
  # resistance, <type>" and "Resist <type> energy" keys) rather than
  # trailing the match in parentheses the way `read_argument/1` would read
  # one. Whatever the tokenizer captured after the key (`entry.argument`,
  # ordinarily `nil` here — there is nothing left to capture) is overwritten,
  # never merged with: the value is fully determined by which key matched,
  # so there is nothing to reconcile.
  defp classify_feat_entry(%{value: {:feat, id, argument}} = entry),
    do: to_feat_entry(%{entry | argument: argument}, :feat, id)

  defp classify_feat_entry(%{value: {:feat, id}} = entry), do: to_feat_entry(entry, :feat, id)

  defp classify_feat_entry(%{value: {:special, tag}} = entry),
    do: to_feat_entry(entry, :special, tag)

  defp classify_feat_entry(%{value: nil} = entry) do
    case Regex.run(~r/^([\p{L}]+) domain powers$/u, entry.raw) do
      [_, domain] -> to_feat_entry(entry, :special, {:domain_powers, String.capitalize(domain)})
      _ -> to_feat_entry(entry, :unknown, nil)
    end
  end

  defp to_feat_entry(entry, kind, id) do
    %{kind: kind, id: id, raw: entry.raw, argument: entry.argument, rank: entry.rank}
  end

  # `Discipline +5, Heal +1` — unlike `FEATS:`, no name here contains a comma
  # (checked against every skill in `priv/rules/*/skills.json`), so a plain
  # comma split is safe and the longest-match machinery `FeatListTokenizer`
  # exists for would be unneeded weight.
  defp resolve_skill_deltas(nil, _dictionary, _level, problems), do: {[], problems}

  defp resolve_skill_deltas(text, dictionary, level, problems) do
    entries =
      text
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn segment ->
        case Regex.run(~r/^(.+?)\s+\+(\d+)$/u, segment) do
          [_, name, delta] ->
            %{skill: Map.get(dictionary, normalize(name)), name: name, delta: to_int(delta)}

          _ ->
            %{skill: nil, name: segment, delta: nil}
        end
      end)

    unresolved =
      for %{skill: nil, name: name} <- entries, do: {:unresolved_skill_delta, level, name}

    {entries, problems ++ unresolved}
  end

  # ---------------------------------------------------------------- checksum --

  @doc """
  Compares the header's per-class tally against the ladder actually read.

  Returns `:ok` or the list of disagreements — never corrects one side from
  the other (see the moduledoc). Called by `parse/2`, exposed on its own so a
  caller can re-check after editing a parsed log by hand.
  """
  @spec checksum(t()) :: :ok | {:mismatch, [problem()]}
  def checksum(%__MODULE__{} = struct) do
    header_counts =
      for %{class: id, count: count} when not is_nil(id) <- struct.header_classes,
          into: %{},
          do: {id, count}

    body_counts =
      Enum.reduce(struct.levels, %{}, fn
        %{class: nil}, acc -> acc
        %{class: id}, acc -> Map.update(acc, id, 1, &(&1 + 1))
      end)

    ids = (Map.keys(header_counts) ++ Map.keys(body_counts)) |> Enum.uniq()

    mismatches =
      for id <- ids,
          header = Map.get(header_counts, id),
          body = Map.get(body_counts, id, 0),
          not is_nil(header),
          header != body,
          do: {:header_body_mismatch, id, header, body}

    extra =
      for id <- Map.keys(body_counts) -- Map.keys(header_counts),
          do: {:class_missing_from_header, id, Map.fetch!(body_counts, id)}

    case mismatches ++ extra do
      [] -> :ok
      problems -> {:mismatch, problems}
    end
  end

  defp put_checksum_problems(struct) do
    case checksum(struct) do
      :ok -> struct
      {:mismatch, problems} -> add_problems(struct, problems)
    end
  end

  @doc """
  Level-sequence anomalies: gaps and repeats in `levels[].level`.

  A real dump should read `1, 2, 3, …` with no exceptions — this exists to
  say so loudly if a future one does not, rather than let `levels` quietly
  become misleading. Order itself (CLAUDE.md §3: order decides base attack and
  saves past character level 20) is never touched by this or anything else in
  this module — `levels` stays exactly the sequence the text was read in.
  Called by `parse/2` (its findings land in `problems`, same as `checksum/1`'s)
  and exposed on its own so a caller can re-check after editing a parsed log
  by hand.
  """
  @spec level_sequence_problems(t()) :: [problem()]
  def level_sequence_problems(%__MODULE__{levels: levels}) do
    seen = Enum.map(levels, & &1.level)
    expected = if seen == [], do: [], else: 1..length(seen)//1

    gaps =
      for {want, got} <- Enum.zip(expected, seen),
          want != got,
          do: {:level_out_of_sequence, want, got}

    duplicates =
      seen
      |> Enum.frequencies()
      |> Enum.filter(fn {_level, n} -> n > 1 end)
      |> Enum.map(fn {level, _n} -> {:level_duplicate, level} end)

    gaps ++ duplicates
  end

  defp put_level_sequence_problems(struct) do
    add_problems(struct, level_sequence_problems(struct))
  end

  # -------------------------------------------------------------- dictionaries --

  # Feat name → `{:feat, id}`, from the ruleset's own `name` and `ru` fields —
  # the same two sources `WikiBuildPage.feat_dictionary/0` reads, so a feat
  # renamed in the data needs no edit here either. Merged with a handful of
  # spellings this project's own dumps use that the canonical name does not
  # quite match, and with the non-feat "special" tokens the moduledoc
  # describes. A name two entries would answer to raises rather than picks
  # one silently — the same rule `WikiBuildPage` applies, now shared code.
  #
  # ⚠️ One shape of "the client's own name is not the wiki's" gets a general
  # rule instead of another one-off alias, `feat_key_variants/1` below. Some
  # feat names carry the wiki's own "(feat)" disambiguation suffix — it tells
  # a class ability apart from a same-named SPELL on Fandom (CLAUDE.md §9's
  # own assassin/blackguard pattern), eighteen feats today
  # (`remove_disease_feat`, `dual_wield_feat`, `animate_dead_feat`,
  # `animal_companion_feat` and fourteen more, mostly copies of an
  # Assassin/Blackguard/Pale Master spell-like ability) — and nobody typing
  # their own `.билд` build reproduces a *wiki* disambiguation suffix. Three
  # real dumps found this one feat at a time (`dual_wield_feat`,
  # `animate_dead_feat`, `animal_companion_feat`, each patched in below as
  # its own alias) before a sixth log's own "Remove Disease" (task 3.119,
  # 27.08.2026) made the shape plain: it was never three separate findings,
  # only one, and the other fourteen feats were simply waiting for their own
  # log. Safe as a blanket rule because no feat's own name — suffixed or
  # not — already answers to the stripped key (checked by hand against all
  # eighteen, task 3.119's own commit), and the collision guard above still
  # raises if that ever stops being true. The three one-off aliases this
  # replaced are gone from `feat_spelling_aliases/0` below on purpose —
  # keeping them too would leave two records of the same rule, agreeing by
  # coincidence rather than by construction (CLAUDE.md §9's own "two records
  # of one rule" trap, task 3.85).
  defp feat_dictionary(ruleset) do
    named =
      for {id, feat} <- ruleset.feats,
          name <- [feat.name, feat.ru],
          is_binary(name),
          key <- feat_key_variants(name),
          reduce: %{} do
        acc ->
          case acc do
            %{^key => {:feat, ^id}} ->
              acc

            %{^key => other} ->
              raise "two entries answer to #{inspect(key)}: #{inspect(other)}, #{id}"

            _ ->
              Map.put(acc, key, {:feat, id})
          end
      end

    named
    |> Map.merge(feat_spelling_aliases())
    |> Map.merge(favored_enemy_aliases(ruleset))
    |> Map.merge(special_tokens(ruleset))
    |> FeatListTokenizer.dictionary()
  end

  @feat_wiki_suffix " (feat)"

  # A name's own normalised key alone, or — when the name carries the wiki's
  # "(feat)" disambiguation suffix — that key AND the same key with the
  # suffix stripped. See `feat_dictionary/1`'s own note just above for why
  # this is a rule rather than an alias typed out per feat.
  defp feat_key_variants(name) do
    key = normalize(name)

    if String.ends_with?(key, @feat_wiki_suffix) do
      [key, String.trim_trailing(key, @feat_wiki_suffix)]
    else
      [key]
    end
  end

  # "Blind-Fight" is hnyupius.log's own spelling of "Blind fight", hyphenated
  # the same way `WikiBuildPage`'s own alias table records six wiki pages
  # doing it.
  #
  # "Energy resistance, <type>" (hnyupius.log, level 39: "Energy Resistance,
  # Fire I") is not a new finding — it is the exact alias
  # `WikiBuildPage.feat_aliases/0` already carries for the same reason: the
  # community (wiki build-page authors and, now, the client's own `.билд`
  # dump) drops "Epic" off the shard's actual name "Epic energy resistance"
  # when naming the feat. All five elemental types are listed, because the
  # underlying page is the same one `WikiBuildPage` already cites (`Epic
  # energy resistance`, five icon captions) — this is the closed set that
  # page already established, not a guess at what the other four would look
  # like.
  #
  # ⚠️ Each of these five, and the five "Resist <type> energy" ones below, is
  # a TRIPLE — `{:feat, id, element}` — not the bare pair every other alias
  # here is. Task 3.118 (27.08.2026): before this, the element was baked into
  # *which* key matched and nowhere `classify_feat_entry/1` could carry it
  # forward, so `hnyupius.log`'s own "Energy Resistance, Fire I" read with
  # `argument: nil` and `GameLogImport` reported a choice the text plainly
  # states as unreadable. The fix stays inside the dictionary on purpose —
  # `GameLogImport`'s own moduledoc explains why recovering it downstream, by
  # re-reading `raw`, would have been the wrong move (guessing from context
  # instead of the dictionary); the dictionary's own value naming the element
  # is not that; it is the ordinary case a matched key carries information,
  # no different in kind from `Weapon focus (Longsword)`'s parenthesis.
  # `classify_feat_entry/1` below is what reads the third element.
  #
  # "Resist <type> energy" (frah_hall.log, level 36: "Resist Sonic Energy",
  # task 3.118) is the same element-in-the-name shape one word position over:
  # the canonical name is "Resist energy" and the element sits in the
  # *middle* of the client's own phrasing rather than after a comma, so
  # neither of the two existing forms (comma-suffix above, a parenthesised
  # argument) matches it. Same closed set of five, same feat page
  # (`fandom:Resist energy`, already cited above), same triple-value
  # mechanism.
  #
  # "Damage reduction 1".."4" (babuka.log, task 3.116, levels 11/15/18/25) is
  # the same shape of mismatch again, an arabic digit this time rather than a
  # "(feat)" suffix: the ruleset's own name is "Damage reduction (barbarian)"
  # — a wiki disambiguation suffix nobody typing a `.билд` dump reproduces —
  # while the client instead numbers the four grants 1 through 4. Four fixed
  # keys, not a general "strip a trailing digit" rule, for the same reason
  # `@header_class_abbreviations` stays a closed table: `dwarven_defender_
  # damage_reduction` and `epic_barbarian_damage_reduction` are two *other*
  # feats one word away ("Dwarven Defender Damage Reduction",
  # "Epic Barbarian Damage Reduction" — both attested, hnyupius.log level 15
  # and babuka.log level 28), and both keep resolving on their own full name
  # untouched — the tokenizer's longest-match-at-this-position rule means a
  # short "damage reduction …" key is never even tried where the text starts
  # with "dwarven defender" or "epic barbarian" instead. Levels checked
  # against `ruleset.classes.barbarian.granted_feats` by hand (task 3.116):
  # `damage_reduction_barbarian` is granted at the barbarian's own class
  # levels 11/14/17/20, which land on babuka's character levels 11/15/18/25
  # exactly (level 13 is a Fighter level taken in between) — so all four
  # readings are the class handing the feat over for free, never a slot pick,
  # confirmed by `GameLogImport`'s own tests below.
  #
  # "Greater rage" (babuka.log, levels 16/17/25, with and without a trailing
  # "(Nx per day)" argument) is a redirect, not a second feat — `Barbarian
  # rage.wikitext` (revid 71367) opens with `{{redirect|Greater rage|…}}`, and
  # the ruleset carries no `greater_rage` id at all (checked: no feat file in
  # either ruleset defines one). One key covers all three log spellings
  # because the "(Nx per day)" part is never part of the dictionary key to
  # begin with — it is `read_argument/1`'s job, the same parenthesised-suffix
  # reading `Weapon focus (Longsword)` already goes through.
  defp feat_spelling_aliases do
    %{
      "blind-fight" => {:feat, :blind_fight},
      "energy resistance, acid" => {:feat, :epic_energy_resistance, "acid"},
      "energy resistance, cold" => {:feat, :epic_energy_resistance, "cold"},
      "energy resistance, electrical" => {:feat, :epic_energy_resistance, "electrical"},
      "energy resistance, fire" => {:feat, :epic_energy_resistance, "fire"},
      "energy resistance, sonic" => {:feat, :epic_energy_resistance, "sonic"},
      "resist acid energy" => {:feat, :resist_energy, "acid"},
      "resist cold energy" => {:feat, :resist_energy, "cold"},
      "resist electrical energy" => {:feat, :resist_energy, "electrical"},
      "resist fire energy" => {:feat, :resist_energy, "fire"},
      "resist sonic energy" => {:feat, :resist_energy, "sonic"},
      "damage reduction 1" => {:feat, :damage_reduction_barbarian},
      "damage reduction 2" => {:feat, :damage_reduction_barbarian},
      "damage reduction 3" => {:feat, :damage_reduction_barbarian},
      "damage reduction 4" => {:feat, :damage_reduction_barbarian},
      "greater rage" => {:feat, :barbarian_rage}
    }
  end

  # "Favored Enemy: Elementals" / "Favored Enemy: Giants" (aley.log, levels
  # 8/10, task 3.121) is a FOURTH shape of "the argument is glued onto the
  # name differently than a parenthesis" — a colon this time, after the comma
  # (`energy resistance, fire`) and the argument sitting inside the name
  # (`resist sonic energy`), both task 3.118 just above. `Favored enemy` is
  # the one feat in either ruleset whose domain is `creature_type`
  # (`creature_types_test.exs`, "favored enemy chooses a creature type"), and
  # every key here is GENERATED off that domain's own 25 entries rather than
  # typed out one creature at a time — the same discipline
  # `class_epic_spellings/1` below already applies to a class's own name.
  #
  # ⚠️ The log writes the value in the PLURAL ("Elementals", "Giants") and the
  # domain's own names are singular ("Elemental", "Giant"). Stripping a
  # trailing "s" off arbitrary INPUT text would be exactly the blind rule
  # CLAUDE.md forbids — some day a creature type's own name could end in one
  # and lose a letter that belongs to it. This does the safe half of the same
  # idea instead: both the bare name and name + "s" are generated as keys
  # against the CLOSED 25-entry list the domain already states, and the
  # `case` below raises if that naive pluralisation ever makes two DIFFERENT
  # creature types answer to the same key. Checked against all 25 by that
  # guard on every load — zero collisions today (task 3.121).
  #
  # ⚠️ Not gated by the feat's own `favored_enemy: true/false` flag
  # (`creature_types.json`'s per-feat gate, `ooze` the one exception) — the
  # same choice `BuildCalculatorWeb.Builder.ChoiceIndex.build/1` already makes
  # for every other reader of this text. A value the gate would refuse is
  # still resolved here and refused later, at placement
  # (`Rules.FeatChoices.reasons/3`'s own `invalid_choice`), not silently
  # swallowed while merely being read off the page.
  defp favored_enemy_aliases(ruleset) do
    case Map.get(ruleset.choice_domains || %{}, :creature_type) do
      %{values: %MapSet{} = values, names: %{} = names} ->
        for value <- values,
            name = Map.get(names, value),
            is_binary(name),
            key <- [normalize(name), normalize(name) <> "s"],
            reduce: %{} do
          acc ->
            full_key = "favored enemy: " <> key
            entry = {:feat, :favored_enemy, Atom.to_string(value)}

            case acc do
              %{^full_key => ^entry} ->
                acc

              %{^full_key => other} ->
                raise "favored_enemy_aliases: naive \"+s\" pluralisation makes both " <>
                        "#{inspect(other)} and #{inspect(entry)} answer to " <>
                        "#{inspect(full_key)} — a real resolver is needed for these two, " <>
                        "not a generated alias"

              _ ->
                Map.put(acc, full_key, entry)
            end
        end

      _no_dictionary ->
        %{}
    end
  end

  # The fixed non-feat tokens the moduledoc names, plus one generated per
  # class. «Дух Сиалы» is read off `ruleset.innate_hp_bonus.ru` rather than
  # typed out again, so a future rename of the shard's own wording cannot
  # drift the two apart. "Epic Character" has no ruleset counterpart at all —
  # CLAUDE.md's epic rules put the character-level-21 threshold in
  # `ruleset.epic`, not in a feat, and this token is the engine announcing
  # that the same threshold has been crossed, nothing more. "Epic
  # <ClassName>" is the same announcement for one class's own epic threshold
  # (21 levels for a base class, 11 for a prestige one) and is generated
  # from `ruleset.classes` rather than typed per class, so a class this
  # project has not seen the marker for yet is still covered.
  defp special_tokens(ruleset) do
    base = %{"epic character" => {:special, :character_epic}}

    base =
      case ruleset.innate_hp_bonus do
        %{ru: ru} when is_binary(ru) -> Map.put(base, normalize(ru), {:special, :innate_hp_bonus})
        _ -> base
      end

    Enum.reduce(ruleset.classes, base, fn {id, class}, acc ->
      [class.name, class.ru]
      |> Enum.filter(&is_binary/1)
      |> Enum.flat_map(&class_epic_spellings/1)
      |> Enum.reduce(acc, fn spelling, acc2 ->
        Map.put(acc2, spelling, {:special, {:class_epic, id}})
      end)
    end)
  end

  # Observed spelling twice, disagreeing with each other: "Epic Palemaster"
  # (brunna.log — the space inside "Pale master" is dropped) against "Epic
  # Dwarven Defender" (hnyupius.log — the space inside "Dwarven defender" is
  # kept). Both variants are generated from the one name so a class the
  # fixtures have not exercised this way yet is still covered either way.
  defp class_epic_spellings(name) do
    plain = normalize("epic " <> name)
    tight = normalize("epic " <> String.replace(name, " ", ""))
    Enum.uniq([plain, tight])
  end

  # Class name → id, off `name` alone: the ladder always writes English
  # (`FIGHTER`, `DWARVEN DEFENDER`), never the shard's Russian class titles —
  # unlike a feat name, a class name on this format is never freeform enough
  # to need an alias table.
  defp class_dictionary(ruleset) do
    for {id, class} <- ruleset.classes,
        is_binary(class.name),
        into: %{},
        do: {normalize(class.name), id}
  end

  # Skill name → id, off `name`, plus the two spellings the fixtures use that
  # do not match the canonical name literally: "Heal" for the ruleset's "Heal
  # (skill)" (disambiguated from the Heal *spell* the same way Fandom
  # disambiguates it, CLAUDE.md §9) and "UMD" for "Use magic device" — the
  # client's own abbreviation, printed as such in `moxie.log`'s
  # `SKILLS WITH RANKS` block.
  defp skill_dictionary(ruleset) do
    named =
      for {id, skill} <- ruleset.skills,
          is_binary(skill.name),
          into: %{},
          do: {normalize(skill.name), id}

    Map.merge(named, %{"heal" => :heal_skill, "umd" => :use_magic_device})
  end

  # ------------------------------------------------------------------- utils --

  defp normalize(text), do: text |> String.trim() |> String.downcase() |> String.replace("ё", "е")

  defp to_int(string), do: String.to_integer(string)

  defp add_problem(struct, problem), do: %{struct | problems: struct.problems ++ [problem]}
  defp add_problems(struct, problems), do: %{struct | problems: struct.problems ++ problems}
end
