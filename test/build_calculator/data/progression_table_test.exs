defmodule BuildCalculator.Data.ProgressionTableTest do
  @moduledoc """
  Task 3.96 (25.08.2026): Purple Dragon Knight lost its **entire** class
  contribution to base attack and all three saves the moment a build's own
  class levels reached six — `siala_41/classes.json` had raised the class's
  `max_level` to 10 (the shard doubled its schedule), but `class.progression`
  stayed the five-row table it inherited from `vanilla/classes.json`, and
  `Rules.Progression.progression_row/3` looks a class up by one cumulative
  level. A five-row table asked for level 6 answers `{:missing_data,
  {:class_progression, …}}`, which `Progression.total/2` folds to zero — not
  "a bit short", the whole class contributing nothing at all (`Fighter 5 /
  Purple Dragon Knight 10` read base attack 5, not 15).

  Two things are pinned here:

    * **the general invariant** the fix relies on holding for every class the
      loader ever builds, on both rulesets — a progression table that does not
      reach its own class's cap silently drops that class the moment a build
      crosses the gap (`describe "every class's progression table…"`);
    * **the fix itself**, end to end off the exact wiki table
      (`priv/wiki_cache/siala/Пурпурный рыцарь дракон.wikitext`, revid 20530)
      and against the loader mechanism a `"what": "progression_table"` fact
      now exercises (`describe "the mechanism, on fixtures"`).

  Builds are appended one validated level at a time where the claim under test
  is that a level *is* legal (CLAUDE.md §3 — «Сценарий для игрока собирать тем
  же путём, каким его пройдёт игрок»); where the claim is only about the
  numbers `compute/2` returns, they are built directly with `Build.new/1`,
  matching `compute_test.exs`'s own convention — `compute/2` has no opinion on
  legality either way.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  describe "every class's progression table reaches its own cap" do
    # The invariant the fix depends on, checked on the *loaded* ruleset rather
    # than on the raw JSON: `class.max_level` is whatever the shard layer left
    # it at after every `changes[]` entry has run (`overrides.json`'s
    # `except_max_level` is a *different*, independent number — the class
    # level cap a build is validated against — but Purple Dragon Knight's own
    # `max_level` fact restates the same 10, and it is the loaded struct field
    # `Rules.Progression.progression_row/3` is blind to what does not appear
    # here). Before task 3.96, Purple Dragon Knight was the one class in
    # either ruleset where the two disagreed.
    test "on both rulesets" do
      for version <- ["vanilla", "siala_41"] do
        ruleset = Data.ruleset!(version)

        for {id, class} <- ruleset.classes do
          table_max = class.progression |> Map.keys() |> Enum.max(fn -> 0 end)

          assert table_max >= class.max_level,
                 "#{version}/#{id}: max_level is #{class.max_level}, but the progression " <>
                   "table only reaches #{table_max} — level #{table_max + 1} would read " <>
                   "{:missing_data, {:class_progression, …}} and drop the class out of base " <>
                   "attack and the saves entirely, not just underestimate them"
        end
      end
    end
  end

  describe "Purple Dragon Knight, class levels 1-10 (task 3.96 regression)" do
    setup do
      %{ruleset: Data.ruleset!("siala_41")}
    end

    @base_abilities %{str: 14, dex: 12, con: 14, int: 14, wis: 10, cha: 12}

    defp fighter_five do
      Build.new(
        ruleset_version: "siala_41",
        race: :human,
        alignment: :lawful_good,
        base_abilities: @base_abilities,
        levels: List.duplicate(:fighter, 5),
        skills: %{1 => %{intimidate: 4, listen: 4, persuade: 4, spot: 4}}
      )
    end

    test "all ten levels validate one at a time, exactly as a player would take them", %{
      ruleset: ruleset
    } do
      Enum.reduce(1..10, fighter_five(), fn n, build ->
        assert Rules.validate_level_up(build, :purple_dragon_knight, ruleset) == :ok,
               "Purple Dragon Knight level #{n} refused on a build whose own cap allows it"

        Build.add_level(build, :purple_dragon_knight)
      end)
    end

    # The quoted table (`priv/rules/siala_41/classes.json`), cumulative BAB
    # first, then the three saves — level by level, so a break at level 6
    # would fail here at exactly the level it broke at before the fix.
    @wiki_table %{
      1 => {1, 2, 0, 0},
      2 => {2, 3, 0, 0},
      3 => {3, 3, 1, 1},
      4 => {4, 4, 1, 1},
      5 => {5, 4, 1, 1},
      6 => {6, 5, 2, 2},
      7 => {7, 5, 2, 2},
      8 => {8, 6, 2, 2},
      9 => {9, 6, 3, 3},
      10 => {10, 7, 3, 3}
    }

    test "base attack and all three saves match the wiki table at every level", %{
      ruleset: ruleset
    } do
      # Fighter 5 alone, off the same table (`bab_progression: "high"`, saves
      # good/poor/poor): bab 5, fort 4, ref 1, will 1 — sanity-checked once so
      # a failure below points at Purple Dragon Knight, not at the fixture.
      fighter_only = Rules.compute(fighter_five(), ruleset)
      assert fighter_only.base_attack == 5
      assert fighter_only.saves_naked == %{fort: 6, ref: 2, will: 1}

      for {n, {bab, fort, ref, will}} <- @wiki_table do
        build =
          Build.new(
            ruleset_version: "siala_41",
            race: :human,
            alignment: :lawful_good,
            base_abilities: @base_abilities,
            levels: List.duplicate(:fighter, 5) ++ List.duplicate(:purple_dragon_knight, n),
            skills: %{1 => %{intimidate: 4, listen: 4, persuade: 4, spot: 4}}
          )

        stats = Rules.compute(build, ruleset)

        # +2 CON, +1 DEX, +0 WIS — the same ability modifiers every one of
        # these builds carries, applied on top of the two classes' base rows.
        assert stats.base_attack == 5 + bab, "level #{n}: base_attack"
        assert stats.saves_naked.fort == 4 + fort + 2, "level #{n}: fort"
        assert stats.saves_naked.ref == 1 + ref + 1, "level #{n}: ref"
        assert stats.saves_naked.will == 1 + will + 0, "level #{n}: will"

        refute Enum.any?(stats.gaps, &match?({:missing_data, {:class_progression, _, _}}, &1)),
               "level #{n} still reports a class_progression gap: #{inspect(stats.gaps)}"
      end
    end

    # The failure mode task 3.96 fixed was not "underestimated" but
    # "contributes nothing at all past level 5" — pinned directly, so a
    # regression that brought back a *partial* version of the bug (say, only
    # levels 8-10 going blank again) could not hide behind a passing sum.
    test "level 10 contributes strictly more than level 5, not less", %{ruleset: ruleset} do
      five =
        Rules.compute(
          Build.new(
            levels: List.duplicate(:fighter, 5) ++ List.duplicate(:purple_dragon_knight, 5)
          ),
          ruleset
        )

      ten =
        Rules.compute(
          Build.new(
            levels: List.duplicate(:fighter, 5) ++ List.duplicate(:purple_dragon_knight, 10)
          ),
          ruleset
        )

      assert ten.base_attack > five.base_attack
      assert ten.saves_naked.fort > five.saves_naked.fort
      assert ten.saves_naked.ref > five.saves_naked.ref
      assert ten.saves_naked.will > five.saves_naked.will
    end

    # The other half of epic rule 2 (CLAUDE.md §3): class levels past
    # character level 20 earn no share of base attack or the saves at all,
    # counted or not — so Purple Dragon Knight taken *after* twenty levels of
    # Fighter must read exactly as it did before this task, unaffected by the
    # progression table gaining five rows it will never be asked for.
    test "levels taken past character level 20 are unaffected", %{ruleset: ruleset} do
      fighter_twenty =
        Build.new(
          ruleset_version: "siala_41",
          race: :human,
          alignment: :lawful_good,
          base_abilities: @base_abilities,
          levels: List.duplicate(:fighter, 20),
          skills: %{1 => %{intimidate: 4, listen: 4, persuade: 4, spot: 4}}
        )

      full =
        Enum.reduce(1..10, fighter_twenty, fn n, build ->
          assert Rules.validate_level_up(build, :purple_dragon_knight, ruleset) == :ok,
                 "Purple Dragon Knight level #{n} refused past character level 20"

          Build.add_level(build, :purple_dragon_knight)
        end)

      stats = Rules.compute(full, ruleset)

      assert stats.base_attack == 25
      assert stats.saves_naked == %{fort: 19, ref: 12, will: 11}
      assert stats.hp == 410

      refute Enum.any?(stats.gaps, &match?({:missing_data, {:class_progression, _, _}}, &1))
    end
  end

  describe "the vanilla layer is untouched" do
    test "purple dragon knight's own vanilla table still stops at level 5" do
      vanilla = Data.ruleset!("vanilla").classes[:purple_dragon_knight]

      assert vanilla.max_level == 5
      assert vanilla.progression |> Map.keys() |> Enum.sort() == [1, 2, 3, 4, 5]
      assert vanilla.progression[5] == %{bab: 5, fort: 4, ref: 1, will: 1}
    end
  end

  # `Loader.load!/1` on a directory carrying only what it insists on — the
  # vanilla epic file (copied from the real snapshot, so the cross-checks it
  # feeds stay honest) and a single hand-written "fighter", the same recipe
  # `Data.RepeatedGrantsTest`'s `load/3` uses.
  describe "the mechanism, on fixtures" do
    @describetag :tmp_dir

    test "a row that disagrees with the class's own BAB label fails the build", %{tmp_dir: dir} do
      assert_raise RuntimeError, ~r/base attack 2.*label.*works out to 1/s, fn ->
        load(dir, value: [row(1, bab: 2)])
      end
    end

    test "a row that disagrees with the class's own save label fails the build", %{tmp_dir: dir} do
      assert_raise RuntimeError, ~r/fort 5.*label.*works out to 2/s, fn ->
        load(dir, value: [row(1, fort: 5)])
      end
    end

    test "a malformed row fails the build", %{tmp_dir: dir} do
      assert_raise RuntimeError, ~r/is not \{level:, bab:, fort:, ref:, will:\}/, fn ->
        load(dir, value: [%{"level" => 1, "bab" => "one", "fort" => 2, "ref" => 0, "will" => 0}])
      end
    end

    test "a gap in the levels fails the build", %{tmp_dir: dir} do
      assert_raise RuntimeError, ~r/neither a gap nor a repeat/, fn ->
        load(dir, value: [row(1), row(3, bab: 3, fort: 3, ref: 1, will: 1)])
      end
    end

    test "a repeated level fails the build", %{tmp_dir: dir} do
      assert_raise RuntimeError, ~r/neither a gap nor a repeat/, fn ->
        load(dir, value: [row(1), row(1)])
      end
    end

    test "a well-formed table grows the class past the vanilla one it inherited", %{
      tmp_dir: dir
    } do
      ruleset =
        load(dir,
          max_level: 3,
          value: [
            row(1),
            row(2, bab: 2, fort: 3, ref: 0, will: 0),
            row(3, bab: 3, fort: 3, ref: 1, will: 1)
          ]
        )

      fighter = ruleset.classes[:fighter]

      assert fighter.max_level == 3
      assert fighter.progression[1] == %{bab: 1, fort: 2, ref: 0, will: 0}
      assert fighter.progression[3] == %{bab: 3, fort: 3, ref: 1, will: 1}
    end

    # The universal `"status": "unclear"` skip (CLAUDE.md §3 — a value a human
    # could not pin down must not become a number) applies to this `what` the
    # same as any other: the class keeps the shorter, vanilla-length table,
    # and the fact surfaces honestly instead of vanishing.
    test "an unclear status leaves the table alone and reports the honest gap", %{tmp_dir: dir} do
      ruleset = load(dir, max_level: 3, status: "unclear", value: [row(1)])
      fighter = ruleset.classes[:fighter]

      assert Map.keys(fighter.progression) == [1]
      assert fighter.max_level == 3

      stats = Rules.compute(Build.new(levels: [:fighter]), ruleset)
      assert {:not_modelled, {:class_change, :fighter, "progression_table"}} in stats.gaps
    end

    defp row(level, overrides \\ []) do
      base = %{"level" => level, "bab" => level, "fort" => 2, "ref" => 0, "will" => 0}
      Enum.reduce(overrides, base, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)
    end

    defp load(dir, opts) do
      File.mkdir_p!(Path.join(dir, "vanilla"))

      File.cp!(
        Path.join(File.cwd!(), "priv/rules/vanilla/epic.json"),
        Path.join([dir, "vanilla", "epic.json"])
      )

      File.write!(
        Path.join([dir, "vanilla", "classes.json"]),
        Jason.encode!([
          %{
            "id" => "fighter",
            "name" => "Fighter",
            "bab_progression" => "high",
            "saves" => %{"fort" => "good", "ref" => "poor", "will" => "poor"},
            "progression" => [
              %{"level" => 1, "bab" => 1, "fort" => 2, "ref" => 0, "will" => 0}
            ]
          }
        ])
      )

      table_change = %{
        "what" => "progression_table",
        "value" => Keyword.fetch!(opts, :value),
        "status" => Keyword.get(opts, :status, "verified")
      }

      changes =
        case Keyword.get(opts, :max_level) do
          nil ->
            [table_change]

          level ->
            [%{"what" => "max_level", "value" => level, "status" => "verified"}, table_change]
        end

      File.mkdir_p!(Path.join(dir, "siala_41"))

      File.write!(
        Path.join([dir, "siala_41", "classes.json"]),
        Jason.encode!(%{"classes" => [%{"vanilla_id" => "fighter", "changes" => changes}]})
      )

      Loader.load!(dir)["siala_41"]
    end
  end
end
