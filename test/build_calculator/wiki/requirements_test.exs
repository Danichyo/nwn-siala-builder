defmodule BuildCalculator.Wiki.RequirementsTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.Requirements

  @classes [
    %{id: "shifter", title: "Shifter", prestige?: true},
    %{id: "weapon_master", title: "Weapon master", prestige?: true},
    %{id: "barbarian", title: "Barbarian", prestige?: false},
    # Три класса, выдающие Evasion, и рейнджер, которого `favored_enemy`
    # называет вовсе без уровня — выборка для списка выдающих классов.
    %{id: "monk", title: "Monk", prestige?: false},
    %{id: "rogue", title: "Rogue", prestige?: false},
    %{id: "shadowdancer", title: "Shadowdancer", prestige?: true},
    %{id: "ranger", title: "Ranger", prestige?: false}
  ]

  @feats [
    %{id: "improved_initiative", title: "Improved initiative"},
    %{id: "weapon_of_choice", title: "Weapon of choice"},
    %{id: "smite_evil", title: "Smite evil"},
    %{id: "smite_good", title: "Smite good"},
    %{id: "wild_shape", title: "Wild shape"},
    %{id: "greater_wildshape_iv", title: "Greater wildshape IV"},
    %{id: "spell_focus", title: "Spell focus"},
    %{id: "weapon_focus", title: "Weapon focus"},
    %{id: "ki_strike", title: "Ki strike"}
  ]

  # The numbers the `Epic class` and `Epic character` pages state, which is where
  # `mix wiki.parse` gets them from as well.
  @epic %{character_level: 21, base_class_level: 21, prestige_class_level: 11}

  defp lookup(epic \\ @epic) do
    Requirements.lookup(%{
      classes: @classes,
      skills: [%{id: "spellcraft", title: "Spellcraft"}],
      feats: @feats,
      races: [],
      epic: epic
    })
  end

  describe "feat/2 and the phrase \"epic <class>\"" do
    test "an epic prestige class is eleven levels of it" do
      parsed = Requirements.feat("[[epic class|epic]] [[shifter]]", lookup())

      assert parsed.requirements == [{"class_levels", {:obj, [{"shifter", 11}]}}]
      assert parsed.unparsed == []
    end

    test "an epic base class is twenty-one levels of it" do
      parsed = Requirements.feat("[[epic class|epic]] [[barbarian]]", lookup())

      assert parsed.requirements == [{"class_levels", {:obj, [{"barbarian", 21}]}}]
    end

    test "an epic character is a character level" do
      parsed = Requirements.feat("[[epic character]], [[improved initiative]]", lookup())

      assert parsed.requirements == [
               {"character_level", 21},
               {"feats", ["improved_initiative"]}
             ]

      assert parsed.unparsed == []
    end

    test "reads the rest of the line alongside it" do
      parsed =
        Requirements.feat("[[weapon of choice]], [[epic class|epic]] [[weapon master]]", lookup())

      assert parsed.requirements == [
               {"feats", ["weapon_of_choice"]},
               {"class_levels", {:obj, [{"weapon_master", 11}]}}
             ]
    end

    # "epic level caster" is not a class, and there is no level of "caster" to
    # count — the fragment has to stay prose rather than become a number.
    test "epic with no class named stays unparsed" do
      parsed = Requirements.feat("[[epic class|epic level caster]], [[spellcraft]] 34", lookup())

      assert parsed.unparsed == ["[[epic class|epic level caster]]"]
      refute List.keymember?(parsed.requirements, "class_levels", 0)
    end

    # The thresholds are read off the wiki, not assumed here: without them the
    # phrase is prose, never a guessed 11 or 21 (CLAUDE.md §3).
    test "without the thresholds nothing is invented" do
      parsed = Requirements.feat("[[epic class|epic]] [[shifter]]", lookup(%{}))

      assert parsed.requirements == [{"unparsed", ["[[epic class|epic]] [[shifter]]"]}]
    end
  end

  # "Can only take this feat at 1st-level" is the one shape on either wiki that
  # states a ceiling instead of a floor, and reading it as `character_level`
  # would invert it — a feat only a first-level character may take would become
  # one only a first-level character may *not* take.
  describe "feat/2 and max_character_level" do
    test "reads the digit spelling, with or without the full stop" do
      assert requirements("Can only take this feat at 1st-level.") ==
               [{"max_character_level", 1}]

      assert requirements("Can only take this feat at 1st-level, [[improved initiative]]") ==
               [{"max_character_level", 1}, {"feats", ["improved_initiative"]}]
    end

    test "reads the word spelling, with and without the word \"feat\"" do
      assert requirements("Can only take this feat at first level.") ==
               [{"max_character_level", 1}]

      assert requirements("Can only take this at first level.") == [{"max_character_level", 1}]
    end

    test "a minimum is still a minimum" do
      assert requirements("21st level") == [{"character_level", 21}]
    end

    # Only the two spellings these pages use are decoded. "second" is not in the
    # corpus, so it is prose, and prose is reported rather than guessed at.
    test "an ordinal word the corpus does not use is not decoded" do
      assert requirements("Can only take this feat at second level.") ==
               [{"unparsed", ["Can only take this feat at second level"]}]
    end
  end

  # The highest circle the character can cast, which is neither a character
  # level nor a class level — a Wizard 5 / Fighter 10 casts 3rd-level spells.
  describe "feat/2 and casts_spell_level" do
    test "reads every spelling of the circle on these pages" do
      assert requirements("ability to cast 9th level spells") == [{"casts_spell_level", 9}]
      assert requirements("ability to cast 2nd-level [[spell]]s") == [{"casts_spell_level", 2}]
      assert requirements("ability to cast first-level spells") == [{"casts_spell_level", 1}]
      assert requirements("the ability to cast 9th level spells") == [{"casts_spell_level", 9}]
    end

    test "sits alongside the rest of the line" do
      assert requirements("21st level, [[spellcraft]] 30, ability to cast 9th level spells") ==
               [
                 {"character_level", 21},
                 {"casts_spell_level", 9},
                 {"skills", {:obj, [{"spellcraft", 30}]}}
               ]
    end

    # No number is invented for a phrase that names no circle: "epic level
    # caster" is not a level of anything countable.
    test "a phrase with no circle in it stays prose" do
      assert requirements("ability to cast epic spells") ==
               [{"unparsed", ["ability to cast epic spells"]}]
    end
  end

  # The *caster* level, which parts company with character level as soon as a
  # build multiclasses — a Wizard 3 / Fighter 7 is a 10th-level character and a
  # 3rd-level caster.
  describe "feat/2 and caster_level" do
    test "reads it with and without the plus, linked or not" do
      assert requirements("spellcaster level 3+") == [{"caster_level", 3}]
      assert requirements("[[spellcaster]] level 1") == [{"caster_level", 1}]
    end

    # The wiki gave Sap an impossible prerequisite on purpose, to take the feat
    # away from player characters. 100 is what the page says, so 100 is what is
    # written down — rounding it to something plausible would hand the feat back.
    test "an impossible threshold is copied, not smoothed" do
      assert requirements("[[base attack bonus]] +1, ''spellcaster level 100''") ==
               [{"caster_level", 100}, {"base_attack_bonus", 1}]
    end

    test "a caster level with no number stays prose" do
      assert requirements("spellcaster level") == [{"unparsed", ["spellcaster level"]}]
    end
  end

  describe "feat/2 and any_of" do
    test "a disjunction inside one fragment becomes a list of alternatives" do
      assert requirements("[[smite evil]] or [[smite good]]") ==
               [
                 {"any_of",
                  [
                    {:obj, [{"feats", ["smite_evil"]}]},
                    {:obj, [{"feats", ["smite_good"]}]}
                  ]}
               ]
    end

    test "\"either A or B\" is the same choice, and the rest of the line survives it" do
      parsed = Requirements.feat("21st level, either [[smite good]] or [[smite evil]]", lookup())

      assert parsed.requirements == [
               {"character_level", 21},
               {"any_of",
                [
                  {:obj, [{"feats", ["smite_good"]}]},
                  {:obj, [{"feats", ["smite_evil"]}]}
                ]}
             ]

      assert parsed.unparsed == []
    end

    # `[[wild shape]] 6x/day` is a feat plus a number of uses the schema has no
    # room for. Half a branch is worse than none, so the whole choice stays prose.
    test "a branch the schema cannot hold whole leaves the choice unread" do
      parsed =
        Requirements.feat("either [[wild shape]] 6x/day or [[greater wildshape IV]]", lookup())

      assert parsed.unparsed == ["either [[wild shape]] 6x/day or [[greater wildshape IV]]"]
      refute List.keymember?(parsed.requirements, "any_of", 0)
      refute List.keymember?(parsed.requirements, "feats", 0)
    end

    # An "or" that starts a fragment continues a choice whose other branches are
    # in earlier fragments — reading it alone would turn one third of a choice
    # into a requirement, and it poisons the entity groups as it always did.
    test "an alternative spread over several fragments is still refused" do
      parsed =
        Requirements.feat("[[improved initiative]], or [[weapon of choice]]", lookup())

      refute List.keymember?(parsed.requirements, "any_of", 0)
      refute List.keymember?(parsed.requirements, "feats", 0)
      assert "[[improved initiative]]" in parsed.unparsed
    end

    # `any_of` is one list, so it holds one choice. Two independent choices in
    # one feat is a shape the schema has no room for.
    test "two separate choices in one feat leave both unread" do
      parsed =
        Requirements.feat(
          "[[smite evil]] or [[smite good]]; [[wild shape]] or [[greater wildshape IV]]",
          lookup()
        )

      refute List.keymember?(parsed.requirements, "any_of", 0)

      assert parsed.unparsed == [
               "[[smite evil]] or [[smite good]]",
               "[[wild shape]] or [[greater wildshape IV]]"
             ]
    end

    # "+1 or higher" is one bonus written out longhand, not a choice between a
    # bonus and a comparative.
    test "\"or higher\" is not a disjunction" do
      assert requirements("[[base attack bonus]] of +1 or higher") == [{"base_attack_bonus", 1}]
    end

    # A parenthesised "or" qualifies the requirement in front of it rather than
    # offering an alternative to it, so the fragment is one requirement — kept,
    # and listed as not fully read because of the qualifier.
    test "an \"or\" inside parentheses does not split the fragment" do
      parsed =
        Requirements.feat("[[weapon of choice]] ([[smite evil]] or [[smite good]])", lookup())

      refute List.keymember?(parsed.requirements, "any_of", 0)
      assert List.keyfind(parsed.requirements, "feats", 0) == {"feats", ["weapon_of_choice"]}
      assert parsed.unparsed == ["[[weapon of choice]] ([[smite evil]] or [[smite good]])"]
    end
  end

  # Дизъюнкция, которую страница не объявляет: `evasion` печатает
  # «[[monk]] 1, [[rogue]] 2, [[shadowdancer]] 2» той же запятой, что и
  # конъюнкция. Вывод держится на том, что это список ВЫДАЮЩИХ классов, каждый
  # со своим уровнем выдачи, — см. `Requirements` и пин по `classN`/`bonusN`
  # в `parsed_snapshot_test.exs`.
  describe "feat/2 and a list of granting classes" do
    test "several class levels are the classes that grant the feat, not a build that is all of them" do
      parsed = Requirements.feat("[[monk]] 1, [[rogue]] 2, [[shadowdancer]] 2", lookup())

      assert parsed.requirements == [
               {"any_of",
                [
                  {:obj, [{"class_levels", {:obj, [{"monk", 1}]}}]},
                  {:obj, [{"class_levels", {:obj, [{"rogue", 2}]}}]},
                  {:obj, [{"class_levels", {:obj, [{"shadowdancer", 2}]}}]}
                ]}
             ]

      assert parsed.unparsed == []
    end

    # `favored_enemy` печатает «[[ranger]], [[Harper scout]] 1» — у рейнджера
    # уровня нет вовсе. Это тот же «класс без уровня — один уровень его», что уже
    # действует вне дизъюнкции, а не выдуманное для неё число.
    test "a class named without a level is one level of it inside the choice too" do
      parsed = Requirements.feat("[[ranger]], [[monk]] 1", lookup())

      assert parsed.requirements == [
               {"any_of",
                [
                  {:obj, [{"class_levels", {:obj, [{"monk", 1}]}}]},
                  {:obj, [{"class_levels", {:obj, [{"ranger", 1}]}}]}
                ]}
             ]
    end

    # ⚠️ Запятая по умолчанию значит «и»: `weapon specialization` требует
    # и воина, И BAB +4, И Weapon Focus. Дизъюнкция включается только на прогоне
    # из ДВУХ И БОЛЕЕ классов, поэтому один класс рядом с другими требованиями
    # обязан остаться конъюнкцией.
    test "one class beside other requirements is still a conjunction" do
      parsed =
        Requirements.feat("[[monk]], [[base attack bonus]] +4, [[improved initiative]]", lookup())

      assert parsed.requirements == [
               {"base_attack_bonus", 4},
               {"feats", ["improved_initiative"]},
               {"class_levels", {:obj, [{"monk", 1}]}}
             ]

      refute List.keymember?(parsed.requirements, "any_of", 0)
    end

    # `uncanny_dodge` пишет за каждым классом список уровней улучшений
    # («[[barbarian]] 2 (5, 10, 13, 16, 19)»). Ветка, стоящая на недочитанном
    # хвосте, прошла бы за всю дизъюнкцию, поэтому не читается весь список.
    test "a class fragment with a tail nobody read leaves the whole list prose" do
      parsed = Requirements.feat("[[monk]] 1 (5, 10), [[rogue]] 2", lookup())

      refute List.keymember?(parsed.requirements, "any_of", 0)
      refute List.keymember?(parsed.requirements, "class_levels", 0)
      assert parsed.unparsed == ["[[monk]] 1 (5, 10)", "[[rogue]] 2"]
    end

    # Положительный контроль к предыдущему: тот же список без хвоста читается.
    # Без него `refute` выше зеленел бы и от опечатки в самом тесте.
    test "the same list without the tail is read" do
      parsed = Requirements.feat("[[monk]] 1, [[rogue]] 2", lookup())

      assert List.keymember?(parsed.requirements, "any_of", 0)
      assert parsed.unparsed == []
    end

    # `immunity_to_sleep` — «[[elf]], [[half-elf]], or [[red dragon disciple]] 10».
    # Нечитаемое «или» по-прежнему травит группы целиком: иначе дизъюнкция
    # классов подменила бы собой дизъюнкцию, которая шире её.
    test "an unreadable alternative still suppresses the list" do
      parsed = Requirements.feat("[[monk]] 1, [[rogue]] 2, or [[shifter]] 10", lookup())

      refute List.keymember?(parsed.requirements, "any_of", 0)
      refute List.keymember?(parsed.requirements, "class_levels", 0)

      # Положительный контроль: фрагменты дошли до разбора и вернулись прозой,
      # а не потерялись по дороге — иначе `refute` выше зеленел бы впустую.
      assert parsed.unparsed == ["or [[shifter]] 10", "[[monk]] 1", "[[rogue]] 2"]
    end

    # Список классов — это один выбор, и `any_of` держит один. Рядом с выбором,
    # который страница объявила словом «или», оба уходят в прозу.
    test "a stated choice beside the class list leaves both unread" do
      parsed =
        Requirements.feat("[[smite evil]] or [[smite good]]; [[monk]] 1, [[rogue]] 2", lookup())

      refute List.keymember?(parsed.requirements, "any_of", 0)

      assert parsed.unparsed == [
               "[[smite evil]] or [[smite good]]",
               "[[monk]] 1",
               "[[rogue]] 2"
             ]
    end

    # ⚠️ Вывод «список классов = выбор» верен для КЛАССОВЫХ УМЕНИЙ, то есть для
    # фитов. У престиж-класса «Fighter 4 и Rogue 2» вполне может быть настоящей
    # конъюнкцией, поэтому на странице класса тот же список остаётся прозой.
    test "a class page's list of classes is not turned into a choice" do
      parsed = Requirements.class("'''Class''': [[monk]] 1, [[rogue]] 2", lookup())

      refute List.keymember?(parsed.requirements, "any_of", 0)
      refute List.keymember?(parsed.requirements, "class_levels", 0)
      assert parsed.unparsed == ["[[monk]] 1", "[[rogue]] 2"]
    end
  end

  # The "→ N" badge of CLAUDE.md §6 asks what a feat is a gateway to. It is a
  # static property of the feat, not of the build in front of the player, so a
  # feat named as one of several alternatives is still a gateway.
  describe "unlocks/1" do
    defp unlocks(pairs) do
      Requirements.unlocks(
        for {id, raw} <- pairs, do: {id, Requirements.feat(raw, lookup()).requirements}
      )
    end

    test "counts a feat required outright" do
      assert unlocks([{"great_cleave", "[[improved initiative]]"}]) ==
               %{"improved_initiative" => ["great_cleave"]}
    end

    test "counts every branch of a disjunction, not just the first" do
      assert unlocks([{"extra_smiting", "[[smite evil]] or [[smite good]]"}]) ==
               %{"smite_evil" => ["extra_smiting"], "smite_good" => ["extra_smiting"]}
    end

    # The regression this guards: counting only hard `feats` left both smiting
    # feats claiming they open nothing, which is a false statement rather than a
    # cautious one.
    test "a feat reachable only through a branch is not left with an empty badge" do
      indexed = unlocks([{"extra_smiting", "[[smite evil]] or [[smite good]]"}])

      refute Map.get(indexed, "smite_evil", []) == []
    end

    test "a fragment that stayed prose contributes nothing" do
      assert unlocks([
               {"dragon_shape", "either [[wild shape]] 6x/day or [[greater wildshape IV]]"}
             ]) ==
               %{}
    end
  end

  # A requirement the schema cannot hold used to cost the requirement standing
  # beside it: the whole fragment went to `unparsed`, and `unparsed` makes the
  # core refuse to check **anything** about the feat. `qualifiers` splits the two
  # — what was read is checked, what could not be is named.
  describe "feat/2 and qualifiers" do
    test "the feat is kept and the school it was taken in is named" do
      assert requirements("[[spell focus]] in the chosen [[spell school]]") ==
               [{"feats", ["spell_focus"]}, {"qualifiers", ["in the chosen spell school"]}]
    end

    test "every spelling of the weapon choice in this corpus" do
      for raw <- [
            "[[weapon focus]] (chosen weapon)",
            "[[weapon focus]] (weapon to be chosen)",
            "[[weapon focus]] with the chosen weapon",
            "[[weapon focus]] all in the chosen weapon",
            "[[weapon focus]] in a [[melee weapon]]"
          ] do
        assert [{"feats", ["weapon_focus"]}, {"qualifiers", [_phrase]}] = requirements(raw)
      end
    end

    # `proficiency with the chosen weapon` is a whole fragment rather than a
    # tail, and it stands next to a base attack bonus that *is* read.
    test "a whole fragment can be the qualifier when the block says more" do
      assert requirements("proficiency with the chosen weapon, [[base attack bonus]] +1") ==
               [{"base_attack_bonus", 1}, {"qualifiers", ["proficiency with the chosen weapon"]}]
    end

    # One wiki page covers Ki Strike I, II and III, so `+3` names a step the id
    # cannot — the same thing `granted_feat_ranks` carries verbatim for a class.
    test "a rank inside a feat family is a qualifier of that feat" do
      assert requirements("[[ki strike]] +3") ==
               [{"feats", ["ki_strike"]}, {"qualifiers", ["+3"]}]
    end

    test "one caveat said twice is one caveat" do
      assert [{"feats", _both}, {"qualifiers", ["(weapon to be chosen)"]}] =
               requirements(
                 "[[weapon focus]] (weapon to be chosen), [[weapon of choice]] (weapon to be chosen)"
               )
    end

    # ⚠ The line that keeps `qualifiers` from becoming a dumping ground. A phrase
    # outside the vocabulary is not "read, with a footnote": the feat it trails
    # is still kept, and the fragment still counts as not fully read, which is
    # exactly what the answer was before `qualifiers` existed.
    test "a phrase outside the vocabulary is still prose" do
      assert requirements("[[weapon focus]] every second Tuesday") ==
               [
                 {"feats", ["weapon_focus"]},
                 {"unparsed", ["[[weapon focus]] every second Tuesday"]}
               ]
    end

    # `[[greater rage]]` is a redirect and names no page in the snapshot, so the
    # fragment yields nothing for the frequency to qualify. Resolving it through
    # the alias would reach `barbarian rage`, which every barbarian has from
    # level 1: the requirement would not weaken, it would vanish.
    test "a frequency qualifies nothing when the feat it trails resolves to nothing" do
      assert requirements("[[greater rage]] (6x per day)") ==
               [{"unparsed", ["[[greater rage]] (6x per day)"]}]
    end

    # `skill focus` says only "able to use the skill". A block that is nothing
    # but footnotes has not been read at all, and left as a qualifier it would
    # read as fully understood.
    test "a block with nothing but a qualifier hands it back to unparsed" do
      assert requirements("proficiency with the chosen weapon") ==
               [{"unparsed", ["proficiency with the chosen weapon"]}]
    end

    # `any_of` passes as soon as one branch does, so a branch resting on a
    # footnote would carry the whole disjunction on it.
    test "a branch of a choice may not rest on a qualifier" do
      parsed =
        Requirements.feat("[[weapon focus]] (chosen weapon) or [[smite evil]]", lookup())

      refute List.keymember?(parsed.requirements, "any_of", 0)
      refute List.keymember?(parsed.requirements, "qualifiers", 0)
      assert parsed.unparsed == ["[[weapon focus]] (chosen weapon) or [[smite evil]]"]
    end

    # An unreadable alternative already withdraws every named group; a footnote
    # to a requirement that has just been withdrawn is a footnote to nothing.
    test "an unreadable alternative withdraws the qualifier with the feat" do
      parsed =
        Requirements.feat("[[weapon focus]] (chosen weapon), or [[smite evil]]", lookup())

      refute List.keymember?(parsed.requirements, "qualifiers", 0)
      assert "[[weapon focus]] (chosen weapon)" in parsed.unparsed
    end
  end

  # Two scalars that name a derived stat rather than a level. Both are computed
  # by the core, so both are real checks rather than names to be shrugged at.
  describe "feat/2, save_bonus and any_skill_ranks" do
    test "reads the save and the number off resist energy's line" do
      assert requirements("[[fortitude]] save bonus +8") ==
               [{"save_bonus", {:obj, [{"fortitude", 8}]}}]
    end

    test "the other two saves read alike" do
      assert requirements("[[reflex]] save bonus +4") ==
               [{"save_bonus", {:obj, [{"reflex", 4}]}}]

      assert requirements("will save bonus 2") == [{"save_bonus", {:obj, [{"will", 2}]}}]
    end

    # There is no fourth saving throw, and a name outside the three is not one.
    test "a name that is not a saving throw is not read as one" do
      assert requirements("[[spellcraft]] save bonus +8") ==
               [{"unparsed", ["[[spellcraft]] save bonus +8"]}]
    end

    test "\"in the chosen skill\" is any skill, not a skill named skill" do
      assert requirements("21st level, 20 [[skill rank|rank]]s in the chosen skill") ==
               [{"character_level", 21}, {"any_skill_ranks", 20}]
    end

    # `skills` names one skill; folding "the chosen skill" into it would have to
    # pick which, and there is nothing to pick from.
    test "it does not become an entry in skills" do
      parsed = Requirements.feat("20 [[skill rank|rank]]s in the chosen skill", lookup())

      refute List.keymember?(parsed.requirements, "skills", 0)
      assert parsed.unparsed == []
    end
  end

  # A prestige class writes its criteria as bold labels rather than as one line,
  # and the same qualifier turns up there: Champion of Torm and Weapon Master
  # both ask for `[[weapon focus]] in a [[melee weapon]]`.
  describe "class/2 and qualifiers" do
    test "a qualifier under a bold label leaves the feat readable" do
      parsed =
        Requirements.class(
          """
          '''[[Base attack bonus]]''': +7
          '''Feats''': [[weapon focus]] in a [[melee weapon]]
          """,
          lookup()
        )

      assert parsed.requirements == [
               {"base_attack_bonus", 7},
               {"feats", ["weapon_focus"]},
               {"qualifiers", ["in a melee weapon"]}
             ]

      assert parsed.unparsed == []
    end

    # "(requires [[ride]] 1)" is an aside about the required *feat's* own
    # prerequisites — the inline form of the `''Note:''` paragraph the parser
    # already lifts off a label. Kept rather than dropped, so that one naming a
    # condition the block does not repeat stays visible.
    test "an aside about the required feat's own prerequisites is a qualifier" do
      parsed =
        Requirements.class("'''Feats:''' [[weapon focus]] (requires [[ride]] 1)", lookup())

      assert parsed.requirements == [
               {"feats", ["weapon_focus"]},
               {"qualifiers", ["(requires ride 1)"]}
             ]
    end
  end

  defp requirements(raw), do: Requirements.feat(raw, lookup()).requirements
end
