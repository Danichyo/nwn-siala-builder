defmodule BuildCalculator.Rules.SkillsTest do
  @moduledoc """
  Skill budget, price and ceiling — the three rules a skill row lies without.

  Class values come from `classes.json` (fandom), the racial per-level bonus from
  `races.json`, the ceilings from `epic.json`'s formulas, which the loader
  cross-checks against the tabulated epic rows.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader.Character
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Bonuses, Build, Gear, Skills}

  setup_all do
    # ⚠️ Ваниль нужна как ОТРИЦАТЕЛЬНЫЙ контроль к фильтру получателей: словаря
    # у неё нет вовсе, значит она называет всё, что называла до 17.08.2026, — и
    # по разнице видно, что оговорку сняла разметка, а не сломанная доставка.
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "points per level" do
    # source: fandom "Skill point" revid 55950 — class value plus the
    # intelligence modifier, minimum one, quadrupled at character level 1.
    # Class values from classes.json: rogue 8, fighter 2, wizard 2.
    test "class value plus intelligence, quadrupled on the first level", %{ruleset: ruleset} do
      build = build_with(:rogue, 5, int: 14)

      # (8 + 2) * 4 on level 1, then 10 a level
      assert Skills.points_at(build, ruleset, 1) == 40
      assert Skills.points_at(build, ruleset, 2) == 10
      assert Skills.budget(build, ruleset, 5).earned == 40 + 10 * 4
    end

    test "never fewer than one point before the racial bonus", %{ruleset: ruleset} do
      # wizard 2 + intelligence 6 (-2) would be 0
      build = build_with(:wizard, 2, int: 6)

      assert Skills.points_at(build, ruleset, 1) == 4
      assert Skills.points_at(build, ruleset, 2) == 1
    end

    # source: races.json — human bonus_skill_points %{per_level: 1, extra: 4}
    # (fandom "Human" revid 70207); the +4 at level 1 is the per-level bonus
    # falling inside the quadrupling.
    test "humans get one extra point a level", %{ruleset: ruleset} do
      human = build_with(:fighter, 3, int: 10, race: :human)
      dwarf = build_with(:fighter, 3, int: 10, race: :dwarf)

      assert Skills.points_at(human, ruleset, 1) == 12
      assert Skills.points_at(dwarf, ruleset, 1) == 8
      assert Skills.points_at(human, ruleset, 2) == 3
      assert Skills.points_at(dwarf, ruleset, 2) == 2
    end

    test "the intelligence used is the one held at that level", %{ruleset: ruleset} do
      build = build_with(:rogue, 5, int: 13, ability_increases: %{4 => :int})

      # 13 -> +1 up to level 3, 14 -> +2 from level 4
      assert Skills.points_at(build, ruleset, 3) == 9
      assert Skills.points_at(build, ruleset, 4) == 10
    end
  end

  # «INT с вещей скилл поинты при повышении уровня не увеличивает» (Dan,
  # 25.08.2026, `source: user`; `_vanilla_constants_confirmed.
  # skill_points_gear_intelligence`). Задача 3.105 не сдвинула ни одного числа —
  # она превратила наш выбор в прочитанное правило, и проверять здесь надо
  # ровно две вещи: что число не сдвинулось и что запись ЖИВАЯ.
  #
  # ⚠️ Три состояния проверяются на СИНТЕТИЧЕСКОМ ruleset'е, а не на живой
  # записи: контроль, стоящий на данных, назавтра получает правку данных и
  # молча перестаёт что-либо проверять (CLAUDE.md §9, пять сгоревших подряд).
  # На живых данных проверяется только одно — что сегодня они говорят
  # `:ignored` и оговорки поэтому нет.
  describe "интеллект с вещей и скилл-поинты" do
    test "надетый интеллект в бюджет не идёт", %{ruleset: ruleset} do
      # Rogue 8 + INT 14 (+2) + 1 человеку = 11 за уровень, ×4 на первом;
      # +12 INT с вещей подняли бы модификатор до +8, то есть 17 вместо 11.
      assert Skills.points_at(rogue_with_gear_int(0), ruleset, 1) == 44
      assert Skills.points_at(rogue_with_gear_int(12), ruleset, 1) == 44
      assert Skills.points_at(rogue_with_gear_int(12), ruleset, 2) == 11

      assert Skills.budget(rogue_with_gear_int(12), ruleset, 10).earned ==
               Skills.budget(rogue_with_gear_int(0), ruleset, 10).earned
    end

    test "и ванильный ruleset отвечает то же самое", %{vanilla: vanilla} do
      # Секция `_vanilla_constants_confirmed` видна обоим (`@vanilla_sections`),
      # и это не случайность: вопрос про движок, а не про баланс шарда.
      assert Skills.gear_intelligence(vanilla) == :ignored
      assert Skills.points_at(rogue_with_gear_int(12), vanilla, 1) == 44
    end

    test "сегодня правило названо, поэтому оговорки нет", %{ruleset: ruleset} do
      geared = Rules.compute(rogue_with_gear_int(12), ruleset)
      bare = Rules.compute(rogue_with_gear_int(0), ruleset)

      assert Skills.gear_intelligence(ruleset) == :ignored
      refute {:assumed, :skill_points_ignore_gear_intelligence} in geared.gaps

      # Отрицательный контроль: у билда без вещевого интеллекта её и не было,
      # то есть зелёная строка выше говорит про снятие, а не про билд.
      refute {:assumed, :skill_points_ignore_gear_intelligence} in bare.gaps
    end

    test "без записи считаем так же — и говорим об этом", %{ruleset: ruleset} do
      unstated = Map.put(ruleset, :skill_points_gear_intelligence, nil)
      build = rogue_with_gear_int(12)

      assert Skills.points_at(build, unstated, 1) == 44

      assert {:assumed, :skill_points_ignore_gear_intelligence} in Rules.compute(build, unstated).gaps

      # ⚠️ И только там, где надетый интеллект мог бы сдвинуть число: оговорка
      # у голого билда была бы неопределённостью про решённое.
      refute {:assumed, :skill_points_ignore_gear_intelligence} in Rules.compute(
               rogue_with_gear_int(0),
               unstated
             ).gaps
    end

    test "запись читается, а не лежит рядом: обратный ответ двигает число", %{ruleset: ruleset} do
      counted = Map.put(ruleset, :skill_points_gear_intelligence, :counted)
      build = rogue_with_gear_int(12)

      # INT 14 + 12 = 26, модификатор +8: (8 + 8 + 1 человеку) × 4 = 68.
      assert Skills.points_at(build, counted, 1) == 68
      assert Skills.points_at(build, counted, 2) == 17

      # Голого билда чужой ответ не касается — вещей у него нет.
      assert Skills.points_at(rogue_with_gear_int(0), counted, 1) == 44

      refute {:assumed, :skill_points_ignore_gear_intelligence} in Rules.compute(build, counted).gaps
    end

    test "невыверенная запись правилом не становится" do
      assert Character.skill_points_gear_intelligence(%{
               "_vanilla_constants_confirmed" => %{
                 "skill_points_gear_intelligence" => %{"value" => false, "status" => "unclear"}
               }
             }) == nil

      # ⚠️ `false` — это ОТВЕТ, и потерять его на проверке истинности значило бы
      # вернуть оговорку про подтверждённое правило.
      assert Character.skill_points_gear_intelligence(%{
               "_vanilla_constants_confirmed" => %{
                 "skill_points_gear_intelligence" => %{"value" => false, "status" => "verified"}
               }
             }) == :ignored

      assert Character.skill_points_gear_intelligence(%{}) == nil
    end

    test "снятая из данных запись возвращает оговорку" do
      # Полный маршрут «данные → загрузчик → ядро» на копии `priv/rules`
      # с удалённым ключом: синтетическая мапа выше проверяет читателя,
      # а это — что запись действительно доезжает до ответа.
      ruleset = ruleset_without_gear_intelligence()
      build = rogue_with_gear_int(12)

      assert Skills.gear_intelligence(ruleset) == nil
      assert Skills.points_at(build, ruleset, 1) == 44

      assert {:assumed, :skill_points_ignore_gear_intelligence} in Rules.compute(build, ruleset).gaps
    end
  end

  describe "rank price" do
    # source: CLAUDE.md §6 — one point for a class skill, two for a cross-class
    # one, and "class" means the class taken on exactly that level.
    # discipline is a fighter class skill and not a wizard one (classes.json).
    test "follows the class taken on that very level", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter, :wizard])

      assert Skills.rank_cost(build, ruleset, :discipline, 1) == 1
      assert Skills.rank_cost(build, ruleset, :discipline, 2) == 2
      # spellcraft the other way round
      assert Skills.rank_cost(build, ruleset, :spellcraft, 1) == 2
      assert Skills.rank_cost(build, ruleset, :spellcraft, 2) == 1
    end

    test "the budget charges each level at its own price", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: [:fighter, :wizard],
          base_abilities: abilities(int: 10),
          skills: %{1 => %{discipline: 4}, 2 => %{discipline: 1}}
        )

      budget = Skills.budget(build, ruleset, 2)

      # fighter 2 + int 0 -> 8 on level 1, 2 on level 2
      assert budget.earned == 10
      # 4 ranks at 1 point, then 1 rank at 2 points
      assert budget.spent == 6
      assert budget.free == 4
    end

    test "unspent points carry over rather than lapsing", %{ruleset: ruleset} do
      build = build_with(:rogue, 3, int: 10, skills: %{3 => %{hide: 6}})

      # 32 on level 1, 8 each after; hide is a rogue class skill, 1 point a rank
      assert Skills.budget(build, ruleset, 3) == %{earned: 48, spent: 6, free: 42}
    end
  end

  describe "rank ceiling" do
    # source: epic.json skill_ranks — "character_level + 3" for a class skill,
    # "floor(max_rank / 2)" for a cross-class one. The loader checks the formula
    # against the tabulated epic rows 21..40 at compile time.
    test "class and cross-class ceilings by level", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 41))

      table = [{1, 4, 2}, {2, 5, 2}, {20, 23, 11}, {21, 24, 12}, {40, 43, 21}, {41, 44, 22}]

      for {level, class_cap, cross_cap} <- table do
        assert Skills.rank_cap(build, ruleset, :discipline, level) == class_cap
        assert Skills.rank_cap(build, ruleset, :hide, level) == cross_cap
      end
    end

    # source: CLAUDE.md §6 — "классовость определяется по классам, взятым к этому
    # уровню: будущие классы задним числом потолок не поднимают."
    test "a class taken later does not raise an earlier ceiling", %{ruleset: ruleset} do
      # hide is a rogue class skill, not a fighter one
      build = Build.new(levels: [:fighter, :fighter, :rogue])

      assert Skills.rank_cap(build, ruleset, :hide, 1) == 2
      assert Skills.rank_cap(build, ruleset, :hide, 2) == 2
      assert Skills.rank_cap(build, ruleset, :hide, 3) == 6
    end

    # ⚠️ И обратное, которое до 03.08.2026 было неверно: класс, взятый РАНЬШЕ,
    # не поднимает потолок ПОЗЖЕ. Потолок читается по классу самого уровня.
    test "a class taken earlier does not raise a later ceiling", %{ruleset: ruleset} do
      build = Build.new(levels: [:rogue, :rogue, :fighter])

      assert Skills.rank_cap(build, ruleset, :hide, 2) == 5
      assert Skills.rank_cap(build, ruleset, :hide, 3) == 3

      # …а ранги, купленные на первых двух, никуда не деваются.
      assert Skills.max_ranks(build, ruleset, :hide, 3) == 5
    end

    test "over-cap ranks come back as machine-readable reasons", %{ruleset: ruleset} do
      build = build_with(:rogue, 2, int: 14, skills: %{1 => %{hide: 4}, 2 => %{hide: 2}})

      # rogue class skill: ceiling 4 on level 1, 5 on level 2. Filtered rather
      # than compared whole — a build made of classes and skills the shard
      # rewrote also reports those, and that list is not what this test is about.
      assert accusations(build, ruleset) == [{:skill_over_cap, :hide, 2, 6, 5}]
    end
  end

  # ⚠️ source: Дан, наблюдение в игре 03.08.2026 (`source: user` — высший ранг,
  # ни одна вики этого при мультиклассе не описывает): «Sorcerer 1–39, 40-м
  # уровнем Fighter, на уровнях сорка залито 35 рангов Spellcraft — в игре на
  # уровне воина поднять его нельзя».
  #
  # Второй, независимый источник — сама вики: «Мастер Вор» пишет «*Discipline -
  # 43 (Доступен только на уровнях рейнджера)», а «Мастер Монах» — «*Spot - 43
  # (Доступен только на уровнях ассасина)». Оба навыка кросс-классово покупаются
  # свободно, так что «доступен только на уровнях» может относиться лишь
  # к потолку. Проверено в `reference/wiki_builds_test.exs`.
  describe "the ceiling belongs to the level, not to the build" do
    test "a caster who takes Fighter at 40 may not raise Spellcraft there", %{ruleset: ruleset} do
      build = sorcerer_then_fighter(35)

      # Потолок 40-го уровня — кросс-классовый: Spellcraft не классовый у воина.
      assert Skills.rank_cap(build, ruleset, :spellcraft, 40) == 21
      assert Skills.rank_room(build, ruleset, :spellcraft, 40) == 0

      # ⚠️ Вторая половина: 35 рангов НЕ отбираются и не становятся нарушением.
      assert Build.skill_ranks(build, :spellcraft, 40) == 35
      assert accusations(build, ruleset) == []

      # …и билд легален не только по потолку: очков хватило.
      assert Skills.budget(build, ruleset, 40).free >= 0
    end

    # ⚠️ Положительный контроль. Без него тест выше зеленел бы и при полностью
    # сломанной покупке рангов: «нельзя» ничего не доказывает, пока рядом нет
    # «можно» на той же машинерии.
    test "the same ladder in the other order may raise it", %{ruleset: ruleset} do
      build = fighter_then_sorcerer(35)

      assert Skills.rank_cap(build, ruleset, :spellcraft, 40) == 43
      assert Skills.rank_room(build, ruleset, :spellcraft, 40) == 8
      assert Skills.rank_cost(build, ruleset, :spellcraft, 40) == 1
    end

    # Граница: кросс-классовый потолок ровно равен накопленному — покупок нет,
    # а на ранг ниже есть ровно одна.
    test "the boundary where the cross-class ceiling equals what is held", %{ruleset: ruleset} do
      for {held, room} <- [{20, 1}, {21, 0}, {22, 0}] do
        build = sorcerer_then_fighter(held)

        assert Skills.rank_room(build, ruleset, :spellcraft, 40) == room,
               "#{held} рангов должны оставлять #{room}"
      end
    end

    # ⚠️ `max_ranks/4` отвечает на ДРУГОЙ вопрос — «сколько навык вообще мог
    # набрать»: самый высокий потолок, который дал хоть один уровень лестницы.
    # Путать его с потолком последнего уровня — ровно та ошибка, из-за которой
    # регрессия по вики обвиняла «Мастера Вора» в его же законных рангах.
    test "max_ranks reads the whole ladder, not its last step", %{ruleset: ruleset} do
      build = sorcerer_then_fighter(35)

      # 39-й уровень — соркерер, потолок 42; 40-й — воин, потолок 21.
      assert Skills.rank_cap(build, ruleset, :spellcraft, 39) == 42
      assert Skills.max_ranks(build, ruleset, :spellcraft, 40) == 42
    end

    # Покупка сверх допустимого — по-прежнему нарушение, и обвиняется именно
    # покупка: тот же билд, плюс один ранг на уровне воина.
    test "a purchase past the level's ceiling is still accused", %{ruleset: ruleset} do
      build = sorcerer_then_fighter(35)
      overspent = %{build | skills: Map.put(build.skills, 40, %{spellcraft: 1})}

      assert accusations(overspent, ruleset) == [{:skill_over_cap, :spellcraft, 40, 36, 21}]
    end

    # source: skills.json — perform несёт `cross_class: no`, то есть кросс-классово
    # не покупается вовсе. Бард 39, взявший 40-м уровнем воина, получает на нём
    # ноль покупок — не «половину потолка», а ноль.
    test "an exclusive skill gives a multiclass level nothing at all", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:bard, 39) ++ [:fighter],
          base_abilities: abilities(int: 14, cha: 16),
          skills: Map.new(1..30, &{&1, %{perform: 1}})
        )

      assert Skills.exclusive?(ruleset, :perform)
      assert Skills.rank_cap(build, ruleset, :perform, 40) == 0
      assert Skills.rank_room(build, ruleset, :perform, 40) == 0

      # Положительный контроль: на уровне барда навык живой, и 30 рангов законны.
      assert Skills.rank_cap(build, ruleset, :perform, 39) == 42
      assert Skills.max_ranks(build, ruleset, :perform, 40) == 42
      assert accusations(build, ruleset) == []
    end

    # Мультикласс на четыре класса: потолок скачет по лестнице вслед за классом
    # уровня, а не выбирается один раз на весь билд.
    test "four classes, and the ceiling follows the level's own", %{ruleset: ruleset} do
      build =
        Build.new(
          levels:
            List.duplicate(:rogue, 10) ++
              List.duplicate(:fighter, 10) ++
              List.duplicate(:wizard, 10) ++ List.duplicate(:sorcerer, 11)
        )

      # hide: классовый только у вора (1–10), дальше кросс-классовый
      table = [{10, 13}, {20, 11}, {30, 16}, {41, 22}]

      for {level, cap} <- table do
        assert Skills.rank_cap(build, ruleset, :hide, level) == cap,
               "уровень #{level} должен давать потолок #{cap}"
      end

      # Пока лестница идёт по вору, самый высокий потолок — его же, 13 на 10-м.
      assert Skills.max_ranks(build, ruleset, :hide, 10) == 13

      # ⚠️ А дальше кросс-классовый потолок обгоняет старый классовый: на 41-м
      # уровне половина от 44 — это 22, больше тринадцати. «Классов вора больше
      # нет» не значит «навык замер».
      assert Skills.max_ranks(build, ruleset, :hide, 41) == 22
    end
  end

  describe "exclusive skills" do
    # source: skills.json — use_magic_device, perform and animal_empathy carry
    # `exclusive: true` / `cross_class_raw: "no"`, meaning they cannot be bought
    # cross-class at all (the "forbidden skills" of the community calculators).
    test "cannot be bought without a class that grants them", %{ruleset: ruleset} do
      fighter = Build.new(levels: List.duplicate(:fighter, 10))
      rogue = Build.new(levels: List.duplicate(:rogue, 10))

      assert Skills.exclusive?(ruleset, :use_magic_device)
      assert Skills.rank_cap(fighter, ruleset, :use_magic_device, 10) == 0
      assert Skills.rank_cap(rogue, ruleset, :use_magic_device, 10) == 13
    end

    test "an ordinary skill is merely halved cross-class", %{ruleset: ruleset} do
      fighter = Build.new(levels: List.duplicate(:fighter, 10))

      refute Skills.exclusive?(ruleset, :hide)
      assert Skills.rank_cap(fighter, ruleset, :hide, 10) == 6
    end

    # ✅ Измерено в игре: Dan, тестовый сервер, 04.08.2026 (`source: user`, высший
    # ранг по §3 CLAUDE.md). Взял Харпер-скаута и увидел, что Perform, Use Magic
    # Device и Animal Empathy закрыты ему полностью — «даже кросс-классово нельзя
    # взять».
    #
    # ⚠️ Это НЕ кастомная механика шарда, хотя выглядит ею: три запретных навыка
    # — ванильное правило NWN, и модель их уже знала. Замер поэтому ценен не как
    # новость, а как **сверка модели с игрой на классе, которого никто не
    # проверял**: список запретных навыков совпал ровно, и совпал состав классов,
    # которым каждый из них открыт.
    #
    # Отсюда же следствие для `lasting_inspiration` (см. §1.6 бэклога): требование
    # Perform 25 чистому Харперу недостижимо не «с трудом», а в принципе — ноль
    # рангов, а не половина потолка.
    test "Харперу закрыты все три запретных навыка — сверено с игрой", %{ruleset: ruleset} do
      exclusive =
        for {id, skill} <- ruleset.skills, Map.get(skill, :exclusive?), into: MapSet.new(), do: id

      assert Enum.sort(MapSet.to_list(exclusive)) == [
               :animal_empathy,
               :perform,
               :use_magic_device
             ]

      harper = Build.new(levels: List.duplicate(:harper_scout, 5))

      for skill <- exclusive do
        assert Skills.rank_cap(harper, ruleset, skill, 5) == 0,
               "#{skill} должен быть закрыт Харперу целиком (замер Dan 04.08.2026)"
      end

      # Положительный контроль: у классов, которым навык открыт, потолок не ноль —
      # иначе тест зеленел бы и у модели, запретившей эти навыки вообще всем.
      bard = Build.new(levels: List.duplicate(:bard, 5))
      druid = Build.new(levels: List.duplicate(:druid, 5))

      assert Skills.rank_cap(bard, ruleset, :perform, 5) == 8
      assert Skills.rank_cap(bard, ruleset, :use_magic_device, 5) == 8
      assert Skills.rank_cap(druid, ruleset, :animal_empathy, 5) == 8
    end
  end

  describe "class skills" do
    # source: skills.json — heal and lore carry `classes_all: true`, so they are
    # a class skill for every class.
    test "a universal skill is a class skill everywhere", %{ruleset: ruleset} do
      for class <- [:fighter, :wizard, :rogue, :weapon_master] do
        assert MapSet.member?(ruleset.classes[class].class_skills, :heal_skill)
        assert MapSet.member?(ruleset.classes[class].class_skills, :lore)
      end
    end

    # source: siala_41/classes.json — blackguard change "class_skills"
    # {"added": ["hide", "move_silently"]}, status "verified". Not in the vanilla
    # list on fandom "Blackguard".
    test "the shard's additions arrive through the data layer", %{ruleset: ruleset} do
      vanilla = Data.ruleset!("vanilla")

      refute MapSet.member?(vanilla.classes[:blackguard].class_skills, :hide)
      assert MapSet.member?(ruleset.classes[:blackguard].class_skills, :hide)
      assert MapSet.member?(ruleset.classes[:blackguard].class_skills, :move_silently)
    end

    # source: siala_41/skills.json — the same fact written on the other page
    # («#Навыки [[Скрытность]] и [[Тихое передвижение]] сделаны классовыми»,
    # Чёрный страж revid 18232), plus alchemy's own «Классовый навык для
    # Арфиста». Both are restatements of what classes.json already says, and a
    # union is idempotent, so applying both changes nothing — which is the point:
    # the two sides of the wiki agree and the loader does not have to choose.
    test "a class-skill fact stated on the skill's page lands the same way", %{ruleset: ruleset} do
      assert MapSet.member?(ruleset.classes[:harper_scout].class_skills, :alchemy)
      assert MapSet.member?(ruleset.classes[:blackguard].class_skills, :hide)
    end

    # source: замер Dan 17.08.2026 — «для теневого танцора craft_trap и set_trap
    # являются классовыми навыками». Половины факта лежат в РАЗНЫХ файлах:
    # `set_trap` со страницы класса (siala_41/classes.json), `craft_trap` со
    # страницы навыка (siala_41/skills.json) — и до замера это считалось
    # расхождением двух прочтений одного предложения. Верны оба.
    #
    # ⚠️ Проверяются ОБА навыка вместе: поодиночке каждый зеленел бы и при
    # потерянной половине — set_trap применялся и до замера, а craft_trap
    # применился бы даже если бы вторую запись случайно снесли.
    test "Теневой танцор получил ОБА навыка ловушек, и оба — от шарда",
         %{ruleset: ruleset} do
      vanilla = Data.ruleset!("vanilla")

      for skill <- [:craft_trap, :set_trap] do
        assert MapSet.member?(ruleset.classes[:shadowdancer].class_skills, skill)
        refute MapSet.member?(vanilla.classes[:shadowdancer].class_skills, skill)
      end
    end

    # Цена правки в числах, и она вся — на уровнях Теневого танцора. Классовость
    # берётся от класса ТОГО уровня, где покупается ранг (CLAUDE.md §6), поэтому
    # контраст снимается на одном билде двумя разными уровнями, а не двумя
    # билдами: на 20-м взят ШД, на 30-м — Мастер оружия, у которого нет ни того,
    # ни другого навыка ни в одном ruleset'е.
    #
    # ⚠️ Мастер оружия здесь не «ещё один класс», а ЕДИНСТВЕННЫЙ оставшийся
    # без craft_trap: в ванили навык классовый у 21 класса из 23, и после правки
    # у 22. Значит контроль «шард тронул одну строку, а не список» проверяется
    # ровно этим классом и никаким другим.
    test "на уровне ШД оба навыка классовые, на уровне не-ШД — как в ванили",
         %{ruleset: siala} do
      vanilla = Data.ruleset!("vanilla")

      build =
        Build.new(
          levels:
            List.duplicate(:rogue, 10) ++
              List.duplicate(:shadowdancer, 10) ++ List.duplicate(:weapon_master, 10)
        )

      for skill <- [:craft_trap, :set_trap] do
        # Уровень 20 — Теневой танцор: цена вдвое ниже, потолок вдвое выше.
        assert Skills.rank_cost(build, siala, skill, 20) == 1
        assert Skills.rank_cap(build, siala, skill, 20) == 23
        assert Skills.rank_cost(build, vanilla, skill, 20) == 2
        assert Skills.rank_cap(build, vanilla, skill, 20) == 11

        # Уровень 30 — Мастер оружия: оба ruleset'а отвечают одинаково, то есть
        # правка не расползлась на соседей.
        for ruleset <- [siala, vanilla] do
          assert Skills.rank_cost(build, ruleset, skill, 30) == 2
          assert Skills.rank_cap(build, ruleset, skill, 30) == 16
        end

        # И то же самое в итоге по лестнице: 13 рангов против 23 на двадцатом
        # уровне — «докуда навык вообще мог дорасти» (`max_ranks/4`), а не
        # «сколько купить здесь».
        assert Skills.max_ranks(build, siala, skill, 20) == 23
        assert Skills.max_ranks(build, vanilla, skill, 20) == 13
      end
    end

    # source: siala «Установка ловушки» revid 11494 — «Классы, которые
    # используют данный навык: воры, рейнджеры, убийцы», против
    # `vanilla/skills.json` → `set_trap.classes_raw` = «assassin, ranger, rogue»
    # (fandom «Set trap» revid 70062). Три названных совпадают ровно, и с задачи
    # 3.78 это совпадение СВЕРЯЕТ загрузчик, а не человек глазами.
    #
    # 🔴 Тест здесь ради того, чего сверка НЕ имеет права сделать. Страница
    # называет трёх, а классов у навыка четыре: Теневой танцор приходит
    # со страницы КЛАССА (`siala_41/classes.json`, замер Dan 17.08.2026),
    # и «сделать классовыми ровно названных» отняло бы у него навык молча —
    # цена ранга вдвое, потолок вдвое.
    #
    # ⚠️ Билд собран ЛЕВЕЛАПАМИ через `validate_level_up/3` и проверен на каждом
    # (CLAUDE.md §3: билд, собранный засовыванием списка в `Build.new`,
    # валидацию не проходит вовсе). Четыре класса — предел Сиалы — и лестница
    # доходит до капа 41, поэтому здесь же стоят граничные уровни.
    test "сверка ванильного списка не двигает ни одной цены и ни одного потолка",
         %{ruleset: siala, vanilla: vanilla} do
      build = trapper_41(siala)

      assert length(build.levels) == 41
      assert map_size(Build.class_levels(build)) == 4

      # Уровни 1 и 10 — вор, он в ванильной тройке: оба ruleset'а отвечают
      # одинаково, то есть правило пришло из ванили и там же осталось.
      for {level, cap} <- [{1, 4}, {10, 13}] do
        assert Skills.rank_cost(build, siala, :set_trap, level) == 1
        assert Skills.rank_cap(build, siala, :set_trap, level) == cap
        assert Skills.rank_cost(build, vanilla, :set_trap, level) == 1
        assert Skills.rank_cap(build, vanilla, :set_trap, level) == cap
      end

      # Уровни 11 и 20 — Теневой танцор, которого страница навыка не называет.
      # Единственное место, где два ruleset'а расходятся, и расходятся они
      # ровно на сиальскую добавку.
      assert Skills.rank_cost(build, siala, :set_trap, 11) == 1
      assert Skills.rank_cap(build, siala, :set_trap, 11) == 14
      assert Skills.rank_cost(build, vanilla, :set_trap, 11) == 2
      assert Skills.rank_cap(build, vanilla, :set_trap, 11) == 7

      assert Skills.rank_cost(build, siala, :set_trap, 20) == 1
      assert Skills.rank_cap(build, siala, :set_trap, 20) == 23
      assert Skills.rank_cost(build, vanilla, :set_trap, 20) == 2
      assert Skills.rank_cap(build, vanilla, :set_trap, 20) == 11

      # Уровни 21 и 41 — волшебник и воин, которых нет ни в одном списке:
      # кросс-классово у обоих ruleset'ов. Отрицательный контроль — сверка
      # не раздала навык никому.
      assert Skills.rank_cost(build, siala, :set_trap, 21) == 2
      assert Skills.rank_cap(build, siala, :set_trap, 21) == 12
      assert Skills.rank_cost(build, siala, :set_trap, 41) == 2
      assert Skills.rank_cap(build, siala, :set_trap, 41) == 22

      # ⚠️ У ванили на 41-м потолок 0, а не 22, и это не про эту правку:
      # у неё кап 40, сорок первого уровня нет вовсе. Стоит здесь затем, чтобы
      # «оба ruleset'а согласны» выше не читалось как «ruleset'ы неразличимы».
      assert Skills.rank_cap(build, vanilla, :set_trap, 41) == 0

      # И итог по лестнице — «докуда навык вообще мог дорасти».
      assert Skills.max_ranks(build, siala, :set_trap, 41) == 23
      assert Skills.max_ranks(build, vanilla, :set_trap, 41) == 21
    end
  end

  # Вор 10 → Теневой танцор 10 → Волшебник 10 → Воин 11. Требования Теневого
  # танцора (Dodge, Mobility, Hide 10, Move Silently 8, Tumble 5) закрыты
  # на уровнях вора; 11-й уровень престиж-класса приходится ровно на 20-й
  # уровень персонажа, как того требует `fandom:Epic class`.
  defp trapper_41(ruleset) do
    base =
      Build.new(
        race: :human,
        base_abilities: %{str: 12, dex: 15, con: 12, int: 14, wis: 10, cha: 10},
        levels: [:rogue],
        feats: %{1 => %{general: :dodge}, 3 => %{general: :mobility}},
        skills: %{9 => %{hide: 10, move_silently: 8, tumble: 5}}
      )

    ladder =
      List.duplicate(:rogue, 9) ++
        List.duplicate(:shadowdancer, 10) ++
        List.duplicate(:wizard, 10) ++ List.duplicate(:fighter, 11)

    Enum.reduce(ladder, base, fn class, build ->
      assert Rules.validate_level_up(build, %{class: class}, ruleset) == :ok,
             "#{class} на уровне #{length(build.levels) + 1} — билд собран нелегально"

      Build.add_level(build, class)
    end)
  end

  # source: siala_41/skills.json → global.multiclass_stealth_penalty, status
  # "verified" («Каждый такой персонаж получает штраф к навыкам Скрытности и
  # Тихого передвижения в размере -1 за каждый уровень класса, не относящегося к
  # профильным классам скрытности», Скрытность revid 19465, restated word for
  # word on Тихое передвижение revid 19466).
  describe "the four-class stealth penalty" do
    test "three classes are free, the fourth turns it on", %{ruleset: ruleset} do
      three =
        Build.new(
          levels:
            List.duplicate(:rogue, 20) ++
              List.duplicate(:shadowdancer, 10) ++ List.duplicate(:fighter, 10)
        )

      assert Skills.modifiers(three, ruleset, 40) == %{}

      four =
        Build.new(
          levels:
            List.duplicate(:rogue, 20) ++
              List.duplicate(:shadowdancer, 10) ++
              List.duplicate(:fighter, 6) ++ List.duplicate(:wizard, 4)
        )

      # fighter 6 + wizard 4 = 10 levels outside the shard's stealth list
      assert Skills.modifiers(four, ruleset, 40) == %{hide: -10, move_silently: -10}
    end

    # Every class on the shard's list is a "profile" class, so a build made of
    # four of them takes no penalty at all — the rule counts levels, not classes.
    test "four stealth classes cost nothing", %{ruleset: ruleset} do
      build =
        Build.new(
          levels:
            List.duplicate(:rogue, 10) ++
              List.duplicate(:shadowdancer, 10) ++
              List.duplicate(:ranger, 10) ++ List.duplicate(:assassin, 10)
        )

      assert Skills.modifiers(build, ruleset, 40) == %{}
    end

    # The rule is Siala's; vanilla has nothing of the kind and must not acquire
    # it by accident.
    test "vanilla has no such rule" do
      vanilla = Data.ruleset!("vanilla")

      build =
        Build.new(
          levels:
            List.duplicate(:rogue, 20) ++
              List.duplicate(:shadowdancer, 10) ++
              List.duplicate(:fighter, 6) ++ List.duplicate(:wizard, 4)
        )

      assert Skills.modifiers(build, vanilla, 40) == %{}
    end
  end

  # source: fandom "Spellcraft" revid 68572 — "The character also gains a +1
  # bonus for every 5 ranks in this skill to all saving throws against spells."
  # Transcribed machine-readably into siala_41/overrides.json →
  # _vanilla_constants_confirmed.skill_save_bonus, because vanilla/skills.json is
  # machine-generated and keeps the sentence only as prose in `check_raw`.
  describe "Spellcraft's contribution to saving throws" do
    test "one point per five ranks, rounded down", %{ruleset: ruleset} do
      for {ranks, bonus} <- [{0, 0}, {4, 0}, {5, 1}, {9, 1}, {10, 2}, {43, 8}] do
        build = build_with(:wizard, 40, int: 14, skills: %{40 => %{spellcraft: ranks}})

        from = if bonus > 0, do: [:spellcraft], else: []

        assert Skills.save_bonus(build, ruleset, 40) == {bonus, from},
               "#{ranks} ranks should give +#{bonus}"
      end
    end

    # It is a vanilla rule, not a shard one — both rulesets carry it.
    test "vanilla carries it too" do
      vanilla = Data.ruleset!("vanilla")
      build = build_with(:wizard, 40, int: 14, skills: %{40 => %{spellcraft: 20}})

      assert Skills.save_bonus(build, vanilla, 40) == {4, [:spellcraft]}
    end
  end

  # What the character actually rolls. The interface used to assemble this
  # itself, in two places, and both forgot the racial affinities and the shard
  # modifiers — so the number captioned "с модификаторами" was short.
  describe "a skill's final value" do
    # source: vanilla/races.json — elf `skill_bonuses` %{listen: 2, search: 2,
    # spot: 2} (fandom "Elf": Skill Affinity), ability_modifiers %{DEX: +2,
    # CON: -2}. vanilla/skills.json: spot keys off WIS, hide off DEX.
    test "ranks plus the key ability modifier plus the racial affinity", %{ruleset: ruleset} do
      build =
        build_with(:rogue, 10, wis: 14, dex: 14, race: :elf, skills: %{1 => %{spot: 8, hide: 8}})

      # spot: 8 ranks + WIS 14 (+2) + elf affinity +2
      assert %{ranks: 8, ability: :wis, ability_modifier: 2, race_bonus: 2, total: 12} =
               Skills.value(build, ruleset, :spot, 10)

      # hide: 8 ranks + DEX 14+2 racial = 16 (+3), and no affinity for hide
      assert %{ability: :dex, ability_modifier: 3, race_bonus: 0, total: 11} =
               Skills.value(build, ruleset, :hide, 10)
    end

    # The cascade the equipment layer exists for (CLAUDE.md §6): +12 INT is not
    # "+12 Spellcraft", it is +6 — and a value computed off the naked score
    # would miss all six.
    test "the ability modifier is the geared one", %{ruleset: ruleset} do
      naked = build_with(:wizard, 10, int: 14, skills: %{1 => %{spellcraft: 10}})
      geared = %{naked | gear: BuildCalculator.Rules.Gear.new(abilities: %{int: 12})}

      assert Skills.value(naked, ruleset, :spellcraft, 10).total == 12
      # INT 14 -> 26, modifier +2 -> +8
      assert Skills.value(geared, ruleset, :spellcraft, 10).total == 18
    end

    test "the four-class stealth penalty reaches the value", %{ruleset: ruleset} do
      build =
        Build.new(
          race: :human,
          levels:
            List.duplicate(:rogue, 20) ++
              List.duplicate(:shadowdancer, 10) ++
              List.duplicate(:fighter, 6) ++ List.duplicate(:wizard, 4),
          skills: %{1 => %{hide: 20}}
        )

      assert %{shard_modifier: -10, ability_modifier: 0, total: 10} =
               Skills.value(build, ruleset, :hide, 40)
    end

    # 🔴 Здесь стояло «a skill with no key ability has no value, and says why»
    # на живой Алхимии: её характеристику не называла ни одна вики, поэтому
    # значение было `nil`, а рядом лежала оговорка. **Закрыто замером Dan
    # 17.08.2026, кейс P1** — «ее атрибут - мудрость», — и кейс перевёрнут
    # в положительный: тот же навык, то же число рангов, но теперь у него есть
    # значение. Отказ никуда не делся и проверяется ниже на синтетическом
    # ruleset'е — просто в живых данных он больше не про этот навык.
    test "у Alchemy есть значение: ранги плюс мудрость (замер Dan, кейс P1)", %{
      ruleset: ruleset
    } do
      build = build_with(:bard, 10, wis: 14, skills: %{1 => %{alchemy: 5}})

      assert %{ability: :wis, ability_modifier: 2, ranks: 5, total: 7, gaps: []} =
               Skills.value(build, ruleset, :alchemy, 10)
    end

    # ⚠️ И вторая половина того же факта, без которой первая ничего не значит:
    # характеристика приезжает ИЗ ДАННЫХ, а не из совпадения. Мудрость с вещей
    # каскадом двигает значение навыка, как у любого другого.
    test "мудрость Алхимии — та же характеристика, что у всех: с вещей она каскадит", %{
      ruleset: ruleset
    } do
      naked = build_with(:bard, 10, wis: 14, skills: %{1 => %{alchemy: 5}})
      geared = %{naked | gear: Gear.new(abilities: %{wis: 12})}

      # WIS 14 -> 26, модификатор +2 -> +8
      assert Skills.value(geared, ruleset, :alchemy, 10).total == 13
    end

    test "values/3 covers the skills bought and nothing else", %{ruleset: ruleset} do
      build = build_with(:rogue, 10, dex: 14, skills: %{1 => %{hide: 4, move_silently: 0}})

      assert Map.keys(Skills.values(build, ruleset, 10)) == [:hide]
    end

    test "compute/2 carries them, and both skills come back with a number", %{ruleset: ruleset} do
      build =
        build_with(:bard, 10, int: 14, wis: 14, skills: %{1 => %{alchemy: 5, spellcraft: 5}})

      stats = Rules.compute(build, ruleset)

      assert stats.skill_values[:spellcraft].total == 7
      assert stats.skill_values[:alchemy].total == 7

      # ⚠️ Оговорка обязана исчезнуть вместе с причиной: печатать «не можем
      # посчитать» про посчитанное запрещено так же прямо, как молчать про
      # непосчитанное (CLAUDE.md §6).
      refute Enum.any?(stats.gaps, &match?({:missing_data, {:skill_key_ability, _}}, &1))
    end
  end

  # 🔴 Механизм отказа жив, свидетеля в данных не осталось — и это ДВА разных
  # утверждения, поэтому и тестов два. Первое проверяется единственным способом,
  # каким его можно проверить без выдуманного игрового факта: копией
  # `priv/rules`, у которой поле снято (приём `gear_weapon_test.exs` и
  # `feat_hp_bonuses_test.exs`). Второе — обходом живых данных.
  #
  # ⚠️ Оба поля закрыл ОДИН ответ Dan 17.08.2026 (кейс P1) и оба держались
  # на одном навыке, поэтому проверяются парой: разъедься они, и «в данных
  # никого не осталось» превратилось бы в «свидетель просто перестал сюда
  # попадать».
  describe "навык, про который источник не высказался" do
    test "снятая ключевая характеристика возвращает отказ, и он доезжает до билда" do
      ruleset = ruleset_without_skill_field("key_ability")
      build = build_with(:fighter, 10, str: 14, skills: %{1 => %{discipline: 4}})
      value = Skills.value(build, ruleset, :discipline, 10)

      assert value.total == nil
      assert value.ability == nil
      assert value.ability_modifier == nil

      # Известное всё равно возвращается — вызывающий покажет ранги.
      assert value.ranks == 4
      assert value.gaps == [{:missing_data, {:skill_key_ability, :discipline}}]

      stats = Rules.compute(build, ruleset)

      assert stats.skill_values[:discipline].total == nil

      # Один раз, а не дважды: что значит неизвестное слагаемое, решает одно
      # место (`Skills.value/4`).
      assert Enum.count(
               stats.gaps,
               &(&1 == {:missing_data, {:skill_key_ability, :discipline}})
             ) == 1
    end

    test "снятый штраф брони возвращает отказ — но только пока надето штрафующее" do
      ruleset = ruleset_without_skill_field("armor_check_penalty")

      plated =
        Build.new(
          levels: List.duplicate(:fighter, 10),
          base_abilities: abilities(str: 14),
          skills: %{1 => %{discipline: 4}},
          gear: Gear.new(worn: %{armor: :full_plate})
        )

      value = Skills.value(plated, ruleset, :discipline, 10)

      assert value.armor_penalty == nil
      assert value.total == nil
      assert {:missing_data, {:skill_armor_check_penalty, :discipline}} in value.gaps

      assert {:missing_data, {:skill_armor_check_penalty, :discipline}} in Rules.compute(
               plated,
               ruleset
             ).gaps

      # ⚠️ Голым персонажем вопрос не встаёт: штраф `0` при любом ответе, и
      # неопределённость про решённое печатать нельзя. Половина, без которой
      # первая зеленела бы и у реализации «оговорка на каждом билде».
      bare = %{plated | gear: Gear.new()}
      bare_value = Skills.value(bare, ruleset, :discipline, 10)

      assert bare_value.armor_penalty == 0
      assert bare_value.total == 4 + 2
      assert bare_value.gaps == []
    end

    # 🔴 Утверждение о живых данных, а не о механизме: свидетелей у обеих форм
    # не осталось ни в одном ruleset'е. Обязано упасть в тот день, когда шард
    # добавит навык без этих полей, — иначе игрок увидит уверенное число там,
    # где источник молчит.
    test "в данных таких навыков не осталось — ни у Сиалы, ни у ванили", %{ruleset: siala} do
      vanilla = Data.ruleset!("vanilla")

      for ruleset <- [siala, vanilla] do
        assert for({id, %{key_ability: nil}} <- ruleset.skills, do: id) == []
        assert for({id, %{armor_check_penalty: :unknown}} <- ruleset.skills, do: id) == []

        # Положительный контроль: список навыков не пуст и поля читаются, то
        # есть два `== []` выше — это ответ, а не пустой обход.
        assert map_size(ruleset.skills) >= 28
        assert ruleset.skills[:discipline].key_ability == :str
        assert ruleset.skills[:hide].armor_check_penalty == :applies
      end

      # ...и у навыка, ради которого обе формы заводились: 17.08.2026 у него
      # появились оба ответа сразу (Dan, кейс P1).
      assert siala.skills[:alchemy].key_ability == :wis
      assert siala.skills[:alchemy].armor_check_penalty == :none
    end
  end

  # ⚠️ Третий отказ ядра: прибавку фита к навыку («+3» у Skill focus, «+10»
  # у Epic skill focus) не называет ни одно поле данных — она лежит английской
  # прозой в `description` на Fandom. Вытащить число оттуда значило бы его
  # выдумать (§3), поэтому значение остаётся коротким, но говорит, НА ЧТО.
  describe "feats taken for a skill" do
    # 🔴 ВЕСЬ ЭТОТ БЛОК ПЕРЕВЁРНУТ 25.08.2026 (задача 3.92), и переворот —
    # не починка теста, а починка того, что он фиксировал. Здесь стояло
    # «`Skill focus` и `Epic skill focus` попадают в оговорку по паре (пик,
    # `repeatable.choice`)» и рядом «число НЕ меняется: +3 нет ни в одном поле
    # данных, и подставить его было бы выдумыванием». Первое было верно,
    # второе — нет: число лежало в `feat_skill_bonuses.json` с дословной
    # цитатой и `status: verified`, не хватало только соединения. Решение Dan:
    # «данные фиты, как и любые другие фиты, увеличивающие скиллы, нужно
    # плюсовать в скиллах».
    #
    # Механизм пары при этом жив и нужен — он про фит, взятый НА навык, чью
    # прибавку разметка не считает, — поэтому проверяется на ruleset'е,
    # у которого записи опущены обратно (`without_focus/1`).
    test "посчитанный фит оговоркой больше не идёт, а его число — идёт",
         %{ruleset: ruleset} do
      build =
        build_with(:rogue, 21,
          dex: 14,
          int: 14,
          skills: %{1 => %{discipline: 20, spellcraft: 4}},
          feats: %{
            1 => %{general: {:skill_focus, :discipline}},
            21 => %{general: {:epic_skill_focus, :discipline}}
          }
        )

      assert Skills.feats_by_skill(build, ruleset, 21) == %{}

      discipline = Skills.value(build, ruleset, :discipline, 21)

      # source: fandom "Skill focus" revid 72101 — «+3 bonus on all checks with
      # it»; "Epic skill focus" revid 72105 — «+10 bonus on all skill checks
      # with the chosen skill». Складываются по слову обеих страниц:
      # «This feat stacks with epic skill focus» и наоборот.
      assert discipline.feat_bonus == 13
      assert discipline.feat_bonus_from == [:skill_focus, :epic_skill_focus]

      # Навык, на который фит не брали, не вырос ни на очко.
      assert Skills.value(build, ruleset, :spellcraft, 21).feat_bonus == 0
    end

    # 🔴 Механизм пары «пик + домен выбора» жив: ruleset, чья разметка эти
    # записи не применяет, называет оба фита оговоркой ровно как раньше.
    # Без этого теста снятие оговорки было бы неотличимо от её поломки.
    test "механизм оговорки по паре жив — его лишились две записи, а не все",
         %{ruleset: ruleset} do
      build =
        build_with(:rogue, 21,
          dex: 14,
          int: 14,
          skills: %{1 => %{discipline: 20}},
          feats: %{
            1 => %{general: {:skill_focus, :discipline}},
            21 => %{general: {:epic_skill_focus, :discipline}}
          }
        )

      demoted = without_focus(ruleset)

      assert Skills.feats_by_skill(build, demoted, 21) == %{
               discipline: [:skill_focus, :epic_skill_focus]
             }

      value = Skills.value(build, demoted, :discipline, 21)
      assert value.feat_bonus == 0
      assert value.unmodelled_feats == [:skill_focus, :epic_skill_focus]
    end

    # Положительный контроль рядом с отрицательным: без него `refute` зеленел
    # бы и оттого, что в поле зрения не попал вообще ни один фит.
    test "фит с выбором НЕ-навыка сюда не попадает", %{ruleset: ruleset} do
      build =
        build_with(:wizard, 10,
          int: 14,
          skills: %{1 => %{spellcraft: 4}},
          feats: %{
            1 => %{general: {:spell_focus, :evocation}},
            3 => %{general: {:skill_focus, :spellcraft}}
          }
        )

      found = Skills.feats_by_skill(build, without_focus(ruleset), 10)

      # Школа магии — не навык, и `evocation` не должен стать ключом.
      assert found == %{spellcraft: [:skill_focus]}
      refute Map.has_key?(found, :evocation)
    end

    # Доставка адресной оговорки: она ложится в ТОТ навык, которого недостаёт,
    # и не трогает соседний.
    #
    # ⚠️ Ruleset синтетический с 25.08.2026 (задача 3.95, см.
    # `with_narrow_skill_bonus/2`): у живого `Favored enemy` оговорки больше
    # нет — её сняло решение владельца, потому что описание фита называет
    # и число, и условие. Проверяется поэтому механизм, а не состав данных.
    test "значение остаётся числом, но называет недостающее слагаемое", %{ruleset: ruleset} do
      build =
        build_with(:ranger, 10,
          dex: 14,
          int: 14,
          skills: %{1 => %{spot: 13, hide: 13}},
          feats: %{1 => %{{:class_bonus, :ranger} => {:favored_enemy, :goblinoid}}}
        )

      narrow = with_narrow_skill_bonus(ruleset)
      spot = Skills.value(build, narrow, :spot, 10)

      # ⚠️ Число НЕ меняется: прибавка условная, и подставить её в безусловную
      # строку значило бы соврать. Меняется то, что у нехватки есть имя.
      assert spot.total == spot.ranks + spot.ability_modifier
      assert spot.unmodelled_feats == [:favored_enemy]

      # Навык, которого фит не касается, ничего не сообщает.
      assert Skills.value(build, narrow, :hide, 10).unmodelled_feats == []

      # 🔴 И то же самое на ЖИВЫХ данных: ни числа, ни оговорки. Первое
      # не менялось никогда, второе снято решением владельца.
      live = Skills.value(build, ruleset, :spot, 10)
      assert live.total == live.ranks + live.ability_modifier
      assert live.unmodelled_feats == []
    end

    # Своего гэпа здесь не заводится: тот же факт уже едет из `FeatChoices`,
    # и второй под другим именем превратил бы список в тот, который скользят
    # глазами.
    #
    # ⚠️ Обе половины пришлось завести синтетически (задача 3.95): у живого
    # `Favored enemy` сняты ОБЕ оговорки сразу — и `{:feat_bonus, …}` решением
    # в `feat_effect_receivers.json`, и адресная в разметке навыков. Здесь
    # решение снимается обратно, чтобы вопрос «сколько раз про один факт»
    # вообще имел смысл.
    test "фит уже отчитан один раз, и второй записи не появляется", %{ruleset: ruleset} do
      build =
        build_with(:ranger, 10,
          dex: 14,
          int: 14,
          skills: %{1 => %{spot: 13}},
          feats: %{1 => %{{:class_bonus, :ranger} => {:favored_enemy, :goblinoid}}}
        )

      talkative =
        ruleset
        |> with_narrow_skill_bonus()
        |> Map.update!(:feat_effect_receivers, &Map.delete(&1, :favored_enemy))

      gaps = Rules.compute(build, talkative).gaps

      assert Enum.count(gaps, &(&1 == {:not_modelled, {:feat_bonus, :favored_enemy}})) == 1

      # И на живых данных про этот факт не говорится ни разу — обе оговорки
      # сняты решением владельца, а не одна из двух.
      live = Rules.compute(build, ruleset).gaps
      refute {:not_modelled, {:feat_bonus, :favored_enemy}} in live
    end

    # 🔴 И обратная сторона той же правки: у посчитанного фита эта оговорка
    # ПРОПАДАЕТ, иначе «прибавку от фита в статы не считаем» печаталась бы
    # рядом с термом «Skill focus +3» в разборе того же навыка на том же
    # экране. Ровно та поломка, которую задача 1.9 чинила у `Epic toughness`.
    test "у посчитанного фита пропадает и общая оговорка про прибавку",
         %{ruleset: ruleset} do
      build =
        build_with(:rogue, 21,
          dex: 14,
          int: 14,
          skills: %{1 => %{discipline: 20}},
          feats: %{
            1 => %{general: {:skill_focus, :discipline}},
            21 => %{general: {:epic_skill_focus, :discipline}}
          }
        )

      gaps = Rules.compute(build, ruleset).gaps

      refute {:not_modelled, {:feat_bonus, :skill_focus}} in gaps
      refute {:not_modelled, {:feat_bonus, :epic_skill_focus}} in gaps

      # 🔴 Положительный контроль тот же билд и тот же механизм, отличается
      # только разметка: на ruleset'е, который эти записи не применяет, обе
      # оговорки на месте. Иначе два `refute` зеленели бы и на модели,
      # которая перестала говорить про фиты вообще.
      demoted = Rules.compute(build, without_focus(ruleset)).gaps

      assert {:not_modelled, {:feat_bonus, :skill_focus}} in demoted
      assert {:not_modelled, {:feat_bonus, :epic_skill_focus}} in demoted
    end
  end

  # Ruleset, чья разметка `Skill focus` и `Epic skill focus` НЕ применяет —
  # ровно то, чем сегодня является `vanilla` для второго из них. Нужен как
  # свидетель для механизма, у которого после задачи 3.92 не осталось живых
  # носителей: снятая оговорка и сломанная оговорка иначе выглядят одинаково.
  # 🔴 Узкая запись разметки навыков — СИНТЕТИЧЕСКАЯ с 25.08.2026 (задача 3.95).
  # Живых записей с нашим получателем в `feat_skill_bonuses.json` не осталось
  # ни одной: `trackless_step` и `stonecunning` ушли решением Dan (3.76),
  # `skill_focus` стал посчитанным (3.92), `favored_enemy` ушёл решением
  # владельца (3.95). Три замены носителя подряд — признак того, что живой
  # пример проверял не то: вопрос здесь про ДОСТАВКУ оговорки, а не про
  # сегодняшний состав данных.
  #
  # ⚠️ Синтетическая только запись. Фит настоящий, маршрут владения настоящий
  # (`{:feat, :favored_enemy}` — слот или выдача класса), и правило
  # «прибавка условная, значит в число не идёт» тоже настоящее.
  defp with_narrow_skill_bonus(ruleset, skills \\ [:spot, :listen, :taunt]) do
    record = %{
      id: :favored_enemy,
      source: {:feat, :favored_enemy},
      verdict: :not_modelled,
      skills: skills,
      amount: %{kind: :flat, bonus: 1},
      counted_for_classes: [],
      affects: ["skill_values"]
    }

    %{
      ruleset
      | skill_bonuses: %{ruleset.skill_bonuses | unmodelled: [record]}
    }
  end

  defp without_focus(ruleset) do
    {demoted, kept} =
      Enum.split_with(ruleset.skill_bonuses.applied, &(&1.skills_from == :feat_choice))

    %{
      ruleset
      | skill_bonuses: %{
          ruleset.skill_bonuses
          | applied: kept,
            unmodelled:
              ruleset.skill_bonuses.unmodelled ++
                Enum.map(demoted, &%{&1 | verdict: :not_modelled})
        }
    }
  end

  describe "плоские прибавки фитов к навыкам" do
    # source: fandom "Alertness" revid 40887 — «+2 bonus to [[spot]] and
    # [[listen]] checks due to finely tuned senses.» Перенесено вручную
    # в priv/rules/vanilla/feat_skill_bonuses.json: в feats.json связи
    # «фит → навык» нет ни в одном поле, только прозой в description.
    test "Alertness поднимает Spot и Listen на 2", %{ruleset: ruleset} do
      build =
        build_with(:rogue, 3,
          wis: 10,
          int: 14,
          skills: %{1 => %{spot: 15, listen: 4, hide: 4}},
          feats: %{1 => %{general: :alertness}}
        )

      spot = Skills.value(build, ruleset, :spot, 3)

      # Раньше здесь было 15: прибавка терялась молча, и ни один гэп о ней
      # не говорил (HANDOFF §A.1).
      assert {spot.ranks, spot.feat_bonus, spot.total} == {15, 2, 17}
      assert spot.feat_bonus_from == [:alertness]
      assert Skills.value(build, ruleset, :listen, 3).feat_bonus == 2

      # Положительный контроль: навык, которого фит не касается, не вырос.
      assert Skills.value(build, ruleset, :hide, 3).feat_bonus == 0
    end

    # source: fandom "Stealthy" revid 41246 — «+2 bonus on [[hide]] and
    # [[move silently]] checks».
    test "Stealthy поднимает Hide и Move Silently на 2", %{ruleset: ruleset} do
      build =
        build_with(:rogue, 3,
          dex: 10,
          int: 14,
          skills: %{1 => %{hide: 6, move_silently: 6, spot: 6}},
          feats: %{1 => %{general: :stealthy}}
        )

      assert Skills.value(build, ruleset, :hide, 3).total == 8
      assert Skills.value(build, ruleset, :move_silently, 3).total == 8
      assert Skills.value(build, ruleset, :spot, 3).total == 6
    end

    test "два фита на один навык складываются и оба названы", %{ruleset: ruleset} do
      build =
        build_with(:rogue, 3,
          wis: 10,
          int: 14,
          skills: %{1 => %{spot: 10}},
          feats: %{1 => %{general: :alertness, second: :blooded}}
        )

      spot = Skills.value(build, ruleset, :spot, 3)

      assert spot.feat_bonus == 4
      assert spot.feat_bonus_from == [:alertness, :blooded]
    end

    # ⚠️ Регрессия на двойной счёт. `skill_affinity_spot` — расовый фит эльфа,
    # и его +2 УЖЕ приезжает из races.json → skill_bonuses. Если фит начнёт
    # считаться и как фит, у эльфа станет +4, а тест на Alertness останется
    # зелёным — он про другой фит.
    test "расовая склонность считается один раз, а не и как раса, и как фит",
         %{ruleset: ruleset} do
      elf =
        build_with(:rogue, 3,
          wis: 10,
          int: 14,
          race: :elf,
          skills: %{1 => %{spot: 10}}
        )

      spot = Skills.value(elf, ruleset, :spot, 3)

      assert spot.race_bonus == 2
      assert spot.feat_bonus == 0
      assert spot.total == 12
    end

    # source: fandom "Trackless step" revid 70101 — «+4 competence bonus to
    # [[hide]] and [[move silently]] checks **when in wilderness areas**».
    # Условие на местность калькулятору неизвестно, поэтому число не берём.
    # ⚠️ Название и половина проверок сменились 22.08.2026 (задача 3.76).
    # Было «условная прибавка не считается, но названа на той же строке»
    # с `assert :trackless_step in hide.unmodelled_feats`. Решением Dan
    # прибавка перестала быть и пробелом, и оговоркой билда: её условие —
    # МЕСТНОСТЬ, то есть состояние мира.
    #
    # 🔴 Первая половина теста не изменилась ни на строку, и это главное:
    # прибавка КАК НЕ СЧИТАЛАСЬ, ТАК И НЕ СЧИТАЕТСЯ. Решение убрало
    # признание, а не число — и если завтра кто-нибудь «починит» его,
    # прибавив +4 к значению, тест упадёт здесь же.
    test "условная прибавка не считается и больше не называется", %{ruleset: ruleset} do
      build =
        build_with(:ranger, 3,
          dex: 10,
          int: 14,
          skills: %{1 => %{hide: 6, spot: 6}}
        )

      hide = Skills.value(build, ruleset, :hide, 3)

      assert hide.feat_bonus == 0
      assert hide.total == 6
      refute :trackless_step in hide.unmodelled_feats
      refute :trackless_step in Skills.value(build, ruleset, :spot, 3).unmodelled_feats

      # 🔴 Положительный контроль: список оговорок не опустел вообще — иначе
      # два `refute` выше зеленели бы и на модели, которая растеряла их все.
      #
      # ⚠️ Носитель СИНТЕТИЧЕСКИЙ с 25.08.2026 (задача 3.95). Живой менялся
      # трижды и трижды по одной причине — оговорку с него снимали: `Skill
      # focus` стал посчитанным (3.92), `Favored enemy` ушёл решением
      # владельца (3.95). Живых записей с нашим получателем в этой разметке
      # не осталось ни одной, и назначать четвёртую жертву незачем.
      hunter =
        build_with(:ranger, 3,
          dex: 10,
          int: 14,
          skills: %{1 => %{spot: 6}},
          feats: %{1 => %{{:class_bonus, :ranger} => {:favored_enemy, :goblinoid}}}
        )

      narrow = with_narrow_skill_bonus(ruleset)

      assert :favored_enemy in Skills.value(hunter, narrow, :spot, 3).unmodelled_feats
    end

    # ⚠️ Тест перевёрнут 22.08.2026 (задача 3.76). Здесь стояло `assert … in
    # ruleset.gaps` с названием «условная прибавка объявлена и в данных».
    # Решение Dan: условие у обеих прибавок — МЕСТНОСТЬ («in wilderness areas»
    # / «in interior areas»), то есть состояние мира, а не свойство билда, —
    # та же категория, что баффы, конь и боевая обстановка. Признаваться
    # не в чем, и проверяется теперь ОТСУТСТВИЕ: вернуться пункт может
    # только молча.
    #
    # ⚠️ Сама запись при этом на месте и вердикт у неё прежний — меняется
    # не то, считаем ли мы прибавку (не считаем и не считали), а то, обязаны
    # ли мы про неё говорить.
    test "условная прибавка в данных есть, но пробелом не объявляется", %{ruleset: ruleset} do
      refute {:not_modelled, {:feat_skill_bonus, :trackless_step}} in ruleset.gaps

      record = Enum.find(ruleset.skill_bonuses.unmodelled, &(&1.id == :trackless_step))
      assert record.verdict == :not_modelled
      assert record.affects == ["skill_values"]
      assert is_map(record.not_a_gap)
    end

    # source: fandom "Gnome" revid 65710 и "Halfling" revid 71190 (снято
    # 01.08.2026, оба лежат в priv/wiki_cache) — «+4 size bonus to standard
    # [[stealth]] and [[detect]]ion checks (modifies [[hide]], [[listen]],
    # [[move silently]], and [[spot]])».
    # source: fandom "Skill level" revid 56492 (снято 01.08.2026) — «A [[size
    # modifier]] is applied to [[stealth]] and [[detect]]ion skills, but this is
    # considered part of those specific checks, NOT part of the skill level (the
    # size modifier is neither reported on the character sheet nor used in custom
    # [[script]]s that do not explicitly add it)».
    # source: fandom "Detect" revid 68890 (снято 01.08.2026) — «Relative size
    # modifiers (Tiny: +8, Small: +4, Medium: 0, Large: -4, Huge: -8)», то есть
    # модификатор ОТНОСИТЕЛЬНЫЙ: против такого же мелкого он ноль.
    #
    # ⚠️ AGENT_QUEUE §7 звал дописать этот +4 в feat_skill_bonuses.json как
    # «пропущенную прибавку». Нельзя: получатель у него — бросок, а не значение
    # навыка, и лист персонажа его не показывает. Тест держит именно это, потому
    # что число на вики есть, и следующий читатель захочет его прибавить.
    #
    # Ожидания собраны из источников по слагаемым, а не из вывода кода:
    # halfling DEX +2 (races.json) → dex 12 → мод +1; его же affinity
    # listen +2 и move_silently +2; у gnome DEX не меняется, affinity — listen.
    test "размерный модификатор Карлика и Гоблина в значение навыка не идёт",
         %{ruleset: ruleset} do
      ranks = %{1 => %{hide: 4, listen: 4, move_silently: 4, spot: 4}}

      halfling = build_with(:rogue, 3, race: :halfling, int: 14, skills: ranks)
      gnome = build_with(:rogue, 3, race: :gnome, int: 14, skills: ranks)

      # Карлик = Gnome, Гоблин = Halfling (CLAUDE.md §4) — обе мелкие расы.
      assert value_parts(halfling, ruleset, :hide) == %{ranks: 4, race: 0, feat: 0, total: 5}
      assert value_parts(halfling, ruleset, :listen) == %{ranks: 4, race: 2, feat: 0, total: 6}
      assert value_parts(gnome, ruleset, :spot) == %{ranks: 4, race: 0, feat: 0, total: 4}

      assert value_parts(gnome, ruleset, :move_silently) == %{
               ranks: 4,
               race: 0,
               feat: 0,
               total: 4
             }

      # Положительный контроль: механизм прибавок к этим же навыкам жив —
      # Alertness на том же билде даёт свои +2, значит ноль выше не от того,
      # что расчёт вообще ничего не складывает.
      alert =
        build_with(:rogue, 3,
          race: :halfling,
          int: 14,
          skills: ranks,
          feats: %{1 => %{general: :alertness}}
        )

      assert value_parts(alert, ruleset, :spot) == %{ranks: 4, race: 0, feat: 2, total: 6}
      assert value_parts(alert, ruleset, :listen) == %{ranks: 4, race: 2, feat: 2, total: 8}
    end

    # ⚠️ **Тест перевёрнут 10.08.2026 задачей 3.25, и это не починка теста, а
    # починка того, что он фиксировал.** Здесь стояло «оговорка живёт в данных, но
    # не на билде»: `unmodelled_skill_bonus` читался через `Build.feats_owned/3`,
    # куда расовые склонности не попадают сознательно, а вида источника
    # `race_feat` у скилловой разметки не было вовсе. Гейт не менялся — у записи
    # появился вид источника, и теперь её держит РАСА (`Bonuses.held?/5`, ветка
    # `{:race_feat, id}`).
    #
    # ⚠️ Число по-прежнему НЕ прибавляется (тест выше про это, и он не тронут):
    # исправлена доставка оговорки, а не вердикт.
    test "оговорка про размерный модификатор не доезжает НИКУДА, и оба списка согласны",
         %{ruleset: ruleset, vanilla: vanilla} do
      # ⚠️ Здесь стояло `assert {:not_modelled, {:feat_skill_bonus,
      # :small_stature}} in ruleset.gaps` — снято 17.08.2026 задачей «пять
      # файлов прибавок». Не потому, что доставка сломалась (гейт
      # `{:race_feat, id}` остаётся ровно тем же), а потому, что у записи
      # появился `affects: ["special_ability"]`: источник дословно говорит,
      # что размерный модификатор «not part of the skill level» и «neither
      # reported on the character sheet», то есть это не факт про наш
      # получатель `skill_values` вовсе.
      refute {:not_modelled, {:feat_skill_bonus, :small_stature}} in ruleset.gaps

      # ⚠️ 22.08.2026 (задача 3.76) положительный контроль ПОТЕРЯЛ носителя:
      # `stonecunning` и `trackless_step` ушли из списка решением Dan (условие
      # по местности — состояние мира, а не свойство билда), и записей вида
      # `{:feat_skill_bonus, …}` в `ruleset.gaps` не осталось НИ ОДНОЙ.
      #
      # 🔴 Поэтому контроль сменил форму, а не исчез: проверяется, что запись
      # `small_stature` по-прежнему ДОСТАВЛЯЕТСЯ (лежит в разметке, держится
      # расой), и отсутствие её гэпа — про получателя, а не про сломанную
      # доставку. Иначе `refute` выше зеленел бы и на модели, которая
      # растеряла разметку целиком.
      assert Enum.find(ruleset.skill_bonuses.unmodelled, &(&1.id == :trackless_step))

      record = Enum.find(ruleset.skill_bonuses.unmodelled, &(&1.id == :small_stature))
      assert record.skills == [:hide, :listen, :move_silently, :spot]
      assert record.source == {:race_feat, :small_stature}

      ranks = %{1 => %{hide: 4, listen: 4, move_silently: 4, spot: 4}}

      # 🔴 ДВА СПИСКА ПРО ОДНО И ТО ЖЕ СОШЛИСЬ (17.08.2026, вторая половина той
      # же задачи). Здесь стоял `assert :small_stature in unmodelled_feats` с
      # честной оговоркой, что корпусный список её уже не называет, а панель
      # навыка называет: фильтр стоял только в `data/loader.ex`, а
      # `Rules.Bonuses.held_rejected/4` про получателей не знал вовсе. Два
      # ответа на один вопрос хуже, чем оба неверных, — теперь правило
      # применяется в единственной воронке, и панель Hide у Гоблина молчит
      # ровно там же, где молчит `ruleset.gaps`.
      for race <- [:halfling, :gnome], skill <- record.skills do
        build = build_with(:rogue, 3, race: race, int: 14, skills: ranks)

        refute :small_stature in Skills.value(build, ruleset, skill, 3).unmodelled_feats,
               "#{race}: #{skill} с оговоркой про то, чего мы не показываем"
      end

      # 🔴 Отрицательный контроль ко всему блоку: маршрут доставки жив, и
      # снимает оговорку ровно словарь получателей. У ванили его нет —
      # тот же гоблин, тот же навык, оговорка на месте.
      goblin = build_with(:rogue, 3, race: :halfling, int: 14, skills: ranks)
      assert :small_stature in Skills.value(goblin, vanilla, :hide, 3).unmodelled_feats

      # И третья половина, тоже под этим же тестом: `Build.feats_owned/3` НЕ
      # расширен — расовой склонности там нет, иначе изменилась бы каждая
      # проверка требований в приложении.
      refute MapSet.member?(Build.feats_owned(goblin, ruleset, 3), :small_stature)

      # Положительный контроль на другой вид источника: оговорка фита, которым
      # билд ВЛАДЕЕТ, доезжает тем же путём и на Сиале.
      #
      # ⚠️ Пример сменился ТРИЖДЫ и на третий раз стал синтетическим.
      # 22.08.2026 (3.76) `trackless_step` ушёл решением Dan; 25.08.2026 (3.92)
      # ушёл `Skill focus` — его +3 считаются; в тот же день (3.95) ушёл
      # `Favored enemy` — решение владельца. Запись синтетическая
      # (`with_narrow_skill_bonus/2`), маршрут `{:feat, id}` живой.
      hunter =
        build_with(:ranger, 3,
          int: 14,
          skills: %{1 => %{spot: 4}},
          feats: %{1 => %{{:class_bonus, :ranger} => {:favored_enemy, :goblinoid}}}
        )

      assert :favored_enemy in Skills.value(hunter, with_narrow_skill_bonus(ruleset), :spot, 3).unmodelled_feats
    end

    # Вторая расовая склонность того же файла, и она проверяет ровно то, что
    # правка задела не один фит: Гном (= Dwarf) со Каменной кладкой получает
    # оговорку у Search, а Гоблин — нет.
    # ⚠️ 22.08.2026 (задача 3.76): оговорка снята решением Dan, и тест
    # проверяет теперь ДОСТАВКУ отдельно от ПРИЗНАНИЯ. Прежний `assert
    # :stonecunning in … unmodelled_feats` смешивал два вопроса в один,
    # и после решения владельца различить их стало обязательно.
    test "Stonecunning держится Гномом и только им, но оговоркой не выходит", %{
      ruleset: ruleset
    } do
      ranks = %{1 => %{search: 4}}

      dwarf = build_with(:rogue, 3, race: :dwarf, int: 14, skills: ranks)
      halfling = build_with(:rogue, 3, race: :halfling, int: 14, skills: ranks)

      record = Enum.find(ruleset.skill_bonuses.unmodelled, &(&1.id == :stonecunning))

      # Доставка цела: расовый гейт различает Гнома и Гоблина, как различал.
      assert Bonuses.held?(record.source, dwarf, ruleset, MapSet.new(), 3)
      refute Bonuses.held?(record.source, halfling, ruleset, MapSet.new(), 3)

      # А до строки навыка не доходит ни у кого — по решению владельца,
      # и число при этом не изменилось: прибавка как не считалась, так и нет.
      refute :stonecunning in Skills.value(dwarf, ruleset, :search, 3).unmodelled_feats
      assert Skills.value(dwarf, ruleset, :search, 3).feat_bonus == 0
    end

    # ⚠️ Тот же факт под двумя именами — то, чего этот проект избегает: у
    # repeatable-фитов оговорку уже везёт `FeatChoices`, и вторая запись
    # в ruleset.gaps была бы дублем.
    test "фит с выбором навыка второй записи в данных не получает", %{ruleset: ruleset} do
      refute {:not_modelled, {:feat_skill_bonus, :skill_focus}} in ruleset.gaps
      refute {:not_modelled, {:feat_skill_bonus, :epic_skill_focus}} in ruleset.gaps
    end
  end

  # ⚠️ Раздел переписан 16.08.2026 по замеру Dan (`GAME_CHECKS.md`, кейс F7).
  # Здесь стояло «Bardic Knowledge Арфиста-скаута», и модель считала ТОЛЬКО
  # уровни Арфиста и только с его 2-го уровня. В игре прибавка равна СУММЕ
  # уровней барда и Арфиста-скаута, а «со 2-го» относится к выдаче самого фита,
  # а не к тому, какие уровни идут в сумму. На билде Dan мы недосчитывали 8.
  #
  # source (правило): fandom «Bardic knowledge» revid 51806, раздел Notes —
  # «Harper scout and bard levels stack for the bonus granted by this feat»;
  # там же «it is hardcoded to the bard and Harper scout class levels».
  # source (сдвиг выдачи на Сиале): siala «Арфист-скаут» revid 19414.
  describe "Bardic Knowledge — сумма уровней барда и Арфиста" do
    # 🔴 Дословный замер Dan 16.08.2026: один персонаж, Знание 9 рангов,
    # INT 12 (мод +1), четыре точки. До правки все четыре давали 10.
    #
    #   | билд                   | лист | разбор     |
    #   | бард 6                 |  16  | 9 + 1 + 6  |
    #   | бард 7                 |  17  | 9 + 1 + 7  |
    #   | бард 7 + Арфист 1      |  18  | 9 + 1 + 8  |
    #   | ↑ + рейнджер 2         |  18  | без измен. |
    test "четыре точки замера F7 воспроизводятся числом в число", %{ruleset: ruleset} do
      table = [
        {"бард 6", List.duplicate(:bard, 6), 6, 16, 6},
        {"бард 7", List.duplicate(:bard, 7), 7, 17, 7},
        {"бард 7 + Арфист 1", List.duplicate(:bard, 7) ++ [:harper_scout], 8, 18, 8},
        {"+ рейнджер 2", List.duplicate(:bard, 7) ++ [:harper_scout, :ranger, :ranger], 10, 18, 8}
      ]

      for {label, levels, level, total, class_bonus} <- table do
        lore = Skills.value(dan_f7(levels), ruleset, :lore, level)

        assert {lore.ranks, lore.ability_modifier} == {9, 1}, label
        assert {lore.class_bonus, lore.total} == {class_bonus, total}, label
      end
    end

    # ⚠️ Отрицательный контроль самого замера: третий класс не добавляет ничего,
    # потому что складываются только два названных записью. Без этой проверки
    # «сумма уровней» зеленела бы и у кода, который складывает уровни ВСЕХ
    # классов, — а такой код дал бы на последней строке таблицы выше 20.
    test "рейнджер в сумму не идёт — складываются только названные классы",
         %{ruleset: ruleset} do
      with_ranger = dan_f7(List.duplicate(:bard, 7) ++ [:harper_scout, :ranger, :ranger])

      lore = Skills.value(with_ranger, ruleset, :lore, 10)

      assert lore.class_bonus == 8
      assert lore.class_bonus_from == [:bard, :harper_scout]
      refute :ranger in lore.class_bonus_from
    end

    # ⚠️ Уровень выдачи и состав суммы — РАЗНЫЕ вопросы, и это главное, что
    # вскрыл замер. Шард выдаёт умение Арфисту на 2-м классовом уровне, а
    # персонаж Dan владел фитом с 1-го уровня БАРДА — и его первый уровень
    # Арфиста всё равно дал +1.
    test "первый уровень Арфиста считается, если фит уже есть от барда",
         %{ruleset: ruleset} do
      bard_only = Skills.value(dan_f7(List.duplicate(:bard, 7)), ruleset, :lore, 7)

      with_harper =
        Skills.value(dan_f7(List.duplicate(:bard, 7) ++ [:harper_scout]), ruleset, :lore, 8)

      assert with_harper.class_bonus - bard_only.class_bonus == 1
      assert with_harper.class_bonus_from == [:bard, :harper_scout]
    end

    # ✅ Инвариант правки: у ЧИСТОГО Арфиста числа не изменились ни на единицу —
    # бардовских уровней ноль, фит выдан на 2-м уровне класса, сумма равна
    # уровню Арфиста. Тот единственный случай, ради которого правило когда-то
    # и записывали, был верен всё это время; поэтому дыру никто не замечал.
    test "у чистого Арфиста числа прежние", %{ruleset: ruleset} do
      build = harper(5, %{1 => %{lore: 12}}, int: 14)

      lore = Skills.value(build, ruleset, :lore, 10)

      # 12 рангов + INT +2 + 5 уровней Арфиста
      assert {lore.ranks, lore.ability_modifier, lore.class_bonus, lore.total} == {12, 2, 5, 19}
      assert lore.class_bonus_from == [:harper_scout]
    end

    # 🔴 Регрессия на двойной счёт — самая дорогая ошибка этой правки. Уровни
    # Арфиста считали ДВА механизма: правило `siala_41/skills.json` и запись
    # разметки. Останься оба живыми, Арфист 5 получил бы +10 вместо +5, а число
    # выглядело бы правдоподобно. Шардовая запись помечена `counted_elsewhere`,
    # то есть правил её слой больше не строит.
    test "уровни Арфиста считаются ОДИН раз, а не двумя механизмами",
         %{ruleset: ruleset} do
      assert ruleset.skill_rules.class_level_bonuses == []
      assert Skills.value(harper(5, %{1 => %{lore: 12}}), ruleset, :lore, 10).class_bonus == 5
    end

    test "растёт вместе с классом", %{ruleset: ruleset} do
      assert Skills.value(harper(2, %{1 => %{lore: 12}}), ruleset, :lore, 7).class_bonus == 2
      assert Skills.value(harper(5, %{1 => %{lore: 12}}), ruleset, :lore, 10).class_bonus == 5
    end

    # На Сиале умение выдаётся на 2-м уровне класса — значит у Арфиста 1 фита
    # ещё нет вовсе, и прибавки нет. ⚠️ Это про ВЫДАЧУ: у билда с бардом фит уже
    # есть, и тот же первый уровень Арфиста считается (тест выше).
    test "на первом уровне класса прибавки ещё нет — фит не выдан", %{ruleset: ruleset} do
      assert Skills.value(harper(1, %{1 => %{lore: 12}}), ruleset, :lore, 6).class_bonus == 0
    end

    test "билду без Арфиста и барда не достаётся ничего", %{ruleset: ruleset} do
      build = build_with(:rogue, 10, int: 14, skills: %{1 => %{lore: 12}})

      assert Skills.value(build, ruleset, :lore, 10).class_bonus == 0
    end

    # ⚠️ Вторая половина задачи, и без неё правка была бы вредной: посчитали —
    # значит молчим. CLAUDE.md §6 запрещает продолжать печатать «не можем
    # посчитать» про то, что посчитано.
    #
    # ⚠️ Положительный контроль переписан задачей "навыки: получатели у
    # фактов" (data-miner, 14.08.2026): раньше им было `scroll_crafting_check`
    # — тоже оговорка Lore, — но у него получатель `crafting`, не наш, и после
    # разметки он больше не гэп ни у кого. Значит и то, что Lore не выпал из
    # виду целиком, теперь показывает не второй гэп, а то, что остальные факты
    # Lore по-прежнему в `siala_unapplied` — просто не все `siala_unapplied`
    # факты становятся гэпом.
    test "оговорка про изменение навыка больше не приходит", %{ruleset: ruleset} do
      build = harper(5, %{1 => %{lore: 12}}, int: 14)
      gaps = Rules.compute(build, ruleset).gaps

      refute {:not_modelled, {:skill_change, :lore, "harper_bardic_knowledge_bonus"}} in gaps

      # Положительный контроль: остальные факты Lore никуда не делись —
      # `refute` выше зеленеет не оттого, что весь навык выпал из виду.
      whats = Enum.map(ruleset.skills[:lore].siala_unapplied, & &1["what"])
      assert "scroll_crafting_check" in whats
      refute "harper_bardic_knowledge_bonus" in whats
    end

    # ⚠️ Здесь стояло «оговорка про сам фит достаётся барду, но не Арфисту» —
    # один id фита, два ответа, потому что бардовскую половину не считал никто.
    # Половина оказалась одна, и оговорка ушла у ОБОИХ: CLAUDE.md §6 запрещает
    # печатать «не можем посчитать» про посчитанное так же прямо, как молчать
    # про непосчитанное.
    test "оговорки про фит больше нет ни у барда, ни у Арфиста", %{ruleset: ruleset} do
      harper = Skills.value(harper(5, %{1 => %{lore: 12}}), ruleset, :lore, 10)
      bard = Skills.value(build_with(:bard, 5, skills: %{1 => %{lore: 12}}), ruleset, :lore, 5)

      assert harper.unmodelled_feats == []
      assert bard.unmodelled_feats == []

      # Положительный контроль: у барда прибавка не просто «без оговорки»,
      # а ПОСЧИТАНА — иначе строка зеленела бы и у кода, который молча
      # выбросил бы запись из разметки вовсе.
      assert bard.class_bonus == 5
      assert bard.class_bonus_from == [:bard]
    end

    # ⚠️ Третий маршрут владения — фит С ВЕЩИ. До правки он приносил оговорку;
    # теперь приносит ЧИСЛО, и у воина это ноль — потому что складывать нечего.
    # Ноль здесь посчитанный, а не молчание: «it is hardcoded to the bard and
    # Harper scout class levels» (fandom, Custom content notes) — то есть
    # источник прямо отвечает, что у персонажа без этих классов прибавки нет.
    #
    # Маршрут — `Build.feats_owned/3`, а не `feats_taken/2`: это ЭФФЕКТ фита,
    # а эффекты фитов с вещей считаются (Dan, 09.08.2026). Сужение 14.08.2026
    # (H7) касалось требований других фитов, а не эффектов.
    test "объявленный с вещи фит считается, и у воина это честный ноль",
         %{ruleset: ruleset} do
      %Build{} = base = build_with(:fighter, 6, skills: %{1 => %{lore: 4}})
      worn = geared(base, Gear.new(feats: [:bardic_knowledge]))
      lore = Skills.value(worn, ruleset, :lore, 6)

      assert lore.class_bonus == 0
      assert lore.class_bonus_from == []
      assert lore.unmodelled_feats == []
    end

    # ⚠️ И положительный контроль к тому же маршруту, потому что сам по себе ноль
    # выше зеленел бы и у кода, который фиты с вещей не читает вовсе. Взять его
    # на самом `Bardic knowledge` нельзя, и это свойство умения, а не пробел
    # теста: уровни считаются ровно у тех двух классов, которые фит и выдают, —
    # значит у кого есть что складывать, у того фит уже есть от класса, и вещь
    # ничего не добавляет никогда. Поэтому маршрут проверяется на соседней
    # записи того же файла: `Alertness` с вещи обязан поднимать Spot.
    test "маршрут «фит с вещи» у этой разметки живой — Alertness с вещи считается",
         %{ruleset: ruleset} do
      %Build{} = base = build_with(:rogue, 3, wis: 10, int: 14, skills: %{1 => %{spot: 10}})
      worn = geared(base, Gear.new(feats: [:alertness]))

      assert Skills.value(base, ruleset, :spot, 3).feat_bonus == 0
      assert Skills.value(worn, ruleset, :spot, 3).feat_bonus == 2
    end
  end

  # ============================ прибавки к навыкам с вещей (задача 3.20) ======
  #
  # Запрос Dan 09.08.2026: «чтобы можно было указать „дисциплина +50“, „хайд
  # +50“, „мув +50“ … чтобы в „Итого“ увидеть финальную картинку по скиллам».
  # Ручной ввод итога, как у характеристик, AC и сейвов (CLAUDE.md §6), а не
  # армори.
  #
  # source потолка: siala «Система оружия» revid 20527 — «Одевая любой такой
  # посох, персонаж на 40 уровне получает бонус +12 к спеллкрафту … Этот бонус
  # складывается с остальными бонусами к навыкам, но входит в кап +50». То есть
  # предмет, дающий бонус к навыку, внутри капа +50 по слову источника.
  describe "прибавка к навыку с вещей" do
    test "вписанное число доезжает до значения и стоит своим термом", %{ruleset: ruleset} do
      %Build{} = base = build_with(:fighter, 10, str: 16, skills: %{1 => %{discipline: 4}})
      typed = geared(base, Gear.new(skills: %{discipline: 50}))

      # 4 ранга + STR 16 (+3) = 7 голым, +50 с вещей = 57
      assert Skills.value(base, ruleset, :discipline, 10).total == 7
      value = Skills.value(typed, ruleset, :discipline, 10)

      assert value.total == 57
      assert value.gear_bonus == 50

      # ⚠️ Своим полем, а не внутри чужого: у навыка нет типов прибавки, поэтому
      # раздельная строка — единственная защита от двойного счёта.
      assert value.ranks == 4
      assert value.feat_bonus == 0
    end

    test "ложится только на названный навык", %{ruleset: ruleset} do
      build =
        build_with(:rogue, 10, dex: 14, skills: %{1 => %{hide: 4, move_silently: 4}})
        |> geared(Gear.new(skills: %{hide: 50}))

      values = Skills.values(build, ruleset, 10)

      assert values[:hide].gear_bonus == 50
      assert values[:move_silently].gear_bonus == 0
    end

    # Навык, в который не вложено рангов, но вписано число, — строка законная:
    # ровно ради неё поле и заводилось. А навык, про который билд не сказал
    # ничего, в список не попадает (иначе панель печатала бы все 28).
    test "навык без рангов попадает в values, если игроку есть что сказать", %{ruleset: ruleset} do
      typed = geared(build_with(:fighter, 10, dex: 14), Gear.new(skills: %{hide: 20}))

      assert Map.keys(Skills.values(typed, ruleset, 10)) == [:hide]
      value = Skills.values(typed, ruleset, 10)[:hide]
      assert value.ranks == 0
      assert value.total == 20 + 2

      # положительный контроль: без вписанного числа тот же билд не печатает ничего
      %Build{} = empty = build_with(:fighter, 10, dex: 14)
      assert Skills.values(empty, ruleset, 10) == %{}

      # и вписанный ноль — тоже ничего: «вписал и стёр» это не «вложился»
      zero = geared(empty, Gear.new(skills: %{hide: 0}))
      assert Skills.values(zero, ruleset, 10) == %{}
    end

    # ⚠️ И то, что расовый бонус сам по себе навык в список НЕ приводит: у
    # Человека +12 дисциплины есть на 40-м всегда, и строка появилась бы у
    # каждого билда, где игрок про дисциплину ничего не говорил.
    test "расовый бонус без рангов навык в список не приводит", %{ruleset: ruleset} do
      assert Skills.values(human_40(%Gear{}, 0), ruleset, 40) == %{}

      # положительный контроль: бонус у этого билда ЕСТЬ, просто без рангов ему
      # негде появиться — иначе проверка зеленела бы и на билде без бонуса
      with_rank = human_40(%Gear{}, 1)
      assert Skills.values(with_rank, ruleset, 40)[:discipline].shard_race_bonus == 12
    end
  end

  # 🔴 Главное правило задачи 3.20. Клип ОДИН на пул: расовый бонус шарда
  # (+12 дисциплины у Человека, «Этот бонус входит в кап навыка +50») и вписанное
  # игроком число режутся вместе, а не по половинке. Клип по слагаемому дал бы
  # 69 вместо 57 — та же поломка, которой сейвы однажды несли +40 (CLAUDE.md §9).
  describe "потолок +50 на бонусы к навыку — один на сумму" do
    test "расовый +12 и вписанные +50 срезаются до 50", %{ruleset: ruleset} do
      value = discipline_value(ruleset, Gear.new(skills: %{discipline: 50}))

      # слагаемые остаются сырыми, срез — отдельным полем
      assert value.shard_race_bonus == 12
      assert value.gear_bonus == 50
      assert value.bonus_clipped == -12
      assert value.bonus_capped?

      # 4 ранга + STR +3 + (12 + 50 − 12) = 57
      assert value.total == 57
    end

    test "обратный контроль: +30 с вещей и +12 расовых — среза нет", %{ruleset: ruleset} do
      value = discipline_value(ruleset, Gear.new(skills: %{discipline: 30}))

      assert value.bonus_clipped == 0
      refute value.bonus_capped?
      assert value.total == 4 + 3 + 12 + 30
    end

    # Граница ровно на потолке: `Caps.clamp/3` режет только `value > cap`,
    # и «упёрлось ровно» — не то же самое, что «срезано».
    test "12 + 38 = ровно 50 — потолок не заявляет среза", %{ruleset: ruleset} do
      value = discipline_value(ruleset, Gear.new(skills: %{discipline: 38}))

      assert value.bonus_clipped == 0
      refute value.bonus_capped?
      assert value.total == 4 + 3 + 50
    end

    # ⚠️ ПОРЧА: клип по каждому слагаемому вместо суммы. Названа числом, которое
    # такой клип дал бы, — иначе тест зеленел бы на обеих реализациях: расовый
    # +12 прошёл бы целиком (12 < 50) и вписанные +50 тоже (50 ≤ 50), итого 69.
    test "клип по слагаемому дал бы 69 вместо 57", %{ruleset: ruleset} do
      value = discipline_value(ruleset, Gear.new(skills: %{discipline: 50}))

      refute value.total == 4 + 3 + 12 + 50
      assert value.total == 57
    end

    # У сагровика расовый вариант другой (+18), и в пул идёт именно он.
    test "у сагровика в пуле +18, срез больше", %{ruleset: ruleset} do
      %Build{} = base = human_40(Gear.new(skills: %{discipline: 50}))
      sagra = %Build{base | levels: List.duplicate(:fighter, 40)}

      value = Skills.value(sagra, ruleset, :discipline, 40)

      assert value.shard_race_bonus == 18
      assert value.bonus_clipped == -18
      assert value.total == 57
    end

    # Прибавки фитов, классов и ванильной склонности в пул НЕ входят: ни один
    # источник этого не говорит. Значит они лежат ПОВЕРХ среза, и «+2 от
    # Alertness» на билде, уже стоящем на потолке, — это +2, а не ничто
    # (`Bonuses.clip/3`, 09.08.2026, Dan).
    test "фит лежит поверх среза, а не внутри него", %{ruleset: ruleset} do
      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :skill_bonus, 5)}

      build =
        build_with(:wizard, 10, wis: 10, skills: %{1 => %{spot: 4}})
        |> geared(Gear.new(skills: %{spot: 50}, feats: [:alertness]))

      value = Skills.value(build, ruleset, :spot, 10)
      clipped = Skills.value(build, tight, :spot, 10)

      assert value.feat_bonus == 2
      assert value.total == 4 + 0 + 50 + 2

      # с потолком 5: в пуле остаётся 5, фит по-прежнему +2 сверху
      assert clipped.bonus_clipped == -45
      assert clipped.total == 4 + 0 + 5 + 2
    end
  end

  # 🔴 Потолок ИТОГА, 127 («до максимального значения 127», siala «Скрытность»
  # revid 19465; общим правилом это сделал игрок — Dan 03.08.2026, `source: user`).
  # ПРИМЕНЁН с задачи 3.20; на легальном билде недостижим (максимум 119: Lore на
  # Арфисте — 44 ранга + 16 характеристика + 2 склонность + 50 пул + 2 фиты +
  # 5 Арфист), поэтому проверяется на опущенном потолке — тем же приёмом, каким
  # до этой задачи проверялся +50.
  describe "потолок значения навыка 127" do
    test "итог клипается и говорит, сколько потерял", %{ruleset: ruleset} do
      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :max_skill_value, 30)}
      value = Skills.value(typed_discipline(), tight, :discipline, 10)

      assert value.total == 30
      assert value.value_clipped == -27
      assert value.value_capped?

      # ⚠️ Потолок ИТОГА и потолок ПУЛА — разные вещи и разные поля: пул здесь
      # не тронут вовсе (50 не больше 50), срезан именно итог. Один флаг на два
      # потолка не сказал бы, что именно упёрлось.
      assert value.bonus_clipped == 0
      refute value.bonus_capped?
    end

    test "настоящий потолок 127 недостижим — не режет и не заявляет среза", %{ruleset: ruleset} do
      value = Skills.value(typed_discipline(), ruleset, :discipline, 10)

      assert ruleset.stat_caps.max_skill_value == 127
      assert value.total == 57
      assert value.value_clipped == 0
      refute value.value_capped?
    end

    # ⚠️ ПОРЧА: ранги в потолок итога входят, а в потолок бонусов — нет. Билд, у
    # которого одних рангов больше потолка: клип «только по бонусам» вернул бы 41.
    test "потолок итога считает и ранги", %{ruleset: ruleset} do
      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :max_skill_value, 30)}
      build = build_with(:fighter, 41, str: 10, skills: Map.new(1..41, &{&1, %{discipline: 1}}))
      value = Skills.value(build, tight, :discipline, 41)

      assert value.ranks == 41
      assert value.total == 30
      assert value.value_clipped == -11
    end
  end

  # 🔴 Самое вероятное место незаметной поломки после 3.20: бонус Spellcraft к
  # сейвам считается от КУПЛЕННЫХ РАНГОВ, а не от значения навыка. Dan
  # 09.08.2026: 30 рангов дают +6, значит с вещей до потолка добирается ровно +14.
  describe "прибавка к навыку с вещей и бонус Spellcraft к сейвам" do
    test "вписанные +50 к Spellcraft на сейвы не влияют вообще", %{ruleset: ruleset} do
      plain = spellcraft_wizard(30, %Gear{})
      typed = spellcraft_wizard(30, Gear.new(skills: %{spellcraft: 50}))

      assert Skills.save_bonus(plain, ruleset, 40) == {6, [:spellcraft]}
      assert Skills.save_bonus(typed, ruleset, 40) == {6, [:spellcraft]}

      # положительный контроль: прибавка при этом ДОЕХАЛА до самого навыка,
      # то есть равенство выше зеленеет не потому, что её нигде нет
      assert Skills.value(typed, ruleset, :spellcraft, 40).total == 30 + 50
    end

    test "6 от рангов + 14 с вещей = 20 без флага капа", %{ruleset: ruleset} do
      stats = Rules.compute(spellcraft_wizard(30, Gear.new(saves: 14)), ruleset)

      assert stats.skill_save_bonus == 6
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 20}
      assert stats.capped == []
    end

    test "6 от рангов + 20 с вещей = срез с флагом", %{ruleset: ruleset} do
      stats = Rules.compute(spellcraft_wizard(30, Gear.new(saves: 20)), ruleset)

      assert stats.skill_save_bonus == 6
      assert stats.save_bonus == %{fort: 20, ref: 20, will: 20}
      assert stats.save_cap_clipped == %{fort: -6, ref: -6, will: -6}
      assert Enum.sort(stats.capped) == [:fort_save, :ref_save, :will_save]
    end

    # ⚠️ И то же с прибавкой к навыку сверху: она не добавляет к сейвам ни
    # единицы, то есть флаг капа появляется от вещей, а не от навыка.
    test "прибавка к навыку не создаёт и не снимает срез сейвов", %{ruleset: ruleset} do
      gear = Gear.new(saves: 14, skills: %{spellcraft: 50})
      both = Rules.compute(spellcraft_wizard(30, gear), ruleset)

      assert both.skill_save_bonus == 6
      assert both.capped == []
      assert both.save_bonus == %{fort: 20, ref: 20, will: 20}
    end
  end

  # ========================= штраф брони (задача 3.42) =======================
  #
  # Источник — `fandom:Armor check penalty` (в кэше, снят 16.08.2026), дословно:
  # «An armor check penalty applies to most dexterity-based skills when a
  # character wears armor heavier than leather, and it applies to hide, move
  # silently, parry, pick pocket, set trap, and tumble. The only dexterity-based
  # skills not on this list are open lock and ride, to which neither the maximum
  # dexterity bonus nor the armor check penalty apply. … If a character is
  # wearing armor and using a shield, both armor check penalties apply.»
  #
  # Сиала про штраф не говорит нигде (проверен весь кэш 16.08.2026) — ванильный
  # по общему правилу `CLAUDE.md` §3, источник помечен в данных.
  describe "штраф брони: сколько отнимает надетое" do
    # 🔴 Кейс приёмки. Вор с рангами в Скрытности, латы (−8) и башенный щит
    # (−10): оба штрафа складываются, потому что так сказано на странице.
    test "латы и башенный щит вместе дают −18, и штраф стоит своим термом", %{ruleset: ruleset} do
      value = hide_value(ruleset, %{armor: :full_plate, shield: :tower})

      assert value.armor_penalty == -18

      # ⚠️ И терм не растворён в соседях: ранги и модификатор ловкости стоят
      # ровно те же, что у голого билда, — иначе штраф был бы «учтён» вычитанием
      # из чужого числа, и разбор перестал бы сходиться со своим итогом.
      assert value.ranks == 10
      assert value.ability_modifier == 2
      assert value.gear_bonus == 0
      assert value.total == 10 + 2 - 18
    end

    # Табличный кейс: все двенадцать строк источника, по одной. Проверяется
    # у ЯДРА через значение навыка, а не чтением JSON: смысл в том, что число
    # доезжает до расчёта.
    test "двенадцать строк таблицы, каждая своим числом", %{ruleset: ruleset} do
      armor = [
        {:none, 0},
        {:padded, 0},
        {:leather, 0},
        {:studded_leather, -1},
        {:chain_shirt, -2},
        {:chainmail, -5},
        {:splint_mail, -7},
        {:half_plate, -7},
        {:full_plate, -8}
      ]

      shields = [{:small, -1}, {:large, -2}, {:tower, -10}]

      for {item, penalty} <- armor do
        assert hide_value(ruleset, %{armor: item}).armor_penalty == penalty,
               "#{item}: ожидали штраф #{penalty}"
      end

      for {item, penalty} <- shields do
        assert hide_value(ruleset, %{shield: item}).armor_penalty == penalty,
               "щит #{item}: ожидали штраф #{penalty}"
      end
    end

    # 🔴 Кейс приёмки «нет штрафа»: кожаный доспех и никакого щита. Строка
    # источника прямо говорит «none», а не число, и первые три строки таблицы
    # (без доспеха / стёганый / кожаный) обязаны вести себя одинаково.
    test "кожаный доспех без щита не отнимает ничего", %{ruleset: ruleset} do
      value = hide_value(ruleset, %{armor: :leather})

      assert value.armor_penalty == 0
      assert value.total == 10 + 2
    end

    # ⚠️ Одна половина без другой ничего не доказывает: щит без доспеха
    # штрафует, и доспех без щита штрафует. Обе стороны сложения — под тестом,
    # иначе реализация «берём только доспех» зеленела бы на кейсе приёмки.
    test "каждое надетое штрафует по отдельности, и вместе они складываются", %{ruleset: ruleset} do
      assert hide_value(ruleset, %{armor: :full_plate}).armor_penalty == -8
      assert hide_value(ruleset, %{shield: :tower}).armor_penalty == -10
      assert hide_value(ruleset, %{armor: :full_plate, shield: :tower}).armor_penalty == -18
    end

    # Пол не назван ни одним источником, поэтому его нет и в модели: значение
    # уходит в минус, а `max(0, …)` был бы выдуманным игровым числом (§3).
    test "значение навыка уходит в минус, и мы его не подпираем", %{ruleset: ruleset} do
      value = hide_value(ruleset, %{armor: :full_plate, shield: :tower}, 1)

      assert value.ranks == 1
      assert value.total == 1 + 2 - 18
    end
  end

  describe "штраф брони: кому он достаётся" do
    # 🔴 Кейс приёмки. Шесть названных страницей навыков получают штраф, а
    # `open_lock` и `ride` — нет, и это сказано отдельным предложением
    # источника, а не выведено из «они не про ловкость».
    test "шесть названных навыков штрафуются, Открытый замок и Верховая езда — нет", %{
      ruleset: ruleset
    } do
      values = penalised_rogue_values(ruleset)

      for skill <- [:hide, :move_silently, :parry, :pick_pocket, :set_trap, :tumble] do
        assert values[skill].armor_penalty == -18, "#{skill}: штраф не доехал"
      end

      for skill <- [:open_lock, :ride] do
        assert values[skill].armor_penalty == 0, "#{skill}: штраф достался навыку из исключений"
      end
    end

    # ⚠️ И навык не про ловкость вовсе — третий случай рядом с двумя выше:
    # исключение из списка и «в списке никогда и не был» это разные утверждения
    # источника, но одно и то же число.
    test "навык не из списка штрафа не получает", %{ruleset: ruleset} do
      assert penalised_rogue_values(ruleset)[:discipline].armor_penalty == 0
    end

    # Список — из данных, а не из кода: ни одного имени навыка в `rules/` нет.
    # Проверка тому, что ruleset несёт ровно шесть и ровно тех.
    test "ruleset называет ровно шесть подверженных навыков", %{ruleset: ruleset} do
      penalised =
        for {id, %{armor_check_penalty: :applies}} <- ruleset.skills, do: id

      assert Enum.sort(penalised) == [
               :hide,
               :move_silently,
               :parry,
               :pick_pocket,
               :set_trap,
               :tumble
             ]
    end
  end

  # 🔴 Здесь стоял кейс приёмки «про Alchemy не высказался никто, значит штраф
  # НЕИЗВЕСТЕН, а не равен нулю». **Закрыто замером Dan 17.08.2026 (кейс P1):
  # «Штрафа нет»** — то есть ноль, но названный источником, а не подставленный
  # нами. Сам механизм трёх ответов не отменён и проверяется на синтетическом
  # ruleset'е выше («навык, про который источник не высказался»); здесь остаётся
  # третий ответ в его нынешнем виде — ЧИСЛО, и число нулевое при любом надетом.
  describe "штраф брони: навык шарда, у которого ответ есть" do
    test "Alchemy в латах считается, и доспех у неё не отнимает ничего", %{ruleset: ruleset} do
      value = alchemy_value(ruleset, %{armor: :full_plate, shield: :tower})

      assert ruleset.skills[:alchemy].armor_check_penalty == :none
      assert value.armor_penalty == 0
      assert value.gaps == []

      # 4 ранга + мудрость 14 (+2) — и ни доспех, ни щит числа не трогают.
      assert value.total == 4 + 2
    end

    # ⚠️ Половина, без которой первая ничего не доказывает: «не отнимает» —
    # это утверждение про ЭТОТ навык, а не выключенный на билде штраф. У
    # подверженного навыка того же персонажа он на месте.
    test "у подверженного навыка того же билда штраф на месте", %{ruleset: ruleset} do
      build = alchemy_build(%{armor: :full_plate, shield: :tower})

      assert Skills.value(build, ruleset, :alchemy, 10).armor_penalty == 0
      assert Skills.value(build, ruleset, :hide, 10).armor_penalty == -18
    end
  end

  # ⚠️ ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ ко всей задаче: штраф падает на ЗНАЧЕНИЕ навыка и
  # не имеет права тронуть ни один из трёх соседних механизмов. Каждый из них
  # легко задеть, и ни один не сообщил бы об этом сам.
  describe "штраф брони не трогает соседей" do
    test "цена ранга, потолок рангов и классовость не двигаются", %{ruleset: ruleset} do
      bare = penalised_rogue(%{})
      plated = penalised_rogue(%{armor: :full_plate, shield: :tower})

      for skill <- [:hide, :tumble, :discipline] do
        assert Skills.rank_cost(plated, ruleset, skill, 10) ==
                 Skills.rank_cost(bare, ruleset, skill, 10)

        assert Skills.rank_cap(plated, ruleset, skill, 10) ==
                 Skills.rank_cap(bare, ruleset, skill, 10)

        assert Skills.class_skill_at?(plated, ruleset, skill, 10) ==
                 Skills.class_skill_at?(bare, ruleset, skill, 10)
      end

      assert Skills.budget(plated, ruleset, 10) == Skills.budget(bare, ruleset, 10)
    end

    # 🔴 Потолок бонусов +50 — не про штраф: он односторонний и стоит на пуле
    # бонусов. Билд, у которого пул уже упёрся, обязан получить ровно тот же
    # срез и с доспехом, и без.
    test "потолок +50 на бонусы не шелохнулся", %{ruleset: ruleset} do
      gear = fn worn -> Gear.new(skills: %{discipline: 50, hide: 50}, worn: worn) end

      bare = discipline_value(ruleset, gear.(%{}))
      plated = discipline_value(ruleset, gear.(%{armor: :full_plate, shield: :tower}))

      assert bare.bonus_clipped == plated.bonus_clipped
      assert bare.bonus_capped? == plated.bonus_capped?
      assert bare.total == plated.total

      # Положительный контроль: срез вообще есть, то есть равенство выше
      # проверяет работающий потолок, а не два нуля.
      assert bare.bonus_capped?
      assert bare.bonus_clipped < 0
    end

    # ...а вот у самой Скрытности того же билда штраф ЕСТЬ и вычитается ПОСЛЕ
    # клипа пула: пул это бонусы, штраф в него не входит.
    test "у подверженного навыка того же билда штраф вычитается поверх клипа", %{
      ruleset: ruleset
    } do
      gear = Gear.new(skills: %{hide: 50}, worn: %{armor: :full_plate, shield: :tower})
      value = Skills.value(human_40(gear), ruleset, :hide, 40)

      assert value.gear_bonus == 50
      assert value.bonus_clipped == 0
      assert value.armor_penalty == -18
      assert value.total == 50 - 18
    end

    # Прибавка Spellcraft к сейвам считается от РАНГОВ, а не от значения, — то
    # есть штраф до сейвов не доезжает даже теоретически. Проверено на навыке,
    # который штраф не получает, и на билде, который его получает.
    test "сейвы от штрафа не двигаются", %{ruleset: ruleset} do
      bare = Rules.compute(spellcraft_wizard(30, Gear.new()), ruleset)

      plated =
        Rules.compute(
          spellcraft_wizard(30, Gear.new(worn: %{armor: :full_plate, shield: :tower})),
          ruleset
        )

      assert plated.skill_save_bonus == bare.skill_save_bonus
      assert plated.save_bonus == bare.save_bonus
    end
  end

  # Штраф не зависит ни от уровня, ни от состава классов — утверждение
  # очевидное ровно настолько, чтобы его сломать незаметно: правило монаха про
  # надетое лежит рядом и устроено именно так.
  describe "штраф брони на границах" do
    test "одинаков на 1, 20, 21 и 41 уровне", %{ruleset: ruleset} do
      for level <- [1, 20, 21, 41] do
        build =
          Build.new(
            levels: List.duplicate(:rogue, level),
            base_abilities: abilities(dex: 14),
            skills: %{1 => %{hide: 1}},
            gear: Gear.new(worn: %{armor: :full_plate, shield: :tower})
          )

        assert Skills.value(build, ruleset, :hide, level).armor_penalty == -18,
               "уровень #{level}: штраф поехал"
      end
    end

    # Билд из четырёх классов — лимит Сиалы, и единственная форма билда со своим
    # правилом по составу (штраф к скрытности за непрофильные уровни). Два
    # штрафа на одном навыке обязаны стоять РАЗНЫМИ термами: один про состав
    # билда, другой про надетое.
    test "у билда из четырёх классов штраф брони и штраф состава — разные термы", %{
      ruleset: ruleset
    } do
      levels =
        List.duplicate(:rogue, 20) ++
          List.duplicate(:shadowdancer, 10) ++
          List.duplicate(:fighter, 6) ++ List.duplicate(:wizard, 5)

      build =
        Build.new(
          race: :human,
          levels: levels,
          base_abilities: abilities(dex: 10),
          skills: %{1 => %{hide: 20}},
          gear: Gear.new(worn: %{armor: :full_plate, shield: :tower})
        )

      value = Skills.value(build, ruleset, :hide, 41)

      assert value.shard_modifier == -11
      assert value.armor_penalty == -18
      assert value.total == 20 - 11 - 18
    end
  end

  # Вор 10-го уровня с DEX 14 (+2) и `ranks` рангами в шести подверженных
  # навыках и двух исключённых. Ранги розданы по одному на уровень, чтобы
  # потолок уровня не мешал.
  defp penalised_rogue(worn, ranks \\ 10) do
    skills =
      for level <- 1..ranks,
          into: %{},
          do:
            {level,
             %{
               hide: 1,
               move_silently: 1,
               parry: 1,
               pick_pocket: 1,
               set_trap: 1,
               tumble: 1,
               open_lock: 1,
               ride: 1,
               discipline: 1
             }}

    Build.new(
      levels: List.duplicate(:rogue, 10),
      base_abilities: abilities(dex: 14),
      skills: skills,
      gear: Gear.new(worn: worn)
    )
  end

  defp penalised_rogue_values(ruleset) do
    Skills.values(penalised_rogue(%{armor: :full_plate, shield: :tower}), ruleset, 10)
  end

  defp hide_value(ruleset, worn, ranks \\ 10) do
    Skills.value(penalised_rogue(worn, ranks), ruleset, :hide, 10)
  end

  # Арфист-скаут: единственный класс, у которого Alchemy классовая. ⚠️ WIS 14
  # не для красоты — с 17.08.2026 у навыка есть ключевая характеристика (замер
  # Dan, кейс P1), и с десяткой во всех статах модификатор был бы нулём, то есть
  # кейсы про значение зеленели бы и у реализации, которая характеристику
  # потеряла.
  defp alchemy_build(worn) do
    Build.new(
      levels: List.duplicate(:rogue, 5) ++ List.duplicate(:harper_scout, 5),
      base_abilities: abilities(wis: 14),
      skills: %{1 => %{alchemy: 4}},
      gear: Gear.new(worn: worn)
    )
  end

  defp alchemy_value(ruleset, worn) do
    Skills.value(alchemy_build(worn), ruleset, :alchemy, 10)
  end

  # Полная копия `priv/rules`, у которой ОДНОМУ навыку снято одно поле. Ни
  # одного утверждения про игру здесь нет: испорчена копия, а не снапшот, —
  # и это единственный способ проверить отказ теперь, когда в живых данных
  # свидетеля не осталось (см. describe «навык, про который источник
  # не высказался»).
  #
  # ⚠️ Правится ВАНИЛЬНЫЙ файл, хотя грузится `siala_41`: слой шарда ложится
  # поверх ванильного, и снятое поле не всплывает обратно. Заодно это
  # доказывает, что маршрут «данные → загрузчик → ядро» жив целиком, а не
  # только последнее звено.
  defp ruleset_without_skill_field(field) do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join([root, "vanilla", "skills.json"])

    patched =
      for skill <- path |> File.read!() |> Jason.decode!() do
        if skill["id"] == "discipline", do: Map.delete(skill, field), else: skill
      end

    File.write!(path, Jason.encode!(patched))

    BuildCalculator.Data.Loader.load!(root)["siala_41"]
  end

  # Человек-несагровик 40-го уровня: расовый бонус базовый, +12. Один уровень
  # барда — ровно чтобы билд не был «Воином Сагры» (у того вариант +18).
  # ⚠️ Оружие домешивается в переданный `gear`, а не заменяет его: с 15.08.2026
  # расовый бонус Сиалы включается оружием в руках (замер Dan, `GAME_CHECKS.md`
  # Q1/Q4), и без меча `shard_race_bonus` был бы нулём — то есть все кейсы про
  # кап +50 проверяли бы клип ОДНОГО слагаемого вместо двух и зеленели бы
  # на любой реализации.
  defp human_40(%Gear{} = gear, ranks \\ 4) do
    Build.new(
      race: :human,
      levels: List.duplicate(:fighter, 39) ++ [:bard],
      base_abilities: %{str: 16, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
      skills: %{1 => %{discipline: ranks}},
      gear: %Gear{gear | weapon: :longsword, feats: [:siala_blade_proficiency | gear.feats]}
    )
  end

  defp discipline_value(ruleset, gear), do: Skills.value(human_40(gear), ruleset, :discipline, 40)

  # Тот же ввод без расового бонуса: 10 уровней, то есть ниже уровня, для
  # которого числа расового бонуса вообще названы.
  defp typed_discipline do
    build_with(:fighter, 10, str: 16, skills: %{1 => %{discipline: 4}})
    |> geared(Gear.new(skills: %{discipline: 50}))
  end

  defp geared(%Build{} = build, %Gear{} = gear), do: %Build{build | gear: gear}

  defp spellcraft_wizard(ranks, gear) do
    Build.new(
      race: :human,
      levels: List.duplicate(:wizard, 40),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
      skills: %{40 => %{spellcraft: ranks}},
      gear: gear
    )
  end

  # Персонаж замера F7 (Dan, 16.08.2026): Знание 9 рангов, INT 12 (мод +1),
  # ранги куплены на 1-м уровне — Lore классовый и у барда, и у Арфиста, так
  # что цена и потолок в этом кейсе ни при чём.
  defp dan_f7(levels) do
    Build.new(
      levels: levels,
      base_abilities: abilities(int: 12),
      skills: %{1 => %{lore: 9}}
    )
  end

  # Пять уровней вора, потом `levels` уровней Арфиста-скаута: у престижа есть
  # требования, и билд из одного только Арфиста был бы формой, которой в игре
  # не бывает.
  defp harper(levels, skills, opts \\ []) do
    Build.new(
      levels: List.duplicate(:rogue, 5) ++ List.duplicate(:harper_scout, levels),
      base_abilities: abilities(opts),
      skills: skills
    )
  end

  # Дословный билд Дана: соркерер 1–39, воин 40-м, `ranks` рангов Spellcraft
  # залиты по одному на уровнях соркерера — каждый под потолком своего уровня.
  defp sorcerer_then_fighter(ranks) do
    Build.new(
      levels: List.duplicate(:sorcerer, 39) ++ [:fighter],
      base_abilities: abilities(int: 14, cha: 16),
      skills: Map.new(1..ranks, &{&1, %{spellcraft: 1}})
    )
  end

  # Он же наоборот: воин первым уровнем, дальше соркерер. Ранги ложатся на
  # уровни соркерера (2..ranks+1), чтобы цена и потолок были классовыми.
  defp fighter_then_sorcerer(ranks) do
    Build.new(
      levels: [:fighter] ++ List.duplicate(:sorcerer, 39),
      base_abilities: abilities(int: 14, cha: 16),
      skills: Map.new(2..(ranks + 1), &{&1, %{spellcraft: 1}})
    )
  end

  # Обвинения по потолку рангов, отфильтрованные из общего списка гэпов: билд из
  # переписанных шардом классов везёт и другие, и они здесь ни при чём.
  defp accusations(build, ruleset) do
    build
    |> Rules.compute(ruleset)
    |> Map.fetch!(:gaps)
    |> Enum.filter(&match?({:skill_over_cap, _, _, _, _}, &1))
  end

  @ability_keys [:str, :dex, :con, :int, :wis, :cha]

  # Слагаемые строки навыка, названные по отдельности: тест, сравнивающий один
  # `total`, зеленеет и когда прибавка приехала не из того источника.
  defp value_parts(build, ruleset, skill) do
    value = Skills.value(build, ruleset, skill, Build.character_level(build))

    %{ranks: value.ranks, race: value.race_bonus, feat: value.feat_bonus, total: value.total}
  end

  # `build_with(:rogue, 5, int: 14, skills: %{...})` — ability keys go into the
  # ability map, anything else straight onto the build.
  defp build_with(class, levels, opts) do
    {scores, fields} = Enum.split_with(opts, fn {key, _} -> key in @ability_keys end)

    Build.new(
      [levels: List.duplicate(class, levels), base_abilities: abilities(scores)] ++ fields
    )
  end

  defp abilities(opts) do
    Map.merge(%{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}, Map.new(opts))
  end

  # Человек-вор с базовым INT 14 и надетым интеллектом на `bonus`. Раса названа
  # ради лишнего очка за уровень: с ним «40 и 68» отличаются не только
  # модификатором, а `+12` — потолок вещей на характеристику, то есть самый
  # крупный сдвиг, который вообще можно ввести.
  defp rogue_with_gear_int(bonus) do
    Build.new(
      race: :human,
      levels: List.duplicate(:rogue, 10),
      base_abilities: abilities(int: 14),
      gear: %Gear{abilities: if(bonus == 0, do: %{}, else: %{int: bonus})}
    )
  end

  # Копия `priv/rules`, у которой снята ОДНА запись подтверждённых констант.
  # Тот же приём и та же причина, что у `ruleset_without_skill_field/1` ниже:
  # испорчена копия, а не снапшот, — и это единственный способ увидеть
  # умолчание теперь, когда в живых данных правило названо.
  defp ruleset_without_gear_intelligence do
    root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join([root, "siala_41", "overrides.json"])
    overrides = path |> File.read!() |> Jason.decode!()

    patched =
      update_in(overrides, ["_vanilla_constants_confirmed"], fn section ->
        Map.delete(section, "skill_points_gear_intelligence")
      end)

    File.write!(path, Jason.encode!(patched))

    BuildCalculator.Data.Loader.load!(root)["siala_41"]
  end
end
