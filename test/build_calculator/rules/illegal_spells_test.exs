defmodule BuildCalculator.Rules.IllegalSpellsTest do
  @moduledoc """
  `Rules.illegal_spells/2` and `Rules.lost_slot_picks/2` (task 4.63) — a known
  spell its level cannot hold, on both rulesets.

  The defect (found in task 4.62): a Sorcerer 1 with his six spells chosen, then
  the class of level 1 switched to Fighter. The spells stayed in `build.spells`;
  the builder's ladder hid them (it draws a level's spells off the slots the level
  grants), but the levelling guide and the export printed «01: Fighter(1): [0]
  Electric jolt, …», `Spells.known/2` counted them, and the next Sorcerer levels
  refused them as already known. The core named such a spell with nothing — the
  `illegal_*` family had no member for spells.

  Which spells a level offers is the class's `spells_known` table read off the
  ruleset (`Spells.slots_at/3`: the difference between the row of this class level
  and the row before it — Sorcerer 1 four of circle 0 and two of circle 1, Sorcerer
  2 one more of circle 0, Bard 1 four of circle 0; `fandom:Sorcerer` revid 71586,
  `fandom:Bard`), and which circle a spell is for a class is its spell list
  (`Spells.list_for/2`). Both rulesets carry the same tables for both classes; the
  one difference this file leans on is Siala's own 41st level, where no spell is
  chosen (`epic.spell_selection_at_41`, wiki «41-ый уровень» revid 20387).

  Every build here is assembled the way the builder assembles it: a class level
  through `validate_level_up/3`, a spell into a free slot of its own circle off
  the class's list — so «named» never means «was illegal from the start». The
  edits are the builder's own: `Build.replace_level/3` on an early level.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Spells}

  @versions ["siala_41", "vanilla"]
  @abilities %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18}

  # Sorcerer 1's six: four cantrips and two of circle 1. `electric_jolt` and
  # `ray_of_frost` are on the Sorcerer's list and not on the Bard's; `flare` and
  # `daze` are on both (checked below, not assumed).
  @sorcerer_1 [:electric_jolt, :ray_of_frost, :flare, :daze, :burning_hands, :grease]

  setup_all do
    %{rulesets: Map.new(@versions, &{&1, Data.ruleset!(&1)})}
  end

  defp start(ruleset),
    do:
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        base_abilities: @abilities
      )

  # One level-up the builder's way, and the spells into the new level's slots in
  # order — each one off the class's list at the slot's circle, as `pick_spell`
  # offers it.
  defp level_up(build, class, ruleset, spells \\ []) do
    assert Rules.validate_level_up(build, class, ruleset) == :ok
    build = Build.add_level(build, class)
    level = Build.character_level(build)
    slots = Spells.slots_at(build, ruleset, level)
    assert length(spells) <= length(slots)

    picks =
      for {slot, spell} <- Enum.zip(slots, spells), into: %{} do
        assert spell in circle_list(ruleset, class, slot.circle),
               "#{spell} is not a #{class} spell of circle #{slot.circle}"

        {slot.id, spell}
      end

    if picks == %{}, do: build, else: %Build{build | spells: Map.put(build.spells, level, picks)}
  end

  defp circle_list(ruleset, class, circle),
    do: for(%{id: id, circle: ^circle} <- Spells.list_for(ruleset, class), do: id)

  defp sorcerer_2(ruleset) do
    ruleset
    |> start()
    |> level_up(:sorcerer, ruleset, @sorcerer_1)
    |> level_up(:sorcerer, ruleset, [:light])
  end

  # What the core calls «the level grants no such slot» — the yardstick
  # `lost_slot_picks/2` has to match, reason and all.
  defp not_granted(build, ruleset) do
    for {_level, _slot, _spell, {:spell_slot_not_granted, _, _}} = pick <-
          Rules.illegal_spells(build, ruleset),
        do: pick
  end

  for version <- @versions do
    @version version

    describe "#{version}" do
      setup %{rulesets: rulesets}, do: %{ruleset: Map.fetch!(rulesets, @version)}

      test "control: the build as the builder made it is named by nothing", %{ruleset: ruleset} do
        build = sorcerer_2(ruleset)

        assert Rules.illegal_spells(build, ruleset) == []
        assert Rules.lost_slot_picks(build, ruleset) == %{feats: [], spells: []}
        assert MapSet.new(@sorcerer_1 ++ [:light]) == Spells.known(build, 2)
      end

      test "level 1 → Fighter: all six spells, no slot of either circle", %{ruleset: ruleset} do
        edited = Build.replace_level(sorcerer_2(ruleset), 1, :fighter)
        assert Spells.slots_at(edited, ruleset, 1) == []

        slots =
          [{:circle, 0, 0}, {:circle, 0, 1}, {:circle, 0, 2}, {:circle, 0, 3}] ++
            [{:circle, 1, 0}, {:circle, 1, 1}]

        # A Fighter's level grants none of either circle: `granted` is 0 for all
        # six, the second cantrip as much as the first.
        lost =
          for {{:circle, circle, _} = slot, spell} <- Enum.zip(slots, @sorcerer_1),
              do: {1, slot, spell, {:spell_slot_not_granted, circle, 0}}

        assert Rules.illegal_spells(edited, ruleset) == lost

        # Level 2 is now the FIRST Sorcerer level: its own `{:circle, 0, 0}` is
        # granted there again (Sorcerer 1 has four of circle 0), and Light stays.
        assert Rules.lost_slot_picks(edited, ruleset) == %{feats: [], spells: lost}
      end

      test "level 1 → Bard: circle 1 lost, two cantrips off the Bard's list", %{ruleset: ruleset} do
        # The lists, asked rather than assumed (task 4.63's own premise had Flare
        # off the Bard's list; it is on it in both rulesets).
        bard_0 = circle_list(ruleset, :bard, 0)
        assert :flare in bard_0 and :daze in bard_0
        refute :electric_jolt in bard_0 or :ray_of_frost in bard_0

        edited = Build.replace_level(sorcerer_2(ruleset), 1, :bard)

        assert Enum.map(Spells.slots_at(edited, ruleset, 1), & &1.id) ==
                 for(i <- 0..3, do: {:circle, 0, i})

        assert Rules.illegal_spells(edited, ruleset) == [
                 {1, {:circle, 0, 0}, :electric_jolt, {:not_on_spell_list, :bard, 0}},
                 {1, {:circle, 0, 1}, :ray_of_frost, {:not_on_spell_list, :bard, 0}},
                 {1, {:circle, 1, 0}, :burning_hands, {:spell_slot_not_granted, 1, 0}},
                 {1, {:circle, 1, 1}, :grease, {:spell_slot_not_granted, 1, 0}}
               ]

        # Only a lost SLOT is a lost pick: the two cantrips stand in slots the
        # level grants (their chips show them, ✕ clears them).
        assert Rules.lost_slot_picks(edited, ruleset).spells == [
                 {1, {:circle, 1, 0}, :burning_hands, {:spell_slot_not_granted, 1, 0}},
                 {1, {:circle, 1, 1}, :grease, {:spell_slot_not_granted, 1, 0}}
               ]
      end

      # The renumbering: a class taken earlier makes every later level of it a
      # level higher, and the new row offers fewer new spells.
      test "Fighter 1 / Sorcerer 1 → level 1 made Sorcerer: level 2's extra slots lost",
           %{ruleset: ruleset} do
        build =
          ruleset
          |> start()
          |> level_up(:fighter, ruleset)
          |> level_up(:sorcerer, ruleset, @sorcerer_1)

        assert Rules.illegal_spells(build, ruleset) == []

        edited = Build.replace_level(build, 1, :sorcerer)
        assert Enum.map(Spells.slots_at(edited, ruleset, 2), & &1.id) == [{:circle, 0, 0}]

        # Sorcerer 2 grants ONE new cantrip and nothing of circle 1 — the count
        # rides in the reason, so «only 1» can be said about the three lost ones.
        assert Rules.illegal_spells(edited, ruleset) == [
                 {2, {:circle, 0, 1}, :ray_of_frost, {:spell_slot_not_granted, 0, 1}},
                 {2, {:circle, 0, 2}, :flare, {:spell_slot_not_granted, 0, 1}},
                 {2, {:circle, 0, 3}, :daze, {:spell_slot_not_granted, 0, 1}},
                 {2, {:circle, 1, 0}, :burning_hands, {:spell_slot_not_granted, 1, 0}},
                 {2, {:circle, 1, 1}, :grease, {:spell_slot_not_granted, 1, 0}}
               ]

        assert Rules.lost_slot_picks(edited, ruleset).spells == not_granted(edited, ruleset)
        assert length(not_granted(edited, ruleset)) == 5
      end

      # The slot is there, the circle is not the class's: Lesser dispel is a
      # Sorcerer's circle 2 and a Bard's circle 1 (`list_for/2`).
      test "a spell the new class puts on another circle", %{ruleset: ruleset} do
        assert :lesser_dispel in circle_list(ruleset, :sorcerer, 2)
        assert :lesser_dispel in circle_list(ruleset, :bard, 1)

        build =
          ruleset
          |> start()
          |> level_up(:sorcerer, ruleset)
          |> level_up(:sorcerer, ruleset)
          |> level_up(:sorcerer, ruleset)
          |> level_up(:sorcerer, ruleset, [:light, :lesser_dispel])

        assert Map.get(build.spells, 4) == %{
                 {:circle, 0, 0} => :light,
                 {:circle, 2, 0} => :lesser_dispel
               }

        assert Rules.illegal_spells(build, ruleset) == []

        bard = Enum.reduce(1..4, build, &Build.replace_level(&2, &1, :bard))

        # Bard 4: two new of circle 2 and none of circle 0 (`fandom:Bard`).
        assert Enum.map(Spells.slots_at(bard, ruleset, 4), & &1.id) ==
                 [{:circle, 2, 0}, {:circle, 2, 1}]

        assert Rules.illegal_spells(bard, ruleset) == [
                 {4, {:circle, 0, 0}, :light, {:spell_slot_not_granted, 0, 0}},
                 {4, {:circle, 2, 0}, :lesser_dispel, {:not_on_spell_list, :bard, 2}}
               ]
      end

      # Past the build's end and below the first level the builder never puts a
      # spell; a link edited by hand can, and the core names it all the same.
      test "levels past the end of the build and level 0 grant no slot", %{ruleset: ruleset} do
        build = sorcerer_2(ruleset)

        ahead = %Build{
          build
          | spells: Map.put(build.spells, 3, %{{:circle, 0, 0} => :resistance})
        }

        zero = %Build{build | spells: Map.put(build.spells, 0, %{{:circle, 0, 0} => :resistance})}

        lost_3 = {3, {:circle, 0, 0}, :resistance, {:spell_slot_not_granted, 0, 0}}
        lost_0 = {0, {:circle, 0, 0}, :resistance, {:spell_slot_not_granted, 0, 0}}

        assert Rules.illegal_spells(ahead, ruleset) == [lost_3]
        assert Rules.illegal_spells(zero, ruleset) == [lost_0]
        assert Rules.lost_slot_picks(ahead, ruleset).spells == [lost_3]
        assert Rules.lost_slot_picks(zero, ruleset).spells == [lost_0]

        # Control: once level 3 is a Sorcerer's the level is there, and still
        # grants no cantrip — Sorcerer 3 adds one of circle 1 only.
        three = Build.add_level(ahead, :sorcerer)
        assert Enum.map(Spells.slots_at(three, ruleset, 3), & &1.id) == [{:circle, 1, 0}]
        assert not_granted(three, ruleset) == [lost_3]
      end

      test "feats and spells in one answer", %{ruleset: ruleset} do
        human = Build.put_feat(sorcerer_2(ruleset), 1, :racial, :iron_will)
        assert Rules.illegal_feats(human, ruleset) == []

        edited = %Build{Build.replace_level(human, 1, :fighter) | race: :elf}

        assert %{feats: [{1, :racial, :iron_will}], spells: [_, _, _, _, _, _]} =
                 Rules.lost_slot_picks(edited, ruleset)
      end
    end
  end

  # Siala's 41st level grants no choice of spells (`selectable_level?/2`), while
  # vanilla's 40th does: the same Sorcerer 20 on the top level, one data flag apart.
  test "the top level: Siala's 41st grants no spell slot, vanilla's 40th does", %{
    rulesets: rulesets
  } do
    for {version, fighters} <- [{"siala_41", 21}, {"vanilla", 20}] do
      ruleset = Map.fetch!(rulesets, version)

      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :true_neutral,
          base_abilities: @abilities,
          levels: List.duplicate(:fighter, fighters) ++ List.duplicate(:sorcerer, 20)
        )

      top = Build.character_level(build)
      build = %Build{build | spells: %{top => %{{:circle, 9, 0} => :time_stop}}}
      assert :time_stop in circle_list(ruleset, :sorcerer, 9)

      expected =
        if version == "siala_41",
          do: [{top, {:circle, 9, 0}, :time_stop, {:spell_slot_not_granted, 9, 0}}],
          else: []

      assert Rules.illegal_spells(build, ruleset) == expected, version
    end
  end

  # Положительный контроль сверки с ядром: `not_granted/2` и `lost_slot_picks/2`
  # выше сравниваются на непустом — иначе равенство пустого с пустым прошло бы
  # и у ядра, которое ничего не называет.
  test "control: an edited build gives a non-empty answer", %{rulesets: rulesets} do
    ruleset = Map.fetch!(rulesets, "siala_41")
    edited = Build.replace_level(sorcerer_2(ruleset), 1, :fighter)

    assert length(not_granted(edited, ruleset)) == 6
    assert length(Rules.lost_slot_picks(edited, ruleset).spells) == 6
  end
end
