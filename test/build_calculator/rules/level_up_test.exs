defmodule BuildCalculator.Rules.LevelUpTest do
  @moduledoc """
  Level-up validation: machine-readable reasons, all of them at once.

  Caps and limits are read off the ruleset (`siala_41/overrides.json`,
  `vanilla/epic.json`); prerequisite reasons come from a class's structured
  `requirements`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, LevelUp, Spells}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "caps and limits from the ruleset" do
    # source: siala_41/overrides.json character.max_classes = 4, kind "user"
    # (Dan). Vanilla 1.69 allowed 3, NWN:EE patch 35 allows 8 — hence a ruleset
    # value and not a literal.
    test "the class limit is the ruleset's number", %{ruleset: ruleset} do
      assert ruleset.max_classes == 4

      three = Build.new(levels: [:fighter, :rogue, :wizard], alignment: :true_neutral)
      four = Build.add_level(three, :cleric)

      # a fourth class is fine
      assert Rules.validate_level_up(three, :cleric, ruleset) == :ok
      # a fifth is not, but taking more of one already used still is
      assert {:error, reasons} = Rules.validate_level_up(four, :sorcerer, ruleset)
      assert {:max_classes, 4} in reasons
      assert Rules.validate_level_up(four, :fighter, ruleset) == :ok
    end

    # source: siala_41/overrides.json character.level_cap = 41 (wiki
    # "41-ый уровень" revid 20387); vanilla epic.json caps at 40.
    test "the character level cap is the ruleset's number", %{ruleset: ruleset, vanilla: vanilla} do
      at_40 = Build.new(levels: List.duplicate(:fighter, 40))
      at_41 = Build.new(levels: List.duplicate(:fighter, 41))

      assert Rules.validate_level_up(at_40, :fighter, ruleset) == :ok

      # both the character cap and the class cap are hit, and both are reported
      assert {:error, reasons} = Rules.validate_level_up(at_41, :fighter, ruleset)
      assert {:level_cap, 41} in reasons
      assert {:class_level_cap, :fighter, 41} in reasons

      assert {:error, vanilla_reasons} = Rules.validate_level_up(at_40, :fighter, vanilla)
      assert {:level_cap, 40} in vanilla_reasons
    end

    # source: siala_41/overrides.json classes.prestige_level_cap = 31 with
    # except_max_level {purple_dragon_knight: 10, harper_scout: 5}
    # (wiki "41-ый уровень" revid 20387, class pages revid 20530 / 19414).
    test "per-class level caps come from the shard layer", %{ruleset: ruleset, vanilla: vanilla} do
      assert LevelUp.effective_class_level_cap(ruleset, ruleset.classes[:dwarven_defender]) == 31

      assert LevelUp.effective_class_level_cap(ruleset, ruleset.classes[:purple_dragon_knight]) ==
               10

      assert LevelUp.effective_class_level_cap(ruleset, ruleset.classes[:harper_scout]) == 5
      # a base class runs to the character level cap
      assert LevelUp.effective_class_level_cap(ruleset, ruleset.classes[:fighter]) == 41
      assert LevelUp.effective_class_level_cap(vanilla, vanilla.classes[:fighter]) == 40
    end

    test "exceeding a class cap is reported with the cap", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 20) ++ List.duplicate(:harper_scout, 5),
          alignment: :neutral_good
        )

      assert {:error, reasons} = Rules.validate_level_up(build, :harper_scout, ruleset)
      assert {:class_level_cap, :harper_scout, 5} in reasons
    end

    # source: epic.json epic_thresholds — "the 11th level of a prestige class
    # cannot be taken unless the character has a total of 20 levels already"
    # (fandom "Prestige class" revid 66794).
    test "the 11th prestige level needs 20 character levels", %{ruleset: ruleset} do
      early = Build.new(levels: List.duplicate(:dwarven_defender, 10), alignment: :lawful_good)

      assert {:error, reasons} = Rules.validate_level_up(early, :dwarven_defender, ruleset)
      assert {:requires_character_level, 20} in reasons

      late =
        Build.new(
          levels: List.duplicate(:fighter, 10) ++ List.duplicate(:dwarven_defender, 10),
          alignment: :lawful_good
        )

      assert {:error, late_reasons} = Rules.validate_level_up(late, :dwarven_defender, ruleset)
      refute {:requires_character_level, 20} in late_reasons
    end

    test "an unknown class is its own reason", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter])

      assert Rules.validate_level_up(build, :sorcerer_king, ruleset) ==
               {:error, [unknown_class: :sorcerer_king]}
    end
  end

  # ⚠️ Раздел заведён под починенный баг, а не под новую фичу. Правило «11-й
  # уровень престижа требует 20 уровней персонажа» считало свои две половины
  # от разных моментов: уровни престижа — по билду ЦЕЛИКОМ, уровень персонажа —
  # по моменту решения. На растущем билде это незаметно (целиком и есть момент),
  # а на готовой лестнице половины расходятся, и ядро обвиняло легальный билд
  # формы «Воин 10 / Мастер оружия 31» — ровно ту, что лежит на вики
  # («Мастер оружия Сагровик»). Форма `%{class:, at:}` — это импорт и регрессия.
  #
  # source: vanilla/epic.json epic_thresholds (fandom «Prestige class» revid 66794)
  describe "the pre-epic prestige ceiling is judged at one moment" do
    test "a legal finished ladder is accused nowhere on it", %{ruleset: ruleset} do
      # 11-й уровень Мастера оружия приходится на 21-й уровень персонажа.
      build = ladder(10, 31)

      assert too_early(build, ruleset) == []
    end

    # Положительный контроль: без него тест выше зеленел бы и в мире, где
    # проверка вообще перестала срабатывать. Та же лестница на уровень раньше —
    # 11-й уровень престижа падает на 20-й уровень персонажа, и это рано
    # ровно на единицу.
    test "and the ladder that really breaks the rule is still caught", %{ruleset: ruleset} do
      build = ladder(9, 11)

      # Обвиняется РОВНО тот уровень, на котором правило нарушено, а не вся
      # лестница класса: раньше отказ размазывался по всем его уровням.
      assert too_early(build, ruleset) == [20]
    end

    test "growing a build and editing a finished one agree, level by level", %{ruleset: ruleset} do
      # Два входа в ядро: конструктор растит билд по уровню, импорт проигрывает
      # готовую лестницу. По этому правилу они обязаны давать одно и то же —
      # расхождение половин и было расхождением этих двух входов.
      whole = ladder(9, 12)

      for {class, level} <- Enum.with_index(whole.levels, 1) do
        grown = Rules.validate_level_up(Build.truncate(whole, level - 1), class, ruleset)
        edited = Rules.validate_level_up(whole, %{class: class, at: level}, ruleset)

        assert character_level_reasons(grown) == character_level_reasons(edited),
               "уровень #{level} (#{class}): выращенный #{inspect(grown)} ≠ " <>
                 "правленый #{inspect(edited)}"
      end

      # И снова положительный контроль: сверять было что — на 20-м оба входа
      # отказывают, а не молчат.
      assert too_early(whole, ruleset) == [20]
    end
  end

  # Воин, затем Мастер оружия — форма «Сагровика» с вики, без фитов и рангов:
  # они этому правилу не нужны, и их отсутствие даёт свои отказы, которые
  # `too_early/2` отфильтровывает.
  defp ladder(fighter, weapon_master) do
    Build.new(
      levels: List.duplicate(:fighter, fighter) ++ List.duplicate(:weapon_master, weapon_master),
      alignment: :lawful_good
    )
  end

  # Уровни готовой лестницы, на которых ядро говорит «нужен 20-й уровень».
  defp too_early(build, ruleset) do
    for {class, level} <- Enum.with_index(build.levels, 1),
        result = Rules.validate_level_up(build, %{class: class, at: level}, ruleset),
        {:requires_character_level, _} <- character_level_reasons(result),
        do: level
  end

  defp character_level_reasons(:ok), do: []

  defp character_level_reasons({:error, reasons}),
    do: Enum.filter(reasons, &match?({:requires_character_level, _}, &1))

  describe "alignment restrictions" do
    # source: classes.json alignment_restriction_raw — monk "any lawful",
    # barbarian "any non-lawful", paladin "[[lawful good]] only", druid
    # "any [[neutral]]".
    test "are checked against the build's alignment", %{ruleset: ruleset} do
      table = [
        {:monk, :lawful_good, :ok},
        {:monk, :chaotic_good, :error},
        {:barbarian, :chaotic_neutral, :ok},
        {:barbarian, :lawful_neutral, :error},
        {:paladin, :lawful_good, :ok},
        {:paladin, :lawful_neutral, :error},
        {:druid, :true_neutral, :ok},
        {:druid, :lawful_good, :error}
      ]

      for {class, alignment, expected} <- table do
        build = Build.new(levels: [], alignment: alignment)
        result = Rules.validate_level_up(build, class, ruleset)

        case expected do
          :ok -> assert result == :ok, "#{class} / #{alignment}"
          :error -> assert {:error, [{:requires_alignment, _}]} = result
        end
      end
    end

    test "a build with no alignment cannot satisfy a restriction", %{ruleset: ruleset} do
      build = Build.new(levels: [])

      assert {:error, [{:requires_alignment, _}]} = Rules.validate_level_up(build, :monk, ruleset)
      # a class without a restriction is unaffected
      assert Rules.validate_level_up(build, :fighter, ruleset) == :ok
    end
  end

  describe "prerequisites" do
    # source: siala_41/classes.json — purple_dragon_knight requirements
    # {"base_attack_bonus": 4, "skills": {...}}, status "verified".
    test "the shard's structured requirements produce specific reasons", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter], alignment: :lawful_good)

      assert {:error, reasons} = Rules.validate_level_up(build, :purple_dragon_knight, ruleset)
      assert {:requires_bab, 4} in reasons
      assert {:requires_skill_ranks, :spot, 2} in reasons
      # every reason at once, not just the first
      assert length(reasons) >= 4
    end

    test "meeting them all clears the class", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 4),
          alignment: :lawful_good,
          skills: %{1 => %{spot: 2, listen: 2, intimidate: 1, persuade: 1}}
        )

      assert Rules.validate_level_up(build, :purple_dragon_knight, ruleset) == :ok
    end

    # The vanilla requirement blocks are structured now (`mix wiki.parse` reads
    # the bold labels), so the dwarven defender is checked against what the wiki
    # actually says instead of being refused for want of data.
    # source: vanilla/classes.json requirements — {"alignment": "any lawful",
    # "base_attack_bonus": 7, "race": ["dwarf"], "feats": ["dodge", "toughness"]},
    # read from fandom "Dwarven defender".
    test "the vanilla requirement block is checked, not reported missing", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 3), race: :elf, alignment: :lawful_good)

      assert {:error, reasons} = Rules.validate_level_up(build, :dwarven_defender, ruleset)

      refute {:missing_data, {:class_requirements, :dwarven_defender}} in reasons
      assert {:requires_bab, 7} in reasons
      assert {:requires_race, [:dwarf]} in reasons
      assert {:requires_feat, :dodge} in reasons

      # Toughness тоже в требованиях, но его НЕ должно быть в отказе: Fighter
      # выдаёт его бесплатно на 1-м уровне (siala_41/classes.json,
      # auto_feat_at_level_1). Просить взять фит, который у персонажа уже есть,
      # значит запереть его в классе, куда он проходит.
      refute {:requires_feat, :toughness} in reasons
    end

    test "a dwarf who meets the block clears the dwarven defender", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 7),
          race: :dwarf,
          alignment: :lawful_good,
          feats: %{1 => %{general: :dodge}, 3 => %{general: :toughness}}
        )

      assert Rules.validate_level_up(build, :dwarven_defender, ruleset) == :ok
      # ... and the alignment in that block is enforced, not merely stored
      chaotic = %{build | alignment: :chaotic_good}
      assert {:error, reasons} = Rules.validate_level_up(chaotic, :dwarven_defender, ruleset)
      assert {:requires_alignment, %{require: ["lawful"]}} in reasons
    end

    # A class whose prerequisites the data layer could not read at all is never
    # declared legal — the contract survives every vanilla block being readable.
    test "unreadable prerequisites are a gap, not a pass", %{ruleset: ruleset} do
      ruleset = put_in(ruleset.classes[:dwarven_defender].requirements, nil)
      build = Build.new(levels: List.duplicate(:fighter, 10), alignment: :lawful_good)

      assert {:error, reasons} = Rules.validate_level_up(build, :dwarven_defender, ruleset)
      assert {:missing_data, {:class_requirements, :dwarven_defender}} in reasons
    end
  end

  # Requirements that stand on the page and mean something the page says
  # elsewhere. The parser writes the label out verbatim and cannot do better; a
  # human reads the prose into `vanilla/class_requirements.json` and the ordinary
  # interpreter checks it.
  #
  # ⚠️ Why this file has a whole section: until it was read, Pale Master's block
  # consisted of an alignment and a gap, and **a Pale Master could be taken at
  # character level 1** — the loudest kind of false legality, because it looks
  # like a working answer.
  describe "requirements whose meaning is in the page's prose" do
    # source: fandom "Pale master" revid 71581 — «'''Arcane spellcasting:''' level
    # 3 or higher», and in Notes: «The spellcasting requirement refers to the
    # caster level required, **not the level of spell that can be cast**. Three
    # levels of bard, sorcerer, or wizard fulfills this requirement.»
    #
    # ⚠️ The number in the table is a **class level**, not a spell circle, and the
    # difference is four levels for a bard: he first sees circle 3 at bard 7.
    # Corroborated by a source that outranks Fandom (CLAUDE.md §3): the Siala
    # build page «Бледный Призыватель» (revid 18469) takes Bard 1–3 and Pale
    # Master from character level 4 — exact under this reading, illegal under the
    # other.
    @pale_master_cases [
      {"ни одного уровня заклинателя", [], :refused},
      {"бард 2 — на один меньше", [:bard, :bard], :refused},
      {"бард 3 — ровно столько, сколько названо", [:bard, :bard, :bard], :allowed},
      {"соркерер 3", [:sorcerer, :sorcerer, :sorcerer], :allowed},
      {"маг 3", [:wizard, :wizard, :wizard], :allowed},
      # A caster the requirement does not name: «arcane», and the note lists three
      # classes. Divine casting is not arcane at any class level.
      {"клирик 5 — каст божественный", List.duplicate(:cleric, 5), :refused},
      # Read per class, because a caster level is per class: three arcane classes
      # at level 1 apiece are three first-level casters, not a third-level one.
      # The one inference in the entry, and it is written down there.
      {"бард 1 + соркерер 1 + маг 1", [:bard, :sorcerer, :wizard], :refused},
      # The class stays takeable deep into epic — the requirement is about what
      # the character holds, not about when.
      {"бард 3 и 17 уровней воина", [:bard, :bard, :bard | List.duplicate(:fighter, 17)],
       :allowed},
      {"воин 20 без единого арканового уровня", List.duplicate(:fighter, 20), :refused}
    ]

    for {label, levels, verdict} <- @pale_master_cases do
      test "pale master: #{label} → #{verdict}", %{ruleset: ruleset, vanilla: vanilla} do
        build = Build.new(levels: unquote(levels), race: :human, alignment: :neutral_evil)

        for rules <- [ruleset, vanilla] do
          assert arcane_gate(build, :pale_master, rules) == unquote(verdict)
        end
      end
    end

    # The reason is the one the player can act on, and it names all three
    # alternatives — a flat list of three would read as three demands.
    test "the refusal names the alternatives, not a flattened conjunction", %{ruleset: ruleset} do
      build = Build.new(levels: [:bard, :bard], race: :human, alignment: :neutral_evil)

      assert {:error, reasons} = Rules.validate_level_up(build, :pale_master, ruleset)

      assert {:requires_any_of,
              [
                [{:requires_class_level, :bard, 3}],
                [{:requires_class_level, :sorcerer, 3}],
                [{:requires_class_level, :wizard, 3}]
              ]} in reasons

      # and the rest of the block still applies at the same time
      good = %{build | alignment: :neutral_good}
      assert {:error, good_reasons} = Rules.validate_level_up(good, :pale_master, ruleset)
      assert {:requires_alignment, %{forbid: ["good"]}} in good_reasons
    end

    # The other entrance to the core — the one import and a shared link use. It
    # judges a level against the build **as it stood then**, so a ladder that
    # earns its arcane levels later must still be refused.
    test "editing a level in the middle is judged at that moment", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: [:bard, :bard, :bard, :fighter, :fighter],
          race: :human,
          alignment: :neutral_evil
        )

      # level 4 comes after Bard 3 — legal
      assert Rules.validate_level_up(build, %{class: :pale_master, at: 4}, ruleset) == :ok

      # level 2 comes after Bard 1 — the two bard levels that follow do not count
      assert {:error, reasons} =
               Rules.validate_level_up(build, %{class: :pale_master, at: 2}, ruleset)

      assert Enum.any?(reasons, &match?({:requires_any_of, _}, &1))
    end

    # source: fandom "Arcane archer" revid 71569 — the requirement line struck
    # «Able to cast first level arcane spells» out and replaced it with «A level
    # of bard, sorcerer, or wizard», and Notes says why: «Only a single level of
    # any arcane class is needed. For example, bards don't get level 1 spells
    # until their second level… The same applies to wizards with 10 or lower
    # intelligence.» So it is a class level and explicitly **not** a spell.
    test "arcane archer needs one arcane level, not a spell", %{ruleset: ruleset} do
      archer = fn levels ->
        Build.new(
          levels: levels,
          race: :half_elf,
          alignment: :true_neutral,
          feats: %{1 => %{general: :point_blank_shot}, 2 => %{general: :weapon_focus}}
        )
      end

      # six levels of fighter reach base attack +6 and hold both feats — only the
      # arcane level is missing
      assert arcane_gate(archer.(List.duplicate(:fighter, 6)), :arcane_archer, ruleset) ==
               :refused

      # one bard level, and a bard of level 1 casts nothing at all
      one_bard = [:bard | List.duplicate(:fighter, 6)]
      assert arcane_gate(archer.(one_bard), :arcane_archer, ruleset) == :allowed
      assert Rules.validate_level_up(archer.(one_bard), :arcane_archer, ruleset) == :ok
    end

    # На Сиале у того же требования есть вторая половина, и с 17.08.2026 она
    # проверяется: `Weapon focus` обязан быть взят на одно из ЧЕТЫРЁХ
    # дальнобойных, а не на что угодно.
    #
    # source: Dan, 17.08.2026, дословно: «по поводу arcane archer: требование
    # эльф или темный эльф, т.е. оба подходят, и weapon focus на одно из
    # 4 орудий: короткий лук/арбалет, длинный лук, тяжелый арбалет».
    # source: `siala:Тайный лучник`, revid 20405 — «Умения: Владение оружием
    # (Короткий лук, Длинный лук, Малый арбалет или Большой арбалет)».
    #
    # ⚠️ Оба ruleset'а в одном тесте намеренно: сиальское расширение до четырёх
    # не имеет права протечь в ваниль, а «ваниль пропускает меч» поодиночке
    # зеленело бы и на модели, которая не проверяет выбор нигде.
    test "на Сиале Тайный лучник требует фокус ИМЕННО на дальнобойном", %{
      ruleset: siala,
      vanilla: vanilla
    } do
      archer = fn weapon ->
        Build.new(
          levels: [:bard | List.duplicate(:fighter, 6)],
          race: :half_elf,
          alignment: :true_neutral,
          feats: %{
            1 => %{general: :point_blank_shot},
            2 => %{general: {:weapon_focus, weapon}}
          }
        )
      end

      refusal =
        {:requires_feat_choice, :weapon_focus,
         [:shortbow, :longbow, :light_crossbow, :heavy_crossbow]}

      # Четыре названных источником — проходят. Арбалеты здесь и есть отличие
      # от ванили: её собственный список — только два лука.
      for weapon <- [:shortbow, :longbow, :light_crossbow, :heavy_crossbow] do
        assert Rules.validate_level_up(archer.(weapon), :arcane_archer, siala) == :ok,
               "#{weapon} обязан подходить"
      end

      # Ближний бой — нет, и причина называет фит вместе со списком.
      assert {:error, reasons} =
               Rules.validate_level_up(archer.(:longsword), :arcane_archer, siala)

      assert refusal in reasons

      # ⚠️ Обе расы шарда проходят — «Эльф или Тёмный эльф» на странице значит
      # elf И half_elf, а не одну из них (тот же ответ Dan).
      for race <- [:elf, :half_elf] do
        build = %{archer.(:longbow) | race: race}
        assert Rules.validate_level_up(build, :arcane_archer, siala) == :ok, "#{race}"
      end

      assert {:error, [{:requires_race, [:elf, :half_elf]}]} =
               Rules.validate_level_up(%{archer.(:longbow) | race: :human}, :arcane_archer, siala)

      # 🔴 И ваниль не тронута: у неё оружие остаётся непроверяемой оговоркой,
      # поэтому длинный меч там класс НЕ закрывает.
      #
      # ⚠️ Сравнивается ОТСУТСТВИЕ этой причины, а не `:ok`: у ванильного
      # ruleset'а нет лимита классов вовсе (`max_classes` — сиальская настройка),
      # и билд из трёх классов получает там свой `{:missing_data, :max_classes}`,
      # к оружию отношения не имеющий.
      assert {:error, vanilla_reasons} =
               Rules.validate_level_up(archer.(:longsword), :arcane_archer, vanilla)

      refute refusal in vanilla_reasons
      assert vanilla_reasons == [{:missing_data, :max_classes}]
    end

    # source: fandom "Red dragon disciple" revid 71919 — the criteria table:
    # «Class: bard or sorcerer», «Skills: lore (8 ranks)». The class line is a
    # disjunction, which is why the parser put it aside: `class_levels` is a
    # conjunction and cannot hold two branches.
    test "red dragon disciple needs a bard or a sorcerer level", %{ruleset: ruleset} do
      disciple = fn levels ->
        Build.new(
          levels: levels,
          race: :human,
          alignment: :true_neutral,
          skills: %{1 => %{lore: 4}, 2 => %{lore: 4}}
        )
      end

      assert arcane_gate(disciple.([:rogue, :rogue]), :red_dragon_disciple, ruleset) == :refused

      assert arcane_gate(disciple.([:sorcerer, :rogue]), :red_dragon_disciple, ruleset) ==
               :allowed

      # the readable half of the block did not stop being checked
      assert Rules.validate_level_up(
               disciple.([:sorcerer, :rogue]),
               :red_dragon_disciple,
               ruleset
             ) ==
               :ok

      no_lore = Build.new(levels: [:sorcerer], race: :human, alignment: :true_neutral)
      assert {:error, reasons} = Rules.validate_level_up(no_lore, :red_dragon_disciple, ruleset)
      assert {:requires_skill_ranks, :lore, 8} in reasons
    end

    # The positive control for everything above: a `refute` on a refusal goes
    # green just as readily when the check never ran. Shifter carries the same
    # «Spellcasting: level 3 or higher» line as Pale Master, and it must NOT
    # refuse — so if the gate above ever starts firing at everything, this is
    # what catches it.
    #
    # ⚠️ The build is Dan's observation reproduced literally (03.08.2026, test
    # server): a druid of level 5 with WIS 12 casts two circles of spells — the
    # third needs WIS 13 — and the game offers him the class regardless. That is
    # what rules out reading the line as «able to cast third-circle spells»; had
    # we read it that way, this build would be refused here and the calculator
    # would be wrong against the game.
    # source: fandom "Shifter" revid 71744 + user observation.
    test "shifter is offered to a druid who cannot cast third-circle spells", %{
      ruleset: ruleset
    } do
      druid =
        Build.new(
          levels: List.duplicate(:druid, 5),
          race: :human,
          alignment: :true_neutral,
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 12, cha: 10}
        )

      assert MapSet.member?(Build.feats_owned(druid, ruleset, 5), :wild_shape)
      # The premise of the observation, held here so the test cannot quietly
      # become one about a druid who *does* reach the third circle: the table
      # hands him a third-circle slot at druid 5, but casting it takes WIS 13
      # and this build has 12.
      assert Spells.minimum_ability_score(ruleset, 3) == 13

      assert {:error, reasons} = Rules.validate_level_up(druid, :shifter, ruleset)
      assert reasons == [requires_feat: :alertness]
    end
  end

  # `:allowed` / `:refused` by the arcane-level gate alone. Vanilla answers
  # `{:missing_data, :max_classes}` to every level-up (no wiki states a class
  # limit for it), so a bare `== :ok` would only ever be testable on one ruleset.
  defp arcane_gate(build, class, ruleset) do
    case Rules.validate_level_up(build, class, ruleset) do
      :ok ->
        :allowed

      {:error, reasons} ->
        if Enum.any?(reasons, &match?({:requires_any_of, _}, &1)),
          do: :refused,
          else: :allowed
    end
  end

  describe "the requirements interpreter" do
    # Exercised against a fixture ruleset: the shapes below are what the data
    # layer will hand over once data-miner structures the remaining classes.
    setup %{ruleset: ruleset} do
      requirements = %{
        base_attack_bonus: 7,
        race: ["dwarf"],
        feats: ["dodge", "toughness"],
        skills: %{"discipline" => 5},
        class_levels: %{"fighter" => 2},
        abilities: %{"str" => 13},
        alignment: %{require: ["lawful"]}
      }

      {:ok, ruleset: put_in(ruleset.classes[:dwarven_defender].requirements, requirements)}
    end

    test "reports every unmet requirement in one go", %{ruleset: ruleset} do
      build = Build.new(levels: [:rogue], race: :elf, alignment: :chaotic_good)

      assert {:error, reasons} = Rules.validate_level_up(build, :dwarven_defender, ruleset)

      assert {:requires_bab, 7} in reasons
      assert {:requires_race, [:dwarf]} in reasons
      assert {:requires_feat, :dodge} in reasons
      assert {:requires_feat, :toughness} in reasons
      assert {:requires_skill_ranks, :discipline, 5} in reasons
      assert {:requires_class_level, :fighter, 2} in reasons
      assert {:requires_ability, :str, 13} in reasons
      assert {:requires_alignment, %{require: ["lawful"]}} in reasons
    end

    test "a build that satisfies everything passes", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 7),
          race: :dwarf,
          alignment: :lawful_good,
          base_abilities: %{str: 13, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :dodge}, 3 => %{general: :toughness}},
          skills: %{1 => %{discipline: 5}}
        )

      assert Rules.validate_level_up(build, :dwarven_defender, ruleset) == :ok
    end

    test "an alignment phrase outside the known vocabulary is a gap", %{ruleset: ruleset} do
      ruleset = put_in(ruleset.classes[:dwarven_defender].requirements, %{alignment: nil})
      build = Build.new(levels: [:fighter], alignment: :lawful_good)

      assert {:error, reasons} = Rules.validate_level_up(build, :dwarven_defender, ruleset)
      assert {:missing_data, :alignment_requirement} in reasons
    end
  end

  describe "vanilla ruleset" do
    # Vanilla states no class limit anywhere — neither wiki records it — so the
    # validator says so rather than inventing 3 or 8.
    test "reports the missing class limit instead of guessing", %{vanilla: vanilla} do
      assert vanilla.max_classes == nil
      build = Build.new(levels: [:fighter], alignment: :true_neutral)

      assert {:error, reasons} = Rules.validate_level_up(build, :rogue, vanilla)
      assert {:missing_data, :max_classes} in reasons
    end
  end

  describe "feats a class hands out for free count as owned" do
    # source: siala_41/classes.json — auto_feat_at_level_1 ["toughness"] у девяти
    # воинских классов; vanilla/classes.json — Dwarven defender требует toughness.
    # Без этого воин не мог бы взять ДД из-за фита, который у него уже есть.
    test "Fighter has Toughness from level 1 without spending a slot", %{ruleset: ruleset} do
      build = Build.new(race: :dwarf, alignment: :lawful_good, levels: [:fighter])

      assert MapSet.member?(Build.granted_feats(build, ruleset, 1), :toughness)
      refute MapSet.member?(Build.feats_taken(build, 1), :toughness)
      assert MapSet.member?(Build.feats_owned(build, ruleset, 1), :toughness)
    end

    test "Dwarven Defender is not refused over a granted Toughness", %{ruleset: ruleset} do
      dwarf = fn levels, feats ->
        Build.new(
          race: :dwarf,
          alignment: :lawful_good,
          levels: levels,
          feats: feats
        )
      end

      # Шесть уровней воина: Dodge взят, Toughness выдан классом, BAB ещё 6.
      six = dwarf.(List.duplicate(:fighter, 6), %{1 => %{general: :dodge}})
      assert {:error, reasons} = Rules.validate_level_up(six, :dwarven_defender, ruleset)
      assert reasons == [requires_bab: 7]
      refute {:requires_feat, :toughness} in reasons

      # Семь — BAB дотянул, остальное уже было.
      seven = dwarf.(List.duplicate(:fighter, 7), %{1 => %{general: :dodge}})
      assert :ok = Rules.validate_level_up(seven, :dwarven_defender, ruleset)
    end

    test "a class that grants nothing still needs the feat taken", %{ruleset: ruleset} do
      # Волшебник Toughness не выдаёт, поэтому требование остаётся.
      build =
        Build.new(race: :dwarf, alignment: :lawful_good, levels: List.duplicate(:wizard, 14))

      assert {:error, reasons} = Rules.validate_level_up(build, :dwarven_defender, ruleset)
      assert {:requires_feat, :toughness} in reasons
    end
  end
end
