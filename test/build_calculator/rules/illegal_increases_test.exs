defmodule BuildCalculator.Rules.IllegalIncreasesTest do
  @moduledoc """
  `Rules.illegal_increases/2` — an ability increase keyed at a level that
  grants none (task 4.37), on both rulesets.

  The defect: `Abilities.scores_at/3` added every increase keyed up to a level
  and asked nothing of the key, and neither `illegal_class_levels/2` nor
  `illegal_feats/2` looked at increases. A link or a library entry built by the
  text import before task 4.36 carries `DEX +1` on level 5 and read as legal,
  one point of dexterity above what the game gives.

  Which levels grant an increase — `priv/rules/vanilla/epic.json` →
  `ability_increases` (`fandom:Level progression` revid 51665, `fandom:Ability
  score` revid 71148): «every four character levels a single ability score can
  be increased by one», enumerated as 4 … 20 pre-epic and 24 … 40 epic, «only up
  to level 40». Siala's layer says what its level 41 grants — base attack, no
  saves (`siala_41/overrides.json` → `epic.level_41_behaviour`, Dan
  01.08.2026) — and names no increase. Both loaded rulesets carry the same set
  (`test/snapshots/ruleset_*.snap`, `:epic/:ability_increase_levels`), and the
  engine agrees on Siala: its own `.билд` logs print an increase on exactly
  those levels, five of them at level 41 with none on 41 (the test «the
  engine's own logs agree with the data» below).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, Build}

  @versions ["vanilla", "siala_41"]

  # The enumeration of the source, as written in `vanilla/epic.json`
  # (`pre_epic_levels` ++ `epic_levels`). Stated here once so the table below is
  # not the data checked against itself: the test that pins this list to the
  # loaded ruleset is what fails if the data moves.
  @source_levels [4, 8, 12, 16, 20, 24, 28, 32, 36, 40]

  setup_all do
    %{rulesets: Map.new(@versions, &{&1, Data.ruleset!(&1)})}
  end

  # A human (no racial modifiers), so every point of a score in these tests is
  # point buy or an increase — arithmetic anybody can redo by hand.
  defp fighter(version, levels, increases) do
    Build.new(
      ruleset_version: version,
      race: :human,
      alignment: :lawful_good,
      levels: List.duplicate(:fighter, levels),
      base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8},
      ability_increases: increases
    )
  end

  defp dex(build, ruleset), do: Rules.compute(build, ruleset).abilities.dex

  test "the source's levels are the loaded rulesets' levels", %{rulesets: rulesets} do
    for {version, ruleset} <- rulesets do
      assert Enum.sort(ruleset.epic.ability_increase_levels) == @source_levels, version
    end
  end

  describe "an increase on a level that grants none" do
    for version <- @versions do
      test "#{version}: on level 5 it is named; on levels 4 and 8 it is not", %{
        rulesets: rulesets
      } do
        ruleset = rulesets[unquote(version)]

        # Positive control first: the same build with its increases where the
        # source puts them is clean — what is found below is found for level 5,
        # not for having increases at all.
        legal = fighter(ruleset.version, 8, %{4 => :str, 8 => :str})
        assert Rules.illegal_increases(legal, ruleset) == []

        stray = fighter(ruleset.version, 8, %{4 => :str, 5 => :dex, 8 => :str})

        assert Rules.illegal_increases(stray, ruleset) ==
                 [{5, :dex, {:increase_not_granted, 5}}]
      end

      test "#{version}: which levels grant one is the ruleset's, not a constant", %{
        rulesets: rulesets
      } do
        ruleset = rulesets[unquote(version)]
        build = fighter(ruleset.version, 8, %{4 => :str, 5 => :dex, 8 => :str})

        moved =
          update_in(ruleset, [:epic, :ability_increase_levels], fn levels ->
            levels |> MapSet.put(5) |> MapSet.delete(8)
          end)

        assert Rules.illegal_increases(build, moved) == [{8, :str, {:increase_not_granted, 8}}]
      end
    end
  end

  # The family's precedent (task 4.37, «что делать с числом»): `illegal_feats/2`
  # names `Great strength` picked on level 3 — its character-level requirement —
  # and `compute/2` still adds its point of strength. The increase follows it:
  # named, and still in the number. A change to either half of the precedent is
  # a change to this decision, and this test makes that visible.
  describe "the number keeps what the check names" do
    for version <- @versions do
      test "#{version}: an increase off its level still raises the score, and is named", %{
        rulesets: rulesets
      } do
        ruleset = rulesets[unquote(version)]
        base = fighter(ruleset.version, 8, %{})
        stray = fighter(ruleset.version, 8, %{5 => :dex})

        assert dex(stray, ruleset) == dex(base, ruleset) + 1
        assert [{5, :dex, _}] = Rules.illegal_increases(stray, ruleset)

        # The term-by-term account says where the point came from, and still
        # sums to the score (`Abilities.breakdown/2`'s honesty check).
        row = Abilities.breakdown(stray, ruleset).dex
        assert row.level_bonus == 1

        assert row.point_buy + row.race_bonus + row.level_bonus + row.own_bonus + row.gear_bonus ==
                 row.score

        # The precedent, on the same ruleset.
        feat = Build.put_feat(base, 3, :general, :great_strength)

        assert [{3, :general, :great_strength, {:requires_character_level, _}}] =
                 Rules.illegal_feats(feat, ruleset)

        assert Rules.compute(feat, ruleset).abilities.str ==
                 Rules.compute(base, ruleset).abilities.str + 1
      end
    end
  end

  # Every level from 0 to two past the cap, one increase at a time, on a build
  # of the full cap: named exactly when the number counts it (a key up to the
  # build's level) and the source does not list its level; counted exactly when
  # its key is within the build. The boundaries the task names are all inside:
  # 1, 20/21 (the last pre-epic and the first epic level), 24 (the first epic
  # increase), 40, and the cap itself — 40 on vanilla, 41 on Siala.
  describe "every level, one increase at a time" do
    for version <- @versions do
      test "#{version}: named iff counted and not listed by the source", %{rulesets: rulesets} do
        ruleset = rulesets[unquote(version)]
        cap = ruleset.level_cap
        base = fighter(ruleset.version, cap, %{})

        for level <- 0..(cap + 2) do
          build = fighter(ruleset.version, cap, %{level => :dex})
          counted? = level <= cap
          granted? = level in @source_levels

          expected =
            if counted? and not granted?,
              do: [{level, :dex, {:increase_not_granted, level}}],
              else: []

          assert Rules.illegal_increases(build, ruleset) == expected, "level #{level}"

          assert dex(build, ruleset) == dex(base, ruleset) + if(counted?, do: 1, else: 0),
                 "level #{level}"
        end
      end
    end

    test "the named boundary levels, spelled out", %{rulesets: rulesets} do
      for {version, ruleset} <- rulesets, level <- [1, 20, 21, 24, 40] do
        build = fighter(version, ruleset.level_cap, %{level => :con})
        named? = Rules.illegal_increases(build, ruleset) != []

        assert named? == level in [1, 21], "#{version}, level #{level}"
      end
    end
  end

  describe "Siala's cap, 41" do
    test "the forty-first level grants no increase; the fortieth does", %{rulesets: rulesets} do
      ruleset = rulesets["siala_41"]
      assert ruleset.level_cap == 41

      full = Map.new(@source_levels, &{&1, :str})
      capped = fighter(ruleset.version, 41, full)

      # Positive control on a finished build: all ten, and nothing named.
      assert Rules.illegal_increases(capped, ruleset) == []

      eleventh = fighter(ruleset.version, 41, Map.put(full, 41, :con))

      assert Rules.illegal_increases(eleventh, ruleset) ==
               [{41, :con, {:increase_not_granted, 41}}]
    end

    # The top of the source ranking (CLAUDE.md §3: «игрок наблюдал в игре»): the
    # shard's own `.билд` command prints every level the engine gave the
    # character, the ability increase with it. On all twenty logs of
    # `test/fixtures/game_logs*/` the engine printed an increase on exactly the
    # data's levels up to the character's own, and five of them are logs of
    # level-41 characters — four characters, `moxie` printed by both commands
    # (`babuka`, `frah_hall`, `froim`, `moxie`) — with ten increases and none on
    # 41. What `siala_41/overrides.json` does not say about 41, the engine does.
    test "the engine's own logs agree with the data, level 41 included", %{rulesets: rulesets} do
      ruleset = rulesets["siala_41"]

      logs =
        Path.wildcard("test/fixtures/game_logs/*.log") ++
          Path.wildcard("test/fixtures/game_logs_plus/*.log")

      assert length(logs) == 20

      tops =
        for path <- logs do
          log = BuildCalculator.GameLog.parse(File.read!(path), ruleset)
          top = log.levels |> Enum.map(& &1.level) |> Enum.max()
          printed = for entry <- log.levels, entry.ability_increase != nil, do: entry.level

          assert Enum.sort(printed) == Enum.filter(@source_levels, &(&1 <= top)), path
          top
        end

      assert Enum.count(tops, &(&1 == 41)) == 5
    end

    test "vanilla's cap is the last listed level", %{rulesets: rulesets} do
      ruleset = rulesets["vanilla"]
      assert ruleset.level_cap == 40

      build = fighter(ruleset.version, 40, Map.new(@source_levels, &{&1, :str}))
      assert Rules.illegal_increases(build, ruleset) == []
    end
  end

  # Decision of task 4.37: what is checked is what is counted. An increase keyed
  # past the build's last level adds nothing and has no row, so it is not named —
  # the line `illegal_feats/2` draws for picks (`Build.feat_picks/2` up to the
  # build's level). The day the ladder reaches it, it is counted, and named if
  # its level grants none.
  describe "past the build's last level" do
    for version <- @versions do
      test "#{version}: neither counted nor named until the ladder reaches it", %{
        rulesets: rulesets
      } do
        ruleset = rulesets[unquote(version)]
        short = fighter(ruleset.version, 20, %{24 => :str, 25 => :dex})
        bare = fighter(ruleset.version, 20, %{})

        assert Rules.illegal_increases(short, ruleset) == []
        assert Rules.compute(short, ruleset).abilities == Rules.compute(bare, ruleset).abilities

        grown = %Build{short | levels: List.duplicate(:fighter, 25)}
        grown_bare = %Build{bare | levels: List.duplicate(:fighter, 25)}

        assert Rules.illegal_increases(grown, ruleset) ==
                 [{25, :dex, {:increase_not_granted, 25}}]

        abilities = Rules.compute(grown, ruleset).abilities
        bare_abilities = Rules.compute(grown_bare, ruleset).abilities
        assert abilities.str == bare_abilities.str + 1
        assert abilities.dex == bare_abilities.dex + 1
      end
    end

    # A key of 0 is no level at all, and the number counts it (`0 <= level`
    # holds everywhere) — so it is named, at 0. Only a hand-made link carries
    # one: the decoder reads the level as a byte, the constructor and the import
    # never write it.
    test "a key of 0 is counted, so it is named", %{rulesets: rulesets} do
      for {version, ruleset} <- rulesets do
        zero = fighter(version, 3, %{0 => :dex})

        assert Rules.illegal_increases(zero, ruleset) == [{0, :dex, {:increase_not_granted, 0}}]
        assert dex(zero, ruleset) == dex(fighter(version, 3, %{}), ruleset) + 1
      end
    end
  end

  # The four-class limit of Siala (`siala_41/overrides.json`, `source: user`),
  # and the rule the check has to read the right way round: the increase belongs
  # to the CHARACTER level (`fandom:Level progression`), never to a class's own
  # fourth level. Fighter 3 / Wizard 4 / Rogue 5 / Sorcerer 4: character level
  # 4 is the Wizard's first level and grants one; character level 7 is the
  # Wizard's fourth and grants none.
  describe "four classes" do
    for version <- @versions do
      test "#{version}: the character level decides, not the class level", %{
        rulesets: rulesets
      } do
        ruleset = rulesets[unquote(version)]

        levels =
          List.duplicate(:fighter, 3) ++
            List.duplicate(:wizard, 4) ++
            List.duplicate(:rogue, 5) ++ List.duplicate(:sorcerer, 4)

        %Build{} =
          base =
          fighter(ruleset.version, 0, %{4 => :int, 7 => :int, 8 => :dex, 12 => :dex, 16 => :cha})

        build = %Build{base | levels: levels, alignment: :true_neutral}

        assert Build.character_level(build) == 16
        assert MapSet.size(Build.classes_used(build)) == 4
        assert Build.class_level_at(build, 4) == 1
        assert Build.class_level_at(build, 7) == 4

        assert Rules.illegal_increases(build, ruleset) == [{7, :int, {:increase_not_granted, 7}}]
      end
    end
  end
end
