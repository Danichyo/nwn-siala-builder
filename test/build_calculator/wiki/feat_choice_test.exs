defmodule BuildCalculator.Wiki.FeatChoiceTest do
  @moduledoc """
  The curated decisions about repeatable feats, and the guards that keep them
  honest when the wiki moves underneath them.

  The point of these tests is not that the table is right — a human read the
  pages for that — but that a table which has drifted from its sources fails
  loudly. A quote that no longer exists, a prerequisite that no longer applies
  and a newly repeatable feat nobody classified must all be errors, because each
  of them otherwise ends as a silent wrong answer in a build.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.FeatChoice

  defp texts(overrides) do
    Map.merge(%{use: nil, description: nil, page: ""}, overrides)
  end

  describe "decide/2 — the repeat itself" do
    test "reads the statement out of `use` and names the domain" do
      source =
        "automatic. This feat may be selected multiple times, but the effects do not " <>
          "[[stack]]. It applies to a different school of magic in each case."

      assert {:repeatable, decided} = FeatChoice.decide("spell_focus", texts(%{use: source}))

      assert decided.choice == "spell_school"
      assert decided.distinct == true

      assert decided.quote ==
               "This feat may be selected multiple times, but the effects do not [[stack]]. " <>
                 "It applies to a different school of magic in each case."
    end

    # ⚠ The counterexample the core needs: everywhere else a repeat means a new
    # value, and here ten helpings of the same damage type is how the cap is
    # reached. A model that assumed otherwise would reject a legal build.
    test "records a repeat that may reuse the same value" do
      source =
        "The character gains [[damage resistance|resistance]] 10 to the selected damage type. " <>
          "This feat may be taken multiple times, to a maximum of 100 resistance to each damage type."

      assert {:repeatable, decided} =
               FeatChoice.decide("epic_energy_resistance", texts(%{description: source}))

      assert decided.choice == "energy_type"
      assert decided.distinct == false
    end

    # The ranger is told he keeps choosing enemies and never told they must
    # differ. Absence of the key is the honest answer, and the core's own gap
    # covers it (CLAUDE.md §3, rule 1).
    test "leaves `distinct` unset where the page settles it neither way" do
      source = "automatic. The ranger may choose additional favored enemies every 5 levels."

      assert {:repeatable, decided} = FeatChoice.decide("favored_enemy", texts(%{use: source}))

      assert decided.choice == "creature_type"
      refute Map.has_key?(decided, :distinct)
    end

    test "a repeat with nothing to choose gets a nil domain rather than a guess" do
      source = "The character gains 20 hit points. This feat may be taken multiple times."

      assert {:repeatable, %{choice: nil}} =
               FeatChoice.decide("epic_toughness", texts(%{description: source}))
    end

    test "an unclassified feat gets no key at all" do
      assert FeatChoice.decide("power_attack", texts(%{use: "automatic"})) == :none
    end
  end

  describe "decide/2 — the undecided" do
    # Every epic variant lands here: `use` on all of them is the bare word
    # "automatic" while the base feat spells the repeat out. Reasoning from the
    # base feat to the epic one is exactly the analogy §3 forbids.
    test "quotes the choice and refuses to call it repeatable" do
      source = "The character gains a +2 bonus to all [[attack roll]]s with the chosen weapon."

      assert {:raw, quote} =
               FeatChoice.decide("epic_weapon_focus", texts(%{description: source}))

      assert quote == source
    end
  end

  describe "decide/2 — drift" do
    test "raises when the sentence a decision rests on is gone" do
      assert_raise RuntimeError, ~r/no longer in its use/, fn ->
        FeatChoice.decide("spell_focus", texts(%{use: "automatic."}))
      end
    end

    # The wiki wraps `Self concealment` between "may" and "be". A quote must not
    # inherit the column width of its source, and a phrase must not fail to match
    # because of it.
    test "a sentence broken across lines still matches and comes back flat" do
      source = "The character gains 10% concealment. This feat may\nbe taken multiple times."

      assert {:repeatable, %{quote: quote}} =
               FeatChoice.decide("self_concealment", texts(%{description: source}))

      assert quote == "This feat may be taken multiple times."
    end
  end

  describe "same_choice_as/3" do
    test "names the feats that must share this feat's choice" do
      assert %{feats: ["spell_focus"], supersedes: "(selected spell school)"} =
               FeatChoice.same_choice_as(
                 "greater_spell_focus",
                 "[[spell focus]] (selected [[spell school]])",
                 ["spell_focus"]
               )
    end

    test "keeps the phrase it was read from as provenance" do
      assert %{quote: "(selected [[spell school]])"} =
               FeatChoice.same_choice_as(
                 "greater_spell_focus",
                 "[[spell focus]] (selected [[spell school]])",
                 ["spell_focus"]
               )
    end

    # Weapons are not modelled at all, so nothing would check the constraint in
    # place of the caveat. Suppressing it would make six feats look verified
    # while nothing verifies them.
    test "the weapon family keeps its caveat" do
      assert %{supersedes: nil} =
               FeatChoice.same_choice_as(
                 "epic_weapon_focus",
                 "21st level, [[weapon focus]] with the chosen weapon",
                 ["weapon_focus"]
               )
    end

    test "a feat with no entry gets nothing" do
      assert FeatChoice.same_choice_as("power_attack", "[[strength]] 13", []) == nil
    end

    test "raises when the phrase has left the prerequisites" do
      assert_raise RuntimeError, ~r/no longer in its prerequisites/, fn ->
        FeatChoice.same_choice_as("greater_spell_focus", "[[spell focus]]", ["spell_focus"])
      end
    end

    test "raises when a feat it names is no longer required" do
      assert_raise RuntimeError, ~r/no longer requires/, fn ->
        FeatChoice.same_choice_as(
          "greater_spell_focus",
          "[[spell focus]] (selected [[spell school]])",
          []
        )
      end
    end
  end

  describe "unclassified/1" do
    test "reports a feat that discusses repetition and is in no table" do
      by_id = %{"new_feat" => texts(%{page: "This feat may be taken multiple times."})}

      assert FeatChoice.unclassified(by_id) == ["new_feat"]
    end

    # ⚠ The four that matter most. `Armor skin` says "could be taken multiple
    # times, but the Neverwinter Nights version can be taken only once" — a
    # pattern that treated it as a signal would allow an illegal build, so it is
    # classified as a denial rather than left looking unexamined.
    test "the classified denials do not come back as unclassified" do
      by_id =
        Map.new(FeatChoice.not_repeatable_ids(), fn id ->
          {id, texts(%{page: "could be taken multiple times ... can be taken only once"})}
        end)

      assert FeatChoice.unclassified(by_id) == []
    end

    test "every denial explains why its phrase is not an endorsement" do
      for id <- FeatChoice.not_repeatable_ids() do
        assert is_binary(FeatChoice.denial_reason(id)), id
      end
    end

    test "a feat that never mentions repetition is not reported" do
      by_id = %{"power_attack" => texts(%{page: "The character trades attack for damage."})}

      assert FeatChoice.unclassified(by_id) == []
    end
  end

  describe "check!/1" do
    test "raises when a feat the table names is not in the snapshot at all" do
      assert_raise RuntimeError, ~r/absent from the feat snapshot/, fn ->
        FeatChoice.check!(%{})
      end
    end
  end
end
