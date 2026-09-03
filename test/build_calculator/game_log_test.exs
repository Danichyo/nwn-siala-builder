defmodule BuildCalculator.GameLogTest do
  @moduledoc """
  Task 3.111, pass one: does `.билд` read completely and honestly.

  ## The sixteen fixtures (`test/fixtures/game_logs/`, Dan, 26.08–03.09.2026)

    * `brunna.log` — Gnome, Wizard 10 / Pale Master 30. Colon inside a feat
      name (`Epic Spell: Dragon Knight`), a "(feat)"-suffixed ruleset name
      the log spells without the suffix (`Animate dead`).
    * `hnyupius.log` — Gnome, Fighter 10 / Dwarven Defender 23 / Weapon
      Master 7. The comma-in-a-name trap (`Energy Resistance, Fire I`), a
      Russian custom feat name, stage markers in parentheses
      (`Defensive Awareness (1)`), and — the load-bearing one — Fighter's
      *tenth* level printed as `LEVEL 21: FIGHTER`, taken well into the
      epics after ten Dwarven Defender levels and one of Weapon Master.
    * `moxie.log` — Elf, Monk 4 / Cleric 35 / Rogue 1 / Ranger 1. The shard's
      41-level cap and its four-class limit both exercised at once, plus
      cleric domain grants (`War Domain Powers`) that are not feats at all.
    * `babuka.log` (task 3.116) — Half-Orc, Barbarian 35 / Fighter 1 / Weapon
      Master 5. A header abbreviation none of the first three used (`BARB`),
      an ability-score bump that lands on two different abilities instead of
      one (`+1 STR` ×8, then `+1 CON` ×2 past level 35), and three more
      shapes of the same "client's own name for a repeated class ability
      does not match the wiki's" mismatch the first three fixtures did not
      happen to exercise: an arabic-numbered stage (`Damage Reduction 1`..
      `4`, unlike `hnyupius.log`'s own roman-numeralled
      `Great strength I`..`VII`), a wiki redirect target printed as if it
      were its own feat (`Greater Rage`, never `Barbarian rage`), and a
      trailing `+` after a roman numeral (`Uncanny Dodge VI+`) that
      `read_rank/1` did not accept before this task.
    * `frah_hall.log` (task 3.118) — Human, Sorcerer 32 / Wizard 3 / Druid 4 /
      Bard 2. The first pure-caster build among the fixtures (every class
      taken casts, unlike `moxie.log`'s Monk/Rogue/Ranger dip alongside its
      Cleric). Three more header spellings — `SORC`, `DRU`, and `Bard`
      itself, the class's own FULL name rather than a code, since the
      header apparently only abbreviates when it bothers to — a
      "(feat)"-suffixed grant spelled without the suffix again (`Animal
      companion`, druid's own first level), an element folded *inside* a
      feat's own name rather than after a comma or in parentheses (`Resist
      Sonic Energy`), and two takes of `Epic energy resistance` on the SAME
      element (`Energy Resistance, Fire I` then `…Fire II` — legal per the
      data's own `distinct?: false`, and what finally recovers the element
      `energy resistance, <type>`'s alias used to throw away, see
      `feat_spelling_aliases/0`'s own moduledoc note).
    * `froim.log` (task 3.119) — Halfling, Paladin 13 / Ranger 4 / Rogue 15 /
      Fighter 9. A header abbreviation the first five never used (`PAL`), and
      the fixture that turned the "(feat)"-suffix mismatch from three
      one-off aliases (`dual_wield_feat`, `animate_dead_feat`,
      `animal_companion_feat` — the previous three fixtures, one each) into
      a general rule: `Remove Disease` is the ruleset's own
      `remove_disease_feat`, spelled without its "(feat)" suffix same as the
      other three, and fourteen more feats share the identical shape
      untested until now (`feat_dictionary/1`'s own note). Also the fixture
      `GameLogImportTest` uses to pin that the grant lands on the class's
      own third Paladin level, not a slot.
    * `aley.log` (task 3.121) — Human, Bard 9 / Ranger 2 / Harper Scout 1 /
      Rogue 8, **20 levels** — the first fixture under the cap, proving this
      module never secretly assumed 40 or 41. A header abbreviation none of
      the first six used (`HS`), and a FOURTH way an argument rides along
      with a feat's name: a colon (`Favored Enemy: Elementals`), after a
      parenthesis, a comma (`Energy Resistance, Fire I`) and a word sitting
      inside the name itself (`Resist Sonic Energy`) — see
      `favored_enemy_aliases/1`'s own note. Also the log's own value is
      plural (`Elementals`, `Giants`) where the domain's 25 entries are
      singular (`Elemental`, `Giant`), which is what that function's naive
      "+s" generation and its collision guard are for.
    * `elith.log` (task 3.131) — Half-Elf, Sorcerer 1 / Ranger 10 / Arcane
      Archer 14, **25 levels**. The first fixture built to
      `docs/log_coverage.md`'s own plan rather than sent as an existing
      character's build (its own Build 1) — a header abbreviation none of
      the first seven used (`AA`), Arcane Archer's own class grants across
      all ten of its class levels (`Enchant arrow` I–VII, `Seeker arrow`
      I/II, `Imbue arrow`, `Hail of arrows`, `Arrow of death`), and the
      first fixture whose `SKILLS WITH RANKS:` block is simply absent from
      the text rather than present with entries — read as a legal
      zero-skill-points character, not a missing field, see
      `BuildCalculator.GameLog`'s own `put_skill_totals/3` note.
    * `boido.log` (task 3.131) — Gnome, Fighter 7 / Blackguard 8,
      **15 levels**, `docs/log_coverage.md`'s own Build 2. A header
      abbreviation none of the first eight used (`BG`), the first fixture to
      combine the comma-inside-a-name trap AND a parenthesised argument on
      the same token (`Sneak Attack, Blackguard (+1d6)`), and the first live
      confirmation of five of the fourteen "(feat)"-suffixed feats
      `froim.log`'s own task 3.119 closed only against a synthetic dump
      (`Bull's Strength`, `Create Undead`, `Inflict Serious/Critical
      Wounds`, `Contagion`).
    * `nathan.log` (task 3.131) — Human, Rogue 5 / Assassin 9, **14 levels**,
      `docs/log_coverage.md`'s own Build 3. A header abbreviation none of
      the first nine used (`ASS`), and four more of task 3.119's
      "(feat)"-suffixed names resolving live — the four riskiest of the
      fourteen, each sharing its wiki page with an actual spell of the same
      name (`Ghostly Visage`, `Darkness`, `Invisibility`, `Improved
      Invisibility`).
    * `timonall.log` (task 3.131) — Human, Fighter 8 / Champion of Torm 10,
      **18 levels**, `docs/log_coverage.md`'s own Build 4. A header
      abbreviation none of the first ten used, spelled in MIXED case
      (`CoT`, not `COT`) — the lookup is already case-insensitive, so this
      needed no code change — and a second, independent fixture whose
      `SKILLS WITH RANKS:` block is simply absent (see `elith.log` above).
      Also the first fixture built with no gear at all, which let
      `GameLogImportTest` cross-check this project's own `Rules.compute/2`
      against the log's own printed `COMBAT STATS` exactly, five numbers for
      five, and turned up a point-buy finding along the way (see that file's
      own describe block).
    * `trina.log` (task 3.131) — Human, Fighter 5 / Purple Dragon Knight 10,
      **15 levels**, `docs/log_coverage.md`'s own Build 5. A header
      abbreviation none of the first eleven used (`PDK`), Purple Dragon
      Knight's own class grants across all ten of its class levels, a
      second live derived-stats match (`GameLogImportTest` again), and a
      live confirmation that all ten of this prestige class's levels count
      toward base attack and saves — the exact place task 3.96 once found a
      five-row vanilla progression table sitting under a ten-level cap.
    * `hela.log` (task 3.131) — Human, Fighter 2 / Sorcerer 7 / Red Dragon
      Disciple 10, **19 levels**, `docs/log_coverage.md`'s own Build 6. A
      header abbreviation none of the first twelve used (`RDD`), and Red
      Dragon Disciple's own growing hit die (`Hit Die Increase` — `d6`/`d8`/
      `d10` at its own class levels 1/4/6) read correctly all three times,
      even though `ruleset.classes.red_dragon_disciple.granted_feats` only
      names the feat at ONE of the three levels — the resulting gap is
      `GameLogImportTest`'s own to pin, not this module's (its job stops at
      reading the text, `GameLog`'s own moduledoc, "Trap 3"). Sent as part of
      a different, concurrent task's own measurement (CLAUDE.md §3, "Что на
      самом деле печатает `(WHITE) ABILITIES`") before landing here as a
      fixture too.
    * `nicha.log` (task 3.131) — Human, Rogue 10 / Bard 2 / Shadowdancer 12,
      **24 levels**, `docs/log_coverage.md`'s own Build 7. A header
      abbreviation none of the first thirteen used (`SD`), and a live
      confirmation of the Sialan shift CLAUDE.md §3 already documents from
      the wiki alone: `Hide in Plain Sight` prints on Shadowdancer's own 4th
      class level (character level 12), not the 1st — the dip-in-one-level
      build the vanilla version would allow is dead on this shard, now shown
      by the engine itself rather than just read off a page.
    * `hana.log` (task 3.131) — Human, Druid 6 / Shifter 10, **16 levels**,
      `docs/log_coverage.md`'s own Build 8, the plan's last. A header
      abbreviation none of the first fourteen used (`SHIF`), and two
      DIFFERENT schemes for a roman numeral riding on a name, on
      neighbouring lines of the same dump: `Greater Wildshape I` carries its
      numeral as PART OF THE ID (`greater_wildshape_i`, a separate id per
      stage, distinct from `greater_wildshape_ii`/`_iv`), while `Infinite
      Greater Wildshape I` carries the identical-looking numeral as a
      `rank` on ONE shared id (`infinite_greater_wildshape`) — both read
      correctly, and neither reading was guessed from the other. A third,
      independent fixture whose `SKILLS WITH RANKS:` block is simply absent
      (after `elith.log` and `timonall.log`).
    * `hnyupius_alignment.log` (task 3.173, 03.09.2026) — the SAME character
      as `hnyupius.log` above, re-pulled after the shard started printing a
      sixteenth line, `ALIGNMENT:`, right under `RACE:`. Not a new build:
      the ladder, feats and skill deltas are byte-for-byte the same as the
      original dump (only the header timestamp, `CURRENT ABILITIES`/
      `COMBAT STATS` — the character re-geared between the two dumps — and
      the new line differ), which is exactly why keeping BOTH fixtures
      matters: `hnyupius.log` stays the regression pinning that a dump
      without this line still reads exactly as it always did, and this one
      is the only fixture proving the line itself reads at all. See
      `GameLog.put_alignment/2`'s own note for why an absent line is not
      `{:missing_field, …}` the way an absent race is.

  Every level, feat, skill and ability-block number asserted below was
  cross-checked by hand against the raw fixture text (not against anything
  the parser itself produced) before being written down here — the same
  discipline `wiki_builds_test.exs` applies to its own fixtures.

  ## What is deliberately not asserted

  Dan sent a build he assembled by hand in this project's own constructor for
  `hnyupius.log`'s character, meaning to compare it against this parser's
  output. The comparison was made once, by hand, and is **not** encoded here
  as a test, on Dan's own instruction: the hand-built reference has empty
  gear (so its own `CURRENT ABILITIES` / `COMBAT STATS` would disagree with
  the log's by exactly the gear's contribution, telling us nothing), an
  unrecovered point buy (Dan: guessing the pre-racial scores back out of a
  finished sheet is not worth doing), and at least one epic feat swapped for
  a different one from what the log shows (`Iron will` in the reference
  where the log has `Energy Resistance, Fire I`) — three independent reasons
  the reference is a rough guide, not ground truth. A test built against it
  would have to be bent to pass or would fail on real, expected disagreement;
  either way it would stop testing anything. The one honest ground truth for
  a parser is the text it parses, so every assertion below is checked against
  the `.log` file, never against the hand-built build.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.GameLog

  @ruleset BuildCalculator.Data.ruleset!()

  defp fixture(name) do
    "../fixtures/game_logs/#{name}.log" |> Path.expand(__DIR__) |> File.read!()
  end

  defp parsed(name), do: GameLog.parse(fixture(name), @ruleset)

  # A minimal well-formed dump, hand-built rather than a real fixture —
  # exercised both by the "corrupted input" describe block far below (each
  # test there breaks one piece of it) and by task 3.119's own header/collision
  # tests above the moxie block, which need a tiny dump rather than one of the
  # six real 40-41-level ones. Declared here, ahead of every describe block
  # that reads it — a module attribute must exist before its first use in
  # the file, and this one is now used well before the "corrupted input"
  # block it originally lived next to.
  @minimal """
  [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] Command detected: .билд
  ------------------------------------------------
      CHARACTER BUILD: Тест
      Current: 3 FTR
  ------------------------------------------------

  CURRENT ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
  COMBAT STATS: AB 3 AC 12 Fort 5 Refl 1 Will 1
  SKILLS WITH RANKS:
    Discipline 6

  (WHITE) ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
  RACE: Human

  ------------------------------------------------
  LEVEL 1: FIGHTER
    FEATS: Toughness, Dodge
  ------------------------------------------------
  LEVEL 2: FIGHTER
    SKILLS: Discipline +1
  ------------------------------------------------
  LEVEL 3: FIGHTER
    FEATS: Mobility
    SKILLS: Discipline +1
  ------------------------------------------------

  [CHAT WINDOW TEXT] [Wed Aug 26 00:00:00] Build sent to! Тест
  """

  # ---------------------------------------------------------- all seven read --

  describe "reads all sixteen fixtures completely" do
    # `increase_by_ability` is a frequency map rather than a single atom —
    # brunna/hnyupius/moxie each happen to dump all ten `+1`s on one ability
    # (a single-classed stat dump, CLAUDE.md's Toughness /
    # `ability_increases` pattern); every other fixture splits its bumps
    # across two or more abilities instead, in its own pattern. A frequency
    # map states the exact split for all sixteen rather than special-casing
    # the ones that differ.
    #
    # ⚠️ The total is `div(levels, 4)`, not a bare `10` — true for the six
    # 40/41-level fixtures (`div(40, 4) == div(41, 4) == 10`, and
    # `hnyupius_alignment.log` is a seventh: same 40 levels as `hnyupius.log`)
    # but NOT for any of the nine shorter ones sent from `aley.log` on:
    # `div/2` on the fixture's own level count is the only formula that
    # holds for all sixteen.
    for {name, levels, race, header, total_feats, total_skill_deltas, increase_by_ability} <- [
          {"brunna", 40, :dwarf, [{"WIZ", 10, :wizard}, {"PM", 30, :pale_master}], 47, 110,
           %{int: 10}},
          {"hnyupius", 40, :dwarf,
           [{"FTR", 10, :fighter}, {"DD", 23, :dwarven_defender}, {"WM", 7, :weapon_master}], 50,
           62, %{str: 10}},
          {"moxie", 41, :elf,
           [{"MNK", 4, :monk}, {"CLR", 35, :cleric}, {"ROG", 1, :rogue}, {"RNG", 1, :ranger}], 50,
           10, %{wis: 10}},
          {"babuka", 41, :half_orc,
           [{"BARB", 35, :barbarian}, {"FTR", 1, :fighter}, {"WM", 5, :weapon_master}], 51, 29,
           %{str: 8, con: 2}},
          {"frah_hall", 41, :human,
           [{"SORC", 32, :sorcerer}, {"WIZ", 3, :wizard}, {"DRU", 4, :druid}, {"Bard", 2, :bard}],
           36, 2, %{int: 5, con: 1, wis: 1, cha: 3}},
          {"froim", 41, :halfling,
           [
             {"PAL", 13, :paladin},
             {"RNG", 4, :ranger},
             {"ROG", 15, :rogue},
             {"FTR", 9, :fighter}
           ], 55, 26, %{dex: 3, wis: 4, int: 1, con: 1, cha: 1}},
          {"aley", 20, :human,
           [
             {"Bard", 9, :bard},
             {"RNG", 2, :ranger},
             {"HS", 1, :harper_scout},
             {"ROG", 8, :rogue}
           ], 35, 32, %{wis: 2, int: 3}},
          {"elith", 25, :half_elf,
           [{"SORC", 1, :sorcerer}, {"RNG", 10, :ranger}, {"AA", 14, :arcane_archer}], 41, 0,
           %{wis: 3, cha: 3}},
          {"boido", 15, :gnome, [{"FTR", 7, :fighter}, {"BG", 8, :blackguard}], 37, 1,
           %{wis: 1, cha: 2}},
          {"nathan", 14, :human, [{"ROG", 5, :rogue}, {"ASS", 9, :assassin}], 28, 2,
           %{con: 1, wis: 1, cha: 1}},
          {"timonall", 18, :human, [{"FTR", 8, :fighter}, {"CoT", 10, :champion_of_torm}], 28, 0,
           %{int: 2, cha: 2}},
          {"trina", 15, :human, [{"FTR", 5, :fighter}, {"PDK", 10, :purple_dragon_knight}], 24, 4,
           %{int: 1, wis: 1, cha: 1}},
          {"hela", 19, :human,
           [{"FTR", 2, :fighter}, {"SORC", 7, :sorcerer}, {"RDD", 10, :red_dragon_disciple}], 28,
           1, %{wis: 4}},
          {"nicha", 24, :human,
           [{"ROG", 10, :rogue}, {"Bard", 2, :bard}, {"SD", 12, :shadowdancer}], 36, 5,
           %{wis: 5, cha: 1}},
          {"hana", 16, :human, [{"DRU", 6, :druid}, {"SHIF", 10, :shifter}], 28, 0,
           %{int: 1, con: 1, cha: 2}},
          {"hnyupius_alignment", 40, :dwarf,
           [{"FTR", 10, :fighter}, {"DD", 23, :dwarven_defender}, {"WM", 7, :weapon_master}], 50,
           62, %{str: 10}}
        ] do
      test "#{name}.log — nothing left unrecognised, header matches the ladder" do
        result = parsed(unquote(name))

        # The whole point of the parser: never lose a line silently. All
        # sixteen real dumps happen to read cleanly, which is itself worth
        # pinning — the corrupted-input describe block below covers the
        # paths this can't exercise.
        assert result.problems == []

        assert result.race == unquote(race)
        assert length(result.levels) == unquote(levels)

        assert Enum.map(result.header_classes, &{&1.raw, &1.count, &1.class}) ==
                 unquote(Macro.escape(header))

        assert GameLog.checksum(result) == :ok
        assert GameLog.level_sequence_problems(result) == []

        # Every level was read in order 1..N with no reindexing — the
        # invariant `checksum/1` cannot see on its own, since it only tallies
        # classes, never level numbers or order.
        assert Enum.map(result.levels, & &1.level) == Enum.to_list(1..unquote(levels))

        feats = Enum.flat_map(result.levels, & &1.feats)
        assert length(feats) == unquote(total_feats)
        assert Enum.all?(feats, &(&1.kind in [:feat, :special]))

        skill_deltas = Enum.flat_map(result.levels, & &1.skills)
        assert length(skill_deltas) == unquote(total_skill_deltas)
        assert Enum.all?(skill_deltas, &(&1.skill != nil))

        increases = Enum.filter(result.levels, & &1.ability_increase)
        assert length(increases) == div(unquote(levels), 4)

        assert Enum.frequencies(Enum.map(increases, & &1.ability_increase.ability)) ==
                 unquote(Macro.escape(increase_by_ability))

        assert Enum.all?(increases, &(&1.ability_increase.amount == 1))
      end
    end

    test "abilities and combat stats are read as printed — gear-on and gear-off both" do
      brunna = parsed("brunna")

      assert brunna.white_abilities == %{str: 8, dex: 12, con: 18, int: 25, wis: 8, cha: 6}
      assert brunna.current_abilities == %{str: 20, dex: 12, con: 26, int: 47, wis: 8, cha: 6}
      assert brunna.combat_stats == %{ab: 25, ac: 36, fort: 50, refl: 22, will: 28}
    end

    test "the skill totals block resolves multi-word and abbreviated names" do
      moxie = parsed("moxie")

      assert Enum.find(moxie.skills_with_ranks, &(&1.name == "UMD")).skill == :use_magic_device
      assert Enum.find(moxie.skills_with_ranks, &(&1.name == "Discipline")).ranks == 44

      hnyupius = parsed("hnyupius")
      assert Enum.find(hnyupius.skills_with_ranks, &(&1.name == "Heal")).skill == :heal_skill
    end
  end

  # -------------------------------------------------- ALIGNMENT: (task 3.173) --

  describe "ALIGNMENT: — the sixteenth fixture's own line, task 3.173" do
    # ✅ Кейс `AL1` ЗАКРЫТ ЗАМЕРОМ Dan 03.09.2026: средний ряд клиент печатает
    # как **`True Neutral`**, слово в слово так же, как называет его
    # `Ids.alignments/0`. Из трёх мыслимых форм (`True Neutral`, голое
    # `Neutral`, склейка осей `Neutral Neutral` — движок хранит мировоззрение
    # ДВУМЯ числами, `LawfulChaotic`/`GoodEvil`, так что склейка была реальной
    # возможностью) сбылась та, что уже была в словаре.
    #
    # Замерен ОДИН центр, а проверяются здесь все девять — и это не растяжение
    # замера: восемь остальных двусловны по осям (`Lawful Good`, `Chaotic
    # Evil`), другой формы у них не бывает, а единственное неоднозначное имя
    # и есть измеренный центр. Тест сторожит нашу СТОРОНУ договора: словарь
    # и парсер обязаны сходиться на всех девяти, иначе имя, которое шард
    # однажды напечатает, молча не распознается.
    test "все девять имён из Ids.alignments/0 читаются парсером (AL1)" do
      base = File.read!("test/fixtures/game_logs/hnyupius_alignment.log")

      for {id, name} <- BuildCalculator.Ids.alignments() do
        log =
          base
          |> String.replace("ALIGNMENT: Lawful Good", "ALIGNMENT: #{name}")
          |> GameLog.parse(@ruleset)

        assert log.alignment == id, "«#{name}» не прочиталось как #{inspect(id)}"
        assert log.alignment_raw == name
      end
    end

    test "hnyupius_alignment.log resolves Lawful Good, and the old dump stays alignment-free" do
      with_line = parsed("hnyupius_alignment")
      assert with_line.alignment == :lawful_good
      assert with_line.alignment_raw == "Lawful Good"
      assert with_line.problems == []

      # The regression this pair of fixtures exists to pin: the SAME
      # character, read from a dump the shard printed before it started
      # carrying this line, still comes back with alignment simply
      # unknown — not a `problems` entry, not a guess.
      without_line = parsed("hnyupius")
      assert without_line.alignment == nil
      assert without_line.alignment_raw == nil
      assert without_line.problems == []
    end

    test "a value ALIGNMENT: does not recognise is reported, never guessed" do
      bad = String.replace(fixture("hnyupius_alignment"), "Lawful Good", "Something Odd")
      result = GameLog.parse(bad, @ruleset)

      assert {:unresolved_alignment, "Something Odd"} in result.problems
      assert result.alignment == nil
    end

    test "a missing ALIGNMENT: line leaves alignment nil without being reported as missing" do
      # `@minimal` never carried this line — the same shape every fixture
      # sent before 03.09.2026 has. Unlike `RACE:`, an absent alignment line
      # is not `{:missing_field, …}`: see `GameLog.put_alignment/2`'s own
      # note for why race and alignment are not read alike.
      result = GameLog.parse(@minimal, @ruleset)

      assert result.alignment == nil
      assert {:missing_field, :alignment} not in result.problems
      assert result.problems == []
    end
  end

  # ------------------------------------------------------- the order trap --

  describe "hnyupius.log: a class level taken well into the epics" do
    test "LEVEL 21 is Fighter's own 10th level, read in place — not merged, not reordered" do
      levels = parsed("hnyupius").levels

      # Fighter 1-9 (character levels 1-9), ten Dwarven Defender levels and
      # one Weapon Master level come between, then Fighter's 10th at
      # character level 21, then Weapon Master resumes — the header's
      # "10 FTR" only balances because the checksum tallies classes, never
      # character levels or positions. By level number rather than list
      # index, so an off-by-one here cannot go unnoticed.
      by_level = Map.new(levels, &{&1.level, &1.class})
      assert by_level[19] == :dwarven_defender
      assert by_level[20] == :weapon_master
      assert by_level[21] == :fighter
      assert by_level[22] == :weapon_master
      assert Enum.at(levels, 20).level == 21

      fighter_levels = Enum.filter(levels, &(&1.class == :fighter))
      assert length(fighter_levels) == 10
      assert Enum.map(fighter_levels, & &1.level) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 21]
    end

    test "the comma inside \"Energy Resistance, Fire I\" is not read as a separator" do
      level_39 = Enum.find(parsed("hnyupius").levels, &(&1.level == 39))

      # ⚠️ `argument: "fire"`, not `nil` — task 3.118 (27.08.2026) closed the
      # loss `feat_spelling_aliases/0`'s own moduledoc used to name here:
      # this alias now carries the element as part of its own value
      # (`{:feat, :epic_energy_resistance, "fire"}`), so `argument` is no
      # longer thrown away the moment the comma-suffixed key matches.
      assert [
               %{kind: :feat, id: :epic_energy_resistance, argument: "fire", rank: "i"},
               %{kind: :feat, id: :epic_prowess}
             ] = level_39.feats
    end

    test "a stage number in parentheses is kept as an argument, distinct from a chosen weapon" do
      level_11 = Enum.find(parsed("hnyupius").levels, &(&1.level == 11))
      assert [%{id: :defensive_awareness, argument: "1"}] = level_11.feats

      level_4 = Enum.find(parsed("hnyupius").levels, &(&1.level == 4))
      assert [%{id: :weapon_focus, argument: "bastard sword"}] = level_4.feats
    end
  end

  # --------------------------------------------------- the non-feat tokens --

  describe "tokens in a FEATS: line that are not feats" do
    test "«Дух Сиалы» resolves to the innate HP bonus, never to a feat id" do
      level_1 = Enum.find(parsed("hnyupius").levels, &(&1.level == 1))
      assert Enum.any?(level_1.feats, &(&1.kind == :special and &1.id == :innate_hp_bonus))
      refute Enum.any?(level_1.feats, &(&1.kind == :feat and &1.raw =~ "сиалы"))
    end

    test "\"Epic Character\" marks the character crossing level 21, not a feat" do
      level_21 = Enum.find(parsed("brunna").levels, &(&1.level == 21))
      assert Enum.any?(level_21.feats, &(&1.kind == :special and &1.id == :character_epic))
    end

    test "\"Epic <Class>\" marks that class's own epic threshold, with the right class id" do
      # brunna.log: Pale Master's 11th class level lands on character level
      # 21, printing both markers on the same line.
      brunna_21 = Enum.find(parsed("brunna").levels, &(&1.level == 21))
      assert Enum.any?(brunna_21.feats, &(&1.id == {:class_epic, :pale_master}))

      # hnyupius.log: Dwarven Defender's 11th level, spelled with the
      # internal space kept ("Epic Dwarven Defender").
      hnyupius_28 = Enum.find(parsed("hnyupius").levels, &(&1.level == 28))
      assert Enum.any?(hnyupius_28.feats, &(&1.id == {:class_epic, :dwarven_defender}))

      # moxie.log: Cleric's 21st level (a base class, not a prestige one).
      moxie_23 = Enum.find(parsed("moxie").levels, &(&1.level == 23))
      assert Enum.any?(moxie_23.feats, &(&1.id == {:class_epic, :cleric}))

      # elith.log (task 3.131): Arcane Archer's own 11th level lands on
      # character level 22 (Sorcerer 1 + Ranger 10 + Arcane Archer 11), and
      # `ruleset.feats` carries no `epic_arcane_archer` id at all — checked,
      # not assumed, see the standalone describe block below — so there is
      # no real feat this marker could be mistaken for.
      elith_22 = Enum.find(parsed("elith").levels, &(&1.level == 22))
      assert Enum.any?(elith_22.feats, &(&1.id == {:class_epic, :arcane_archer}))
    end

    test "domain grants are recognised as domain powers, not feats or unresolved noise" do
      level_2 = Enum.find(parsed("moxie").levels, &(&1.level == 2))

      assert Enum.any?(level_2.feats, &(&1.id == {:domain_powers, "War"}))
      assert Enum.any?(level_2.feats, &(&1.id == {:domain_powers, "Travel"}))
      assert Enum.all?(level_2.feats, &(&1.kind != :unknown))
    end
  end

  # ---------------- the class-epic marker must never shadow a real feat --

  describe "the \"Epic <Class>\" marker's own keys never collide with a real feat (task 3.131)" do
    # elith.log prints "Epic Arcane Archer" at character level 22 (Arcane
    # Archer's own 11th class level) right next to real feats on the same
    # line, and the task that added this fixture was asked to check a
    # specific claim: that `ruleset.feats` already carries an
    # `epic_arcane_archer` id, making the marker's silent win over a real
    # feat (`special_tokens/1` is merged last in `feat_dictionary/1`, with no
    # collision check against it — unlike the raise `named`'s own
    # construction guards itself with) an accident rather than a decision.
    # The claim does not hold: neither ruleset defines any feat by that id or
    # by the name "Epic arcane archer" (checked below, not eyeballed), so
    # nothing is silently shadowed today. This test is the regression net for
    # that finding — a shard update naming a real feat "Epic <SomeClass>"
    # would make this fail loudly, the same way `favored_enemy_aliases/1`'s
    # own pluralisation guard exists to catch its own kind of silent
    # overwrite before a player ever sees it.
    for ruleset_id <- ["vanilla", "siala_41"] do
      test "no feat's own name collides with a class-epic marker key (#{ruleset_id})" do
        ruleset = BuildCalculator.Data.ruleset!(unquote(ruleset_id))

        refute Map.has_key?(ruleset.feats, :epic_arcane_archer)

        normalize = fn text ->
          text |> String.trim() |> String.downcase() |> String.replace("ё", "е")
        end

        marker_keys =
          for {_id, class} <- ruleset.classes,
              name <- [class.name, class.ru],
              is_binary(name),
              key <- [
                normalize.("epic " <> name),
                normalize.("epic " <> String.replace(name, " ", ""))
              ],
              into: MapSet.new(),
              do: key

        marker_keys = MapSet.put(marker_keys, "epic character")

        colliding_feats =
          for {id, feat} <- ruleset.feats,
              name <- [feat.name, feat.ru],
              is_binary(name),
              MapSet.member?(marker_keys, normalize.(name)),
              do: {id, name}

        assert colliding_feats == []
      end
    end
  end

  # ------------------------- the client's own naming for a repeated grant --

  describe "babuka.log: three more shapes of \"the client's name is not the wiki's\" (task 3.116)" do
    test "the BARB header abbreviation resolves, and the checksum agrees" do
      result = parsed("babuka")
      assert Enum.find(result.header_classes, &(&1.raw == "BARB")).class == :barbarian
      assert GameLog.checksum(result) == :ok
    end

    test "Damage Reduction 1..4 read as damage_reduction_barbarian, digit and all" do
      by_level = Map.new(parsed("babuka").levels, &{&1.level, &1})

      for {level, rank_digit} <- [{11, "1"}, {15, "2"}, {18, "3"}, {25, "4"}] do
        feats = by_level[level].feats

        assert Enum.any?(
                 feats,
                 &(&1.kind == :feat and &1.id == :damage_reduction_barbarian and
                     &1.raw == "damage reduction " <> rank_digit)
               ),
               "level #{level}: expected damage_reduction_barbarian in #{inspect(feats)}"
      end

      # Neighbours one word away must still resolve to their OWN ids — the
      # alias is four fixed keys, not "damage reduction" plus any digit
      # (moduledoc, `feat_spelling_aliases/0`).
      level_28 = by_level[28]
      assert Enum.any?(level_28.feats, &(&1.id == :epic_barbarian_damage_reduction))
      refute Enum.any?(level_28.feats, &(&1.id == :damage_reduction_barbarian))

      hnyupius_15 = Enum.find(parsed("hnyupius").levels, &(&1.level == 15))
      assert Enum.any?(hnyupius_15.feats, &(&1.id == :dwarven_defender_damage_reduction))
      refute Enum.any?(hnyupius_15.feats, &(&1.id == :damage_reduction_barbarian))
    end

    test "Greater Rage — bare and with a (Nx per day) argument — reads as the barbarian_rage redirect" do
      by_level = Map.new(parsed("babuka").levels, &{&1.level, &1})

      assert [%{id: :barbarian_rage, argument: "4x per day"}] = by_level[16].feats

      assert [
               %{id: :uncanny_dodge, argument: nil, rank: "v"},
               %{id: :barbarian_rage, argument: "5x per day"}
             ] = by_level[17].feats

      # Bare, no daily-use count this time — same id all three ways.
      assert [%{id: :barbarian_rage, argument: nil}, %{id: :damage_reduction_barbarian}] =
               by_level[25].feats
    end

    test "Uncanny Dodge VI+ keeps the trailing + as part of the rank, not a leftover token" do
      level_20 = Enum.find(parsed("babuka").levels, &(&1.level == 20))

      assert [%{kind: :feat, id: :uncanny_dodge, rank: "vi+"}] = level_20.feats
      refute Enum.any?(level_20.feats, &(&1.kind == :unknown))
    end
  end

  # ---------------------------------------- three more findings, task 3.118 --

  describe "frah_hall.log: header spellings and an element inside a feat's own name" do
    test "SORC, DRU and the full word \"Bard\" all resolve, and the checksum agrees" do
      result = parsed("frah_hall")

      assert Enum.find(result.header_classes, &(&1.raw == "SORC")).class == :sorcerer
      assert Enum.find(result.header_classes, &(&1.raw == "DRU")).class == :druid
      assert Enum.find(result.header_classes, &(&1.raw == "Bard")).class == :bard
      assert GameLog.checksum(result) == :ok
    end

    test "\"Animal companion\" resolves despite missing the ruleset's own \"(feat)\" suffix" do
      level_36 = Enum.find(parsed("frah_hall").levels, &(&1.level == 36))

      assert Enum.any?(
               level_36.feats,
               &(&1.kind == :feat and &1.id == :animal_companion_feat and
                   &1.raw == "animal companion")
             )
    end

    test "\"Resist Sonic Energy\" keeps the element even though it sits INSIDE the name" do
      level_36 = Enum.find(parsed("frah_hall").levels, &(&1.level == 36))

      assert Enum.any?(
               level_36.feats,
               &(&1.kind == :feat and &1.id == :resist_energy and &1.argument == "sonic")
             )
    end

    test "\"Energy Resistance, Fire I\" then \"…Fire II\" both keep the element, same take twice" do
      by_level = Map.new(parsed("frah_hall").levels, &{&1.level, &1})

      assert [%{id: :epic_energy_resistance, argument: "fire", rank: "i"}] =
               by_level[24].feats

      assert [%{id: :epic_energy_resistance, argument: "fire", rank: "ii"}] =
               by_level[26].feats
    end

    test "\"Bard Song\" is printed on both of Bard's own first two levels" do
      by_level = Map.new(parsed("frah_hall").levels, &{&1.level, &1})

      assert Enum.any?(by_level[40].feats, &(&1.id == :bard_song))
      assert [%{id: :bard_song, argument: nil}] = by_level[41].feats
    end
  end

  # ----------------------------------- one abbreviation, one general rule, task 3.119 --

  describe "froim.log: PAL resolves, and \"Remove Disease\" via the general \"(feat)\"-suffix rule" do
    test "the PAL header abbreviation resolves, and the checksum agrees" do
      result = parsed("froim")
      assert Enum.find(result.header_classes, &(&1.raw == "PAL")).class == :paladin
      assert GameLog.checksum(result) == :ok
    end

    test "\"Remove Disease\" resolves despite missing the ruleset's own \"(feat)\" suffix" do
      level_17 = Enum.find(parsed("froim").levels, &(&1.level == 17))

      assert Enum.any?(
               level_17.feats,
               &(&1.kind == :feat and &1.id == :remove_disease_feat and
                   &1.raw == "remove disease")
             )
    end

    # The point of `feat_dictionary/1`'s own general rule: fourteen more
    # "(feat)"-suffixed feats resolve the same way `Remove Disease` does
    # above, none of them exercised by any of the seven real fixtures yet.
    # `Darkness`/`Invisibility`/`Fear`/`Sleep`/`Bull's Strength`/`Cat's
    # Grace`/`Contagion`/`Create Undead`/`Eagle's Splendor`/`Ghostly
    # Visage`/`Improved Invisibility`/`Inflict Critical Wounds`/`Inflict
    # Serious Wounds`/`Shades` — CLAUDE.md §9's assassin/blackguard/pale
    # master/shifter copies of a same-named spell, spelled the way nobody
    # typing their own build would reproduce the wiki's disambiguation.
    test "the fourteen '(feat)'-suffixed feats no fixture has exercised yet all resolve too" do
      synthetic = """
      ------------------------------------------------
          CHARACTER BUILD: Тест
          Current: 1 FTR
      ------------------------------------------------

      CURRENT ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
      COMBAT STATS: AB 3 AC 12 Fort 5 Refl 1 Will 1
      SKILLS WITH RANKS:
        Discipline 6

      (WHITE) ABILITIES: STR 16 DEX 12 CON 14 INT 10 WIS 10 CHA 8
      RACE: Human

      ------------------------------------------------
      LEVEL 1: FIGHTER
        FEATS: Darkness, Invisibility, Fear, Sleep, Bull's Strength, Cat's Grace, Contagion, Create Undead, Eagle's Splendor, Ghostly Visage, Improved Invisibility, Inflict Critical Wounds, Inflict Serious Wounds, Shades
      ------------------------------------------------
      """

      result = GameLog.parse(synthetic, @ruleset)
      assert result.problems == []

      level_1 = Enum.find(result.levels, &(&1.level == 1))

      assert Enum.map(level_1.feats, & &1.id) == [
               :darkness_feat,
               :invisibility_feat,
               :fear_feat,
               :sleep_feat,
               :bulls_strength_feat,
               :cats_grace_feat,
               :contagion_feat,
               :create_undead_feat,
               :eagles_splendor_feat,
               :ghostly_visage_feat,
               :improved_invisibility_feat,
               :inflict_critical_wounds_feat,
               :inflict_serious_wounds_feat,
               :shades_feat
             ]

      assert Enum.all?(level_1.feats, &(&1.kind == :feat))
    end

    # `frah_hall.log`'s own "Bard" already proved the header sometimes
    # prints a class's FULL name rather than a shortened one; task 3.119
    # generalises that into every class, off `ruleset.classes` rather than
    # one more name typed into `@header_class_abbreviations` by hand.
    test "a class's FULL name in the header resolves too, derived from the ruleset" do
      full_name = String.replace(@minimal, "Current: 3 FTR", "Current: 3 Fighter")
      result = GameLog.parse(full_name, @ruleset)

      assert Enum.find(result.header_classes, &(&1.raw == "Fighter")).class == :fighter
      assert result.problems == []
      assert GameLog.checksum(result) == :ok
    end

    # The general rule only ever ADDS a second way to resolve a class in the
    # header (full name, off the ruleset) — it must not loosen the
    # shortened-spelling table into guessing. A three-letter code this
    # project has not observed is still reported, never invented, even one
    # that happens to be a genuine prefix of some class's own full name.
    test "an unobserved short code is still reported, never guessed from a class's full name" do
      bad = String.replace(@minimal, "Current: 3 FTR", "Current: 3 FIG")
      result = GameLog.parse(bad, @ruleset)

      assert {:unresolved_header_class, "FIG"} in result.problems
      assert [%{raw: "FIG", count: 3, class: nil}] = result.header_classes
    end

    # The collision guard `feat_dictionary/1` already raises on (two entries
    # answering to the same normalised name) must still fire once the
    # "(feat)"-suffix stripping feeds it a second key per name instead of
    # one — a synthetic ruleset is the only way to exercise it, since no
    # real feat pair collides (checked by hand, task 3.119's own commit).
    test "a genuine name collision still raises — the guard survives the general rule" do
      colliding =
        put_in(
          @ruleset.feats,
          Map.merge(@ruleset.feats, %{
            fake_a: %{
              @ruleset.feats.toughness
              | id: :fake_a,
                name: "Some ability (feat)",
                ru: nil
            },
            fake_b: %{@ruleset.feats.toughness | id: :fake_b, name: "Some ability", ru: nil}
          })
        )

      assert_raise RuntimeError, ~r/two entries answer to/, fn ->
        GameLog.parse(@minimal, colliding)
      end
    end
  end

  # ------------------------------------------------ a colon-separated value --

  describe "aley.log: HS resolves, and a colon carries Favored enemy's value (task 3.121)" do
    test "the HS header abbreviation resolves, and the checksum agrees" do
      result = parsed("aley")
      assert Enum.find(result.header_classes, &(&1.raw == "HS")).class == :harper_scout
      assert GameLog.checksum(result) == :ok
    end

    # "Favored Enemy: Elementals" (ranger's own first level, character level
    # 8) and "Favored Enemy: Giants" (Harper Scout's own first level,
    # character level 10) — the value sits after a COLON, the fourth shape
    # this project has read an argument in (parenthesis, comma-suffix, a word
    # inside the name, and now this). Plural in the log, singular in the
    # domain's own 25 entries, and `favored_enemy_aliases/1` bridges the two
    # without stripping an "s" off arbitrary text (its own moduledoc note).
    test "Favored Enemy: Elementals / : Giants both resolve, argument and all" do
      level_8 = Enum.find(parsed("aley").levels, &(&1.level == 8))
      level_10 = Enum.find(parsed("aley").levels, &(&1.level == 10))

      assert Enum.any?(
               level_8.feats,
               &(&1.kind == :feat and &1.id == :favored_enemy and &1.argument == "elemental")
             )

      assert Enum.any?(
               level_10.feats,
               &(&1.kind == :feat and &1.id == :favored_enemy and &1.argument == "giant")
             )
    end

    # The guard `favored_enemy_aliases/1` raises on: two DIFFERENT creature
    # types whose naive "+s" plural and bare name collide at the same key —
    # here `:fooz` ("Abc" → "abc"/"abcs") and `:barz` ("Abcs" → "abcs"),
    # colliding at "abcs". The real domain has zero such collisions across
    # its 25 entries (checked on every load by this same guard); this is the
    # synthetic proof the check itself still fires, the same technique the
    # "(feat)"-suffix collision test above uses for `feat_dictionary/1`'s own
    # guard.
    test "a genuine pluralisation collision still raises — the generated table is guarded too" do
      colliding =
        put_in(@ruleset.choice_domains.creature_type, %{
          values: MapSet.new([:fooz, :barz]),
          flags: %{},
          names: %{fooz: "Abc", barz: "Abcs"},
          source: :file
        })

      assert_raise RuntimeError, ~r/favored_enemy_aliases/, fn ->
        GameLog.parse(@minimal, colliding)
      end
    end
  end

  # ------------------------- the log-coverage plan's first three builds --
  #
  # `docs/log_coverage.md` (task 3.123) named ten builds worth sending, one
  # class or feat-name risk at a time rather than "whatever a player already
  # had". elith/boido/nathan (task 3.131, sent the same day) are the first
  # three of those ten, taken in the plan's own order — Build 1 (Arcane
  # Archer), Build 2 (Blackguard) and Build 3 (Assassin).

  describe "elith.log: AA resolves, and the log-coverage plan's Build 1 lands clean" do
    test "the AA header abbreviation resolves, and the checksum agrees" do
      result = parsed("elith")
      assert Enum.find(result.header_classes, &(&1.raw == "AA")).class == :arcane_archer
      assert GameLog.checksum(result) == :ok
    end

    # `Improved Two-Weapon Fighting` was flagged as a risk (the one hyphen
    # inside a feat's own canonical name in the whole ruleset) but needed no
    # alias at all: the ruleset's own name already carries the hyphen, and
    # `normalize/1` never touches one, so the log's spelling matches the
    # dictionary key directly. Worth reading as a test regardless, so a
    # future rename of the canonical name (dropping the hyphen, say) fails
    # loudly here instead of only in the wiki-comparison tooling.
    test "\"Improved Two-Weapon Fighting\" resolves — the hyphen needed no alias" do
      level_10 = Enum.find(parsed("elith").levels, &(&1.level == 10))
      assert Enum.any?(level_10.feats, &(&1.id == :improved_two_weapon_fighting))
    end

    # A second, real-build confirmation of `favored_enemy_aliases/1` (first
    # exercised by `aley.log`, task 3.121) — plural after a colon, this time
    # on a class the earlier fixture never took past level 1.
    test "\"Favored Enemy: Half-Orcs\" resolves to :favored_enemy with the half_orc value" do
      level_11 = Enum.find(parsed("elith").levels, &(&1.level == 11))
      assert Enum.any?(level_11.feats, &(&1.id == :favored_enemy and &1.argument == "half_orc"))
    end

    # The reason Build 1 goes through Arcane Archer at all: its own class
    # grants across all ten of its class levels, all previously unexercised
    # by any fixture (`docs/log_coverage.md`'s own table, §3.1).
    test "Arcane Archer's own class grants resolve across all ten of its class levels" do
      by_level = Map.new(parsed("elith").levels, &{&1.level, &1})

      for {level, rank} <- [
            {12, "i"},
            {14, "ii"},
            {16, "iii"},
            {18, "iv"},
            {20, "v"},
            {22, "vi"},
            {24, "vii"}
          ] do
        assert Enum.any?(by_level[level].feats, &(&1.id == :enchant_arrow and &1.rank == rank)),
               "level #{level}: expected enchant_arrow(#{rank}) in #{inspect(by_level[level].feats)}"
      end

      assert Enum.any?(by_level[13].feats, &(&1.id == :imbue_arrow))
      assert Enum.any?(by_level[15].feats, &(&1.id == :seeker_arrow and &1.rank == "i"))
      assert Enum.any?(by_level[17].feats, &(&1.id == :seeker_arrow and &1.rank == "ii"))
      assert Enum.any?(by_level[19].feats, &(&1.id == :hail_of_arrows))
      assert Enum.any?(by_level[21].feats, &(&1.id == :arrow_of_death))
    end

    # The point of the whole `put_skill_totals/3` disambiguation this
    # fixture forced: an absent `SKILLS WITH RANKS:` block reads as a legal
    # zero-skill-points character, not as a missing field.
    test "the SKILLS WITH RANKS block being entirely absent reads clean, not as a missing field" do
      refute fixture("elith") =~ "SKILLS WITH RANKS"

      result = parsed("elith")
      assert result.skills_with_ranks == []
      assert result.problems == []
    end
  end

  describe "boido.log: BG resolves, and a comma-plus-parenthesis argument together (Build 2)" do
    test "the BG header abbreviation resolves, and the checksum agrees" do
      result = parsed("boido")
      assert Enum.find(result.header_classes, &(&1.raw == "BG")).class == :blackguard
      assert GameLog.checksum(result) == :ok
    end

    # "Sneak Attack, Blackguard (+1d6)" combines two shapes this project has
    # only ever seen apart until now: the comma-inside-a-name trap
    # `FeatListTokenizer`'s longest-match walk exists for (`hnyupius.log`'s
    # own "Energy Resistance, Fire I") and a parenthesised argument riding
    # along on the same token (`Weapon Focus (Longsword)`). Both fire on the
    # same string here.
    test "\"Sneak Attack, Blackguard (+Nd6)\" keeps its comma AND its argument, both takes" do
      by_level = Map.new(parsed("boido").levels, &{&1.level, &1})

      assert Enum.any?(
               by_level[11].feats,
               &(&1.id == :sneak_attack_blackguard and &1.argument == "+1d6")
             )

      assert Enum.any?(
               by_level[14].feats,
               &(&1.id == :sneak_attack_blackguard and &1.argument == "+2d6")
             )
    end

    # Task 3.119 generalised the "(feat)"-suffix mismatch from three
    # one-off aliases into a rule covering fourteen feats, tested until now
    # only against a synthetic dump (`froim.log`'s own describe block
    # above). This is the first REAL fixture to exercise five of them.
    test "five more '(feat)'-suffixed grants resolve live, the rule's first real confirmation" do
      by_level = Map.new(parsed("boido").levels, &{&1.level, &1})

      assert Enum.any?(by_level[9].feats, &(&1.id == :bulls_strength_feat))
      assert Enum.any?(by_level[10].feats, &(&1.id == :create_undead_feat))
      assert Enum.any?(by_level[13].feats, &(&1.id == :inflict_serious_wounds_feat))
      assert Enum.any?(by_level[14].feats, &(&1.id == :contagion_feat))
      assert Enum.any?(by_level[15].feats, &(&1.id == :inflict_critical_wounds_feat))
    end
  end

  describe "nathan.log: ASS resolves, and four more spell-alike '(feat)' names (Build 3)" do
    test "the ASS header abbreviation resolves, and the checksum agrees" do
      result = parsed("nathan")
      assert Enum.find(result.header_classes, &(&1.raw == "ASS")).class == :assassin
      assert GameLog.checksum(result) == :ok
    end

    # The four riskiest names among the fourteen task 3.119 closed blind —
    # each shares its wiki page with an actual SPELL of the same name, so a
    # collision here would have been the likeliest of the fourteen.
    test "Ghostly Visage / Darkness / Invisibility / Improved Invisibility all resolve to *_feat" do
      by_level = Map.new(parsed("nathan").levels, &{&1.level, &1})

      assert Enum.any?(by_level[7].feats, &(&1.id == :ghostly_visage_feat))
      assert Enum.any?(by_level[10].feats, &(&1.id == :darkness_feat))
      assert Enum.any?(by_level[12].feats, &(&1.id == :invisibility_feat))
      assert Enum.any?(by_level[14].feats, &(&1.id == :improved_invisibility_feat))
    end

    test "\"Skill Focus (Craft Weapon)\" and \"(Move Silently)\" keep the space inside the argument" do
      by_level = Map.new(parsed("nathan").levels, &{&1.level, &1})

      assert Enum.any?(
               by_level[9].feats,
               &(&1.id == :skill_focus and &1.argument == "craft weapon")
             )

      assert Enum.any?(
               by_level[12].feats,
               &(&1.id == :skill_focus and &1.argument == "move silently")
             )
    end

    test "Death Attack's parenthesised stage and Poison Save's bare roman numeral both resolve" do
      by_level = Map.new(parsed("nathan").levels, &{&1.level, &1})

      assert Enum.any?(by_level[6].feats, &(&1.id == :death_attack and &1.argument == "+1d6"))
      assert Enum.any?(by_level[14].feats, &(&1.id == :death_attack and &1.argument == "+5d6"))
      assert Enum.any?(by_level[7].feats, &(&1.id == :poison_save and &1.rank == "i"))
      assert Enum.any?(by_level[13].feats, &(&1.id == :poison_save and &1.rank == "iv"))
    end
  end

  describe "timonall.log: CoT resolves in mixed case, and the block-absence reading repeats (Build 4)" do
    test "the CoT header abbreviation resolves case-insensitively, and the checksum agrees" do
      result = parsed("timonall")
      assert Enum.find(result.header_classes, &(&1.raw == "CoT")).class == :champion_of_torm
      assert GameLog.checksum(result) == :ok
    end

    # A second, independent fixture with the `SKILLS WITH RANKS:` block
    # simply absent — the same shape `elith.log` forced `put_skill_totals/3`
    # to disambiguate, now read clean a second time on a different class
    # combination.
    test "the SKILLS WITH RANKS block is absent here too, and still reads clean" do
      refute fixture("timonall") =~ "SKILLS WITH RANKS"

      result = parsed("timonall")
      assert result.skills_with_ranks == []
      assert result.problems == []
    end

    # Champion of Torm's own class grants, previously unexercised by any
    # fixture (`docs/log_coverage.md`'s own table, §3.1) — `Sacred defense`
    # and `Divine wrath` are also the two feats CLAUDE.md §9 names by hand as
    # sitting on opposite sides of the save-bonus cap despite sharing a
    # record shape, which is why a live confirmation matters here.
    test "Champion of Torm's own class grants resolve" do
      by_level = Map.new(parsed("timonall").levels, &{&1.level, &1})

      assert Enum.any?(by_level[9].feats, &(&1.id == :sacred_defense))
      assert Enum.any?(by_level[12].feats, &(&1.id == :divine_wrath))
    end
  end

  describe "trina.log: PDK resolves, and a repeated class grant prints twice (Build 5)" do
    test "the PDK header abbreviation resolves, and the checksum agrees" do
      result = parsed("trina")
      assert Enum.find(result.header_classes, &(&1.raw == "PDK")).class == :purple_dragon_knight
      assert GameLog.checksum(result) == :ok
    end

    # Purple Dragon Knight's own class grants, previously unexercised — and
    # the class whose Sialan progression table task 3.96 once found missing
    # past its vanilla five-row length (potentially dropping levels 6-10's
    # own base-attack and save contribution entirely, not partially). See
    # `BuildCalculatorWeb.Builder.GameLogImportTest`'s own describe block for
    # the live confirmation that all ten of this class's levels count.
    test "Purple Dragon Knight's own class grants resolve, including the repeated Inspire courage" do
      by_level = Map.new(parsed("trina").levels, &{&1.level, &1})

      assert Enum.any?(by_level[6].feats, &(&1.id == :rallying_cry))
      assert Enum.any?(by_level[8].feats, &(&1.id == :heroic_shield))
      assert Enum.any?(by_level[8].feats, &(&1.id == :inspire_courage))
      assert Enum.any?(by_level[11].feats, &(&1.id == :fear_feat))
      assert Enum.any?(by_level[13].feats, &(&1.id == :oath_of_wrath))
      # Printed again on level 13 — a growing ability re-announced, the same
      # shape `frah_hall.log`'s own Bard Song already proved is not a second
      # take (`reprinted_grant?/4`'s own moduledoc note).
      assert Enum.any?(by_level[13].feats, &(&1.id == :inspire_courage))
      assert Enum.any?(by_level[15].feats, &(&1.id == :final_stand))
    end
  end

  describe "hela.log: RDD resolves, and Hit Die Increase only partly (Build 6)" do
    test "the RDD header abbreviation resolves, and the checksum agrees" do
      result = parsed("hela")
      assert Enum.find(result.header_classes, &(&1.raw == "RDD")).class == :red_dragon_disciple
      assert GameLog.checksum(result) == :ok
    end

    # Red Dragon Disciple's own class grants — `hit_die_increase` prints
    # THREE times (levels 9/12/14, its own class levels 1/4/6, matching the
    # growing die CLAUDE.md §3 already documents: d6/d8/d10) but
    # `ruleset.classes.red_dragon_disciple.granted_feats` only names it at
    # class level 4. This module still reads every occurrence — the gap is
    # in what `GameLogImport` makes of it, pinned in that file's own describe
    # block, not here.
    test "Red Dragon Disciple's own class grants resolve, including all three Hit Die Increase prints" do
      by_level = Map.new(parsed("hela").levels, &{&1.level, &1})

      assert Enum.any?(by_level[9].feats, &(&1.id == :draconic_armor))
      assert Enum.any?(by_level[9].feats, &(&1.id == :hit_die_increase and &1.argument == "d6"))
      assert Enum.any?(by_level[10].feats, &(&1.id == :dragon_abilities))
      assert Enum.any?(by_level[11].feats, &(&1.id == :dragon_breath))
      assert Enum.any?(by_level[12].feats, &(&1.id == :hit_die_increase and &1.argument == "d8"))
      assert Enum.any?(by_level[14].feats, &(&1.id == :hit_die_increase and &1.argument == "d10"))
      assert Enum.any?(by_level[18].feats, &(&1.id == :immunity_to_fire))
      assert Enum.any?(by_level[18].feats, &(&1.id == :immunity_to_paralysis))
    end
  end

  describe "nicha.log: SD resolves, and Hide in Plain Sight lands on the Sialan level (Build 7)" do
    test "the SD header abbreviation resolves, and the checksum agrees" do
      result = parsed("nicha")
      assert Enum.find(result.header_classes, &(&1.raw == "SD")).class == :shadowdancer
      assert GameLog.checksum(result) == :ok
    end

    # CLAUDE.md §3's own Sialan shift for Shadowdancer: `Hide in Plain Sight`
    # moves from vanilla's 1st class level to the 4th. Character level 12 is
    # Shadowdancer's own 4th level here (levels 9-11 are its first three) —
    # the engine printing it there is the shift confirmed by a real dump,
    # not just read off the wiki.
    test "Hide in Plain Sight prints on Shadowdancer's own 4th class level, not the 1st" do
      by_level = Map.new(parsed("nicha").levels, &{&1.level, &1})

      refute Enum.any?(by_level[9].feats, &(&1.id == :hide_in_plain_sight))
      assert Enum.any?(by_level[12].feats, &(&1.id == :hide_in_plain_sight))
    end

    test "Shadowdancer's other class grants resolve too" do
      by_level = Map.new(parsed("nicha").levels, &{&1.level, &1})

      assert Enum.any?(by_level[11].feats, &(&1.id == :shadow_daze))
      assert Enum.any?(by_level[11].feats, &(&1.id == :summon_shadow))
      assert Enum.any?(by_level[12].feats, &(&1.id == :shadow_evade))
      assert Enum.any?(by_level[13].feats, &(&1.id == :defensive_roll))
      assert Enum.any?(by_level[15].feats, &(&1.id == :slippery_mind))
    end
  end

  describe "hana.log: SHIF resolves, two ways a roman numeral rides on a name (Build 8)" do
    test "the SHIF header abbreviation resolves, and the checksum agrees" do
      result = parsed("hana")
      assert Enum.find(result.header_classes, &(&1.raw == "SHIF")).class == :shifter
      assert GameLog.checksum(result) == :ok
    end

    # `Greater Wildshape I (wyrmling shape)` and `Infinite Greater Wildshape I`
    # sit two lines apart and both carry a roman numeral, but the ruleset
    # spells the two families differently: Greater Wildshape has a SEPARATE
    # id per stage (`greater_wildshape_i`/`_ii`/`_iv` — its own numeral is
    # part of the id, not a rank), while Infinite Greater Wildshape is ONE id
    # with the numeral read as `rank`. Both schemes fire correctly next to
    # each other on the same dump.
    test "Greater Wildshape's own numeral is part of the id; Infinite Greater Wildshape's is a rank" do
      by_level = Map.new(parsed("hana").levels, &{&1.level, &1})

      assert Enum.any?(
               by_level[7].feats,
               &(&1.id == :greater_wildshape_i and &1.argument == "wyrmling shape")
             )

      assert Enum.any?(by_level[9].feats, &(&1.id == :greater_wildshape_ii))
      assert Enum.any?(by_level[16].feats, &(&1.id == :greater_wildshape_iv))

      assert Enum.any?(
               by_level[10].feats,
               &(&1.id == :infinite_greater_wildshape and &1.rank == "i")
             )

      assert Enum.any?(
               by_level[13].feats,
               &(&1.id == :infinite_greater_wildshape and &1.rank == "ii")
             )

      assert Enum.any?(
               by_level[16].feats,
               &(&1.id == :infinite_greater_wildshape and &1.rank == "iii")
             )
    end

    # The third fixture whose `SKILLS WITH RANKS:` block is entirely absent
    # (after `elith.log` and `timonall.log`) — a third independent case for
    # the same "legal zero-skill-points character" reading.
    test "the SKILLS WITH RANKS block is absent here too, and still reads clean" do
      refute fixture("hana") =~ "SKILLS WITH RANKS"

      result = parsed("hana")
      assert result.skills_with_ranks == []
      assert result.problems == []
    end
  end

  # -------------------------------------------------------- the cap and limit --

  describe "moxie.log: the shard's level cap and class limit" do
    test "all 41 levels are read, across all four classes" do
      levels = parsed("moxie").levels
      assert length(levels) == 41
      assert Enum.at(levels, 40).level == 41
      assert Enum.at(levels, 40).class == :ranger

      assert levels |> Enum.map(& &1.class) |> Enum.uniq() |> Enum.sort() ==
               Enum.sort([:monk, :cleric, :rogue, :ranger])
    end
  end

  # ------------------------------------------------------------ corrupted input --
  #
  # None of the sixteen real dumps exercises a genuinely bad line — they were
  # all sent by a working chat command. These pin the failure paths the
  # honesty guarantee rests on: every one of them is a `problems` entry, and
  # none of them is a raised exception. `@minimal` itself is declared near
  # the top of the file now, ahead of task 3.119's own header/collision tests
  # above the moxie block, which need it too.

  describe "never raises, and never loses a bad line silently" do
    test "a well-formed minimal dump reads clean, as a control" do
      result = GameLog.parse(@minimal, @ruleset)
      assert result.problems == []
      assert length(result.levels) == 3
    end

    test "a non-string input is reported, not raised on" do
      assert %GameLog{problems: [{:not_a_string}]} = GameLog.parse(123, @ruleset)
    end

    test "an empty string is reported field by field, not raised on" do
      result = GameLog.parse("", @ruleset)

      assert {:missing_field, :name} in result.problems
      assert {:missing_field, :race} in result.problems
      assert {:missing_field, :header_classes} in result.problems
      assert {:missing_field, :levels} in result.problems
      assert result.levels == []
    end

    test "an unresolved class name is reported and does not stop the rest of the ladder" do
      bad = String.replace(@minimal, "LEVEL 2: FIGHTER", "LEVEL 2: NINJA")
      result = GameLog.parse(bad, @ruleset)

      assert {:unresolved_class, 2, "NINJA"} in result.problems
      assert Enum.at(result.levels, 1).class == nil
      assert Enum.at(result.levels, 1).class_raw == "NINJA"
      # Level 3, after the bad one, is still read.
      assert Enum.at(result.levels, 2).class == :fighter
    end

    test "an unresolved header abbreviation is reported, not guessed at" do
      bad = String.replace(@minimal, "Current: 3 FTR", "Current: 3 XYZ")
      result = GameLog.parse(bad, @ruleset)

      assert {:unresolved_header_class, "XYZ"} in result.problems
      assert [%{raw: "XYZ", count: 3, class: nil}] = result.header_classes
    end

    test "a line matching no known shape is reported, not silently skipped" do
      bad = String.replace(@minimal, "RACE: Human", "RACE: Human\nSOME UNEXPECTED LINE")
      result = GameLog.parse(bad, @ruleset)

      assert {:unrecognized_line, "SOME UNEXPECTED LINE"} in result.problems
    end

    test "a second FEATS: line on one level is reported, and the first one wins" do
      bad =
        String.replace(
          @minimal,
          "  FEATS: Toughness, Dodge\n",
          "  FEATS: Toughness, Dodge\n  FEATS: Mobility\n"
        )

      result = GameLog.parse(bad, @ruleset)
      assert {:duplicate_field, 1, :feats_raw} in result.problems

      level_1 = Enum.find(result.levels, &(&1.level == 1))
      assert Enum.map(level_1.feats, & &1.id) == [:toughness, :dodge]
    end

    test "a FEATS: line before any LEVEL is reported, not silently attached to nothing" do
      bad = String.replace(@minimal, "RACE: Human", "RACE: Human\n  FEATS: Toughness")
      result = GameLog.parse(bad, @ruleset)

      assert {:field_before_any_level, :feats_raw} in result.problems
    end

    test "an ability increase other than +1 is reported, and still recorded as read" do
      bad = String.replace(@minimal, "LEVEL 1: FIGHTER", "LEVEL 1: FIGHTER\n  ABILITY: +2 STR")
      result = GameLog.parse(bad, @ruleset)

      assert {:unexpected_ability_increase_amount, 1, 2} in result.problems

      level_1 = Enum.find(result.levels, &(&1.level == 1))
      assert level_1.ability_increase == %{ability: :str, raw: "STR", amount: 2}
    end

    test "a missing RACE: line is reported instead of leaving race silently nil" do
      bad = String.replace(@minimal, "RACE: Human\n", "")
      result = GameLog.parse(bad, @ruleset)

      assert {:missing_field, :race} in result.problems
      assert result.race == nil
    end
  end

  describe "level_sequence_problems/1" do
    test "a gap in the printed level numbers is reported" do
      bad = String.replace(@minimal, "LEVEL 2: FIGHTER", "LEVEL 4: FIGHTER")
      result = GameLog.parse(bad, @ruleset)

      assert {:level_out_of_sequence, 2, 4} in GameLog.level_sequence_problems(result)
      assert {:level_out_of_sequence, 2, 4} in result.problems
    end

    test "a repeated level number is reported" do
      bad = String.replace(@minimal, "LEVEL 2: FIGHTER", "LEVEL 1: FIGHTER")
      result = GameLog.parse(bad, @ruleset)

      assert {:level_duplicate, 1} in GameLog.level_sequence_problems(result)
    end
  end

  describe "checksum/1" do
    test "agrees silently when the header tally matches the ladder" do
      assert GameLog.checksum(parsed("hnyupius")) == :ok
    end

    test "reports a class the header undercounts against the ladder" do
      # Built directly rather than off a broken fixture: `checksum/1` only
      # looks at `header_classes` and `levels`, so this pins its own
      # arithmetic without needing a whole corrupted dump.
      struct = %GameLog{
        header_classes: [%{raw: "FTR", count: 2, class: :fighter}],
        levels: [%{class: :fighter}, %{class: :fighter}, %{class: :fighter}]
      }

      assert {:mismatch, [{:header_body_mismatch, :fighter, 2, 3}]} = GameLog.checksum(struct)
    end

    test "reports a class the ladder carries that the header never mentions at all" do
      struct = %GameLog{header_classes: [], levels: [%{class: :monk}]}
      assert {:mismatch, [{:class_missing_from_header, :monk, 1}]} = GameLog.checksum(struct)
    end
  end
end
