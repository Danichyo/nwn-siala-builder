defmodule BuildCalculator.Wiki.ClassPageTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.ClassPage

  # A four-level stand-in for a class page, written in the punctuation the wiki
  # actually mixes: colon inside the bold, outside it, and a bold run that
  # swallows the value whole. Four levels keep the arithmetic checkable by eye:
  # high BAB = 4, good save = 2 + 4/2 = 4, poor save = 4/3 = 1.
  @page """
  '''Description''': A fighter of sorts.

  '''Alignment restrictions:''' any lawful

  '''[[Hit die]]''': d10

  '''Proficiencies:''' armor ([[armor proficiency (light)|light]]), [[shield proficiency|shields]]

  '''[[Skill point]]s:''' 2 + [[int]] modifier ( (2 + int modifier) * 4 at 1st level)

  '''Skills''': [[discipline]], [[parry]]

  '''Unavailable feats:'''
  [[brew potion]], [[craft wand]]
  <br />These [[general feat]]s cannot be selected.

  '''[[Saving throw|Primary saving throw(s)]]''': [[fortitude]]

  '''[[Base attack bonus]]: +1/level'''

  == Level progression ==

  {| border=2
  |- style="background:#c0c0c0"
  !rowspan=2|Lvl
  !rowspan=2|BAB
  !colspan="3"|Saves
  !rowspan=2|Feats
  !rowspan=2|HP range
  !rowspan="6" style="background:#ffffff"|&nbsp;
  !colspan=2|Base spells per day
  |- style="background:#c0c0c0"
  !Fort
  !Ref
  !Will

  !1st
  !2nd
  |- align=center
  |1st || +1 || +2 || +0 || +0 ||align=left|bonus feat ||5-10 ||- ||-
  |- align=center
  |2nd || +2 || +3 || +0 || +0 ||&nbsp;||10-20 ||0 ||-
  |- align=center
  |3rd || +3 || +3 || +1 || +1 ||align=left|bonus feat ||15-30 ||1 ||-
  |- align=center
  |4th || +4 || +4 || +1 || +1 ||&nbsp;||20-40 ||1 ||0
  |}

  == Epic sample ==

  '''Bonus feats:''' every other level.

  === Epic sample level progression ===

  {| border=2
  |-
  !Lvl
  !Feats
  !HP range
  |- align=center
  |5th ||align=left| ||25-50
  |- align=center
  |6th ||align=left|bonus feat ||30-60
  |}
  """

  describe "parse/1" do
    test "reads the bold labels whatever punctuation the page used" do
      parsed = ClassPage.parse(@page)

      assert parsed.hit_die == 10
      assert parsed.hit_die_raw == "d10"
      assert parsed.skill_points == 2
      assert parsed.alignment_restriction_raw == "any lawful"
      assert parsed.class_skills_raw == "[[discipline]], [[parry]]"
      assert parsed.bab_progression_raw == "+1/level"
      assert parsed.saves_raw == "[[fortitude]]"
      assert parsed.problems == []
    end

    test "keeps a label's value that runs on to the following lines" do
      parsed = ClassPage.parse(@page)

      assert parsed.unavailable_feats_raw ==
               "[[brew potion]], [[craft wand]]\n" <>
                 "<br />These [[general feat]]s cannot be selected."
    end

    test "leaves wiki markup in the raw values" do
      parsed = ClassPage.parse(@page)

      assert parsed.proficiencies_raw =~ "[[armor proficiency (light)|light]]"
    end

    test "derives BAB type and save progressions from the last row of the table" do
      parsed = ClassPage.parse(@page)

      assert parsed.bab_progression == "high"
      assert parsed.bab_progression_label == "high"
      assert parsed.saves == %{fort: "good", ref: "poor", will: "poor"}
      assert parsed.saves_label == %{fort: "good", ref: "poor", will: "poor"}
      assert parsed.max_level == 4
    end

    test "reads the progression rows, spacer column and all" do
      parsed = ClassPage.parse(@page)

      assert [first, second | _] = parsed.progression

      assert first == %{
               level: 1,
               bab: 1,
               fort: 2,
               ref: 0,
               will: 0,
               feats_raw: "bonus feat",
               bonus_feat_rank_raw: nil,
               # Колонки `Hit die` у этой таблицы нет — как и у 22 из 23 настоящих
               # страниц: хит-дайс там одно число и стоит лейблом. Читается
               # построчно только у `red dragon disciple` (задача 3.37).
               hit_die_raw: nil,
               hp: nil,
               hp_raw: "5-10",
               spells_per_day: [],
               spells_known: nil,
               extra: []
             }

      assert second.feats_raw == nil
    end

    test "lifts the spell columns out of the level table, one key per circle" do
      parsed = ClassPage.parse(@page)

      assert Enum.map(parsed.progression, & &1.spells_per_day) == [
               [],
               [{"1", 0}],
               [{"1", 1}],
               [{"1", 1}, {"2", 0}]
             ]
    end

    test "a dashed circle is absent, not zero" do
      parsed = ClassPage.parse(@page)

      # Level 2 has a real `0` in the 1st circle — a slot that only opens up with
      # a high ability score — and a dash in the 2nd, which is no slot at all.
      second = Enum.at(parsed.progression, 1)

      assert List.keyfind(second.spells_per_day, "1", 0) == {"1", 0}
      assert List.keyfind(second.spells_per_day, "2", 0) == nil
    end

    test "a table with no spell columns says so with nil rather than an empty list" do
      parsed = ClassPage.parse(@page)

      assert Enum.map(parsed.progression, & &1.spells_known) == [nil, nil, nil, nil]
      assert Enum.map(parsed.epic_progression, & &1.spells_per_day) == [nil, nil]
    end

    test "reads both kinds of spell column and keys circles by number" do
      page =
        @page
        |> String.replace("!colspan=2|Base spells per day", "!colspan=4|Known spells")
        |> String.replace("!1st\n!2nd", "!0\n!1st\n!2nd\n!9th")
        |> String.replace("||5-10 ||- ||-", "||5-10 ||4 ||- ||- ||-")
        |> String.replace("||10-20 ||0 ||-", "||10-20 ||4 ||0 ||- ||-")
        |> String.replace("||15-30 ||1 ||-", "||15-30 ||4 ||1 ||- ||-")
        |> String.replace("||20-40 ||1 ||0", "||20-40 ||4 ||1 ||0 ||2")

      parsed = ClassPage.parse(page)

      assert List.last(parsed.progression).spells_known ==
               [{"0", 4}, {"1", 1}, {"2", 0}, {"9", 2}]

      assert List.last(parsed.progression).spells_per_day == nil
    end

    test "leaves a spell cell it cannot read in extra instead of guessing" do
      page = String.replace(@page, "||20-40 ||1 ||0", "||20-40 ||1 ||1 or 2")

      parsed = ClassPage.parse(page)

      last = List.last(parsed.progression)

      assert last.spells_per_day == [{"1", 1}]
      assert last.extra == [{"Base spells per day / 2nd", "1 or 2"}]
    end

    test "keeps the epic table apart from the normal one" do
      parsed = ClassPage.parse(@page)

      assert Enum.map(parsed.progression, & &1.level) == [1, 2, 3, 4]
      assert Enum.map(parsed.epic_progression, & &1.level) == [5, 6]
      assert parsed.bonus_feat_levels == [1, 3]
      assert parsed.epic_bonus_feat_levels == [6]
    end

    # AGENT_QUEUE.md §1.13 / CLAUDE.md §9: the red dragon disciple's epic table
    # is the one page (out of 23) that names its slot column "Bonus feats"
    # rather than "Feats", and writes an ordinal word in it ("first" … "fifth")
    # rather than the usual "bonus feat" phrase `@bonus_feat` matches. Before
    # this shape was read, `epic_bonus_feat_levels` for that one class came back
    # `[]` — a build with 30 red dragon disciple levels silently lost all five
    # of its epic bonus feat slots.
    test "an epic 'Bonus feats' column reads ordinals as slots, not as a feats column" do
      page = """
      '''[[Hit die]]''': d10

      == Level progression ==

      {|border=2
      |-
      !Level
      !BAB
      |-align="center"
      |1 || 1
      |}

      == Epic sample level progression ==

      {|border=2
      |-
      !Level
      !Bonus feats
      !HP range
      |-align="center"
      |11
      |&nbsp;
      |48-96
      |-align="center"
      |14
      |align="left"|first
      |66-132
      |}
      """

      parsed = ClassPage.parse(page)

      assert Enum.map(parsed.epic_progression, & &1.level) == [11, 14]

      # A row with no slot leaves both readings nil, same as a class that never
      # had this column at all.
      assert Enum.at(parsed.epic_progression, 0).bonus_feat_rank_raw == nil
      assert Enum.at(parsed.epic_progression, 0).feats_raw == nil

      # The ordinal is captured verbatim (for a human to see it came from this
      # column) but is not itself what makes the level a slot — its mere
      # presence is, which is what `epic_bonus_feat_levels` below reflects.
      assert Enum.at(parsed.epic_progression, 1).bonus_feat_rank_raw == "first"
      assert Enum.at(parsed.epic_progression, 1).feats_raw == nil

      assert parsed.epic_bonus_feat_levels == [14]
      assert parsed.epic_bonus_feat_counts == %{}
    end

    # source: `priv/wiki_cache/fandom/Ranger.wikitext` (revid 68113), epic table
    # row 35 verbatim — `|35th ||align=left|2 bonus feats ||175-350 || +8`. The
    # label above it says the same in words («at levels 23, 25, 26, 29, 30, 32,
    # 35(two bonus feats), 38, and 40»), and `fandom:Bonus feat`'s own table has
    # `12<br />13` in that cell.
    #
    # ⚠ Until 14.08.2026 this cell read as one slot and the player lost a whole
    # feat: `bonus_feat_levels` is a list of levels and had nowhere to put the
    # second (CLAUDE.md §9, «Известные баги модели»).
    test "a cell naming two slots is read as two, not as one" do
      page = """
      '''[[Hit die]]''': d10

      == Level progression ==

      {|border=2
      |-
      !Level
      !BAB
      !Feats
      |-align="center"
      |1 || 1 ||align=left|bonus feat
      |-align="center"
      |2 || 2 ||align=left|&nbsp;
      |}

      == Epic sample level progression ==

      {|border=2
      |-
      !Level
      !Feats
      |-align="center"
      |3 ||align=left|bonus feat
      |-align="center"
      |4 ||align=left|2 bonus feats
      |}
      """

      parsed = ClassPage.parse(page)

      # The level is still listed once — the set of levels is unchanged, so
      # every existing reader keeps its answer…
      assert parsed.bonus_feat_levels == [1]
      assert parsed.epic_bonus_feat_levels == [3, 4]

      # …and the count is the new fact, carried only where it is not one.
      assert parsed.bonus_feat_counts == %{}
      assert parsed.epic_bonus_feat_counts == %{4 => 2}

      # A slot is not a grant, whatever number the cell puts in front of it.
      assert parsed.feat_grants.granted == []

      assert parsed.feat_grants.slots == [
               {1, "bonus feat"},
               {3, "bonus feat"},
               {4, "2 bonus feats"}
             ]
    end

    # ⚠ The champion of Torm writes its slot as a category link whose **target**
    # is plural — `[[:Category:Champion of Torm bonus feats|bonus feat]]` — so
    # the count has to be read off the text with links stripped. Reading the raw
    # wikitext would see "feats" with no number in front of it and report a page
    # shape it cannot count, on a page that is perfectly ordinary.
    test "a plural inside a link target is not a count and not a complaint" do
      page = """
      '''[[Hit die]]''': d10

      == Level progression ==

      {|border=2
      |-
      !Level
      !BAB
      !Feats
      |-align="center"
      |1 || 1 ||align=left|[[:Category:Champion of Torm bonus feats|bonus feat]], [[sacred defense]] (+1)
      |}
      """

      parsed = ClassPage.parse(page)

      assert parsed.bonus_feat_levels == [1]
      assert parsed.bonus_feat_counts == %{}
      refute Enum.any?(parsed.problems, &(&1 =~ "bonus feats"))
    end

    # The other half of the same rule, and the reason the count is not simply
    # defaulted in silence: a cell that says "feats" and names no number is a
    # shape nothing can count, and counting it as one is exactly how the ranger
    # lost a feat for ten days. It still counts as one — dropping the slot would
    # be worse — but it says so in `problems`, which `mix wiki.parse` prints.
    test "'bonus feats' without a number counts as one and is reported" do
      page = """
      '''[[Hit die]]''': d10

      == Level progression ==

      {|border=2
      |-
      !Level
      !BAB
      !Feats
      |-align="center"
      |1 || 1 ||align=left|bonus feats
      |}
      """

      parsed = ClassPage.parse(page)

      assert parsed.bonus_feat_levels == [1]
      assert parsed.bonus_feat_counts == %{}

      assert "level 1: 'bonus feats' without a number — counted as one" in parsed.problems
    end

    test "reports a disagreement between the table and the label instead of picking one" do
      page =
        String.replace(
          @page,
          "'''[[Base attack bonus]]: +1/level'''",
          "'''[[Base attack bonus]]:''' +3/4 levels"
        )

      parsed = ClassPage.parse(page)

      assert parsed.bab_progression == "high"
      assert parsed.bab_progression_label == "medium"
      assert parsed.conflicts == ["BAB progression: table says high, label says medium"]
    end

    test "reports a disagreement about the saves too" do
      page = String.replace(@page, "''': [[fortitude]]", "''': [[fortitude]], [[will]]")

      parsed = ClassPage.parse(page)

      assert parsed.saves == %{fort: "good", ref: "poor", will: "poor"}
      assert parsed.saves_label == %{fort: "good", ref: "poor", will: "good"}

      assert parsed.conflicts == [
               "saves: table says fort good, ref poor, will poor, label says fort good, ref poor, will good"
             ]
    end

    test "takes the requirements section whole" do
      page =
        @page <>
          """

          == Requirements ==

          '''Alignment:''' any lawful

          '''[[Base attack bonus]]''': +7
          """

      parsed = ClassPage.parse(page)

      assert parsed.requirements_raw =~ "'''Alignment:''' any lawful"
      assert parsed.requirements_raw =~ "+7"
      # The requirements section must not overwrite the class' own BAB label.
      assert parsed.bab_progression_raw == "+1/level"
    end

    test "reads a lead definition table when the page uses no bold labels" do
      # The shape the red dragon disciple page uses instead of bold labels.
      page = """
      '''Red dragon disciple''' is a [[class]].

      {| style="border:none"
      |-
      ! Hit die:
      |style="padding-left:0.8em;"| [[hit dice|d6 to d12]] (see [[hit die increase]])
      |-
      ! Skill points:
      |style="padding-left:0.8em;"| [[skill point|2]] + [[intelligence]] modifier
      |-
      ! High saves:
      |style="padding-left:0.8em;"| [[base save|fortitude, will]]
      |}

      == Level progression ==

      {| border=2
      |-
      !Level
      !BA
      !colspan=3|Saves
      |-
      |1 || 0 || +2 || +0 || +2
      |}
      """

      parsed = ClassPage.parse(page)

      # A hit die written as a range is not a number, so it stays raw.
      assert parsed.hit_die == nil
      assert parsed.hit_die_raw == "[[hit dice|d6 to d12]] (see [[hit die increase]])"
      assert parsed.skill_points == 2
      assert parsed.saves_raw == "[[base save|fortitude, will]]"
    end

    test "lists what the page did not provide rather than filling it in" do
      parsed = ClassPage.parse("'''Skills''': [[parry]]\n")

      assert parsed.hit_die == nil
      assert parsed.progression == nil
      assert parsed.bab_progression == nil
      assert "no 'hit_die' label" in parsed.problems
      assert "no level progression table" in parsed.problems
    end

    test "keeps unrecognised labels instead of dropping them" do
      parsed = ClassPage.parse("'''Specialty weapon:''' the [[kama]].\n")

      assert parsed.extra_labels == [{"specialty weapon", "the [[kama]]."}]
    end

    test "reads the feats column of both tables into one class-level key space" do
      parsed = ClassPage.parse(@page)

      assert parsed.feat_grants.granted == []
      assert parsed.feat_grants.slots == [{1, "bonus feat"}, {3, "bonus feat"}, {6, "bonus feat"}]
      assert parsed.feat_grants.prose == []
    end
  end

  # Задача 3.37. Хит-дайс, который РАСТЁТ с уровнем класса: страница печатает
  # его отдельной колонкой на каждой строке, а bold-лейбл несёт диапазон
  # («d6 to d12»), то есть числом не является.
  #
  # source: fandom:Red dragon disciple (revid 71919) — сокращённая копия
  # настоящей страницы, ступени и уровни дословно её. Ту же шкалу целиком
  # печатает третья страница, fandom:Hit die increase: `1 → d6, 4 → d8,
  # 6 → d10, 11 → d12`.
  describe "hit_die_by_class_level" do
    @growing """
    '''Red dragon disciple''' is a [[class]].

    {| style="border:none"
    |-
    ! Hit die:
    |style="padding-left:0.8em;"| [[hit dice|d6 to d12]] (see [[hit die increase]])
    |}

    == Level progression ==

    {| border=2
    |-
    !rowspan=2|Level
    !rowspan=2|BA
    !colspan=3|Saves
    !rowspan=2|Hit die
    |-
    !Fort
    !Ref
    !Will
    |-
    |1 || 0 || +2 || +0 || +2 || d6
    |-
    |2 || 1 || +3 || +0 || +3 || d6
    |-
    |3 || 2 || +3 || +1 || +3 || d6
    |-
    |4 || 3 || +4 || +1 || +4 || d8
    |-
    |5 || 3 || +4 || +1 || +4 || d8
    |-
    |6 || 4 || +5 || +2 || +5 || d10
    |}

    == Epic dragon disciple ==

    '''Hit die:''' d12<br />

    === Epic red dragon disciple level progression ===

    {| border=2
    |-
    !Level
    !HP range
    |-
    |7 || 42-84
    |}
    """

    test "reads the column, and the epic label as the step above it" do
      parsed = ClassPage.parse(@growing)

      assert parsed.hit_die_by_class_level == [{1, 6}, {4, 8}, {6, 10}, {7, 12}]

      # Диапазон в лейбле числом не стал и не должен: два поля отвечают
      # на разные вопросы, и `nil` здесь — верный ответ страницы.
      assert parsed.hit_die == nil
      assert hit_die_problems(parsed) == []
    end

    test "a class whose table has no such column states no scale at all" do
      parsed = ClassPage.parse(@page)

      assert parsed.hit_die_by_class_level == nil
      assert parsed.hit_die == 10
    end

    # ⚠️ Половина шкалы опаснее её отсутствия: последняя ступень покрывает всё,
    # что выше неё, поэтому усечённая шкала молча назначила бы d10 и 7-му
    # уровню класса, и 31-му. Отказ целиком возвращает поведение к «HP не
    # считаем и говорим почему».
    test "a growing die whose epic step is unreadable yields no scale and a problem" do
      parsed = @growing |> String.replace("'''Hit die:''' d12", "") |> ClassPage.parse()

      assert parsed.hit_die_by_class_level == nil

      assert "hit die grows and the epic section states no hit die — no scale read at all" in parsed.problems
    end

    # А вот ОДНА ступень эпического продолжения не требует: колонка с одним
    # и тем же числом во всех строках — это тот же самый один хит-дайс.
    test "a column that never changes needs no epic step" do
      parsed = @growing |> String.replace(~r/\bd(8|10)\b/, "d6") |> ClassPage.parse()

      assert parsed.hit_die_by_class_level == [{1, 6}]
      assert hit_die_problems(parsed) == []
    end

    test "an unreadable cell yields no scale and a problem, never a partial one" do
      parsed = @growing |> String.replace("|| d8\n|-\n|5 ", "|| ?\n|-\n|5 ") |> ClassPage.parse()

      assert parsed.hit_die_by_class_level == nil

      assert "hit die column: a row states something other than 'dN' — no scale read at all" in parsed.problems
    end

    # Фикстуры выше называют не все лейблы страницы, поэтому «отчёт пуст»
    # проверяется по своей теме, а не целиком: пустой `problems` здесь
    # означал бы, что фикстура полная, а не что шкала прочиталась.
    defp hit_die_problems(parsed) do
      Enum.filter(parsed.problems, &String.contains?(&1, "hit die"))
    end
  end

  # Fandom writes no `'''Primary ability:'''` label on any of the 23 class
  # pages — the phrase never occurs in the whole cache. What the seven casters
  # do write is inside `'''Spellcasting:'''`, right after the arcane/divine
  # tag: `[[wisdom]]-based (a base wisdom score of 10 + …)`. These cases pin
  # both that reading and the reasons it is scoped to that one label rather
  # than the whole page.
  describe "primary ability" do
    test "reads it out of the Spellcasting label, keeping the link" do
      page = """
      '''Spellcasting:''' [[Divine]] ([[spell failure]] from armor is ignored), [[wisdom]]-based (a base wisdom score of 10 + the spell's level is required to cast a spell), and requires preparation.
      """

      parsed = ClassPage.parse(page)

      assert parsed.primary_ability_raw == "[[wisdom]]"
      # The two fields answer different questions and neither is a copy of the
      # other: this one is just "which ability", the whole sentence stays put.
      assert parsed.spellcasting_raw =~ "requires preparation"
    end

    test "a class with no Spellcasting label at all stays nil, honestly" do
      # @page (used above) never carries a Spellcasting label — sixteen of the
      # 23 real pages do not either, and that silence means "not a caster",
      # not "not read".
      parsed = ClassPage.parse(@page)

      assert parsed.spellcasting_raw == nil
      assert parsed.primary_ability_raw == nil
    end

    # The bug this scoping exists to prevent: a paladin page note reads "some
    # charisma-based [[bard]]…builds" (someone else's class, in a multiclass
    # tip) and a monk page weighs "Wisdom-based" against "dexterity-based"
    # unarmed playstyles on a page that states two sentences earlier that
    # monks do not cast spells. A page-wide search for "-based" would read
    # either as this class's primary ability. Neither is, and this class's own
    # Spellcasting label says a third thing entirely.
    test "an unrelated '-based' phrase elsewhere on the page is not picked up" do
      page = """
      '''Spellcasting:''' [[Arcane]] ([[spell failure]] from armor is a factor), [[charisma]]-based (a base charisma score of 10 + the spell's level is required to cast a spell), and [[spontaneous cast]] (no spell preparation required).

      == Notes ==

      * A single level of this class is used in some wisdom-based [[cleric]] builds.
      """

      parsed = ClassPage.parse(page)

      assert parsed.primary_ability_raw == "[[charisma]]"
    end

    test "two different abilities named inside the same label are left unresolved" do
      page = """
      '''Spellcasting:''' [[wisdom]]-based normally, but [[charisma]]-based for a favoured soul variant.
      """

      parsed = ClassPage.parse(page)

      # The parser has no way to tell a source's own contradiction from a real
      # one, and picking either would be choosing for the source (CLAUDE.md §3).
      assert parsed.primary_ability_raw == nil
    end

    test "the same ability named twice, differently cased, is not a disagreement" do
      page = """
      '''Spellcasting:''' [[Wisdom]]-based (see below); some modules refer to the wisdom-based save DC elsewhere on this very page.
      """

      parsed = ClassPage.parse(page)

      # One ability, read twice — not two abilities. The first spelling as
      # printed is what comes back, not a normalised-case guess.
      assert parsed.primary_ability_raw == "[[Wisdom]]"
    end

    test "an explicit 'Primary ability' label, if the wiki ever writes one, wins" do
      page = """
      '''Primary ability:''' [[strength]]

      '''Spellcasting:''' [[Divine]], [[wisdom]]-based (a base wisdom score of 10 + the spell's level is required to cast a spell).
      """

      parsed = ClassPage.parse(page)

      assert parsed.primary_ability_raw == "[[strength]]"
    end
  end

  # Every wording the feats column actually uses across the 23 Fandom class
  # pages. `feat_grants/1` is fed the progression rows directly so a case can be
  # one line instead of a whole wiki table.
  describe "feat_grants/1" do
    defp grants(pairs) do
      pairs
      |> Enum.map(fn {level, raw} -> %{level: level, feats_raw: raw} end)
      |> ClassPage.feat_grants()
    end

    test "a linked feat is a grant, and the link target is the id" do
      assert %{granted: [{1, "rallying cry", "rallying cry", ""}, {1, "heroic shield", _, ""}]} =
               grants([{1, "[[rallying cry]], [[heroic shield]]"}])
    end

    test "takes the id from the link target, not from what it displays" do
      assert %{granted: [{3, "fear (feat)", "fear", ""}]} = grants([{3, "[[fear (feat)|fear]]"}])
    end

    # The whole point of the exercise: "bonus feat" is a slot the player fills,
    # already counted by `bonus_feat_levels`. Handing it out as a feat would have
    # the class grant something that does not exist.
    test "a bonus feat slot is never a grant, in any of its five spellings" do
      slots = [
        {1, "bonus feat"},
        {2, "2 bonus feats"},
        {3, "special bonus feat"},
        {4, "wizard bonus feat"},
        {5, "[[:Category:Champion of Torm bonus feats|bonus feat]]"}
      ]

      assert %{granted: [], slots: ^slots} = grants(slots)
    end

    test "a slot standing next to a grant does not swallow it" do
      assert %{granted: [{2, "sacred defense", _, "(+1)"}], slots: [{2, "bonus feat"}]} =
               grants([{2, "bonus feat, [[sacred defense]] (+1)"}])
    end

    # The harper scout's slot names the two feats it may be spent on. They are a
    # pool, not a grant — reading them as one would hand the class both.
    test "the feats a restricted slot may be spent on are not granted" do
      assert %{granted: [{1, "bardic knowledge", _, ""}], slots: [{1, slot}]} =
               grants([
                 {1, "[[bardic knowledge]], bonus feat ([[curse song]], [[favored enemy]])"}
               ])

      assert slot == "bonus feat ([[curse song]], [[favored enemy]])"
    end

    test "a rank or a per-day count after the link belongs to the same feat" do
      assert %{granted: [{2, "uncanny dodge", _, "I"}, {4, "inspire courage", _, "1/day"}]} =
               grants([{2, "[[uncanny dodge]] I"}, {4, "[[inspire courage]] 1/day"}])
    end

    # The wiki keeps one page per ability family, so a later rank is often linked
    # under its own redirect title. `mix wiki.parse` resolves all three of these
    # onto the family's feat id, at which point the display text is the only
    # thing left saying *which* rank was handed out.
    test "keeps what the link displayed, not only what it targeted" do
      assert %{
               granted: [
                 {15, "greater rage", "greater rage", "(4x/day)"},
                 {13, "infinite humanoid shape", "infinite humanoid shape", ""},
                 {20, "elemental shape", "improved elemental shape", ""}
               ]
             } =
               grants([
                 {15, "[[greater rage]] (4x/day)"},
                 {13, "[[infinite humanoid shape]]"},
                 {20, "[[elemental shape | improved elemental shape]]"}
               ])
    end

    # An unlinked rank matches nothing when this call never saw the linked one
    # that would have taught its name — the shape a page uses when only a
    # SINGLE row is fed in, as every other case in this file does. In practice
    # a class page never does this: the rank before it is always somewhere
    # earlier on the same page. See "a later rank repeats the name with no
    # link at all" below for what happens once that earlier row is present.
    test "an unlinked upgrade names nothing this call has granted yet" do
      assert %{granted: [], prose: [{5, "uncanny dodge II"}, {7, "inspire courage 2/day"}]} =
               grants([{5, "uncanny dodge II"}, {7, "inspire courage 2/day"}])
    end

    # ⚠️ CLAUDE.md §3 / AGENT_QUEUE.md §7 (08.08.2026): this is the shape every
    # one of `bone_skin`'s eight steps takes but the first — pale master 1 links
    # `[[bone skin]] (+2AC)`, and 4, 8, 12, 16, 20, 24 and 28 all repeat "bone
    # skin (+2AC)" in plain text, no `[[…]]` at all. Reading only linked rows
    # left six of those eight invisible: `granted_feats` said the feat arrived
    # twice, `feats_owned` never lied (the character owned it from level 1
    # either way), but the `○` glyph and the "you'll get this free" warning
    # (CLAUDE.md §6) had nothing to show on 4, 8, 16, 20, 24 or 28.
    test "a later rank repeats the name with no link at all, and is still a grant" do
      assert %{
               granted: [
                 {1, "bone skin", "bone skin", "(+2AC)"},
                 {4, "bone skin", "bone skin", "(+2AC)"},
                 {8, "bone skin", "bone skin", "(+2AC)"}
               ],
               prose: []
             } =
               grants([
                 {1, "[[bone skin]] (+2AC)"},
                 {4, "bone skin (+2AC)"},
                 {8, "bone skin (+2AC)"}
               ])
    end

    # The target a repeat resolves to is the one the EARLIER link named, not
    # the text of the repeat itself — `greater rage`'s target is the redirect
    # `barbarian rage` linked at level 1, and level 16's bare "greater rage
    # (5x/day)" has to carry that same target forward, or `mix wiki.parse`
    # would resolve it as a feat this page never granted at all.
    test "a repeat inherits the target its teaching grant resolved to, not its own text" do
      assert %{
               granted: [
                 {1, "barbarian rage", "barbarian rage", "(1x/day)"},
                 {15, "greater rage", "greater rage", "(4x/day)"},
                 {16, "greater rage", "greater rage", "(5x/day)"}
               ]
             } =
               grants([
                 {1, "[[barbarian rage]] (1x/day)"},
                 {15, "[[greater rage]] (4x/day)"},
                 {16, "greater rage (5x/day)"}
               ])
    end

    # A shorter, five-levels-earlier name must not cut a longer, still-known one
    # short: barbarian 26 is "epic barbarian damage reduction II", and reading
    # it as the level-11 family ("damage reduction" plus a stray "II") would
    # both misfile the grant and leave "epic barbarian damage reduction III"
    # unable to match its own, correct, later occurrence.
    test "the longest known name wins over a shorter one that is also a prefix" do
      assert %{
               granted: [
                 {11, "Damage Reduction (barbarian)", "damage reduction", "I"},
                 {23, "epic barbarian damage reduction", "epic barbarian damage reduction", ""},
                 {26, "epic barbarian damage reduction", "epic barbarian damage reduction", "II"}
               ]
             } =
               grants([
                 {11, "[[Damage Reduction (barbarian)|damage reduction]] I"},
                 {23, "[[epic barbarian damage reduction]]"},
                 {26, "epic barbarian damage reduction II"}
               ])
    end

    # A sentence naming no grant this call has ever seen — linked or not — still
    # falls through untouched, exactly as before this existed: `repeat/2` only
    # ever repeats a name `grant/2` already taught it, never guesses one.
    test "a sentence with no feat in it is left alone" do
      assert %{granted: [], prose: [{9, "gets wings"}]} = grants([{9, "gets wings"}])

      assert %{granted: [{1, "bone skin", _, "(+2AC)"}], prose: [{4, "improved forms"}]} =
               grants([{1, "[[bone skin]] (+2AC)"}, {4, "improved forms"}])
    end

    test "a comma inside a link title does not split the fragment" do
      assert %{granted: [{4, "sneak attack, blackguard", _, ""}]} =
               grants([{4, "[[sneak attack, blackguard]]"}])
    end

    test "reads a list broken by a line break and an 'and'" do
      raw =
        "becomes a half-dragon:<br />[[darkvision]], [[immunity to fire]], and [[immunity to sleep]]"

      assert %{granted: granted, prose: []} = grants([{10, raw}])

      assert granted == [
               {10, "darkvision", "darkvision", ""},
               {10, "immunity to fire", "immunity to fire", ""},
               {10, "immunity to sleep", "immunity to sleep", ""}
             ]
    end

    test "a feat named in the middle of a sentence is not read as granted" do
      assert %{granted: [], prose: [{6, "counts as [[toughness]] for prerequisites"}]} =
               grants([{6, "counts as [[toughness]] for prerequisites"}])
    end

    test "rows with no feats column say nothing at all" do
      assert grants([{1, nil}, {2, nil}]) == %{granted: [], slots: [], prose: []}
    end
  end
end
