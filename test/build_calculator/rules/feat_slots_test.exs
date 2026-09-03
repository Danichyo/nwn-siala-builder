defmodule BuildCalculator.Rules.FeatSlotsTest do
  @moduledoc """
  Feat slots and what they accept.

  Slot levels come from `epic.json` (general feats) and `classes.json`
  (`bonus_feat_levels` / `epic_bonus_feat_levels`, which are class levels);
  acceptance comes from each feat's `type` and `bonus_for` in `feats.json`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  describe "general slots" do
    # source: epic.json general_feats — levels 1, 3, 6, 9, 12, 15, 18 then
    # 21, 24, 27, 30, 33, 36, 39 (fandom "Level progression" revid 51665).
    # Level 41 is not a multiple of three, so it grants none.
    test "arrive on the levels the ruleset lists", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:wizard, 41))
      levels = for {level, slots} <- FeatSlots.all(build, ruleset), general?(slots), do: level

      assert Enum.sort(levels) == [1, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39]
    end

    test "become epic-general once the character is epic", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:wizard, 41))

      assert [%{id: :general, kind: :general}] = FeatSlots.at(build, ruleset, 18)
      assert [%{id: :general, kind: :epic_general}] = FeatSlots.at(build, ruleset, 21)
    end

    # ✅ Измерено в игре: Dan, 04.08.2026 — «dual wield автоматически даётся
    # и не занимает слот фита».
    #
    # ⚠️ Это снимает подозрение, которое числилось в CLAUDE.md §9 как «похоже
    # на двойной учёт»: у рейнджера 1-го уровня модель ОДНОВРЕМЕННО выдаёт
    # `dual_wield_feat` и открывает бонусный слот, и выглядело это как удвоение.
    # Оказалось — так и в игре: выдача идёт сверх слота, а слот остаётся
    # свободным выбором. Тест держит обе половины сразу, потому что поодиночке
    # каждая выглядит правильной и при неверной модели тоже.
    test "рейнджеру на 1-м уровне выдача не съедает бонусный слот", %{ruleset: ruleset} do
      ranger = Build.new(race: :human, levels: [:ranger])

      assert Enum.any?(FeatSlots.at(ranger, ruleset, 1), &match?(%{kind: :class_bonus}, &1)),
             "бонусный слот рейнджера на 1-м уровне (подтверждён Даном, CLAUDE.md §3)"

      assert MapSet.member?(Build.feats_owned(ranger, ruleset, 1), :dual_wield_feat),
             "dual wield выдаётся классом сам"
    end

    # ✅ Продолжение того же замера (Dan, 04.08.2026): «ranger ещё на 9 лвл
    # получает improved two-weapon fighting».
    #
    # Уровень 9 держит вторую половину правила: бонусных уровней у рейнджера
    # пять — 1/5/10/15/20, — и девятого среди них НЕТ. Значит на 9-м фит
    # приходит выдачей, а стоящий там слот — общий, за уровень персонажа
    # (девять кратно трём), и он остаётся свободным. Тест ловит обе ошибки,
    # которые тут возможны: «выдачу забыли» и «выдаче приписали классовый слот».
    test "выдача рейнджера на 6-м и 9-м уровнях идёт без классового слота", %{
      ruleset: ruleset
    } do
      ranger = Build.new(race: :human, levels: List.duplicate(:ranger, 9))

      owned = Build.feats_owned(ranger, ruleset, 9)
      assert MapSet.member?(owned, :animal_companion_feat)
      assert MapSet.member?(owned, :improved_two_weapon_fighting)

      for level <- [6, 9] do
        slots = FeatSlots.at(ranger, ruleset, level)

        refute Enum.any?(slots, &match?(%{kind: :class_bonus}, &1)),
               "на #{level}-м бонусного слота у рейнджера нет: они на 1/5/10/15/20"

        assert Enum.any?(slots, &match?(%{kind: :general}, &1)),
               "но общий слот за уровень персонажа на месте — #{level} кратно трём"
      end
    end

    # source: races.json — human extra_feats %{level: 1, count: 1}
    # (fandom "Human" revid 70207)
    test "humans get one more slot at level 1", %{ruleset: ruleset} do
      human = Build.new(race: :human, levels: [:wizard])
      elf = Build.new(race: :elf, levels: [:wizard])

      assert Enum.map(FeatSlots.at(human, ruleset, 1), & &1.id) == [:general, :racial]
      assert Enum.map(FeatSlots.at(elf, ruleset, 1), & &1.id) == [:general]
    end
  end

  describe "class bonus slots" do
    # source: classes.json — fighter bonus_feat_levels [1,2,4,6,8,10,12,14,16,18,20]
    # and epic_bonus_feat_levels [22,24,...,40], both class levels
    # (fandom "Fighter" revid 71988).
    test "follow class levels, not character levels", %{ruleset: ruleset} do
      # two wizard levels first, so fighter class level lags the character level
      build = Build.new(levels: [:wizard, :wizard] ++ List.duplicate(:fighter, 6))

      # character level 3 is fighter class level 1 -> a bonus slot, plus the
      # every-third-level general slot
      assert Enum.map(FeatSlots.at(build, ruleset, 3), & &1.id) == [
               :general,
               {:class_bonus, :fighter}
             ]

      # character level 4 is fighter class level 2 -> the bonus slot alone
      assert [%{id: {:class_bonus, :fighter}}] = FeatSlots.at(build, ruleset, 4)
      # character level 5 is fighter class level 3 -> nothing
      assert FeatSlots.at(build, ruleset, 5) == []
    end

    test "a level can grant a general and a class bonus slot at once", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 6))

      assert Enum.map(FeatSlots.at(build, ruleset, 1), & &1.id) == [
               :general,
               {:class_bonus, :fighter}
             ]

      # level 6: general (every third) and fighter class level 6
      assert Enum.map(FeatSlots.at(build, ruleset, 6), & &1.id) == [
               :general,
               {:class_bonus, :fighter}
             ]
    end

    test "a class with no bonus feat levels grants none", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:barbarian, 10))

      assert Enum.all?(
               1..10,
               &(FeatSlots.at(build, ruleset, &1) |> Enum.all?(fn s -> s.class == nil end))
             )
    end

    # source: fandom `Bonus feat` — «each class has a single list of bonus feat
    # choices that is used regardless of whether or not the bonus can be called
    # "epic"», and the class pages of all seven classes with pre-epic bonus
    # feats say the same in their own words (Fighter: «If the character is an
    # epic character, then the epic fighter bonus feats are also available»).
    #
    # So what opens the epic half of the list is the **character** being epic,
    # never the class level. The pair below is the whole rule: the same Fighter
    # class level 1, once reached at character level 1 and once at 22.
    test "the epic list opens on the character being epic, not the class level", %{
      ruleset: ruleset
    } do
      early = Build.new(levels: [:fighter])
      late = Build.new(levels: List.duplicate(:wizard, 21) ++ [:fighter])

      assert Build.class_level_at(late, 22) == 1
      refute MapSet.member?(ruleset.classes[:fighter].epic_bonus_feat_levels, 1)

      assert [_general, %{id: {:class_bonus, :fighter}, epic?: false}] =
               FeatSlots.at(early, ruleset, 1)

      assert [%{id: {:class_bonus, :fighter}, epic?: true}] = FeatSlots.at(late, ruleset, 22)
    end

    # The example `fandom:Bonus feat` gives in full: «an epic character taking a
    # fifth ranger level could potentially substitute ''epic prowess'' (a ranger
    # epic bonus feat) for the favored enemy normally obtained at that level.»
    # Ranger class level 5 is pre-epic and `epic prowess` lists ranger.
    test "an epic character may spend a pre-epic class bonus on an epic feat", %{
      ruleset: ruleset
    } do
      build = Build.new(levels: List.duplicate(:wizard, 21) ++ List.duplicate(:ranger, 5))

      assert Build.class_level_at(build, 26) == 5
      assert [slot] = FeatSlots.at(build, ruleset, 26)
      assert FeatSlots.accepts?(ruleset, slot, :epic_prowess)
      # and the favoured enemy it replaces is still on offer
      assert FeatSlots.accepts?(ruleset, slot, :favored_enemy)
    end

    # AGENT_QUEUE.md §1.8: Dan observed on the test server that Siala's five
    # custom weapon-proficiency feats are offered on the Ranger's bonus slot —
    # the wiki names that slot "when it picks a favoured enemy" rather than
    # "доп фитах", but it is the same slot `bonus_feat_levels` already opens
    # (`overrides.json` → `feats.bonus_slot_aliases`).
    test "a ranger's ordinary bonus slot also takes the five weapon-proficiency feats", %{
      ruleset: ruleset
    } do
      build = Build.new(race: :human, levels: List.duplicate(:ranger, 5))

      assert [%{id: {:class_bonus, :ranger}, epic?: false} = slot] =
               FeatSlots.at(build, ruleset, 5)

      # the ability it competes with, per Dan (04.08.2026): one slot, either/or
      assert FeatSlots.accepts?(ruleset, slot, :favored_enemy)

      for id <- [
            :siala_blade_proficiency,
            :siala_axe_proficiency,
            :siala_hammer_proficiency,
            :siala_polearm_proficiency,
            :siala_ranged_proficiency
          ] do
        assert FeatSlots.accepts?(ruleset, slot, id), "#{id} должен быть кандидатом"
        assert id in FeatSlots.candidates(ruleset, slot)
      end
    end

    # Positive control on the same slot: a class no page ever names must stay
    # refused, or a bug that opened the slot to every feat (not just these
    # five, or every class rather than just Ranger) would pass silently.
    test "the ranger's bonus slot still refuses an unrelated feat", %{ruleset: ruleset} do
      slot = %{id: {:class_bonus, :ranger}, kind: :class_bonus, class: :ranger, epic?: false}

      refute FeatSlots.accepts?(ruleset, slot, :empower_spell)

      wizard_slot = %{
        id: {:class_bonus, :wizard},
        kind: :class_bonus,
        class: :wizard,
        epic?: false
      }

      refute FeatSlots.accepts?(ruleset, wizard_slot, :siala_blade_proficiency)
    end
  end

  # ── a level that grants TWO bonus slots ──────────────────────────────────
  #
  # source: `priv/wiki_cache/fandom/Ranger.wikitext` (revid 68113), and the wiki
  # says it three separate times:
  #
  #   * the epic progression table's own row — `|35th ||align=left|2 bonus feats`
  #     (every other row in the corpus says a bare `bonus feat`);
  #   * the `'''Bonus feats:'''` label above it — «The epic ranger gains a bonus
  #     feat every three levels and every five levels after the 20th. In other
  #     words, at levels 23, 25, 26, 29, 30, 32, **35(two bonus feats)**, 38, and
  #     40.»;
  #   * `fandom:Bonus feat`'s cross-class table, whose «Epic ranger» row carries
  #     `12<br />13` in the level-35 cell — the only two-valued cell in either of
  #     its two tables.
  #
  # And a build page agrees from the other side: «Мастер Ловушек» (siala revid
  # 17928) takes `favored_enemy` twice on its 40th character level, which is its
  # 35th ranger level (`wiki_builds_test.exs`).
  #
  # ⚠ Until 14.08.2026 the player simply lost the second feat: `FeatSlots.at/3`
  # returned one slot, and `epic_bonus_feat_levels` is a MapSet that cannot carry
  # a count to say otherwise.
  describe "a class level that grants more than one bonus slot" do
    test "ranger 35 grants two, and its neighbours one each", %{ruleset: ruleset} do
      build = Build.new(race: :human, levels: List.duplicate(:ranger, 41))

      # ⚠ Both halves in one test on purpose. «Two at 35» alone passes on a model
      # that hands every ranger level two slots, and «one at 32/38» alone passes
      # on the broken model this replaces; only the pair pins the rule.
      assert Enum.map(FeatSlots.at(build, ruleset, 35), & &1.id) == [
               {:class_bonus, :ranger},
               {:class_bonus, :ranger, 2}
             ]

      for level <- [32, 38] do
        assert Enum.map(FeatSlots.at(build, ruleset, level), & &1.id) == [
                 {:class_bonus, :ranger}
               ],
               "ranger class level #{level} grants exactly one bonus slot"
      end
    end

    test "the second slot is a bonus slot in full, not a decoration", %{ruleset: ruleset} do
      build = Build.new(race: :human, levels: List.duplicate(:ranger, 41))

      assert [first, second] = FeatSlots.at(build, ruleset, 35)

      assert %{kind: :class_bonus, class: :ranger, taken_with: :ranger, epic?: true} = second
      assert Map.delete(first, :id) == Map.delete(second, :id)

      # It draws on the same pool, epic half included — the character is epic.
      assert FeatSlots.accepts?(ruleset, second, :favored_enemy)
      assert FeatSlots.accepts?(ruleset, second, :epic_prowess)
      refute FeatSlots.accepts?(ruleset, second, :empower_spell)
    end

    # The whole point of two ids: `build.feats[level]` is a **map** keyed by slot
    # id, so one id would mean the second pick silently overwrote the first —
    # the same loss the fix removes, moved one layer down.
    test "both slots hold a pick of their own, and both reach the build", %{ruleset: ruleset} do
      build =
        Build.new(race: :human, levels: List.duplicate(:ranger, 41))
        |> Build.put_feat(35, {:class_bonus, :ranger}, :epic_prowess)
        |> Build.put_feat(35, {:class_bonus, :ranger, 2}, :epic_toughness)

      assert map_size(build.feats[35]) == 2

      owned = Build.feats_owned(build, ruleset, 41)
      assert MapSet.member?(owned, :epic_prowess)
      assert MapSet.member?(owned, :epic_toughness)

      # …and the core does not call either of them illegal.
      assert Rules.illegal_feats(build, ruleset) == []
    end

    # The shape the source itself describes: the ladder line of «Мастер Ловушек»
    # spends this level on two favoured enemies, and a favoured enemy carries a
    # creature type. So the two slots have to keep two **different** values of
    # the same feat apart, not merely two different feats.
    test "the two slots keep two picks of the SAME feat apart, values and all", %{
      ruleset: ruleset
    } do
      build =
        Build.new(race: :human, levels: List.duplicate(:ranger, 41))
        |> Build.put_feat(35, {:class_bonus, :ranger}, :favored_enemy, :dwarf)
        |> Build.put_feat(35, {:class_bonus, :ranger, 2}, :favored_enemy, :elf)

      assert Build.feat_choices(build, :favored_enemy, 41) == [:dwarf, :elf]
      assert Rules.illegal_feats(build, ruleset) == []
    end

    # `slot_order/1` is what every printed list of one level's picks goes
    # through (the export, the view screen's guide, `feat_picks/2`), so the two
    # have to come out in slot order and stay behind the general one.
    test "the two sort after the general slot and by their own index", %{ruleset: _ruleset} do
      build =
        Build.new(race: :human, levels: List.duplicate(:ranger, 41))
        |> Build.put_feat(35, {:class_bonus, :ranger, 2}, :blinding_speed)
        |> Build.put_feat(35, {:class_bonus, :ranger}, :epic_prowess)
        |> Build.put_feat(35, :general, :toughness)

      assert Build.feat_picks(build, 41) == [
               {35, :general, :toughness, nil},
               {35, {:class_bonus, :ranger}, :epic_prowess, nil},
               {35, {:class_bonus, :ranger, 2}, :blinding_speed, nil}
             ]
    end

    # ⚠ Whether any OTHER class level anywhere grants more than one is a question
    # about the data, not about the ranger, and it is asked of the whole corpus
    # rather than of the one class this fix came from (CLAUDE.md §3 — «проверять
    # на всей доступной выборке»). Checked 14.08.2026 by scanning every
    # `feats_raw` cell of every progression and epic table on both rulesets:
    # ranger 35 is the only one. Should the wiki ever grow a second, this fails
    # and a human decides — it does not silently keep counting one.
    test "ranger 35 is the only multiple in the whole corpus, on both rulesets" do
      for version <- ["vanilla", "siala_41"] do
        ruleset = Data.ruleset!(version)

        multiples =
          for {id, definition} <- ruleset.classes,
              {level, count} <- Map.get(definition, :bonus_feat_counts, %{}),
              do: {id, level, count}

        assert Enum.sort(multiples) == [{:ranger, 35, 2}], "ruleset #{version}"
      end
    end

    # The two fields are one fact read twice, so they must not drift: a class
    # level with a count has to be a level the class grants a slot on at all,
    # or the count would be describing a slot nobody hands out.
    test "every level with a count is a level the class grants a slot on" do
      for version <- ["vanilla", "siala_41"],
          ruleset = Data.ruleset!(version),
          {id, definition} <- ruleset.classes,
          {level, count} <- Map.get(definition, :bonus_feat_counts, %{}) do
        assert count > 1,
               "#{version}/#{id}: a count of #{count} says nothing and should be absent"

        assert MapSet.member?(definition.bonus_feat_levels, level) or
                 MapSet.member?(definition.epic_bonus_feat_levels, level),
               "#{version}/#{id}: class level #{level} carries a count but grants no bonus slot"
      end
    end
  end

  describe "acceptance" do
    # CLAUDE.md §6: slots are not interchangeable. The Fighter bonus takes only
    # feats that list fighter in bonus_for (feats.json).
    test "a class bonus slot takes only that class's list", %{ruleset: ruleset} do
      slot = %{id: {:class_bonus, :fighter}, kind: :class_bonus, class: :fighter, epic?: false}

      # power_attack bonus_for [champion_of_torm, fighter] (fandom revid 70426)
      assert FeatSlots.accepts?(ruleset, slot, :power_attack)
      # empower_spell is a wizard/sorcerer bonus, not a fighter one
      refute FeatSlots.accepts?(ruleset, slot, :empower_spell)
    end

    test "a general slot refuses epic feats, an epic-general one takes them", %{ruleset: ruleset} do
      general = %{id: :general, kind: :general, class: nil, epic?: false}
      epic = %{id: :general, kind: :epic_general, class: nil, epic?: true}

      assert FeatSlots.accepts?(ruleset, general, :power_attack)
      # epic_toughness: type general, epic true (feats.json)
      refute FeatSlots.accepts?(ruleset, general, :epic_toughness)
      assert FeatSlots.accepts?(ruleset, epic, :epic_toughness)
      assert FeatSlots.accepts?(ruleset, epic, :power_attack)
    end

    test "a pre-epic class bonus slot refuses epic feats", %{ruleset: ruleset} do
      pre_epic = %{
        id: {:class_bonus, :fighter},
        kind: :class_bonus,
        class: :fighter,
        epic?: false
      }

      epic = %{pre_epic | epic?: true}

      # epic_toughness lists fighter in bonus_for
      refute FeatSlots.accepts?(ruleset, pre_epic, :epic_toughness)
      assert FeatSlots.accepts?(ruleset, epic, :epic_toughness)
    end

    test "an unknown feat is accepted by nothing", %{ruleset: ruleset} do
      slot = %{id: :general, kind: :general, class: nil, epic?: false}
      refute FeatSlots.accepts?(ruleset, slot, :no_such_feat)
    end

    # ⚠ Fandom's `type` is a taxonomy of feats, not a flag saying which slot
    # takes one, and reading it as a flag cost four legal feats on the wiki
    # builds. The whole vocabulary is split here rather than the handful of
    # feats a fixture happens to reach, so a value nobody thought about cannot
    # slip in as "general" or out of it by accident. The vocabulary itself is
    # pinned in `test/build_calculator/wiki/parsed_snapshot_test.exs`; this says
    # what each of its values *means* to a slot.
    #
    # `false` = the page says the feat is handed out rather than chosen:
    # `Class feat` («type of "class" … means the feat is not a general feat»),
    # `Racial feat` («given … at character creation on the basis of … race»),
    # `Darkvision` (both at once, `use=automatic`), `Blindsight, 60 foot radius`
    # («only available for NPCs by default»), `DM tool` («All DM characters
    # start with this instant feat»).
    @type_is_choosable %{
      "class" => false,
      "classrace" => false,
      "instant custom" => false,
      "monster" => false,
      "race" => false,
      "combat" => true,
      "defensive" => true,
      "epic spell" => true,
      "general" => true,
      "item creation" => true,
      "metamagic" => true,
      "special" => true,
      "spell" => true
    }

    test "the whole feat type vocabulary is classified", %{ruleset: ruleset} do
      types = for {_id, feat} <- ruleset.feats, feat.type != nil, uniq: true, do: feat.type

      assert Enum.sort(types) == Enum.sort(Map.keys(@type_is_choosable)),
             """
             a feat type appeared or left the data — decide what a general slot
             does with it, do not let it default.
             new:  #{inspect(types -- Map.keys(@type_is_choosable))}
             gone: #{inspect(Map.keys(@type_is_choosable) -- types)}
             """

      refused = for {type, false} <- @type_is_choosable, do: type
      assert Enum.sort(FeatSlots.granted_not_chosen()) == Enum.sort(refused)
    end

    test "an epic general slot admits exactly the choosable types", %{ruleset: ruleset} do
      slot = %{id: :general, kind: :epic_general, class: nil, epic?: true}

      # `disabled?` is a separate refusal (Siala switched `Devastating critical`
      # off), so it would answer for its whole type if it were counted here.
      # `siala_only?` feats are excluded for a stronger reason: their `type` is
      # not this vocabulary at all — see the test below.
      verdicts =
        for {id, feat} <- ruleset.feats,
            feat.type != nil,
            not feat.disabled?,
            not feat.siala_only?,
            reduce: %{} do
          acc ->
            Map.update(
              acc,
              feat.type,
              MapSet.new([FeatSlots.accepts?(ruleset, slot, id)]),
              &MapSet.put(&1, FeatSlots.accepts?(ruleset, slot, id))
            )
        end

      assert Map.new(verdicts, fn {type, results} -> {type, MapSet.to_list(results)} end) ==
               Map.new(@type_is_choosable, fn {type, verdict} -> {type, [verdict]} end)
    end

    # ⚠ The vocabulary above is **Fandom's**. A shard-only feat has no Fandom
    # record and its `type` is the Siala page's «Тип навыка» label — a different
    # field that happens to spell to some of the same strings. These two are the
    # proof that the two must not be pooled: both are «Тип навыка: Особый»,
    # which would read as Fandom's choosable `special`, and both pages say
    # «Умение нельзя выбрать при росте персонажа» — they are item abilities
    # («Обломок трезубца», «Шапка Железного Шута»), not level-up choices.
    #
    # ⚠ Since 09.08.2026 the refusal no longer *rests* on that reading: the data
    # states «нельзя выбрать при росте персонажа» outright
    # (`level_up_selectable?`), and `level_up_refusals/2` is what refuses them.
    # Both facts are asserted here on purpose — the flag, so the refusal has a
    # named cause, and the type, because reading the type as a slot flag would
    # still be wrong for every other shard-only feat. That the flag and not the
    # type is now load-bearing is proved by corrupting the type in
    # `gear_feats_test.exs`.
    test "a Siala «Особый» is not Fandom's `special`", %{ruleset: ruleset} do
      slot = %{id: :general, kind: :epic_general, class: nil, epic?: true}

      for id <- [:riding_sprint, :smile_of_death] do
        assert %{siala_only?: true, type: "special", prereqs: nil} = ruleset.feats[id]
        assert ruleset.feats[id].level_up_selectable? == false

        refute FeatSlots.accepts?(ruleset, slot, id), "#{id} cannot be chosen at level-up"
        assert FeatSlots.candidates(ruleset, slot) |> Enum.member?(id) == false

        assert FeatSlots.level_up_refusals(ruleset, id) ==
                 [{:not_selectable_at_level_up, id}]
      end

      # Fandom's own `special` stays choosable, so this refuses the provenance
      # and not the string — and it carries no flag of its own, which is what
      # keeps the two mechanisms apart.
      assert FeatSlots.accepts?(ruleset, slot, :extra_turning)
      assert ruleset.feats[:extra_turning].level_up_selectable?
      assert FeatSlots.level_up_refusals(ruleset, :extra_turning) == []
    end

    # A shard-only page that never says which slots take its feat leaves `type`
    # nil, and that is refused rather than assumed general — "the page did not
    # say" is not "it is a general feat" (CLAUDE.md §3). Exactly one record is
    # in that state and it is the right one: «Фокусировки на школы магии» is a
    # page about a *family* of eight feats, and there is no feat by that name to
    # take. The five custom weapon proficiencies do state their slots
    # (`Возможность взятия фита` → `general: true`) and are offered normally.
    test "a shard feat whose page names no slot is offered by none", %{ruleset: ruleset} do
      slot = %{id: :general, kind: :epic_general, class: nil, epic?: true}
      untyped = for {id, %{type: nil}} <- ruleset.feats, do: id

      assert untyped == [:siala_spell_school_focus]
      refute FeatSlots.accepts?(ruleset, slot, :siala_spell_school_focus)

      assert ruleset.feats[:siala_blade_proficiency].type == "general"
      assert FeatSlots.accepts?(ruleset, slot, :siala_blade_proficiency)
    end

    test "candidates/2 lists exactly what accepts?/3 admits", %{ruleset: ruleset} do
      slot = %{
        id: {:class_bonus, :weapon_master},
        kind: :class_bonus,
        class: :weapon_master,
        epic?: false
      }

      candidates = FeatSlots.candidates(ruleset, slot)

      assert candidates != []
      assert Enum.all?(candidates, &FeatSlots.accepts?(ruleset, slot, &1))
    end
  end

  # source: два независимых источника, слитых в один ключ.
  #   1. Лейбл `Unavailable feats` на каждой из 23 страниц КЛАССОВ Fandom —
  #      «These [[general feat]]s cannot be selected when taking a level of X»
  #      (240 пар, 18 фитов).
  #   2. Раздел `Notes` на страницах самих ФИТОВ — «cannot be selected when
  #      gaining a monk level (even prior to level 6)» и «taking a level of
  #      Harper scout» (ещё 4 пары, 09.08.2026).
  # Итого в `classes.json` → `unavailable_feats` **244 пары**; снапшот закреплён
  # в `parsed_snapshot_test.exs`.
  #
  # ⚠️ На **siala_41** пар не 244, а **229**: замер H1 (`GAME_CHECKS.md`, Dan
  # 09.08.2026) показал, что вору `Brew Potion` предлагается, и все 15 его
  # запретов сняты одной записью `unavailable_for_classes: []` в ручном слое.
  # Ванильный ruleset по-прежнему несёт 244 — проверено ниже, «оба ruleset'а
  # запрещают одинаково» стало «одинаково, кроме одного измеренного фита».
  describe "класс уровня сужает общий пул" do
    # ⚠️ Таблица «кому нельзя» — и рядом ТОТ ЖЕ фит там, где можно. Без второй
    # половины `refute` зеленел бы и от того, что фит не проходит в слот вообще
    # (эпический, не того типа, отключён шардом), — то есть проверял бы не то
    # правило (HANDOFF, «пустые проверки»).
    #
    # Ссылки на источник — по классу, у которого фит стоит в лейбле:
    #   quicken_spell           — Fighter, Ranger, Rogue, …  (не у Wizard)
    #   weapon_specialization   — Bard и все, кроме Fighter
    #   extra_turning           — Druid и все, кроме Cleric, Paladin, Blackguard
    #   curse_song              — все, кроме Bard и Harper scout
    #   two_weapon_fighting     — Ranger, Pale master, Shifter (не у Fighter)
    #
    # ⚠️ Две строки таблицы заменены волной 13 (09.08.2026), и обе — потому что
    # проверять стало нечего, а не потому, что «мешали»:
    #   * `{:druid, :weapon_proficiency_martial, :cleric}` → `extra_turning`.
    #     Фит выключен на Сиале целиком (замер H5), то есть его не берёт ни один
    #     слот ни на одном классе, и положительная половина строки («а на клирике
    #     можно») перестала существовать. Правило запрета такая строка больше не
    #     проверяла бы вовсе — `refute` зеленел бы от `disabled?`.
    #   * `{:monk, :brew_potion, :wizard}` удалена. Запрет снят у всех 15 классов
    #     (замер H1), запрещающего класса для этой пары просто нет.
    @forbidden [
      {:fighter, :quicken_spell, :wizard},
      {:bard, :weapon_specialization, :fighter},
      {:druid, :extra_turning, :cleric},
      {:cleric, :curse_song, :bard},
      {:ranger, :two_weapon_fighting, :fighter},
      {:ranger, :ambidexterity, :fighter},
      {:rogue, :spell_focus, :sorcerer}
    ]

    test "фит, снятый со списка класса, общий слот не берёт — а на другом классе берёт", %{
      ruleset: ruleset
    } do
      for {banning, feat, allowing} <- @forbidden do
        refuted = general_slot(ruleset, banning)
        allowed = general_slot(ruleset, allowing)

        refute FeatSlots.accepts?(ruleset, refuted, feat),
               "#{feat} нельзя выбрать на уровне #{banning}"

        refute feat in FeatSlots.candidates(ruleset, refuted),
               "#{feat} не должен быть и в кандидатах слота на уровне #{banning}"

        assert FeatSlots.accepts?(ruleset, allowed, feat),
               "#{feat} на уровне #{allowing} обязан быть доступен — иначе refute выше пуст"

        assert feat in FeatSlots.candidates(ruleset, allowed)
      end
    end

    # Причина — машинный тапл, и его отдаёт ядро, а не собирает веб-слой.
    test "отказ приходит формой {:forbidden_by_class, класс}", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter])

      assert Rules.class_feat_refusals(build, 1, :quicken_spell, ruleset) ==
               [{:forbidden_by_class, :fighter}]

      assert Rules.class_feat_refusals(build, 1, :power_attack, ruleset) == []

      # `two_weapon_fighting` требований не имеет вовсе (`prereqs: null`),
      # поэтому у рейнджера отказ ровно один и он этот — а у воина отказа нет.
      assert Rules.validate_feat(Build.new(levels: [:ranger]), :two_weapon_fighting, ruleset) ==
               {:error, [forbidden_by_class: :ranger]}

      assert Rules.validate_feat(Build.new(levels: [:fighter]), :two_weapon_fighting, ruleset) ==
               :ok
    end

    # ⚠️ Позитивный контроль против пустой проверки: если `taken_with` не
    # заполняется, весь запрет молча выключается, а все `refute` выше
    # продолжают зеленеть по другой причине.
    test "каждый слот знает класс своего уровня", %{ruleset: ruleset} do
      build = Build.new(race: :human, levels: List.duplicate(:fighter, 21))

      for level <- [1, 3, 21], slot <- FeatSlots.at(build, ruleset, level) do
        assert slot.taken_with == :fighter, "#{level}: #{inspect(slot.id)}"
      end

      # и все четыре вида слотов покрыты этой лестницей
      kinds = for level <- [1, 3, 21], slot <- FeatSlots.at(build, ruleset, level), do: slot.kind
      assert Enum.sort(Enum.uniq(kinds)) == [:class_bonus, :epic_general, :general, :racial]
    end

    # Мультикласс на лимите ruleset'а: пул меняется от уровня к уровню, и
    # запрещает только тот класс, чей уровень берётся. Число классов берётся
    # из ruleset'а, а не пишется цифрой.
    test "у билда из четырёх классов пул свой на каждом уровне", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: [
            :fighter,
            :fighter,
            :wizard,
            :wizard,
            :wizard,
            :cleric,
            :cleric,
            :cleric,
            :bard
          ]
        )

      assert MapSet.size(Build.classes_used(build)) == ruleset.max_classes

      table = [
        {1, :fighter, [quicken_spell: false, weapon_specialization: true, curse_song: false]},
        {3, :wizard, [quicken_spell: true, weapon_specialization: false, curse_song: false]},
        {6, :cleric, [quicken_spell: true, weapon_specialization: false, curse_song: false]},
        {9, :bard, [quicken_spell: true, weapon_specialization: false, curse_song: true]}
      ]

      for {level, class, expected} <- table do
        assert Build.class_at(build, level) == class
        assert %{id: :general} = slot = general_slot_at(build, ruleset, level)

        for {feat, allowed?} <- expected do
          assert FeatSlots.accepts?(ruleset, slot, feat) == allowed?,
                 "уровень #{level} (#{class}): #{feat} должен быть #{allowed?}"
        end
      end
    end

    # Границы лестницы: первый уровень, первый эпический и кап. На 41-м общего
    # слота нет вовсе (41 не кратно трём), поэтому граница проверяется тем
    # вопросом, которому слот не нужен.
    test "правило держится на 1-м, 21-м и 41-м уровнях", %{ruleset: ruleset} do
      build = Build.new(race: :human, levels: List.duplicate(:fighter, ruleset.level_cap))

      for level <- [1, 21] do
        slot = general_slot_at(build, ruleset, level)
        refute FeatSlots.accepts?(ruleset, slot, :quicken_spell)
        assert FeatSlots.accepts?(ruleset, slot, :power_attack)
      end

      assert Enum.all?(FeatSlots.at(build, ruleset, ruleset.level_cap), &(&1.id != :general)),
             "на капе общего слота нет — 41 не кратно трём"

      assert Rules.class_feat_refusals(build, ruleset.level_cap, :quicken_spell, ruleset) ==
               [{:forbidden_by_class, :fighter}]
    end

    # ⚠️ Обратная ошибка, которую никто не поймает: запрет говорит «нельзя
    # ВЫБРАТЬ на этом уровне» и не отбирает уже взятое. Фит, законно взятый
    # на уровне волшебника, остаётся законным после того, как билд добрал
    # воинских уровней.
    test "взятое на законном уровне не становится нелегальным задним числом", %{
      ruleset: ruleset
    } do
      # Девять уровней волшебника, чтобы `casts_spell_level: 4` у самого фита
      # было выполнено: иначе отказ пришёл бы по требованию, а не по классу,
      # и тест проверял бы не то.
      legal =
        Build.new(
          levels: List.duplicate(:wizard, 9) ++ List.duplicate(:fighter, 3),
          base_abilities: %{str: 12, dex: 12, con: 12, int: 18, wis: 10, cha: 10},
          feats: %{9 => %{general: :quicken_spell}}
        )

      assert Rules.illegal_feats(legal, ruleset) == []
      assert Rules.validate_feat(legal, %{feat: :quicken_spell, at: 9}, ruleset) == :ok

      # Позитивный контроль: тот же фит на воинском уровне (12-й — воинский,
      # и общий слот там есть) — уже нарушение, названное поимённо, с уровнем.
      illegal = %{legal | feats: %{12 => %{general: :quicken_spell}}}

      assert Rules.illegal_feats(illegal, ruleset) == [
               {12, :general, :quicken_spell, {:forbidden_by_class, :fighter}}
             ]
    end

    # Смена класса уровня — тот самый сценарий бага 1.3 в новой форме: правка
    # раннего уровня обязана перепроверить стоящий там фит.
    test "смена класса уровня делает стоявший там фит нелегальным", %{ruleset: ruleset} do
      wizard =
        Build.new(
          levels: List.duplicate(:wizard, 9),
          base_abilities: %{str: 12, dex: 12, con: 12, int: 18, wis: 10, cha: 10},
          feats: %{9 => %{general: :quicken_spell}}
        )

      assert Rules.illegal_feats(wizard, ruleset) == []

      # Волшебник 8 всё ещё кастует 4-й круг, поэтому единственное, что меняет
      # правка, — класс самого уровня.
      edited = Build.replace_level(wizard, 9, :fighter)

      assert Rules.illegal_feats(edited, ruleset) == [
               {9, :general, :quicken_spell, {:forbidden_by_class, :fighter}}
             ]
    end

    # ⚠️ Тест ПРИНЯТОГО РЕШЕНИЯ, а не наблюдаемого поведения, и это сказано
    # прямо, потому что иначе он выглядел бы сильнее, чем есть.
    #
    # Запрет объявлен про общие фиты; бонусный слот берёт из своего списка
    # («selected from a restricted list of feats, also set forth in each class'
    # description» — fandom `Bonus feat`), поэтому ядро на него запрет не
    # распространяет. На реальных данных разницы НЕТ ни в одну сторону: ни один
    # класс не запрещает фит, который принял бы его же бонусный слот
    # (`parsed_snapshot_test.exs` роняет сборку, если это изменится). Значит
    # поймать здесь можно только сам код, и слот приходится собрать руками:
    # `at/3` такой не строит — у бонусного слота `taken_with` всегда равен
    # `class`. Тест держит границу правила, чтобы «заодно и бонусный» нельзя
    # было дописать молча.
    test "запрет не распространён на бонусный слот (граница правила)", %{ruleset: ruleset} do
      forbidden_for_ranger = :two_weapon_fighting

      assert MapSet.member?(ruleset.classes[:ranger].unavailable_feats, forbidden_for_ranger)
      assert MapSet.member?(ruleset.feats[forbidden_for_ranger].bonus_for, :fighter)

      # Синтетическая пара: уровень рейнджера (он запрещает) и бонусный слот
      # воина (он принимает). Совпасть в одном слоте они не могут, и ровно
      # поэтому ветку иначе не видно.
      synthetic = %{
        id: {:class_bonus, :fighter},
        kind: :class_bonus,
        class: :fighter,
        taken_with: :ranger,
        epic?: false
      }

      assert FeatSlots.accepts?(ruleset, synthetic, forbidden_for_ranger),
             "бонусный слот читает свой список, а не список запрещённых у класса уровня"

      # А общий слот на том же уровне рейнджера — отказывает.
      refute FeatSlots.accepts?(ruleset, general_slot(ruleset, :ranger), forbidden_for_ranger)
    end

    # Расовый слот человека тянет тот же пул, что общий («the choices for a
    # human's racial bonus feat are exactly all general feats» — fandom
    # `General feat`), поэтому запрет действует и на него. ⚠️ Это вывод из двух
    # источников, а не цитата — вопрос в `GAME_CHECKS.md`.
    test "расовый слот человека сужается так же, как общий", %{ruleset: ruleset} do
      human = Build.new(race: :human, levels: [:fighter])

      assert %{kind: :racial, taken_with: :fighter} =
               racial = Enum.find(FeatSlots.at(human, ruleset, 1), &(&1.kind == :racial))

      refute FeatSlots.accepts?(ruleset, racial, :quicken_spell)
      assert FeatSlots.accepts?(ruleset, racial, :power_attack)
    end

    # Слот без класса уровня (спрашивают про уровень за концом лестницы)
    # не запрещает ничего — и это не «разрешение по умолчанию», а отсутствие
    # уровня, про который правило говорит.
    test "уровня нет — сужать нечем", %{ruleset: ruleset} do
      empty = Build.new(levels: [])

      assert [%{taken_with: nil} = slot] = FeatSlots.at(empty, ruleset, 3)
      assert FeatSlots.accepts?(ruleset, slot, :quicken_spell)
      assert Rules.class_feat_refusals(empty, 3, :quicken_spell, ruleset) == []
    end

    # Ванильный ruleset обязан запрещать то же самое: список — факт Fandom,
    # а сиальский слой про запреты молчит почти везде, поэтому наследуется как
    # есть (и помечен гэпом, см. `loader_test`/`Labels`).
    test "оба ruleset'а запрещают одинаково" do
      for version <- ["vanilla", "siala_41"] do
        ruleset = Data.ruleset!(version)
        slot = general_slot(ruleset, :fighter)

        refute FeatSlots.accepts?(ruleset, slot, :quicken_spell), version
        assert FeatSlots.accepts?(ruleset, slot, :power_attack), version
      end
    end

    # ✅ Замер: Dan, тестовый сервер, 09.08.2026 — `GAME_CHECKS.md` кейс **H1**.
    # «Вору Brew Potion ПРЕДЛАГАЕТСЯ», уточнение того же дня: «у него в
    # требованиях строго Lore = 4 ранг минимум, других ограничений нет».
    #
    # До этого ядро отвечало `{:error, [forbidden_by_class: :rogue]}`, и запрет
    # был ЕДИНСТВЕННОЙ причиной отказа — то есть ложная нелегальность, которую
    # не ловит никто: игрок решает, что фит просто не подошёл.
    #
    # ⚠️ Три половины в одном тесте, и порознь каждая зеленела бы при неверной
    # модели: вор видит фит, бард видит его тоже (положительный контроль того же
    # захода — он видел и до правки), а **ваниль по-прежнему запрещает** — иначе
    # «сняли на Сиале» было бы неотличимо от «сняли везде».
    test "вор с Lore 4 видит Brew Potion — замер H1", %{ruleset: ruleset} do
      vanilla = Data.ruleset!("vanilla")

      for class <- [:rogue, :bard] do
        build = Build.new(race: :human, levels: [class], skills: %{1 => %{lore: 4}})

        assert Rules.validate_feat(build, :brew_potion, ruleset) == :ok, to_string(class)

        assert FeatSlots.accepts?(ruleset, general_slot(ruleset, class), :brew_potion),
               "#{class}: фит обязан быть и в пуле общего слота, а не только проходить проверку"
      end

      # Требование при этом на месте: без рангов отказ ровно один и он про Lore,
      # а не про класс. Без этой строки тест зеленел бы и от «сняли все проверки».
      no_lore = Build.new(race: :human, levels: [:rogue])

      assert Rules.validate_feat(no_lore, :brew_potion, ruleset) ==
               {:error, [{:requires_skill_ranks, :lore, 4}]}

      # Ваниль — та же пара, обратный ответ.
      assert Rules.class_feat_refusals(Build.new(levels: [:rogue]), 1, :brew_potion, vanilla) ==
               [{:forbidden_by_class, :rogue}]
    end

    # ⚠️ ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ к тесту выше, и он тут не для симметрии.
    # Замер **H4** того же дня проверял, работает ли механизм класс-листов на
    # Сиале ВООБЩЕ — на фите, которого шард не переписывал: рейнджер 1 с DEX 18
    # `Ambidexterity` не видит. DEX 18 в билде не для красоты: единственное
    # требование фита — DEX 15, и без него отказов было бы два, а проверялся бы
    # не тот.
    #
    # Значит правило узкое: `Brew Potion` — точечная правка шарда, а не признак
    # того, что списков нет. Остальные 229 пар стоят, и снимать что-то «по
    # аналогии» запрещено.
    test "но механизм класс-листов остался — замер H4", %{ruleset: ruleset} do
      dex = %{str: 10, dex: 18, con: 10, int: 10, wis: 10, cha: 10}
      ranger = Build.new(race: :human, levels: [:ranger], base_abilities: dex)

      assert Rules.validate_feat(ranger, :ambidexterity, ruleset) ==
               {:error, [forbidden_by_class: :ranger]}

      # Положительный контроль: тот же фит на уровне воина — берётся.
      fighter = Build.new(race: :human, levels: [:fighter], base_abilities: dex)
      assert Rules.validate_feat(fighter, :ambidexterity, ruleset) == :ok
    end

    # И то же самое числом, по всему корпусу: снялись ровно 15 пар одного фита,
    # остальное не поехало. Сторож против правки «заодно» — сняв ещё что-нибудь,
    # тест не сойдётся, даже если все именные проверки выше зеленеют.
    #
    # ⚠️ Здесь стояло «244 → 229», и это устарело 10.08.2026, когда прочитали
    # третье семейство `vanilla/feat_requirements.json` — «этот фит можно взять
    # ТОЛЬКО на уровне такого-то класса» (`only_on_class_levels`). Дополнение по
    # списку классов кладётся в тот же `unavailable_feats`, поэтому пар стало
    # больше, чем читается со страниц классов.
    #
    # ⚠️ Числа переписаны 16.08.2026 и посчитаны, а не переписаны глазами: замер
    # Dan (`GAME_CHECKS.md`, E7b/E7c) добавил ключ ещё двум фитам семейства
    # (`thundering_rage`, `terrifying_rage`), по 22 запрещённых класса на каждый.
    # Стало **443 / 428**, со страниц фитов — 199 пар вместо 155.
    #
    # ⚠️ И снова 17.08.2026, замером S4/S4b/S5: ключ получили четыре эпических
    # фита (`automatic_quicken_spell`, `automatic_silent_spell`,
    # `automatic_still_spell`, `epic_spell_penetration`), у каждого разрешено
    # ДЕВЯТЬ классов из 23, то есть по **14** запрещённых — 56 новых пар.
    # **443 → 499**, **428 → 484**, со страниц фитов 199 → **255**.
    #
    # ⚠️ И третий раз за те же сутки, замером S8: три «эпические формы
    # Оборотня» (`construct_shape`, `outsider_shape`, `undead_shape`) разрешены
    # ровно ОДНОМУ классу, то есть по **22** запрещённых — 66 новых пар.
    # **499 → 565**, **484 → 550**, со страниц фитов 255 → **321**.
    #
    # ⚠️ И четвёртый раз, 25.08.2026, задачей 3.103 — но НЕ замером и НЕ новым
    # чтением. Предложение «This feat can only be acquired when advancing in
    # [[druid]] or [[shifter]] levels» лежало в записи `dragon_shape` с
    # 17.08.2026 и не работало: под вердиктом `not_binding` загрузчик ключ
    # не читает вовсе. Вердикт стал `applied` (требование наконец прочитано
    # целиком) — и ключ заработал сам, разрешённых классов ДВА, запрещённых
    # **21**. **565 → 586**, **550 → 571**, со страниц фитов 321 → **342**.
    #
    # Как считать (прогоном, не глазами): пары — сама сборка `pairs` ниже; ключ
    # `only_on_class_levels` несут **18** записей файла, список ниже — те же
    # восемнадцать поимённо; фитов в запретах стало 40 вместо 39.
    # Разница между ruleset'ами не изменилась вовсе: те же 15 пар `brew_potion`,
    # снятые замером H1, — и именно это тест сторожит. Слагаемое «со страниц
    # КЛАССОВ» тоже обязано остаться прежним (244), иначе «стало больше»
    # не отличить от «поехало».
    test "снято ровно 15 пар из 586, и только у brew_potion" do
      pairs = fn ruleset ->
        MapSet.new(
          for {id, class} <- ruleset.classes,
              feat <- MapSet.to_list(class.unavailable_feats),
              do: {id, feat}
        )
      end

      vanilla = pairs.(Data.ruleset!("vanilla"))
      siala = pairs.(Data.ruleset!("siala_41"))

      assert MapSet.size(vanilla) == 586
      assert MapSet.size(siala) == 571
      assert MapSet.subset?(siala, vanilla), "на Сиале не должно появиться НОВЫХ запретов"

      # Из чего собрались 586: 244 пары со страниц КЛАССОВ («These general feats
      # cannot be selected when taking a level of fighter») плюс 342 — дополнение
      # восемнадцати списков `only_on_class_levels` со страниц самих ФИТОВ
      # (у девяти из восемнадцати список стоит на замере, а не на прозе страницы —
      # разбор в записях `terrifying_rage`, `automatic_silent_spell`
      # и `undead_shape`).
      # Разложение проверяется числом, иначе «стало больше» нельзя отличить
      # от «поехало»: 244 обязаны остаться 244.
      from_feat_pages =
        for {_id, class} <- Data.ruleset!("vanilla").classes,
            feat <- MapSet.to_list(class.unavailable_feats),
            feat in [
              :mighty_rage,
              :thundering_rage,
              :terrifying_rage,
              :epic_weapon_specialization,
              :epic_spell_dragon_knight,
              :epic_spell_epic_mage_armor,
              :epic_spell_epic_warding,
              :epic_spell_greater_ruin,
              :epic_spell_hellball,
              :epic_spell_mummy_dust,
              :automatic_quicken_spell,
              :automatic_silent_spell,
              :automatic_still_spell,
              :epic_spell_penetration,
              :construct_shape,
              :outsider_shape,
              :undead_shape,
              :dragon_shape
            ],
            do: {class, feat}

      assert length(from_feat_pages) == 342
      assert MapSet.size(vanilla) - length(from_feat_pages) == 244

      lifted = MapSet.difference(vanilla, siala)
      assert Enum.map(lifted, &elem(&1, 1)) |> Enum.uniq() == [:brew_potion]

      assert lifted |> Enum.map(&elem(&1, 0)) |> Enum.sort() == [
               :arcane_archer,
               :assassin,
               :barbarian,
               :blackguard,
               :champion_of_torm,
               :dwarven_defender,
               :fighter,
               :harper_scout,
               :monk,
               :pale_master,
               :purple_dragon_knight,
               :red_dragon_disciple,
               :rogue,
               :shadowdancer,
               :weapon_master
             ]
    end

    # ⚠️ ЗАФИКСИРОВАННОЕ РЕШЕНИЕ НЕ ПРАВИТЬ, а не забытая строка.
    #
    # `Lingering Song` — второй и последний фит, у которого страница Сиалы
    # называет требования («Песня барда (Bard song).»), то есть правило из
    # замера H1 формально применимо и к нему. Запрет всё равно оставлен, и
    # причина проверяема ровно этим тестом: требование `bard_song` ядро
    # проверяет, но выполнить его умеет МУЛЬТИКЛАСС — у билда «бард 1 / X 2»
    # фит уже во владении, и единственное, что отказывает на втором уровне, —
    # сам запрет. То есть снятие открыло бы фит на уровне любого из 22 классов
    # любому билду с одним уровнем барда, а замера за этим нет ни одного.
    #
    # Без этого теста следующий читатель применит правило «для единообразия»
    # и внесёт ровно ту регрессию, от которой запрет и оставлен.
    test "Lingering Song: запрет оставлен сознательно", %{ruleset: ruleset} do
      banning =
        for {id, c} <- ruleset.classes,
            MapSet.member?(c.unavailable_feats, :lingering_song),
            do: id

      assert length(banning) == 22
      refute :bard in banning

      # Одноклассовый не-бард отвалился бы и без запрета — на нём разницы не видно.
      assert Rules.validate_feat(Build.new(levels: [:fighter]), :lingering_song, ruleset) ==
               {:error, [forbidden_by_class: :fighter, requires_feat: :bard_song]}

      # А вот тут видно: требование выполнено, и держит только запрет.
      multi = Build.new(race: :human, levels: [:bard, :fighter])

      assert Rules.validate_feat(multi, %{feat: :lingering_song, at: 2}, ruleset) ==
               {:error, [forbidden_by_class: :fighter]}

      # Положительный контроль: на уровне барда фит берётся.
      assert Rules.validate_feat(Build.new(levels: [:bard]), :lingering_song, ruleset) == :ok
    end

    defp general_slot(ruleset, class),
      do: general_slot_at(Build.new(levels: [class]), ruleset, 1)

    defp general_slot_at(build, ruleset, level),
      do: Enum.find(FeatSlots.at(build, ruleset, level), &(&1.id == :general))
  end

  describe "compute/2" do
    test "reports the slots of every level of the build", %{ruleset: ruleset} do
      build = Build.new(race: :human, levels: List.duplicate(:fighter, 3))
      stats = Rules.compute(build, ruleset)

      assert Map.keys(stats.feat_slots) |> Enum.sort() == [1, 2, 3]

      assert Enum.map(stats.feat_slots[1], & &1.id) == [
               :general,
               :racial,
               {:class_bonus, :fighter}
             ]

      assert Enum.map(stats.feat_slots[2], & &1.id) == [{:class_bonus, :fighter}]
      assert Enum.map(stats.feat_slots[3], & &1.id) == [:general]
    end
  end

  # ⚠️ Долг «покрытие машинерии мёртвого слота» (AGENT_QUEUE.md §7, HANDOFF.md):
  # вывод «мёртвых слотов не осталось» был сделан проверкой ОДНОГО уровня —
  # ровно тот случай «вывод по недостаточной выборке», против которого HANDOFF
  # и предупреждает. Проверено 18.08.2026 по всем классам обоих ruleset'ов:
  # предпосылка не воспроизвелась, мёртвых слотов нет. Тест здесь не потому,
  # что баг был, а потому что закрывать долг наблюдением без сторожа значит
  # закрыть его до следующего чужого вопроса.
  #
  # Охват назван числом, чтобы «проверено» было проверяемым: **154 пары
  # (класс, уровень слота) на каждом ruleset'е, 22 класса из 23** — у одного
  # бонусных слотов нет вовсе. Долг называл 13 пар у пяти классов; шире взято
  # не из усердия, а потому что «мёртвым» слот делает не класс, а данные,
  # и следующая правка `bonus_for` придёт к произвольному классу.
  #
  # «Мёртвый» = слот, который выдаётся, но заполнить его нечем. Сюда попадают
  # ДВА разных отсутствия, и разводить их обязательно:
  #
  #   1. пул пуст вовсе — ни один фит не называет этот класс в `bonus_for`;
  #   2. пул непуст, но все кандидаты требуют того, чего у стоящего в слоте
  #      быть не обязано, — то есть слот заполним не всегда, а «если повезло».
  #
  # Второе тише первого и потому опаснее: счётчик слотов сходится, а игрок
  # упирается в список, где всё серое.
  describe "мёртвый слот: выданный бонусный слот всегда есть чем заполнить" do
    for version <- ~w(siala_41 vanilla) do
      @version version

      test "#{version}: у каждого бонусного слота непустой пул", _ do
        ruleset = Data.ruleset!(@version)

        empty =
          for {id, class} <- ruleset.classes,
              levels = bonus_levels(class),
              levels != [],
              epic? <- epic_flags(class),
              slot = bonus_slot(id, epic?),
              FeatSlots.candidates(ruleset, slot) == [],
              do: {id, epic?}

        assert empty == [],
               "бонусный слот без единого кандидата: #{inspect(empty)}"
      end

      # Сильная половина: хотя бы один кандидат, чьи требования сводятся
      # к уровню персонажа и к уровням ТОГО ЖЕ класса не выше текущего, —
      # то есть выполнены самим фактом стояния в слоте, без удачи в билде.
      test "#{version}: у каждого есть кандидат, доступный любому, кто в нём стоит", _ do
        ruleset = Data.ruleset!(@version)

        dead =
          for {id, class} <- ruleset.classes,
              level <- bonus_levels(class),
              epic? = level in epic_levels(class),
              slot = bonus_slot(id, epic?),
              sure =
                Enum.filter(
                  FeatSlots.candidates(ruleset, slot),
                  &sure_thing?(ruleset, &1, id, level)
                ),
              sure == [],
              do: {id, level}

        assert dead == [],
               "слот, который нечем заполнить наверняка: #{inspect(dead)}"
      end
    end

    # Положительный контроль: проверка умеет отличать заполнимое от нет —
    # иначе оба теста выше зеленели бы на пустом множестве.
    test "проверка не пуста — у Теневого танцора на 13 кандидат называется поимённо", %{
      ruleset: ruleset
    } do
      slot = bonus_slot(:shadowdancer, true)

      sure =
        Enum.filter(
          FeatSlots.candidates(ruleset, slot),
          &sure_thing?(ruleset, &1, :shadowdancer, 13)
        )

      assert :epic_shadowlord in sure
    end
  end

  # ⚠️ Уровни слотов лежат MapSet'ом, а не списком — `++` на них падает
  # ArgumentError'ом, а не даёт пустоту. Это тот редкий случай, когда ошибка
  # шумная: молчаливая версия оставила бы тест зелёным на пустом множестве.
  defp levels_of(field), do: field |> Kernel.||([]) |> Enum.to_list()

  defp bonus_levels(class),
    do: Enum.sort(levels_of(class.bonus_feat_levels) ++ levels_of(class.epic_bonus_feat_levels))

  defp epic_levels(class), do: levels_of(class.epic_bonus_feat_levels)

  defp epic_flags(class),
    do: Enum.uniq(Enum.map(bonus_levels(class), &(&1 in epic_levels(class))))

  defp bonus_slot(class, epic?),
    do: %{
      id: {:class_bonus, class},
      kind: :class_bonus,
      class: class,
      taken_with: class,
      epic?: epic?
    }

  # ⚠️ Ключи требований в ruleset'е — СТРОКИ, не атомы. Атомный вариант этой
  # проверки молча даёт ноль подходящих у всех классов сразу и читается как
  # находка «все слоты мертвы»; наступили при разведке 18.08.2026.
  defp sure_thing?(ruleset, feat_id, class, level) do
    prereqs = ruleset.feats[feat_id].prereqs || %{}
    own = prereqs["class_levels"] || %{}

    Map.drop(prereqs, ["character_level", "class_levels"]) == %{} and
      Map.keys(own) -- [to_string(class)] == [] and
      (own[to_string(class)] || 0) <= level
  end

  defp general?(slots), do: Enum.any?(slots, &(&1.id == :general))
end
