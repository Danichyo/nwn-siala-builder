defmodule BuildCalculator.Wiki.EpicRulesTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.EpicRules

  # Stand-ins for the character-level pages, cut down to eight epic levels so the
  # arithmetic stays checkable by eye: attack bonus on the odd levels (21, 23, 25,
  # 27), saves on the even ones (22, 24, 26, 28), a general feat every three
  # levels and an ability increase every four.
  @level_progression """
  The level progression described here is based solely on character level.

  {| class="centertable" style="text-align:center"
  |-
  !Level
  !Required<br />XP
  !Max skill<br />rank
  !Cross-class<br />max
  !General<br />feats
  !Ability<br />increase
  |-
  |18 || 153,000 || 21 || 10 || 7th ||&nbsp;
  |-
  |19 || 171,000 || 22 || 11 ||&nbsp;||&nbsp;
  |-
  |20 || 190,000 || 23 || 11 ||&nbsp;|| 5th
  |}

  == Epic progression ==

  {| class="centertable" style="text-align:center"
   |-
    !Level
    !Required<br />XP
    !Epic save<br />bonus
    !Epic attack<br />bonus
    !Max skill<br />rank
    !Cross-class<br />max
    !General<br />feats
    !Ability<br />increases
   |-
    |21 || 210,000 || 0 || 1 || 24 || 12 || 8th ||&nbsp;
   |-
    |22 || 231,000 || 1 || 1 || 25 || 12 ||&nbsp;||&nbsp;
   |-
    |23 || 253,000 || 1 || 2 || 26 || 13 ||&nbsp;||&nbsp;
   |-
    |24 || 276,000 || 2 || 2 || 27 || 13 || 9th || 6th
   |-
    |25 || 300,000 || 2 || 3 || 28 || 14 ||&nbsp;||&nbsp;
   |-
    |26 || 325,000 || 3 || 3 || 29 || 14 ||&nbsp;||&nbsp;
   |-
    |27 || 351,000 || 3 || 4 || 30 || 15 || 10th ||&nbsp;
   |-
    |28 || 378,000 || 4 || 4 || 31 || 15 ||&nbsp;|| 7th
  |}
  """

  @base_attack """
  '''Base attack''' ('''BA''') is a measure of offensive combat ability.

  == Epic characters ==

  After level 20, base attack increases at every odd character level regardless of class. (This is similar to how [[base save]]s progress after level 20.) It is added to whatever the base attack was at level 20 (with no additional attacks per round granted).
  {| class="centertable" style="text-align:center"
   |+ Epic base attack progression
   |-
     ! Character level
     | 21 || 23 || 25 || 27
   |-
     ! Epic attack bonus
     | +1 || +2 || +3 || +4
  |}
  This means that an [[epic character]]'s base attack may depend on the order in which classes were taken.
  """

  @base_save """
  '''Base saves''' are ratings of how capable a creature is at avoiding certain attacks.

  After a character reaches (character) level 20, his base saves cease being affected by which classes advance in level. Instead, all three base saves increase +1 at each even ''character'' level (starting at level 22).

  {| class="centertable" style="text-align:center"
   |+ Epic base save progression
   |-
     ! Character level
     | 22 || 24 || 26 || 28
   |-
     ! Epic base save
     | +1 || +2 || +3 || +4
  |}

  == Multiclassing benefits ==

  To receive the base save benefits of multiclassing, the additional classes must be taken prior to character level 21.
  """

  @prose %{
    "Ability score" =>
      "In addition, every four [[character level]]s a single ability score can be increased by one.\n",
    "Attacks per round" =>
      "Even though BAB continue to increase at epic levels, a character's maximum number of attacks is determined by his or her BAB at [[character level]] 20.\n",
    "Base attack bonus" =>
      "In either case, though, additional attacks are not gained after level 20.\n",
    "Bonus feat" =>
      "An '''epic bonus feat''' is a bonus feat choice obtained because of an [[epic class]] level.\n",
    "Character level" =>
      "Installing ''[[Hordes of the Underdark]]'' raises this limit to 40, allowing epic levels.\n",
    "Epic character" => "Characters become epic characters once they have gained 21 levels.\n",
    "Epic class" =>
      "To become epic with a specific [[class]] the character must have 21 levels for a base class, or 11 levels for a [[prestige class]].\n\n[[Harper scout]]s and [[purple dragon knight]]s are only able to attain five levels and may never become epic.\n",
    "General feat" =>
      "The first general feat is chosen at character creation, and additional ones are gained with every three character levels.\n",
    "Hit point" =>
      "At [[character level]]s 1 through 3, a PC gains base hit points equal to the maximum possible roll of the [[hit die]].\n",
    "Prestige class" =>
      "Prestige classes are limited to 10 [[class level]]s through [[character level]] 20.\n",
    "Skill point" =>
      "Each class has a number of skill points (from 2 to 8) it receives each level.\n" <>
        "The maximum number of ranks a class skill can be raised to is character level plus three,\n" <>
        "while the maximum for a cross-class skill is half this number, rounded down.\n",
    "Unarmed base attack bonus" =>
      "As with the regular BAB, this special UBAB is based upon the base attack achieved at level 20.\n"
  }

  defp wiki(overrides \\ %{}) do
    pages =
      @prose
      |> Map.merge(%{
        "Level progression" => @level_progression,
        "Base attack" => @base_attack,
        "Base save" => @base_save
      })
      |> Map.merge(overrides)

    for {title, wikitext} <- pages, wikitext != nil do
      {%{title: title, revid: 1, fetched: "2026-08-01"}, wikitext}
    end
  end

  defp get(json, path) do
    Enum.reduce(path, json, fn key, {:obj, pairs} ->
      pairs |> List.keyfind(key, 0) |> elem(1)
    end)
  end

  describe "parse/1" do
    test "reads the epic attack bonus off the odd levels and the saves off the even ones" do
      %{json: json, problems: problems} = EpicRules.parse(wiki())

      assert problems == []

      assert get(json, ["epic_attack_bonus", "levels"]) == [21, 23, 25, 27]
      assert get(json, ["epic_attack_bonus", "parity"]) == "odd"
      assert get(json, ["epic_attack_bonus", "level_step"]) == 2
      assert get(json, ["epic_attack_bonus", "bonus_step"]) == 1

      assert get(json, ["epic_save_bonus", "levels"]) == [22, 24, 26, 28]
      assert get(json, ["epic_save_bonus", "parity"]) == "even"
      assert get(json, ["epic_save_bonus", "applies_to"]) == ["fortitude", "reflex", "will"]
    end

    test "records that class levels taken after 20 add neither base attack nor base saves" do
      %{json: json} = EpicRules.parse(wiki())

      assert get(json, ["epic_attack_bonus", "added_to_base_attack_at_character_level"]) == 20
      assert get(json, ["epic_attack_bonus", "class_levels_after_20_add_base_attack"]) == false

      assert get(json, ["epic_attack_bonus", "class_order_raw"]) =~
               "order in which classes were taken"

      assert get(json, ["epic_save_bonus", "added_to_base_saves_at_character_level"]) == 20
      assert get(json, ["epic_save_bonus", "class_levels_after_20_add_base_saves"]) == false
      assert get(json, ["epic_save_bonus", "multiclass_raw"]) =~ "prior to character level 21"
    end

    test "reads the per-level table and cross-checks it against both series" do
      %{json: json} = EpicRules.parse(wiki())

      assert get(json, ["level_table", "status"]) == "parsed"
      assert length(get(json, ["level_table", "rows"])) == 8

      assert get(json, ["level_table", "rows"]) |> hd() ==
               {:obj,
                [
                  {"character_level", 21},
                  {"required_xp", 210_000},
                  {"epic_attack_bonus", 1},
                  {"epic_save_bonus", 0},
                  {"max_skill_rank", 24},
                  {"cross_class_max_rank", 12},
                  {"general_feat", 8},
                  {"ability_increase", nil}
                ]}
    end

    test "reports a disagreement between the two pages instead of picking a winner" do
      levels =
        String.replace(
          @level_progression,
          "|23 || 253,000 || 1 || 2 ||",
          "|23 || 253,000 || 1 || 3 ||"
        )

      %{json: json, problems: problems} =
        EpicRules.parse(wiki(%{"Level progression" => levels}))

      assert get(json, ["level_table", "status"]) == "conflict"

      assert get(json, ["level_table", "conflict_note"]) =~
               "epic attack bonus at level 23: Level progression says 3"

      assert Enum.any?(problems, &(&1 =~ "level_table: epic attack bonus at level 23"))
    end

    test "keeps the cadence of general feats and ability increases across level 20" do
      %{json: json} = EpicRules.parse(wiki())

      assert get(json, ["general_feats", "epic_levels"]) == [21, 24, 27]
      assert get(json, ["general_feats", "every_n_levels"]) == 3
      assert get(json, ["general_feats", "continues_pre_epic_cadence"]) == true
      assert get(json, ["general_feats", "total_by_character_level_40"]) == 10

      assert get(json, ["ability_increases", "epic_levels"]) == [24, 28]
      assert get(json, ["ability_increases", "every_n_levels"]) == 4
      assert get(json, ["ability_increases", "continues_pre_epic_cadence"]) == true
    end

    test "checks the skill rank caps against every row rather than assuming the formula" do
      %{json: json} = EpicRules.parse(wiki())

      assert get(json, ["skill_ranks", "max_rank_formula"]) == "character_level + 3"
      assert get(json, ["skill_ranks", "cross_class_max_rank_formula"]) == "floor(max_rank / 2)"
      assert get(json, ["skill_ranks", "verified_for_character_levels"]) == 11
    end

    test "reports a rank cap that does not follow the formula" do
      levels =
        String.replace(
          @level_progression,
          "|25 || 300,000 || 2 || 3 || 28 ||",
          "|25 || 300,000 || 2 || 3 || 29 ||"
        )

      %{json: json, problems: problems} =
        EpicRules.parse(wiki(%{"Level progression" => levels}))

      assert get(json, ["skill_ranks", "max_rank_formula"]) == nil
      assert get(json, ["skill_ranks", "status"]) == "conflict"
      assert Enum.any?(problems, &(&1 =~ "max skill rank is not character level + 3"))
    end

    test "a value stated only in prose disappears with the sentence that stated it" do
      %{json: json} = EpicRules.parse(wiki(%{"Attacks per round" => "Rewritten by an editor.\n"}))

      assert get(json, ["attacks_per_round", "attacks_per_round_raw"]) == nil
      assert get(json, ["attacks_per_round", "epic_bonus_adds_attacks"]) == nil
      assert get(json, ["attacks_per_round", "determined_by_bab_at_character_level"]) == nil
      # The other pages still say their part, so their quotes stay.
      assert get(json, ["attacks_per_round", "base_attack_bonus_raw"]) =~
               "not gained after level 20"
    end

    test "reports a page it needs but the cache does not have" do
      %{json: json, problems: problems} = EpicRules.parse(wiki(%{"Base save" => nil}))

      assert "page not cached: Base save" in problems
      assert get(json, ["epic_save_bonus", "table"]) == nil
      assert get(json, ["epic_save_bonus", "levels"]) == nil
      assert get(json, ["epic_save_bonus", "status"]) == "conflict"

      assert get(json, ["epic_save_bonus", "sources"]) == [
               {:obj,
                [{"wiki", "fandom"}, {"page", "Base save"}, {"revid", nil}, {"fetched", nil}]}
             ]
    end

    test "leaves level 41 unanswered rather than continuing the tables" do
      %{json: json} = EpicRules.parse(wiki())

      for block <-
            ~w(epic_attack_bonus epic_save_bonus general_feats ability_increases skill_ranks) do
        assert get(json, [block, "at_character_level_41"]) == nil
      end

      assert get(json, ["character_level_cap"]) == 40
      assert get(json, ["skill_points", "epic_override"]) == nil
      assert get(json, ["hit_points", "epic_override"]) == nil
      assert get(json, ["open_questions"]) != []
    end
  end
end
