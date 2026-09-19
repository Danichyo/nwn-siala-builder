defmodule BuildCalculator.Wiki.RacePageTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.RacePage

  # A stand-in race page carrying every shape the seven real ones mix: the two
  # spellings of an ability name, a heading whose case differs from the next
  # page's, a bullet whose plural `s` sits outside the link, a bullet with no
  # colon at all, a conditional skill bonus and a bullet with sub-bullets.
  @page """
  [[Image:Testling.jpg|left|Testling]]
  '''Testlings''' are a race invented for this test.

  Testling [[ability]] adjustments: +2 [[Dex]], -2 [[constitution]], -2 [[Cha]]

  [[Favored class]] ([[Rogue]]): A [[Class#Multiclassing|multiclass]] testling's rogue class does not count.

  ==Special Abilities==
  *[[Skill affinity (listen)]]: +2 racial bonus to [[listen]] checks.
  *[[Stonecunning]]: +2 racial bonus on [[Search]] checks made in subterranean areas.
  *[[Immunity to Sleep|Sleeplessness]]: [[Immunity|Immune]] to [[spell]]s of the '[[Sleep]]' subtype.
  *[[Keen Sense]]s: Testlings make active Search checks automatically.
  *[[Weapon Proficiency (Elf)|Bonus Proficiencies]] ([[Longsword]], [[Rapier]])
  *[[Quick to Master]]: 1 extra [[feat]] at 1st level.
  *[[Skilled]]: 4 extra [[skill point]]s at 1st level, plus 1 additional skill point at each following level.
  * [[Small stature]]: Testlings are small creatures.
  ** +1 [[size modifier]] to [[attack roll]]s.
  ** +4 size bonus to standard [[stealth]] and [[detect]]ion checks (modifies [[hide]], [[listen]], and [[spot]]).
  ** Cannot use [[tower shield]]s.
  ** Cannot use [[weapon size|large weapons]].

  ==Notes==
  *A [[Favored class]] (Any) mention down here must not be read as the real one.
  """

  # Human and half-elf: no adjustments line, favored class "(Any)", and the
  # favored class line is a bullet rather than a paragraph.
  @plain_page """
  [[Human]]s are the most adaptable of the common [[race]]s.

  *[[Favored class]] (Any): When determining whether a [[Class#Multiclassing|multiclass]] human suffers an [[Multiclass penalty|XP penalty]], his highest-level class does not count.

  ==Special abilities==
  *[[Darkvision]]: Testlings are able to see in the dark.
  """

  describe "parse/1" do
    test "reads ability adjustments in page order, abbreviated or spelled out" do
      parsed = RacePage.parse(@page)

      assert parsed.ability_modifiers == [{"DEX", 2}, {"CON", -2}, {"CHA", -2}]

      assert parsed.ability_modifiers_raw ==
               "Testling [[ability]] adjustments: +2 [[Dex]], -2 [[constitution]], -2 [[Cha]]"

      assert parsed.problems == []
    end

    test "an absent adjustments line means no modifiers, not an unread field" do
      parsed = RacePage.parse(@plain_page)

      assert parsed.ability_modifiers == []
      assert parsed.ability_modifiers_raw == nil
      assert parsed.problems == []
    end

    test "reads the favored class from the lead, not from the notes" do
      parsed = RacePage.parse(@page)

      assert parsed.favored_class_name == "Rogue"
      assert parsed.favored_class_any? == false
      assert parsed.favored_class_raw =~ "[[Favored class]] ([[Rogue]])"
    end

    test "reads a favored class of (Any) as a flag rather than a class name" do
      parsed = RacePage.parse(@plain_page)

      assert parsed.favored_class_name == nil
      assert parsed.favored_class_any? == true
    end

    test "names every ability by the feat it links to, whatever the display text" do
      parsed = RacePage.parse(@page)

      assert Enum.map(parsed.abilities, & &1.link) == [
               "Skill affinity (listen)",
               "Stonecunning",
               "Immunity to Sleep",
               "Keen Sense",
               "Weapon Proficiency (Elf)",
               "Quick to Master",
               "Skilled",
               "Small stature"
             ]

      assert Enum.map(parsed.abilities, & &1.name) |> Enum.take(5) == [
               "Skill affinity (listen)",
               "Stonecunning",
               "Sleeplessness",
               "Keen Senses",
               "Bonus Proficiencies"
             ]
    end

    test "keeps a bullet's sub-bullets as part of the same ability" do
      parsed = RacePage.parse(@page)

      small = List.last(parsed.abilities)

      assert small.text == "Testlings are small creatures."
      assert small.raw =~ "** Cannot use [[tower shield]]s."
      assert length(parsed.abilities) == 8
    end

    test "structures only the unconditional single-skill bonus" do
      parsed = RacePage.parse(@page)

      assert parsed.skill_bonuses == [{"listen", 2}]
    end

    test "lists the skill bonuses it refused to structure instead of dropping them" do
      parsed = RacePage.parse(@page)

      assert [stonecunning, small_stature] = parsed.skill_bonuses_prose
      assert stonecunning =~ "made in subterranean areas"
      assert small_stature =~ "+4 size bonus"
    end

    test "does not mistake a bonus to saves or attack rolls for a skill bonus" do
      parsed =
        RacePage.parse("""
        ==Special abilities==
        *[[Lucky]]: +1 luck bonus to all [[saving throw]]s.
        *[[Good aim]]: +1 racial bonus to attack rolls made with [[throwing weapon]]s.
        *[[Battle training vs. giants|Defensive training vs. giants]]: +4 dodge bonus to [[armor class|AC]] against [[giant]]s.
        """)

      assert parsed.skill_bonuses == []
      assert parsed.skill_bonuses_prose == []
    end

    test "reads the human extra feat and extra skill points" do
      parsed = RacePage.parse(@page)

      assert parsed.extra_feats == %{level: 1, count: 1}
      assert parsed.bonus_skill_points == %{level: 1, extra: 4, per_level: 1}
    end

    test "leaves the numbers unread when nothing grants them" do
      parsed = RacePage.parse(@plain_page)

      assert parsed.extra_feats == nil
      assert parsed.bonus_skill_points == nil
      assert parsed.skill_bonuses == []
    end

    test "reports rather than guesses when the page does not say what it used to" do
      parsed =
        RacePage.parse("""
        Testling [[ability]] adjustments: +2 [[Vitality]]

        ==Special abilities==
        Not a bullet at all.
        """)

      assert parsed.ability_modifiers == nil
      assert parsed.favored_class_name == nil
      assert parsed.abilities == []

      assert parsed.problems == [
               "unknown ability name in adjustments: Testling [[ability]] adjustments: +2 [[Vitality]]",
               "no favored class line",
               "text outside a bullet: Not a bullet at all."
             ]
    end

    test "reports a missing special abilities section" do
      parsed = RacePage.parse("[[Favored class]] (Any): nothing else here.\n")

      assert parsed.abilities == []
      assert parsed.problems == ["no `== Special abilities ==` section"]
    end
  end

  # AGENT_QUEUE.md §3.44 — the size bullet and its two legality sub-bullets
  # (tower shield, large weapons), read off the "Small stature" ability rather
  # than guessed from the `small_stature` feat id being among `bonus_feats`.
  describe "size, tower shield ban and large weapon ban (AGENT_QUEUE.md §3.44)" do
    test "a Small stature bullet reads as size small plus both bans" do
      parsed = RacePage.parse(@page)

      assert parsed.size == "small"
      assert parsed.cannot_use_tower_shields == true
      assert parsed.cannot_use_large_weapons == true
      assert parsed.small_stature_raw =~ "Testlings are small creatures."
      assert parsed.small_stature_raw =~ "Cannot use [[tower shield]]s."
      assert parsed.small_stature_raw =~ "Cannot use [[weapon size|large weapons]]."
      assert parsed.problems == []
    end

    test "no Small stature bullet at all means unread here, not medium" do
      parsed = RacePage.parse(@plain_page)

      assert parsed.size == nil
      assert parsed.cannot_use_tower_shields == nil
      assert parsed.cannot_use_large_weapons == nil
      assert parsed.small_stature_raw == nil
      assert parsed.problems == []
    end

    test "a Small stature bullet that drops a ban is a problem, not a silent false" do
      parsed =
        RacePage.parse("""
        [[Favored class]] (Any): filler so this fixture reports only the size problem.

        ==Special abilities==
        * [[Small stature]]: Testlings are small creatures.
        ** Cannot use [[tower shield]]s.
        """)

      assert parsed.size == "small"
      assert parsed.cannot_use_tower_shields == true
      assert parsed.cannot_use_large_weapons == false

      assert parsed.problems == [
               "Small stature bullet has no large weapon ban: * [[Small stature]]: Testlings are small creatures.\n** Cannot use [[tower shield]]s."
             ]
    end

    test "a Small stature bullet with unexpected wording does not guess a size" do
      parsed =
        RacePage.parse("""
        [[Favored class]] (Any): filler so this fixture reports only the size problem.

        ==Special abilities==
        * [[Small stature]]: Testlings are diminutive.
        ** Cannot use [[tower shield]]s.
        ** Cannot use [[weapon size|large weapons]].
        """)

      assert parsed.size == nil

      assert parsed.problems == [
               "Small stature bullet does not open with \"<Race>s are small creatures\": Testlings are diminutive."
             ]
    end
  end
end
