defmodule BuildCalculator.Wiki.SkillPageTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.SkillPage

  # A stand-in skill page carrying every shape the 28 real ones mix: an image
  # line above the prose, a lead sentence that opens in bold (which a plain label
  # reader would mistake for a label of its own), bullets with and without a
  # space after the marker, labels written as links, the colon inside the bold
  # and outside it, a value that runs on to the next line, an unrecognised label,
  # and a trailing category link with no heading to hide behind.
  @page """
  [[Image:Isk testing.gif|right|Testing]]
  '''Testing''' is a skill invented for this test.
  *'''Ability''': [[dexterity]]

  * '''Classes''': [[bard]], [[Harper scout]], [[rogue]]

  *'''[[Cross-class skill|Cross-class]]''': yes

  *'''[[untrained skill check|Requires training]]:''' no

  *'''Check''': A roll against a [[difficulty class]].
  Continued on the next line.

  *'''Special''': [[Armor check penalty|Wearing armor]] hurts.

  *'''Spectacular failure''': The tester trips over.

  *'''Use''': Select the skill.
  [[Category:skills]]

  ==Notes==
  *'''Ability''': a second Ability label down here must not win.
  """

  describe "parse/1" do
    test "reads the bullet labels whatever punctuation the page used" do
      parsed = SkillPage.parse(@page)

      assert parsed.key_ability == "DEX"
      assert parsed.key_ability_raw == "[[dexterity]]"
      assert parsed.trained_only == false
      assert parsed.trained_only_raw == "no"
      assert parsed.cross_class_raw == "yes"
      assert parsed.classes_raw == "[[bard]], [[Harper scout]], [[rogue]]"
      assert parsed.special_raw == "[[Armor check penalty|Wearing armor]] hurts."
      assert parsed.problems == []
    end

    test "keeps a label's value that runs on to the following lines" do
      parsed = SkillPage.parse(@page)

      assert parsed.check_raw ==
               "A roll against a [[difficulty class]].\nContinued on the next line."
    end

    test "does not let page furniture leak into the last label" do
      parsed = SkillPage.parse(@page)

      assert parsed.use_raw == "Select the skill."
    end

    test "reads the lead prose as the description, image line and all removed" do
      parsed = SkillPage.parse(@page)

      assert parsed.description == "'''Testing''' is a skill invented for this test."
    end

    test "names the classes by link target, whatever the display text" do
      parsed = SkillPage.parse(@page)

      assert parsed.classes == ["bard", "Harper scout", "rogue"]
      assert parsed.classes_all? == false
    end

    test "reads a class list of 'all' as a flag rather than a list" do
      parsed = SkillPage.parse("*'''Ability''': [[wisdom]]\n*'''Classes''': all\n")

      assert parsed.classes == []
      assert parsed.classes_all? == true
      assert parsed.classes_raw == "all"
    end

    test "keeps unrecognised labels instead of dropping them" do
      parsed = SkillPage.parse(@page)

      assert parsed.extra_labels == [{"spectacular failure", "The tester trips over."}]
    end

    test "a page with no Ability label is not a skill and is not a problem either" do
      parsed =
        SkillPage.parse("""
        A '''class skill''' is a [[skill]] closely related to the role of a [[class]].
        [[Category:Skills]]
        """)

      assert parsed.key_ability_raw == nil
      assert parsed.classes_raw == nil
      assert parsed.problems == []
    end

    test "lists what the page did not provide rather than filling it in" do
      parsed = SkillPage.parse("*'''Ability''': [[dexterity]]\n")

      assert parsed.classes_raw == nil
      assert parsed.check_raw == nil
      assert parsed.use_raw == nil
      assert parsed.trained_only == nil

      assert parsed.problems == [
               "no 'check' label",
               "no 'classes' label",
               "no 'requires training' label",
               "no 'use' label"
             ]
    end

    test "reports rather than guesses when a label stops saying what it used to" do
      parsed =
        SkillPage.parse("""
        *'''Ability''': [[luck]]
        *'''Classes''': [[bard]]
        *'''[[untrained skill check|Requires training]]''': only for [[bard]]s
        *'''Check''': none
        *'''Use''': none
        """)

      assert parsed.key_ability == nil
      assert parsed.key_ability_raw == "[[luck]]"
      assert parsed.trained_only == nil

      assert parsed.problems == [
               "unknown ability name: [[luck]]",
               "'requires training' is neither yes nor no: only for [[bard]]s"
             ]
    end
  end

  describe "armor_check_skills/1" do
    test "reads the one sentence that says which skills armor hinders" do
      page = """
      An '''armor check penalty''' applies to most [[dexterity]]-based [[skill]]s when a
      character wears [[armor]] heavier than leather, and it applies to [[hide]],
      [[move silently]], [[parry]], [[pick pocket]], [[set trap]], and [[tumble]]. The only
      dexterity-based skills not on this list are [[open lock]] and [[ride]].
      """

      assert SkillPage.armor_check_skills(page) ==
               ["hide", "move silently", "parry", "pick pocket", "set trap", "tumble"]
    end

    test "an unrecognised sentence yields nil, not an empty list" do
      assert SkillPage.armor_check_skills("Armor makes some skills harder.\n") == nil
    end
  end
end
