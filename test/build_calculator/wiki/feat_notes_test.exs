defmodule BuildCalculator.Wiki.FeatNotesTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.FeatNotes

  # Verbatim, minus the `{{feat}}` template header (irrelevant here) — the
  # actual `== Notes ==` bullet from `priv/wiki_cache/fandom/Knockdown.wikitext`
  # (source of Improved knockdown's own ban sentence too — word for word).
  @knockdown """
  == Notes ==

  * This feat cannot be used while wielding a [[ranged weapon]].
  * The prone state lasts for one [[round]] (minus the [[flurry]] in which the knockdown was made).
  * Since monks receive this feat automatically, it cannot be selected when gaining a monk level (even prior to level 6).
  * The combat log will report a knockdown attempt as '''*resisted*''' if the target won the opposed check.

  == Builder notes ==

  '''Item feat:''' yes
  """

  # `priv/wiki_cache/fandom/Improved two-weapon fighting.wikitext`.
  @improved_two_weapon_fighting """
  == Notes ==
  *Since rangers receive this feat automatically, it cannot be selected when gaining a ranger level (even prior to receiving it automatically).
  * The [[dual-wield (feat)|dual-wield]] feat does not satisfy this feat's prerequisites.
  """

  # `priv/wiki_cache/fandom/Blinding speed.wikitext` — the one shape with a
  # linked class name and no accompanying grant sentence at all.
  @blinding_speed """
  == Notes ==
  *Requires [[Hordes of the Underdark]].
  *This feat cannot be selected when taking a level of [[Harper scout]].
  * The haste effect is subject to [[dispel]]ling.
  """

  # `priv/wiki_cache/fandom/Favored enemy.wikitext` — "cannot be selected" is
  # about which RACE, not which class, and the shape must not match it.
  @favored_enemy """
  == Notes ==
  * When a favored enemy is gained, the player selects a [[race]] to be that favored enemy. There are 24 favored enemy races available; of the 25 standard races, only [[ooze]] cannot be selected.
  """

  # `priv/wiki_cache/fandom/Epic skill focus.wikitext` — narrows a BONUS pool
  # for one skill variant, a different mechanic (AGENT_QUEUE.md §1.10).
  @epic_skill_focus """
  ==Notes==
  * ''Epic skill focus'' in ''use magic device'' cannot be selected as a rogue [[bonus feat]], but otherwise bonus feat availability matches [[general feat]] availability.
  """

  # The boilerplate 42 of the 48 `Category:Feats restricted by class` pages
  # carry, under a DIFFERENT section title — must never be read as a ban.
  @custom_content_only """
  == Custom content notes ==
  * A custom class must have this feat in their feat list, or that class will not be able to select it as a general feat.
  """

  describe "forbidden_by_class/1" do
    test "gaining shape: Knockdown names monk" do
      assert FeatNotes.forbidden_by_class(@knockdown) == [
               {"monk",
                "Since monks receive this feat automatically, it cannot be selected when " <>
                  "gaining a monk level (even prior to level 6)."}
             ]
    end

    test "gaining shape: Improved two-weapon fighting names ranger" do
      assert FeatNotes.forbidden_by_class(@improved_two_weapon_fighting) == [
               {"ranger",
                "Since rangers receive this feat automatically, it cannot be selected when " <>
                  "gaining a ranger level (even prior to receiving it automatically)."}
             ]
    end

    test "taking shape: Blinding speed names Harper scout, and the quote keeps the link" do
      assert [{name, quote}] = FeatNotes.forbidden_by_class(@blinding_speed)

      # The link TARGET, not a stripped display string — the same reading
      # `unavailable_feat_targets/1` and `proficiency_targets/1` both use.
      assert name == "Harper scout"
      assert quote == "This feat cannot be selected when taking a level of [[Harper scout]]."
    end

    test "Favored enemy's race sentence matches neither shape" do
      assert FeatNotes.forbidden_by_class(@favored_enemy) == []
    end

    test "Epic skill focus's bonus-pool sentence matches neither shape" do
      assert FeatNotes.forbidden_by_class(@epic_skill_focus) == []
    end

    test "a page with no Notes section at all reads empty" do
      assert FeatNotes.forbidden_by_class("{{feat|type=general|desc=whatever}}") == []
    end

    test "Custom content notes' boilerplate is a different section and is never read" do
      # Same boilerplate phrase family as the real pages ("will not be able to
      # select"), scoped OUT because it lives under a title that is not
      # `Notes` — the scoping this module's moduledoc names as the point of
      # reading `Notes` specifically rather than the whole page.
      assert FeatNotes.forbidden_by_class(@custom_content_only) == []
    end
  end

  describe "mentions_cannot_be_selected?/1 — the canary report_feat_class_bans/1 uses" do
    test "true for a page forbidden_by_class/1 already reads" do
      assert FeatNotes.mentions_cannot_be_selected?(@knockdown)
    end

    test "true for a page that says the phrase but means something else — the point of the canary" do
      assert FeatNotes.mentions_cannot_be_selected?(@favored_enemy)
      assert FeatNotes.mentions_cannot_be_selected?(@epic_skill_focus)
    end

    test "false when the phrase sits outside Notes entirely" do
      refute FeatNotes.mentions_cannot_be_selected?(@custom_content_only)
    end

    test "false for an ordinary page" do
      refute FeatNotes.mentions_cannot_be_selected?(
               @improved_two_weapon_fighting
               |> String.replace("cannot be selected", "is automatic")
             )
    end
  end
end
