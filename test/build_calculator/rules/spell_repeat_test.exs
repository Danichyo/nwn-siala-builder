defmodule BuildCalculator.Rules.SpellRepeatTest do
  @moduledoc """
  `Rules.illegal_spells/2` names a known spell its class already knows, and
  `Spells.already_known/3` answers the builder's list with the same tuple (task
  4.64), on both rulesets.

  The defect (found in task 4.63): a Sorcerer 1 / Sorcerer 2 with Daze chosen on
  level 2, then the player went back to level 1. Level 1 offered Daze as free —
  the list asked `Spells.known/2` for the levels BEFORE it only — and the click
  put it in again; the link and the export carried Daze twice, and the core named
  nothing.

  Who is named: the LATER of two picks, as with feats (CLAUDE.md §9 — the answer
  of the game, blaming the earlier was turned down by Dan): the level-up the game
  would have refused is the one that came second. Two picks on one level — the
  later slot.

  Per class: a class's known spells are a list of its own (NWN:EE `nwscript.nss`,
  `GetIsInKnownSpellList(oCreature, nClassType, nSpellId)`), so a Bard's Daze and
  a Sorcerer's Daze are not a repeat. Whether the Sorcerer's level-up offers what
  the Bard knows no source in hand says — an open question, and the test pins
  today's answer so a change is a decision, not a drift.

  Which slots a level offers and which circle a spell is for a class are the
  ruleset's (`Spells.slots_at/3`, `Spells.list_for/2`; `fandom:Sorcerer` revid
  71586, `fandom:Bard`) — asked below, not assumed.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Spells}

  @versions ["siala_41", "vanilla"]
  @abilities %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18}

  # Sorcerer 1's six — four cantrips, two of circle 1 — with Daze among them.
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

  # One level-up the builder's way, the spells into the level's slots in order,
  # each off the class's list at the slot's circle. No «already known» check
  # here on purpose: this is how a link from before task 4.64 could look.
  defp level_up(build, class, ruleset, spells) do
    assert Rules.validate_level_up(build, class, ruleset) == :ok
    build = Build.add_level(build, class)
    put_spells(build, ruleset, Build.character_level(build), spells)
  end

  defp put_spells(build, ruleset, level, spells) do
    class = Build.class_at(build, level)
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

  # Sorcerer 1 / Sorcerer 2 with `spell` chosen on level 2 — Sorcerer 2 grants
  # one new cantrip.
  defp sorcerer_2(ruleset, spell) do
    ruleset
    |> start()
    |> level_up(:sorcerer, ruleset, @sorcerer_1)
    |> level_up(:sorcerer, ruleset, [spell])
  end

  for version <- @versions do
    @version version

    describe "#{version}" do
      setup %{rulesets: rulesets}, do: %{ruleset: Map.fetch!(rulesets, @version)}

      test "control: different spells on both levels — nothing named", %{ruleset: ruleset} do
        build = sorcerer_2(ruleset, :light)

        assert Rules.illegal_spells(build, ruleset) == []

        # What the class knows is every pick, each at its own level — the
        # level-2 Light too, which a list on level 1 must refuse.
        known = Spells.already_known(build, ruleset, :sorcerer)
        assert map_size(known) == 7
        assert known[:daze] == {:spell_already_known, :sorcerer, 1}
        assert known[:light] == {:spell_already_known, :sorcerer, 2}

        # A class the build does not have knows nothing.
        assert Spells.already_known(build, ruleset, :bard) == %{}
      end

      test "the repro: Daze on levels 1 and 2 — level 2 named, pointing at 1", %{
        ruleset: ruleset
      } do
        assert :daze in circle_list(ruleset, :sorcerer, 0)
        build = sorcerer_2(ruleset, :daze)

        assert Rules.illegal_spells(build, ruleset) == [
                 {2, {:circle, 0, 0}, :daze, {:spell_already_known, :sorcerer, 1}}
               ]

        # The list's refusal is the same tuple the check names.
        assert Spells.already_known(build, ruleset, :sorcerer)[:daze] ==
                 {:spell_already_known, :sorcerer, 1}

        # Not a lost slot: the level grants it, the builder must not take it out.
        assert Rules.lost_slot_picks(build, ruleset) == %{feats: [], spells: []}
      end

      test "two slots of one level — the later slot named", %{ruleset: ruleset} do
        level_1 = [:electric_jolt, :daze, :flare, :daze]

        build =
          ruleset
          |> start()
          |> level_up(:sorcerer, ruleset, level_1)

        assert Rules.illegal_spells(build, ruleset) == [
                 {1, {:circle, 0, 3}, :daze, {:spell_already_known, :sorcerer, 1}}
               ]
      end

      test "three of one spell — both later ones point at the first", %{ruleset: ruleset} do
        build =
          ruleset
          |> start()
          |> level_up(:sorcerer, ruleset, [:daze, :daze])
          |> level_up(:sorcerer, ruleset, [:daze])

        assert Rules.illegal_spells(build, ruleset) == [
                 {1, {:circle, 0, 1}, :daze, {:spell_already_known, :sorcerer, 1}},
                 {2, {:circle, 0, 0}, :daze, {:spell_already_known, :sorcerer, 1}}
               ]
      end

      # Per class (`Spells.known_reason/0`): Bard 1 with Daze, Sorcerer 1 on
      # level 2 with Daze — two lists, nothing named, and each class's list
      # refuses only its own.
      test "Bard 1 / Sorcerer 1, Daze in both — not a repeat", %{ruleset: ruleset} do
        assert :daze in circle_list(ruleset, :bard, 0)

        build =
          ruleset
          |> start()
          |> level_up(:bard, ruleset, [:daze, :flare, :light, :resistance])
          |> level_up(:sorcerer, ruleset, [:daze, :electric_jolt, :ray_of_frost, :acid_splash])

        assert Rules.illegal_spells(build, ruleset) == []

        assert Spells.already_known(build, ruleset, :bard)[:daze] ==
                 {:spell_already_known, :bard, 1}

        assert Spells.already_known(build, ruleset, :sorcerer)[:daze] ==
                 {:spell_already_known, :sorcerer, 2}

        # Control on the same build: the Sorcerer's own repeat is still named.
        repeat = put_spells(Build.add_level(build, :sorcerer), ruleset, 3, [:daze])

        assert Rules.illegal_spells(repeat, ruleset) == [
                 {3, {:circle, 0, 0}, :daze, {:spell_already_known, :sorcerer, 2}}
               ]
      end

      # Only a pick that stands is known: one its level grants no slot for is not
      # known to the class, and the same spell on another level is no repeat.
      test "a pick in a lost slot does not make a repeat", %{ruleset: ruleset} do
        build = sorcerer_2(ruleset, :daze)
        edited = Build.replace_level(build, 1, :fighter)

        daze = for {_, _, :daze, _} = entry <- Rules.illegal_spells(edited, ruleset), do: entry

        # Level 1 is a Fighter's: its Daze is lost, level 2's (now Sorcerer 1)
        # stands — and is what the class knows.
        assert daze == [{1, {:circle, 0, 3}, :daze, {:spell_slot_not_granted, 0, 0}}]

        assert Spells.already_known(edited, ruleset, :sorcerer)[:daze] ==
                 {:spell_already_known, :sorcerer, 2}
      end

      # The same about a pick off the class's list at that circle: Daze in a slot
      # of circle 1 (a hand-edited link) is not a Sorcerer's circle-1 spell, so
      # the class does not know it from there.
      test "a pick off the class's list does not make a repeat", %{ruleset: ruleset} do
        build = sorcerer_2(ruleset, :daze)

        edited = %Build{
          build
          | spells:
              Map.put(build.spells, 1, %{
                {:circle, 0, 0} => :electric_jolt,
                {:circle, 1, 0} => :daze
              })
        }

        assert Rules.illegal_spells(edited, ruleset) == [
                 {1, {:circle, 1, 0}, :daze, {:not_on_spell_list, :sorcerer, 1}}
               ]
      end
    end
  end

  # Положительный контроль сверки список ↔ проверка: на каждом билде выше, где
  # ядро называет повтор, `already_known/3` его класса отдаёт ровно тот кортеж —
  # иначе список отказывал бы одной фразой, а лестница ставила ⚠ другой.
  test "every repeat named is the list's own refusal", %{rulesets: rulesets} do
    ruleset = Map.fetch!(rulesets, "siala_41")

    build =
      ruleset
      |> start()
      |> level_up(:sorcerer, ruleset, [:daze, :daze, :flare, :flare])
      |> level_up(:sorcerer, ruleset, [:flare])

    named =
      for {_, _, _, {:spell_already_known, _, _}} = e <- Rules.illegal_spells(build, ruleset),
          do: e

    assert length(named) == 3

    for {_level, _slot, spell, reason} <- named do
      assert Spells.already_known(build, ruleset, :sorcerer)[spell] == reason
    end
  end
end
