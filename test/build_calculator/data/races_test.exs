defmodule BuildCalculator.Data.RacesTest do
  @moduledoc """
  Guards `vanilla/races.json`'s size, tower-shield ban and large-weapon ban —
  AGENT_QUEUE.md §3.44, the third parser gap of its kind after the red dragon
  disciple's hit die (3.37) and weapon grip (3.40): the fact was on the page,
  it just never became a field. Task 3.43 (запрет «двуручное оружие + щит»,
  a `dev-rules` task, not this one) is the reason these fields exist at all.

  Two of the seven playable races (gnome, halfling) state their own size in so
  many words — a `Small stature` bullet neither Dwarf, Elf, Half-elf, Half-orc
  nor Human carries — and the other five are Medium by elimination over the
  closed set `Category:Playable races` names. Both readings are cross-checked
  against a second, independent page at parse time
  (`Mix.Tasks.Wiki.Parse.verify_small_stature_races!/2`); what is pinned here
  is the outcome as committed, not the parser's internals.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data

  @races "priv/rules/vanilla/races.json" |> File.read!() |> Jason.decode!()
  @weapons "priv/rules/vanilla/weapons.json" |> File.read!() |> Jason.decode!()

  @small ~w(gnome halfling)
  @medium ~w(dwarf elf half_elf half_orc human)

  defp race(id), do: Enum.find(@races, &(&1["id"] == id))

  describe "size" do
    test "all seven playable races are present, and no more" do
      assert Enum.sort(Enum.map(@races, & &1["id"])) == Enum.sort(@small ++ @medium)
    end

    test "gnome and halfling are small, the other five are medium" do
      for id <- @small, do: assert(race(id)["size"] == "small", id)
      for id <- @medium, do: assert(race(id)["size"] == "medium", id)
    end

    # ⚠️ AGENT_QUEUE.md §3.44 forbids deriving `size` from `small_stature`
    # sitting in `bonus_feats` — a fit is not a race property, and nobody
    # declared that link. Both small races happen to carry the feat AND state
    # their size in prose; this only pins that the prose reading exists on
    # its own, not that it was shortcut through the feat list.
    test "size is not merely mirroring small_stature in bonus_feats" do
      for id <- @small do
        assert "small_stature" in race(id)["bonus_feats"], id
      end

      for id <- @medium do
        refute "small_stature" in race(id)["bonus_feats"], id
      end
    end

    test "small is verified from the race's own page; medium is derived by elimination" do
      for id <- @small, do: assert(race(id)["size_status"] == "verified", id)
      for id <- @medium, do: assert(race(id)["size_status"] == "derived", id)
    end

    test "every race carries a quote and a source for its size" do
      for r <- @races do
        assert is_binary(r["size_raw"]), r["id"]
        assert is_binary(r["size_source"]["page"]), r["id"]
        assert is_integer(r["size_source"]["revid"]), r["id"]
      end
    end

    test "small races are sourced from their own page; medium races from Weapon size" do
      for id <- @small do
        assert race(id)["size_source"]["page"] == race(id)["source"]["page"], id
      end

      for id <- @medium do
        assert race(id)["size_source"]["page"] == "Weapon size", id
      end
    end

    # `size_note` is OUR reasoning, not a wiki quote — present only where the
    # citation needs explaining (the five races no page names "medium" by
    # name), silent where a race's own page already says it outright.
    test "size_note explains only the derived five" do
      for id <- @small, do: assert(race(id)["size_note"] == nil, id)

      for id <- @medium do
        assert race(id)["size_note"] =~ "Category:Playable races", id
      end
    end
  end

  describe "the two legality bans" do
    test "small races cannot use tower shields or large weapons" do
      for id <- @small do
        assert race(id)["cannot_use_tower_shields"] == true, id
        assert race(id)["cannot_use_large_weapons"] == true, id
      end
    end

    # `false`, not `nil` — the source is explicit that the ban is exclusive to
    # gnome and halfling ("this only excludes large weapons from gnomes and
    # halflings"), so "the other five may use both" is a sourced answer, not
    # a guess filling in for a missing one.
    test "medium races carry an explicit false, not a missing answer" do
      for id <- @medium do
        assert race(id)["cannot_use_tower_shields"] == false, id
        assert race(id)["cannot_use_large_weapons"] == false, id
      end
    end

    test "a small race's ban quote is verbatim off its own page, sub-bullets included" do
      for id <- @small do
        assert race(id)["size_raw"] =~ "Cannot use [[tower shield]]s.", id
        assert race(id)["size_raw"] =~ "Cannot use [[weapon size|large weapons]].", id
      end
    end

    # AGENT_QUEUE.md §3.44: "не «двуручно», а «нельзя взять вовсе»" — the ban
    # is a separate fact from grip, not a rename of `two_handed`.
    test "the large-weapon ban is not recorded as a grip value" do
      refute Map.has_key?(race("gnome"), "grip")
      refute Map.has_key?(race("gnome"), "two_handed")
    end
  end

  # AGENT_QUEUE.md §3.44's own instruction: `_grip.player_character_sizes` in
  # `weapons.json` must stop being a second, silent source of the same fact.
  describe "`_grip.player_character_sizes` in weapons.json" do
    test "still states the two races in prose, for a human reader" do
      grip = @weapons["_grip"]

      assert grip["player_character_sizes"]["small"] =~ "halfling"
      assert grip["player_character_sizes"]["medium"] =~ "gnome and halfling"
    end

    test "its note now points at races.json as the machine answer" do
      assert @weapons["_grip"]["_note"] =~ "vanilla/races.json"
      assert @weapons["_grip"]["_note"] =~ "size"
    end

    # The invariant the note promises: if this ever disagrees with
    # `races.json`, `mix wiki.parse` fails before either file is committed
    # (`verify_grip_race_sizes!/1`, in `weapon_grip_block/2`) — this only pins
    # that, right now, the two files still agree.
    test "agrees with races.json's own small set" do
      from_races = @races |> Enum.filter(&(&1["size"] == "small")) |> Enum.map(& &1["id"])

      assert Enum.sort(from_races) == Enum.sort(@small)
    end
  end

  describe "the loader still accepts the file" do
    test "vanilla and siala_41 both build a ruleset with all seven races" do
      for version <- ["vanilla", "siala_41"] do
        races = Data.ruleset!(version).races
        ids = races |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort()

        assert ids == Enum.sort(@small ++ @medium), version
      end
    end
  end
end
