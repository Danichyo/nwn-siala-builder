defmodule BuildCalculatorWeb.Builder.GameLogImportTest do
  @moduledoc """
  Task 3.111, second pass: does a `.билд` chat dump turn into a build that
  matches the log, not a plausible-looking one.

  `BuildCalculator.GameLogTest` already pins that the sixteen real fixtures
  read completely (`problems == []`); this file pins the harder question —
  once read, does the ladder land in the right order, do a level's grants get
  told apart from what the player chose, and does a feat taken *with*
  something (`Weapon Focus (bastard sword)`) keep the something.

  Every number asserted below is either checked by hand against the raw
  fixture text (the same discipline `GameLogTest` holds itself to) or derived
  from another part of the very same fixture that was independently pinned
  there — `skill_ranks`, for one, is compared against the sum of
  `SKILLS WITH RANKS`'s own printed totals, not a number pulled out of a
  debugging run.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, GameLog, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{GameLogImport, PointBuy}

  @ruleset Data.ruleset!()

  defp fixture(name) do
    "../../fixtures/game_logs/#{name}.log" |> Path.expand(__DIR__) |> File.read!()
  end

  defp parsed(name), do: GameLogImport.parse(fixture(name), @ruleset)

  # A function boundary rather than an inline `@ruleset.races[race]` at the
  # call site — the inline form makes the compiler's own type checker try to
  # narrow the WHOLE ruleset literal's enormous structural type right there
  # and print an unhelpful warning on an otherwise-correct result; this
  # reads the same field, wrapped so the warning does not show up for
  # `race_out`/`also_increases_out`'s own describe block below.
  defp race_ability_modifiers(ruleset, race),
    do: Map.fetch!(ruleset.races, race).ability_modifiers

  # A `GameLog.level_entry()` built by hand, for the corrupted-input
  # describe block below — the honest way to exercise a shape none of the
  # four real fixtures happens to have, the same technique
  # `BuildCalculator.GameLogTest`'s own `checksum/1` tests use for a
  # `GameLog` struct built directly rather than parsed from text.
  defp entry(level, class, opts \\ []) do
    %{
      level: level,
      class: class,
      class_raw: Keyword.get(opts, :class_raw, class && Atom.to_string(class)),
      ability_increase: Keyword.get(opts, :ability_increase),
      feats: Keyword.get(opts, :feats, []),
      skills: Keyword.get(opts, :skills, [])
    }
  end

  # ------------------------------------------------------ all sixteen fixtures --

  describe "reads all sixteen fixtures into a build" do
    for {name, levels, race} <- [
          {"brunna", 40, :dwarf},
          {"hnyupius", 40, :dwarf},
          {"moxie", 41, :elf},
          {"babuka", 41, :half_orc},
          {"frah_hall", 41, :human},
          {"froim", 41, :halfling},
          {"aley", 20, :human},
          {"elith", 25, :half_elf},
          {"boido", 15, :gnome},
          {"nathan", 14, :human},
          {"timonall", 18, :human},
          {"trina", 15, :human},
          {"hela", 19, :human},
          {"nicha", 24, :human},
          {"hana", 16, :human},
          {"hnyupius_alignment", 40, :dwarf}
        ] do
      test "#{name}.log — ladder, grants and picks all balance" do
        result = parsed(unquote(name))
        read = result.read

        assert read.levels == unquote(levels)
        assert length(result.build.levels) == unquote(levels)
        assert result.build.race == unquote(race)

        # Nothing off the ruleset's own dictionary went unrecognised —
        # `GameLog`'s own `problems == []` for all sixteen fixtures already
        # pins this at the text layer; this pins it survives assembly too.
        assert read.feats_unresolved == 0

        # Every `:feat`-kind token the first pass read is accounted for by
        # exactly one of four buckets: placed in a slot, recognised as an
        # automatic grant (class or race — `feats_auto`), or recognised but
        # not carried over (`feats_not_placed`, always the shard's own
        # disabled vanilla weapon proficiency here, see below). Nothing here
        # is a number pulled from a debugging run — it is arithmetic over
        # what `GameLog` itself already read.
        feat_tokens =
          result.log.levels |> Enum.flat_map(& &1.feats) |> Enum.count(&(&1.kind == :feat))

        assert read.feats_placed + read.feats_auto + read.feats_not_placed +
                 read.feats_unresolved == feat_tokens

        # Trap 3 (CLAUDE.md §6, "Навыки — бюджет, а не каталог"): the ranks
        # this module carried into `Build.skills` are the log's own
        # per-level history, and summing that history must land on exactly
        # the total the log's `SKILLS WITH RANKS` block printed — the
        # character sheet's own checksum, not ours.
        printed_total = Enum.reduce(result.log.skills_with_ranks, 0, &(&1.ranks + &2))
        assert read.skill_ranks == printed_total

        # `Rules.compute/2` never sees a build it cannot finish — the one
        # hard requirement CLAUDE.md §5/§6 place on this module: whatever it
        # hands the core has to be a build the core can compute, not merely
        # one that looks like one.
        stats = Rules.compute(result.build, @ruleset)
        assert is_integer(stats.hp)
        assert is_integer(stats.base_attack)
      end
    end
  end

  # ---------------------------- the gap these fixtures closed, and what is left --

  # 🔴 Здесь стоял describe «the shard's disabled weapon proficiency, recognised
  # and named»: все три лога несли
  # `{:feat_not_placed, 1, :weapon_proficiency_simple, {:feat_disabled, …}}`,
  # и тест требовал этой строки. 26.08.2026 (задача 3.112) выяснилось, что
  # ругался импорт не на дефект лога, а на НАШУ ошибку: шард фит не выключал,
  # а выдаёт его всем классам на 1-м уровне, и именно эти три лога это доказали.
  # Оговорка ушла тем, что мы исправили данные, а не тем, что перестали её
  # печатать, — поэтому тест теперь требует ОБРАТНОГО, и требует поимённо.
  #
  # ⚠️ `hnyupius_alignment` (task 3.173) is the SAME character as `hnyupius`
  # here — same feats, same placements — so it belongs in every generic
  # check this list drives. It is excluded by name from exactly one test
  # below, "а на мировоззрение — по-прежнему жалуется": that is the one
  # place this fixture's own point (`ALIGNMENT:` reading as something other
  # than "unavailable") would make the assertion false, on purpose.
  @all_fixtures ~w(brunna hnyupius moxie babuka frah_hall froim aley elith boido nathan timonall trina hela nicha hana hnyupius_alignment)

  # `hela.log` is the one fixture with a REAL `feat_not_placed` issue of its
  # own (`hit_die_increase`, unrelated to weapon proficiency — see that
  # fixture's own describe block below) — excluded here so this list keeps
  # meaning exactly what its name says: every OTHER fixture places every
  # feat it recognises, with nothing left over.
  @fixtures_with_no_unplaced_feats @all_fixtures -- ["hela"]

  describe "weapon proficiency (simple) раскладывается как выданный" do
    test "ни один лог больше не жалуется на этот фит" do
      for name <- @fixtures_with_no_unplaced_feats do
        result = parsed(name)

        refute Enum.any?(result.issues, &match?({:feat_not_placed, _, _, _}, &1))

        refute Enum.any?(
                 result.issues,
                 &match?({_, _, :weapon_proficiency_simple, _}, &1)
               )

        assert result.read.feats_not_placed == 0

        # Положительный контроль: фит не «потерялся», а доехал до билда —
        # именно выдачей класса, а не потраченным слотом.
        assert MapSet.member?(
                 Build.feats_owned(result.build, @ruleset, length(result.build.levels)),
                 :weapon_proficiency_simple
               )

        refute Enum.any?(result.build.feats, fn {_level, picks} ->
                 :weapon_proficiency_simple in Map.values(picks)
               end)
      end
    end

    # ⚠️ Мировоззрение эти пятнадцать логов не несут вовсе, и это к правке
    # весового фита отношения не имеет — строка остаётся у всех пятнадцати,
    # включая `hela.log`. `hnyupius_alignment` (task 3.173) сюда сознательно
    # НЕ входит: это тот же билд с добавленной строкой `ALIGNMENT:`, и вот
    # он-то и обязан жаловаться ПЕРЕСТАТЬ — проверено ниже как отдельный,
    # положительный контроль.
    test "а на мировоззрение — по-прежнему жалуется" do
      for name <- @all_fixtures -- ["hnyupius_alignment"] do
        assert {:alignment_unavailable} in parsed(name).issues
      end
    end

    # Task 3.173: the shard started printing `ALIGNMENT:` — the last hole
    # `docs/log_coverage.md`'s own plan left. `hnyupius_alignment.log` is
    # the SAME character as `hnyupius.log` right down to the ladder, feats
    # and skill deltas (`GameLogTest`'s own describe block pins that byte
    # comparison) — the only thing that changed is this one line, and this
    # is the one test in the file that cares.
    test "hnyupius_alignment: ALIGNMENT: resolves, and the complaint is gone" do
      result = parsed("hnyupius_alignment")

      assert result.build.alignment == :lawful_good
      refute {:alignment_unavailable} in result.issues
      refute Enum.any?(result.issues, &match?({:unresolved_alignment, _}, &1))
      refute Enum.any?(result.issues, &match?({:unrecognized_line, "ALIGNMENT: " <> _}, &1))

      # The measured price of the gap this line closes (CLAUDE.md §3):
      # Dwarven Defender requires "lawful" on every one of its 23 levels,
      # re-checked level by level (`Rules.illegal_class_levels/2`, not just
      # on the level it was first taken) — `alignment: nil` fails all of
      # them, a real alignment fails none.
      assert Rules.illegal_class_levels(result.build, @ruleset) == []

      without_line = parsed("hnyupius")
      assert without_line.build.alignment == nil
      assert length(Rules.illegal_class_levels(without_line.build, @ruleset)) == 46
    end

    # hnyupius level 39's "Energy Resistance, Fire I" USED TO BE the one place
    # where `GameLog`'s own alias table (its trap 2) folded away the element —
    # `{:feat_argument_missing, 39, :epic_energy_resistance}` named that loss
    # rather than swallowing it. Task 3.118 (27.08.2026) closed the loss at
    # its source (`feat_spelling_aliases/0`'s own moduledoc note): the alias
    # now carries the element as part of its own value, so there is nothing
    # left for `resolve_choice/6` to report here, and hnyupius drops to the
    # one issue every fixture carries — proving the choice actually reached
    # the build, not merely that the issue went quiet, is the point of this
    # test surviving as a POSITIVE assertion rather than being deleted.
    test "hnyupius: Energy resistance's element reaches the build, no issue left to raise" do
      result = parsed("hnyupius")

      refute Enum.any?(result.issues, &match?({:feat_argument_missing, _, _}, &1))
      assert length(result.issues) == 1

      assert Build.feat_choices(result.build, :epic_energy_resistance, 40) == [:fire]
    end

    test "brunna and moxie carry exactly the one general issue, nothing feat-specific extra" do
      for name <- ["brunna", "moxie"] do
        assert length(parsed(name).issues) == 1
      end
    end

    # Task 3.116: before the fix, babuka.log carried 11 issues — the shard's
    # own "BARB" header abbreviation, four arabic-numbered "Damage Reduction
    # N" stages, three "Greater Rage" spellings, and a trailing "+" after a
    # roman numeral (`Uncanny Dodge VI+`) — all of it text-reading, none of
    # it a real gap in the model (`GameLogTest`'s own describe block for this
    # fixture pins each of the four causes on its own). Down to the one every
    # other fixture already carries.
    test "babuka carries exactly the one general issue too, once its own naming resolves" do
      assert length(parsed("babuka").issues) == 1
      assert parsed("babuka").issues == [{:alignment_unavailable}]
    end

    # Task 3.118: before the fix, frah_hall.log carried 13 issues — three
    # unresolved header spellings plus their three `class_missing_from_header`
    # echoes (`SORC`/`DRU`/`Bard`), a "(feat)"-suffix mismatch (`Animal
    # companion`), an element hidden inside a feat's own name (`Resist Sonic
    # Energy`), two element-losing takes of `Epic energy resistance` plus the
    # `already_taken` echo their indistinguishable `nil` arguments produced,
    # and a `Bard Song` reprint on the class's own second level read as a
    # failed duplicate pick — all of it text-reading and one deliberately
    # silenced reprint, none of it a real gap in the model (`GameLogTest`'s
    # own describe block for this fixture pins each cause on its own). Down
    # to the one every other fixture already carries.
    test "frah_hall carries exactly the one general issue too, once its own naming resolves" do
      assert length(parsed("frah_hall").issues) == 1
      assert parsed("frah_hall").issues == [{:alignment_unavailable}]
    end

    # Task 3.119: before the fix, froim.log carried 4 issues — the shard's own
    # "PAL" header abbreviation (plus its `class_missing_from_header` echo,
    # the header's own paladin tally landing on the ladder's paladin count
    # only once the abbreviation resolves) and a "(feat)"-suffix mismatch
    # (`Remove Disease`) — the very fixture that turned that mismatch from
    # three one-off aliases into `GameLog.feat_dictionary/1`'s own general
    # rule (`GameLogTest`'s own describe block for this fixture pins both
    # causes on their own). Down to the one every other fixture already
    # carries.
    test "froim carries exactly the one general issue too, once PAL and Remove Disease resolve" do
      assert length(parsed("froim").issues) == 1
      assert parsed("froim").issues == [{:alignment_unavailable}]
    end

    # Task 3.121: before the fix, aley.log carried 5 issues — the shard's own
    # "HS" header abbreviation (plus its `class_missing_from_header` echo)
    # and the two `Favored Enemy: <type>` picks, unreadable because the value
    # rides after a colon rather than a parenthesis, a comma or a word inside
    # the name (`GameLogTest`'s own describe block for this fixture pins both
    # causes on their own). Also the first fixture under the level cap — 20
    # levels, not 40 or 41 — so this pins the fix on a build the level-cap
    # ones cannot exercise. Down to the one every other fixture already
    # carries.
    test "aley carries exactly the one general issue too, once HS and the colon form resolve" do
      assert length(parsed("aley").issues) == 1
      assert parsed("aley").issues == [{:alignment_unavailable}]
    end

    # Task 3.131: before its own fix, each of these seven carried exactly 3
    # issues — its header abbreviation unresolved, the `class_missing_from_
    # header` echo that follows from it, and `alignment_unavailable` —
    # checked by hand with the new key momentarily removed from
    # `GameLog`'s own `@header_class_abbreviations`, not assumed from the
    # abbreviation's shape. Down to the one every other fixture carries,
    # same as babuka/frah_hall/froim/aley above.
    for name <- ["elith", "boido", "nathan", "timonall", "trina", "nicha", "hana"] do
      test "#{name} carries exactly the one general issue too, once its own abbreviation resolves" do
        assert parsed(unquote(name)).issues == [{:alignment_unavailable}]
      end
    end

    # `hela.log` does NOT belong in the list above — even with "rdd" resolved,
    # it carries a SECOND, real issue: `hit_die_increase` prints three times
    # (RDD's own growing hit die) but the ruleset's own `granted_feats` only
    # names it at one of the three class levels, so one of the three prints
    # falls through to "everything else", finds no open slot (the feat is
    # not normally player-pickable) and gets reported rather than silently
    # dropped — exactly what this module's own honesty discipline promises.
    # Left as a genuine, un-fixed data gap (`priv/rules/*/classes.json`'s own
    # territory, not this file's) — pinned here so a future fix of that gap
    # makes this test fail loudly rather than pass by accident.
    test "hela carries the header issue AND a real, unfixed granted_feats gap" do
      assert parsed("hela").issues == [
               {:feat_not_placed, 9, :hit_die_increase, {:no_free_slot, :hit_die_increase}},
               {:alignment_unavailable}
             ]
    end
  end

  # --------------------------------------------------------- the order trap --

  describe "hnyupius.log: a class level taken well into the epics" do
    test "Fighter's 10th level lands at character level 21, in place" do
      build = parsed("hnyupius").build

      fighter_char_levels =
        build.levels
        |> Enum.with_index(1)
        |> Enum.filter(fn {class, _lvl} -> class == :fighter end)
        |> Enum.map(&elem(&1, 1))

      assert fighter_char_levels == [1, 2, 3, 4, 5, 6, 7, 8, 9, 21]
      assert Build.class_levels(build)[:fighter] == 10
      assert Enum.at(build.levels, 18) == :dwarven_defender
      assert Enum.at(build.levels, 19) == :weapon_master
      assert Enum.at(build.levels, 20) == :fighter
      assert Enum.at(build.levels, 21) == :weapon_master
    end
  end

  # ------------------------------------------------- grants versus real picks --

  describe "trap 1: what the class or race handed over never spends a slot" do
    test "hnyupius level 1: dwarf's racial traits and Fighter's own grants are not slot picks" do
      build = parsed("hnyupius").build

      # Only the general slot is spent, and only on what the player actually
      # chose (Dodge, Luck of Heroes) — nine racial/classal names on the same
      # line (Toughness, Stonecunning, Darkvision, Hardiness ×2, Battle
      # Training ×3, Skill Affinity) hold no slot of their own.
      picks = build.feats |> Map.get(1, %{}) |> Map.values() |> Enum.map(&Build.feat_id/1)

      assert :dodge in picks
      assert :luck_of_heroes in picks
      refute :toughness in picks
      refute :stonecunning in picks
      refute :darkvision in picks
      refute :skill_affinity_lore in picks

      # And the class grant is still true of the finished character — the
      # model derives it, exactly as a build assembled by hand in the
      # constructor would.
      assert :toughness in Build.feats_owned(build, @ruleset, 1)

      # ⚠️ The racial trait is *not* expected here, and that is a fact about
      # `Rules.Build.feats_owned/3` rather than a gap in this module:
      # `bonus_feats` feeds derived stats through its own `{:race_feat, id}`
      # bonus records (`Rules.Bonuses.held?/5`), never through the feat-grant
      # union `feats_owned/3` reads. This module's own job stops at "do not
      # spend a slot on it", which the `refute :stonecunning in picks` above
      # already pins.
      refute :stonecunning in Build.feats_owned(build, @ruleset, 1)
    end

    test "brunna level 1: Wizard's Scribe scroll and Summon familiar are grants, not picks" do
      build = parsed("brunna").build
      picks = build.feats |> Map.get(1, %{}) |> Map.values() |> Enum.map(&Build.feat_id/1)

      assert picks == [:luck_of_heroes]
      assert :scribe_scroll in Build.feats_owned(build, @ruleset, 1)
    end

    test "defensive awareness's numbered stages are all grants, never an argument nor a slot" do
      build = parsed("hnyupius").build

      # Three stages, three different Dwarven Defender levels, none of them
      # in `feats` — `(1)`/`(2)`/`(3)` never becomes a `feat_choice` because
      # `defensive_awareness` has no choice domain to look either up in.
      assert build.feats[11] == nil
      assert build.feats[14] == nil
      assert build.feats[19] == nil
      assert Build.feat_choices(build, :defensive_awareness, 41) == []
      assert :defensive_awareness in Build.granted_feats(build, @ruleset, 19)
    end

    # ⚠️ The required negative control for task 3.116: recognising
    # "Damage Reduction 1", "Greater Rage" and "Uncanny Dodge VI+" is only
    # half the fix — if any of the three rode into a slot instead of being
    # read as the barbarian's own free grant, the build would spend real
    # slots it never had (a general/bonus slot `FeatSlots` would refuse a
    # `type: "class"` ability like these) and turn illegal. Checked across
    # the WHOLE ladder, not just level 1: babuka.log grants
    # `damage_reduction_barbarian` four times (levels 11/15/18/25),
    # `barbarian_rage` seven (1/4/8/12/16/17/25 — the ordinary rage grants at
    # 1/4/8/12 as well as the three "Greater Rage" ones, bare and with a
    # "(Nx per day)" argument alike), and `uncanny_dodge` six
    # (2/5/10/14/17/20).
    test "babuka: damage reduction, greater rage and every uncanny dodge tier never spend a slot" do
      build = parsed("babuka").build
      granted_family = [:damage_reduction_barbarian, :barbarian_rage, :uncanny_dodge]

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      for id <- granted_family do
        refute id in picked_ids, "#{id} was placed in a slot — it should only ever be a grant"

        # Positive companion, same shape as the dwarf/Fighter check above:
        # the model still knows the character has it, derived from the
        # class levels rather than a slot write.
        assert id in Build.feats_owned(build, @ruleset, 41)
      end
    end

    # Task 3.118's own required check: `animal_companion_feat` (Druid's first
    # level) is caught by `classify_feat/8`'s ordinary first clause — nothing
    # new. `bard_song` is the harder case, and the one `reprinted_grant?/4`
    # exists for: the class hands it over once (Bard's own level 1, character
    # level 40), the engine reprints the SAME name on the class's next level
    # too (41), and neither occurrence may spend a slot — the first because
    # it never reaches `to_place` at all, the second because
    # `reprinted_grant?/4` recognises it as the class's own earlier grant
    # rather than a failed duplicate pick.
    test "frah_hall: animal companion and bard song never spend a slot, on EITHER Bard level" do
      build = parsed("frah_hall").build
      granted_family = [:animal_companion_feat, :bard_song]

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      for id <- granted_family do
        refute id in picked_ids, "#{id} was placed in a slot — it should only ever be a grant"
        assert id in Build.feats_owned(build, @ruleset, 41)
      end
    end

    # Task 3.119's own required check, the same shape as the two above:
    # `Remove Disease` is Paladin's own third class level grant
    # (`ruleset.classes.paladin.granted_feats[3] == [:remove_disease_feat,
    # :turn_undead]`), landing at character level 17 in this ladder (level 1
    # is the class's own first, level 16 the second, level 17 the third) —
    # recognising the "(feat)"-suffixed name is only half the fix if it then
    # rode into a slot instead of being read as the free grant it is.
    test "froim: remove disease is Paladin's own third-level grant, never a slot pick" do
      build = parsed("froim").build

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      refute :remove_disease_feat in picked_ids,
             "remove_disease_feat was placed in a slot — it should only ever be a grant"

      assert :remove_disease_feat in Build.feats_owned(build, @ruleset, 41)
    end

    # Task 3.131's own required check: `docs/log_coverage.md`'s Build 1 was
    # built specifically to close Arcane Archer's own class grants — this
    # confirms none of the five rode into a slot, the other half of "closed"
    # besides `GameLogTest`'s own text-level assertion.
    test "elith: Arcane Archer's own class grants never spend a slot" do
      build = parsed("elith").build

      granted_family = [
        :enchant_arrow,
        :imbue_arrow,
        :seeker_arrow,
        :hail_of_arrows,
        :arrow_of_death
      ]

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      for id <- granted_family do
        refute id in picked_ids, "#{id} was placed in a slot — it should only ever be a grant"
        assert id in Build.feats_owned(build, @ruleset, length(build.levels))
      end
    end

    # Same check for Purple Dragon Knight (Build 5) — the class task 3.96
    # once found losing its whole base-attack and save contribution to a
    # missing progression row; this pins the FEAT side never regressed the
    # same way, separately from `GameLogImportTest`'s own derived-stats
    # cross-check below pinning the numeric side.
    test "trina: Purple Dragon Knight's own class grants never spend a slot" do
      build = parsed("trina").build

      granted_family = [
        :rallying_cry,
        :heroic_shield,
        :inspire_courage,
        :fear_feat,
        :oath_of_wrath,
        :final_stand
      ]

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      for id <- granted_family do
        refute id in picked_ids, "#{id} was placed in a slot — it should only ever be a grant"
        assert id in Build.feats_owned(build, @ruleset, length(build.levels))
      end
    end

    # Same check for Shadowdancer (Build 7) — including `Hide in Plain
    # Sight`, the class's own Sialan shift from level 1 to level 4
    # (`GameLogTest`'s own describe block for this fixture pins the shift
    # itself; this pins the resulting grant still never spends a slot).
    test "nicha: Shadowdancer's own class grants never spend a slot" do
      build = parsed("nicha").build

      granted_family = [
        :shadow_daze,
        :summon_shadow,
        :hide_in_plain_sight,
        :shadow_evade,
        :defensive_roll,
        :slippery_mind
      ]

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      for id <- granted_family do
        refute id in picked_ids, "#{id} was placed in a slot — it should only ever be a grant"
        assert id in Build.feats_owned(build, @ruleset, length(build.levels))
      end
    end

    # Same check for Shifter (Build 8) — `Greater Wildshape I`/`II`/`IV` (a
    # separate id per stage) and `Infinite Greater Wildshape` (one id, three
    # ranks) both, the two different schemes `GameLogTest`'s own describe
    # block for this fixture reads apart.
    test "hana: Shifter's own class grants never spend a slot, either numbering scheme" do
      build = parsed("hana").build

      granted_family = [
        :greater_wildshape_i,
        :greater_wildshape_ii,
        :greater_wildshape_iv,
        :infinite_greater_wildshape,
        :humanoid_shape
      ]

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      for id <- granted_family do
        refute id in picked_ids, "#{id} was placed in a slot — it should only ever be a grant"
        assert id in Build.feats_owned(build, @ruleset, length(build.levels))
      end
    end

    # Same check for Red Dragon Disciple (Build 6) — EXCLUDING
    # `hit_die_increase` on purpose: that one is not a clean "always a
    # grant" case today, it is the fixture's own known gap (the standalone
    # test above pins the issue it raises instead). The other five grants
    # are unaffected by that gap and hold the same shape as every class
    # above.
    test "hela: Red Dragon Disciple's own OTHER class grants never spend a slot" do
      build = parsed("hela").build

      granted_family = [
        :draconic_armor,
        :dragon_abilities,
        :dragon_breath,
        :immunity_to_fire,
        :immunity_to_paralysis,
        :immunity_to_sleep
      ]

      picked_ids =
        for {_level, picks} <- build.feats, {_slot, value} <- picks, do: Build.feat_id(value)

      for id <- granted_family do
        refute id in picked_ids, "#{id} was placed in a slot — it should only ever be a grant"
        assert id in Build.feats_owned(build, @ruleset, length(build.levels))
      end

      # `hit_die_increase` specifically: not placed as a slot pick either —
      # it is simply dropped when it fails to place, never silently
      # misfiled — so this half of the "never a slot" promise still holds
      # even for the one grant this fixture's own gap affects.
      refute :hit_die_increase in picked_ids
    end
  end

  # --------------------------------------------------------- feats with a choice --

  describe "trap 2: a parenthesised argument is a choice only when the feat has one" do
    test "Weapon Focus (bastard sword) keeps the weapon, and so does the granted Weapon of choice" do
      build = parsed("hnyupius").build

      assert Build.feat_pick(build, 4, {:class_bonus, :fighter}) ==
               {:weapon_focus, :bastard_sword}

      # `Weapon of choice` at Weapon Master's own level 1 is withheld from
      # `Rules.Build.granted_feats_at/3` by the ruleset's own
      # `grant_substitutions` and opened as a bonus slot instead — it is not
      # a `granted_choices` write, and the choice still survives.
      assert Build.feat_pick(build, 20, {:class_bonus, :weapon_master}) ==
               {:weapon_of_choice, :bastard_sword}

      assert Build.granted_choice(build, 20, :weapon_of_choice) == nil
    end

    test "Spell focus, Greater spell focus and Epic spell focus all keep Necromancy" do
      build = parsed("brunna").build

      assert Build.feat_choices(build, :spell_focus, 41) == [:necromancy]
      assert Build.feat_choices(build, :greater_spell_focus, 41) == [:necromancy]
      assert Build.feat_choices(build, :epic_spell_focus, 41) == [:necromancy]
    end

    test "a bare roman-numeral rank (Great intelligence I..VII) is seven takes, no choice" do
      build = parsed("brunna").build

      assert Build.feat_takes(build, :great_intelligence, 41) == 7
      assert Build.feat_choices(build, :great_intelligence, 41) == List.duplicate(nil, 7)
    end

    # Task 3.118: the element sits INSIDE the feat's own name here ("Resist
    # Sonic Energy"), a third shape alongside the parenthesised weapon above
    # and the comma-suffixed element below — all three reach `Build` through
    # the same `argument` field, because `GameLog`'s own dictionary is what
    # normalises the shape away, not this module.
    test "Resist Sonic Energy keeps the element despite it sitting inside the feat's own name" do
      build = parsed("frah_hall").build
      assert Build.feat_choices(build, :resist_energy, 41) == [:sonic]
    end

    # Task 3.121: a FOURTH shape, a colon rather than a parenthesis, a comma
    # or a word inside the name — "Favored Enemy: Elementals" (ranger's own
    # first level, character level 8) and "Favored Enemy: Giants" (Harper
    # Scout's own first level, character level 10). Both land in the class's
    # own bonus slot, same as `Weapon Focus (bastard sword)` above — the
    # colon is a text-reading question for `GameLog`'s own dictionary
    # (`favored_enemy_aliases/1`), not a new placement rule here.
    test "Favored Enemy: Elementals / : Giants both keep their value, in the class bonus slot" do
      build = parsed("aley").build

      assert Build.feat_pick(build, 8, {:class_bonus, :ranger}) == {:favored_enemy, :elemental}

      assert Build.feat_pick(build, 10, {:class_bonus, :harper_scout}) ==
               {:favored_enemy, :giant}

      assert Build.feat_choices(build, :favored_enemy, 20) == [:elemental, :giant]
    end

    # Two takes of `Epic energy resistance`, both "Fire" — legal per the
    # data's own `distinct?: false` ("Эпическую можно настакивать", CLAUDE.md
    # §6), and the two-take case `feat_spelling_aliases/0`'s own moduledoc
    # names as the reason the fix has to sit in the dictionary rather than in
    # a one-off reading of `raw` here: two DIFFERENT dictionary keys
    # ("energy resistance, fire" matched twice, level 24 and level 26) both
    # carry the SAME element in their own value, exactly as two matches of
    # two DIFFERENT keys would carry two different elements.
    test "Energy Resistance, Fire I then Fire II both land as the fire choice, twice" do
      build = parsed("frah_hall").build
      assert Build.feat_choices(build, :epic_energy_resistance, 41) == [:fire, :fire]
      assert Build.feat_takes(build, :epic_energy_resistance, 41) == 2
    end
  end

  # -------------------------------------------------------------- class choices --

  describe "a domain grant becomes a class choice, not a feat" do
    test "moxie's Cleric picks up War and Travel from level 2's domain markers" do
      build = parsed("moxie").build

      assert Build.class_choice(build, :cleric) == [:war, :travel]
      refute Enum.any?(build.feats |> Map.get(2, %{}) |> Map.values(), &(&1 == :war))
    end
  end

  # -------------------------------------------------------- skills, per level --

  describe "trap 3: skill ranks carry the log's own per-level history" do
    test "hnyupius level 2 is +5 Discipline, level 3 is +1 — not one lump sum" do
      build = parsed("hnyupius").build

      assert build.skills[2] == %{discipline: 5}
      assert build.skills[3] == %{discipline: 1}
      assert build.skills[23] == %{discipline: 1, tumble: 10, heal_skill: 26}
      # Matches the log's own printed "Discipline 43" in SKILLS WITH RANKS —
      # the same cross-check the fixture-wide test above makes generically.
      assert Build.skill_ranks(build, :discipline, 40) == 43
    end
  end

  # ----------------------------------------------------- ability increases --

  describe "the +1 every fourth level" do
    test "hnyupius: ten +1 STR, on the right levels" do
      build = parsed("hnyupius").build

      assert map_size(build.ability_increases) == 10
      assert Enum.uniq(Map.values(build.ability_increases)) == [:str]
      assert Map.has_key?(build.ability_increases, 4)
      assert Map.has_key?(build.ability_increases, 40)
    end
  end

  # ------------------------------------------------------- point buy restored --

  describe "starting ability scores are restored from (WHITE), task 3.172" do
    # `(WHITE) ABILITIES` minus the race's own modifiers and the build's own
    # ability bonuses (`Great …`, a Red Dragon Disciple's own table) is the
    # point-buy purchase — Dan named the formula 03.09.2026, closing the
    # puzzle CLAUDE.md §9 carried since 26.08.2026 (this describe block's own
    # former name, "never guessed", is exactly what stopped being true).
    #
    # ⚠️ 30 is not "close enough to trust" — Dan named it an INVARIANT, not a
    # threshold, twice over: no real character spends anything but exactly
    # the full budget (CLAUDE.md §3, the forced purchase, «иначе игра не
    # даст продвинуться в создании персонажа»; echoed for this exact check,
    # task 3.172, «у абсолютно любого билда все 30 потрачены»). So every one
    # of these sixteen real fixtures is expected to reconstruct to EXACTLY
    # 30, per fixture, not merely "on average" — a single miss would be a
    # finding about this project's own data, never about that one
    # character.
    for {name, race} <- [
          {"brunna", :dwarf},
          {"hnyupius", :dwarf},
          {"moxie", :elf},
          {"babuka", :half_orc},
          {"frah_hall", :human},
          {"froim", :halfling},
          {"aley", :human},
          {"elith", :half_elf},
          {"boido", :gnome},
          {"nathan", :human},
          {"timonall", :human},
          {"trina", :human},
          {"hela", :human},
          {"nicha", :human},
          {"hana", :human},
          {"hnyupius_alignment", :dwarf}
        ] do
      test "#{name}.log: restored starting scores spend exactly the point-buy budget" do
        result = parsed(unquote(name))
        assert result.build.race == unquote(race)

        # No `point_buy_not_restored` issue — the reconstruction trusted
        # itself on every one of the sixteen, not merely on the ones the
        # moduledoc happens to name.
        refute Enum.any?(result.issues, &match?({:point_buy_not_restored, _}, &1))

        assert PointBuy.spent(@ruleset, result.build.base_abilities) == PointBuy.budget(@ruleset)

        for {_ability, score} <- result.build.base_abilities do
          assert score >= PointBuy.min_score(@ruleset)
          assert score <= PointBuy.max_score(@ruleset)
        end

        # The acceptance criterion this task named directly: a build with
        # real starting scores has nothing left refused for LACKING an
        # ability score. `elith`/`timonall`/`hana` keep an unrelated illegal
        # pick each (a weapon-proficiency or skill-rank gap, CLAUDE.md §9) —
        # this only claims the ABILITY-shaped ones are gone, not that the
        # fixture is now spotless.
        ability_refusals =
          result.build
          |> Rules.illegal_feats(@ruleset)
          |> Enum.count(fn {_level, _slot, _feat, reason} ->
            match?({:requires_ability, _, _}, reason)
          end)

        assert ability_refusals == 0
      end
    end

    # The two fragile spots the formula leans on hardest — CLAUDE.md §3's
    # own worked examples for this exact task. Both are ability BONUSES
    # `(WHITE)` bakes in on top of race, and both have to come back out or
    # the reconstructed score overshoots by exactly the bonus — the mistake
    # three older, real builds made (19/22/24 of 30) before this formula was
    # found (CLAUDE.md §9's now-closed open question).
    test "hela.log: Red Dragon Disciple's own class table comes back out, not just race" do
      build = parsed("hela").build

      # `(WHITE) STR 18`, human (no STR modifier), `Dragon abilities` at this
      # class's own ceiling adds `+8` — 18 - 0 - 8 = 10.
      assert build.base_abilities.str == 10
    end

    test "moxie.log: eight takes of Great wisdom come back out, not just race" do
      build = parsed("moxie").build

      # `(WHITE) WIS 26`, elf (no WIS modifier), eight takes of
      # `Great wisdom` add +8 (per-take, capped at +10 by the feat's own
      # page — nowhere near the cap here) — 26 - 0 - 8 = 18.
      assert build.base_abilities.wis == 18
    end
  end

  describe "a mismatch is this project's own gap, never the player's character (task 3.172)" do
    # Built by hand rather than off a real fixture on purpose — a real
    # fixture that ever started failing this check would need FIXING, not a
    # regression test quietly riding along until it does (the same trap
    # CLAUDE.md §9 names for a `not_a_gap` record resting on a live example:
    # the day the example changes, the test stops proving anything).
    test "a (WHITE) that cannot spend exactly 30 keeps the floor, and blames the data" do
      log = %GameLog{
        race: :human,
        white_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
        levels: [entry(1, :fighter)]
      }

      result = GameLogImport.from_log(log, @ruleset)
      floor = PointBuy.min_score(@ruleset)

      # Nothing written — the honest floor, same as before this task.
      assert Enum.all?(result.build.base_abilities, fn {_ability, score} -> score == floor end)

      issue = Enum.find(result.issues, &match?({:point_buy_not_restored, _}, &1))
      assert {:point_buy_not_restored, {:budget_mismatch, 12, 30}} == issue

      text = GameLogImport.issue_text(issue, @ruleset)
      # The coordinator's own clarification, turned into a test: the wording
      # has to say plainly that this is OUR gap, not a fact about the
      # player's own character — no real character spends 12 of 30 at all.
      assert text =~ "пробел в наших данных"
      assert text =~ "не что-то не так с персонажем"
    end

    test "a (WHITE) missing an ability label also keeps the floor" do
      log = %GameLog{
        race: :human,
        white_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10},
        levels: [entry(1, :fighter)]
      }

      result = GameLogImport.from_log(log, @ruleset)
      floor = PointBuy.min_score(@ruleset)

      assert Enum.all?(result.build.base_abilities, fn {_ability, score} -> score == floor end)
      assert {:point_buy_not_restored, :incomplete_white_abilities} in result.issues
    end
  end

  # ---------------------------- derived stats against the engine's own sheet --

  describe "four gearless fixtures: Rules.compute/2 matches COMBAT STATS exactly (task 3.131)" do
    # Every real fixture before `timonall.log` carried gear this project
    # cannot see (`GameLog`'s own moduledoc), so `COMBAT STATS` never had
    # anything honest to compare `Rules.compute/2` against — the difference
    # was always at least the gear's own contribution, unknown by
    # construction. `timonall.log`, `trina.log`, `nicha.log` and `hana.log`
    # are built with no gear at all (Dan, task 3.131's own addenda), which
    # makes this the first REAL check of this project's saves/attack/AC
    # arithmetic against numbers the game engine itself printed, not a wiki
    # page's or another player's build.
    #
    # `(WHITE) ABILITIES` substitutes for `base_abilities` — not `PointBuy`'s
    # floor, and not `CURRENT ABILITIES` either — and `ability_increases` is
    # left exactly as `GameLogImport` already read it off the log, NEVER
    # cleared. That second half matters and was wrong in an earlier version
    # of this test: `(WHITE)` does not carry the log's own `ABILITY: +1 …`
    # bumps at all (CLAUDE.md §3, "Что на самом деле печатает `(WHITE)
    # ABILITIES`"), so `Rules.compute/2` is SUPPOSED to add them on top of
    # `(WHITE)` to reach the same current scores the log's own `CURRENT
    # ABILITIES` prints — clearing them instead only happened to cancel out
    # on `timonall`/`trina`, whose bumps land on INT/CHA, neither of which
    # Fort/Ref/Will/AB/AC read from for a Fighter/Champion of Torm or
    # Fighter/Purple Dragon Knight. `nicha.log` (five WIS bumps, and WIS
    # feeds a Shadowdancer's Will) and `hana.log` (one CON bump, and CON
    # feeds Fort) do not tolerate the mistake — Will and Fort came out two
    # and one short with `ability_increases` cleared, caught by running this
    # very fix against them before trusting it.
    #
    # ⚠️ **Excludes `hela.log` on purpose.** Red Dragon Disciple grants a
    # FLAT class bonus to STR/CON/INT/CHA (`Dragon abilities`), and `(WHITE)`
    # already carries that bonus baked in (same CLAUDE.md §3 note) — feeding
    # `(WHITE)` into `base_abilities` for a build `Rules.compute/2` ALSO adds
    # the same class bonus to (from the build's own RDD levels) double-counts
    # it. Checked by hand: doing it anyway gives STR 26 against the log's own
    # 18, the exact trap CLAUDE.md §3 names by number. None of the other four
    # fixtures' classes (Fighter, Champion of Torm, Purple Dragon Knight,
    # Rogue, Bard, Shadowdancer, Druid, Shifter) grant a flat ability bonus,
    # so this substitution is safe for exactly these four and not general.
    for {name, ab, fort, ref, will, ac} <- [
          {"timonall", 21, 22, 16, 12, 11},
          {"trina", 17, 15, 5, 6, 11},
          {"nicha", 17, 10, 21, 12, 14},
          {"hana", 12, 15, 10, 11, 11}
        ] do
      test "#{name}.log: AB/Fort/Ref/Will/AC AND all six ability scores match the log exactly" do
        result = parsed(unquote(name))
        log = result.log
        %Build{} = build = result.build

        synthetic = %Build{build | base_abilities: log.white_abilities}
        stats = Rules.compute(synthetic, @ruleset)

        assert stats.attack_bonus == unquote(ab)
        assert stats.fort == unquote(fort)
        assert stats.ref == unquote(ref)
        assert stats.will == unquote(will)
        assert stats.ac_naked == unquote(ac)
        assert stats.ac_geared == unquote(ac)

        # The log's own numbers, quoted back at it — this is the promise the
        # test above makes concrete: every value asserted came off
        # `log.combat_stats`, not typed in twice by hand.
        assert log.combat_stats == %{
                 ab: unquote(ab),
                 fort: unquote(fort),
                 refl: unquote(ref),
                 will: unquote(will),
                 ac: unquote(ac)
               }

        # The stronger companion `ability_increases` cleared could never
        # make: not just the four abilities the combat numbers above happen
        # to read from, but all six, matching `CURRENT ABILITIES` exactly —
        # proof `base_abilities` plus the log's own real increases really is
        # the log's own current character, not a number that merely happens
        # to agree on the five that were checked.
        assert stats.abilities == log.current_abilities
      end
    end

    # `trina.log` is also the first LIVE confirmation that Purple Dragon
    # Knight's own ten class levels all count toward base attack and
    # saves — exactly the place task 3.96 found the class's Sialan
    # progression table missing past its vanilla five-row length, which
    # would have dropped this contribution to ZERO for a class taken past
    # character level 5, not merely undercounted it (that task's own note).
    test "trina.log: all ten of Purple Dragon Knight's own levels count, not five" do
      result = parsed("trina")
      breakdown = Rules.compute(result.build, @ruleset).bab_breakdown

      pdk = Enum.find(breakdown.by_class, &(&1.class == :purple_dragon_knight))
      assert pdk.levels_counted == 10
      assert pdk.levels_taken == 10
      assert pdk.levels_ignored == 0
    end

    # Task 3.172's own end-to-end proof: the four tests above all needed a
    # hand-built `synthetic` because `result.build.base_abilities` used to
    # sit on the point-buy floor. Now that it carries the restored starting
    # scores, `Rules.compute/2` on `result.build` ITSELF — no override at
    # all — reaches the same five combat numbers and the same six current
    # abilities the log printed. This is not a new fact about the game (the
    # four tests above already proved the arithmetic); it is the proof that
    # restoring `base_abilities` the way this task does feeds that same
    # arithmetic correctly, on the only four fixtures honest enough
    # (gearless) to check it against.
    for {name, ab, fort, ref, will, ac} <- [
          {"timonall", 21, 22, 16, 12, 11},
          {"trina", 17, 15, 5, 6, 11},
          {"nicha", 17, 10, 21, 12, 14},
          {"hana", 12, 15, 10, 11, 11}
        ] do
      test "#{name}.log: Rules.compute/2 on the IMPORTED build itself matches, no override" do
        result = parsed(unquote(name))
        stats = Rules.compute(result.build, @ruleset)

        assert stats.attack_bonus == unquote(ab)
        assert stats.fort == unquote(fort)
        assert stats.ref == unquote(ref)
        assert stats.will == unquote(will)
        assert stats.ac_naked == unquote(ac)
        assert stats.abilities == result.log.current_abilities
      end
    end
  end

  # ---------------------- the finding that became the behaviour (task 3.172) --

  describe "a point-buy finding from the gearless fixtures (task 3.131 → the formula in task 3.172)" do
    # ⚠️ **No longer "not (yet) a behaviour change" — this describe block's
    # own former title.** The finding below is exactly what `describe
    # "starting ability scores are restored…"` above now writes into
    # `base_abilities` for real, once a build's own class bonuses (`Great
    # …`, a Red Dragon Disciple's own table) are subtracted too. Kept here
    # anyway, narrower and on purpose: these seven fixtures' classes
    # (Sorcerer/Ranger/Arcane Archer, Fighter/Blackguard, Rogue/Assassin,
    # Fighter/Champion of Torm, Fighter/Purple Dragon Knight, Rogue/Bard/
    # Shadowdancer, Druid/Shifter) never touch `AbilityBonuses` at all, so
    # "race alone" reaching the budget is a strictly narrower, independent
    # cross-check of the same seven builds the loop above already covers
    # with the full formula — not a duplicate, because it would still catch
    # a regression the full formula's OWN mistake could hide (an `own_bonus`
    # that wrongly claims a bonus these classes do not have would break
    # this narrower check even if it left the full one looking fine by
    # accident).
    #
    # The finding: `(WHITE) ABILITIES` minus ONLY the race's own ability
    # modifiers — never the log's own recorded level-up `+1`s — spends
    # EXACTLY the point-buy budget (30) on every one of the seven fixtures
    # built to `docs/log_coverage.md`'s own plan whose classes grant no flat
    # ability bonus of their own, across three different races (Half-Elf,
    # Gnome, Human) and one race with real modifiers (Gnome: STR -2 /
    # CON +2). Subtracting the level-up `+1`s ADDITIONALLY (the reading
    # `GameLogImport`'s own moduledoc used to describe before task 3.172,
    # "gear and levels folded in") undershoots on every single one instead —
    # the same shape of undershoot (never an overshoot) the open question in
    # CLAUDE.md §9 recorded for three other, real, geared builds (19/22/24
    # of 30) before Dan named the actual formula. Read together with
    # `hela.log`'s own independent measurement (CLAUDE.md §3, a different
    # task, the same day) — which found the SAME thing from the opposite
    # direction, on a class that DOES grant a flat bonus — those three old
    # builds undershot for the SAME reason: subtracting increases from a
    # value that never had them added in the first place, not because the
    # point-buy table or the budget itself was wrong.
    #
    # ⚠️ **`hela.log` is excluded from this list on purpose** — Red Dragon
    # Disciple's own `Dragon abilities` adds a flat class bonus that
    # `(WHITE)` already carries, so "minus race alone" would overshoot 30
    # there, not confirm it; this file's own "restored" describe block above
    # (and CLAUDE.md §3) work through that case with the actual numbers,
    # `own_bonus` included, instead.
    #
    # ⚠️ This is seven data points from one session, all Dan's own
    # test-server characters built to one plan — not the independent,
    # unrelated-author sample CLAUDE.md's own skill-points lesson asks for
    # before trusting a pattern. The full formula above is checked against
    # all fifteen fixtures instead, eight of them from other sessions.
    for {name, race} <- [
          {"elith", :half_elf},
          {"boido", :gnome},
          {"nathan", :human},
          {"timonall", :human},
          {"trina", :human},
          {"nicha", :human},
          {"hana", :human}
        ] do
      test "#{name}.log: (WHITE) minus race alone spends exactly the point-buy budget" do
        log = parsed(unquote(name)).log
        assert log.race == unquote(race)

        race_mods = race_ability_modifiers(@ruleset, unquote(race))

        race_out =
          for {ability, score} <- log.white_abilities, into: %{} do
            {ability, score - Map.get(race_mods, ability, 0)}
          end

        assert PointBuy.spent(@ruleset, race_out) == PointBuy.budget(@ruleset)

        # The reading `GameLogImport`'s own moduledoc described BEFORE task
        # 3.172 — subtracting the level-up increases TOO — does not reach
        # the budget, on this fixture or any of the other four. Kept here as
        # the negative control: if this ever starts passing, the finding
        # above needs re-reading, not silent deletion.
        increases =
          for %{ability_increase: %{ability: a}} when not is_nil(a) <- log.levels,
              reduce: %{} do
            acc -> Map.update(acc, a, 1, &(&1 + 1))
          end

        also_increases_out =
          for {ability, score} <- race_out, into: %{} do
            {ability, score - Map.get(increases, ability, 0)}
          end

        refute PointBuy.spent(@ruleset, also_increases_out) == PointBuy.budget(@ruleset)
      end
    end
  end

  # ---------------------------------------------------------- corrupted input --

  describe "never raises, and stops the ladder rather than guess past a gap" do
    test "a completely non-string input reads as an empty, honest build" do
      result = GameLogImport.parse(123, @ruleset)

      assert result.build.levels == []
      assert result.build.race == nil
      # `GameLog.parse/2`'s own second clause reports `{:not_a_string}` —
      # spliced straight in, not wrapped, so this module's own
      # `issue_text/2` answers for it directly.
      assert {:not_a_string} in result.issues
      assert GameLogImport.issue_text({:not_a_string}, @ruleset) != ""
    end

    test "an unresolved class stops the ladder, and nothing after it is guessed" do
      log = %GameLog{
        race: :human,
        levels: [entry(1, :fighter), entry(2, nil, class_raw: "Ninja"), entry(3, :fighter)]
      }

      result = GameLogImport.from_log(log, @ruleset)

      assert result.build.levels == [:fighter]
      assert {:ladder_stopped, 2, 1} in result.issues
      # Not "1 из cap" — the *real* level 3 is thrown away rather than
      # silently slid up into position 2, which would corrupt base attack
      # and saves past character level 20 (CLAUDE.md §3).
      assert result.read.levels == 1
    end

    test "more levels than the level cap are clipped, not silently swallowed" do
      cap = @ruleset.level_cap

      log = %GameLog{
        race: :human,
        levels: for(level <- 1..(cap + 3), do: entry(level, :fighter))
      }

      result = GameLogImport.from_log(log, @ruleset)

      assert length(result.build.levels) == cap
      assert {:level_over_cap, cap + 1, cap} in result.issues
    end

    test "a feat name the ruleset has never heard of is reported, not invented" do
      log = %GameLog{
        race: :human,
        levels: [
          entry(1, :fighter,
            feats: [
              %{
                kind: :unknown,
                id: nil,
                raw: "Совершенно неведомый фит",
                argument: nil,
                rank: nil
              }
            ]
          )
        ]
      }

      result = GameLogImport.from_log(log, @ruleset)
      assert result.read.feats_unresolved == 1
      assert result.read.feats_placed == 0
    end

    # Task 3.173: `GameLog.put_alignment/2` can leave `alignment: nil` with
    # `{:unresolved_alignment, raw}` in `problems` — never raised, never
    # guessed. Built by hand rather than through a fixture on purpose: none
    # of the sixteen real dumps carries a value this project has not seen
    # (`GameLogTest`'s own synthetic coverage already pins the `GameLog`
    # layer; this pins that the raw text survives the trip into `issues`
    # AND that the generic "go fill it in" issue still fires, same as it
    # would for a dump with no `ALIGNMENT:` line at all — both are "we do
    # not know", worded differently for a reason: one names what confused
    # the reader, the other tells the player what to do about it).
    test "an ALIGNMENT: value GameLog could not resolve reaches issues, alignment stays nil" do
      log = %GameLog{
        race: :human,
        alignment: nil,
        alignment_raw: "Something Odd",
        problems: [{:unresolved_alignment, "Something Odd"}],
        levels: [entry(1, :fighter)]
      }

      result = GameLogImport.from_log(log, @ruleset)

      assert result.build.alignment == nil
      assert {:unresolved_alignment, "Something Odd"} in result.issues
      assert {:alignment_unavailable} in result.issues

      text = GameLogImport.issue_text({:unresolved_alignment, "Something Odd"}, @ruleset)
      assert text =~ "Something Odd"
    end

    test "every problem GameLog itself can report still gets Russian wording here" do
      for problem <- [
            {:unrecognized_line, "мусор"},
            {:missing_field, :race},
            {:missing_field, "CURRENT ABILITIES"},
            {:field_before_any_level, :feats_raw},
            {:duplicate_field, 1, :feats_raw},
            {:unparsed_header_segment, "???"},
            {:unresolved_header_class, "XYZ"},
            {:unresolved_race, "Полурослик"},
            {:unresolved_alignment, "Нечто странное"},
            {:unresolved_ability_label, "CURRENT ABILITIES", "XYZ"},
            {:incomplete_ability_block, "CURRENT ABILITIES", [:str]},
            {:unresolved_combat_stat_label, "XYZ"},
            {:incomplete_combat_stats, [:ac]},
            {:unresolved_skill_total, "Ремесло"},
            {:unparsed_skill_total, "странно"},
            {:unresolved_class, 5, "Ninja"},
            {:unresolved_ability_increase, 4, "XYZ"},
            {:unexpected_ability_increase_amount, 4, 2},
            {:unresolved_feat, 3, "Неведомый"},
            {:unresolved_skill_delta, 3, "Ремесло"},
            {:header_body_mismatch, :fighter, 10, 9},
            {:class_missing_from_header, :monk, 1},
            {:level_out_of_sequence, 2, 4},
            {:level_duplicate, 1}
          ] do
        text = GameLogImport.issue_text(problem, @ruleset)
        assert text != "", "no wording for #{inspect(problem)}"
        refute text =~ ~r/^\{/, "fell back to inspect/1 for #{inspect(problem)}"
      end
    end
  end

  # ---------------------------------------------------------------- wording --

  describe "issue_text/2 and issue_kind/1 cover every form" do
    test "every form has Russian wording, never a raw tuple" do
      assert length(GameLogImport.issue_forms()) > 20

      for issue <- GameLogImport.issue_forms() do
        text = GameLogImport.issue_text(issue, @ruleset)
        assert text != ""
        refute text =~ ~r/^\{/, "no Russian wording for #{inspect(issue)}"
      end
    end

    test "every form lands in a named group" do
      for issue <- GameLogImport.issue_forms() do
        assert GameLogImport.issue_kind(issue) != ""
      end

      assert GameLogImport.issue_kind({:unrecognized_line, "x"}) == "Пропущенные строки"
      assert GameLogImport.issue_kind({:missing_field, :race}) == "Не хватает данных"
    end
  end
end
