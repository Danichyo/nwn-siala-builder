defmodule BuildCalculator.Rules.AbilityBonusesTest do
  @moduledoc """
  Прибавки к характеристикам от фитов и классовых таблиц — задача 3.1.

  До неё ядро собирало характеристику из четырёх слоёв (поинт-бай, раса,
  прибавки уровней, вещи), и две разные дыры вели себя по-разному: воин 41
  с `Great strength` ×3 показывал силу 16 и **говорил** об этом
  (`{:not_modelled, {:feat_bonus, :great_strength}}` — фит повторяемый), а
  Ученик красного дракона на 10 уровнях класса показывал ту же 16 и молчал
  вовсе, хотя его таблица даёт +8.

  Источники, по которым здесь считаются ожидания:

    * `fandom:Great strength` (revid 51385) и пять сестёр — «+1 to their
      strength. This may be taken multiple times, to a maximum bonus of +10»;
    * `fandom:Dragon abilities` (revid 70475) — таблица уровней РДД: 2 → +2
      STR, 4 → +2 STR, 7 → +2 CON, 9 → +2 INT, 10 → +4 STR и +2 CHA. Она же
      колонкой «Ability increases» в `fandom:Red dragon disciple` (revid
      71919), число в число;
    * `fandom:Ability score` (revid 71148) — что фиты дают **base score**, что
      кап +12 стоит на «magical means», и что предельная сила персонажа 57
      против 40 «without bonuses from feats and race»;
    * `fandom:Red dragon disciple` (revid 71919) — «the constitution increase
      at level 7 can also provide a significant increase to hit points, **+1
      per total character level**»;
    * `fandom:Dragon abilities` (revid 70475), примечания — «The increase to
      Intelligence ''does'' apply increased skill point gain for the 9th level
      of Red Dragon Disciple, which if taken as soon as possible (14th
      Character Level) results in **27 extra skill points** as of character
      level 40».
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, AbilityBonuses, Build, Gear, Skills, Spells}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(levels, fields \\ []) do
    Build.new([levels: levels, base_abilities: @flat, race: :human] ++ fields)
  end

  # Взятия эпического фита, по одному на уровень начиная с 21-го (раньше
  # нельзя — «21st level» стоит в требовании всего семейства).
  #
  # ⚠️ Уровни идут подряд, а не по эпическим общим слотам (21, 24, 27 …),
  # и это осознанно: слотов таких на 41 уровень всего семь, а здесь нужно
  # проверить потолок ЭФФЕКТА, до которого их не хватает. Легальность
  # раскладки по слотам — вопрос `Rules.FeatSlots`, у неё свои тесты; ядро
  # характеристик считает то, что в билде записано.
  #
  # ⚠️ Слот на каждом уровне — голый `:general`: это единственный объявленный
  # id общего слота (`t:Build.slot_id/0`), эпичность лежит в `kind` слота
  # у `FeatSlots`, а не в самом id (`FeatSlots.general_slot/4` всегда пишет
  # `id: :general`, что эпик, что нет). Индекс для различения слотов не нужен —
  # уникальность даёт сам уровень, а не то, что лежит внутри его карты: до
  # 11.08.2026 здесь стояла выдуманная форма `{:general, index}`, которую
  # `Ids.slot_key/1` не умеет закодировать (AGENT_QUEUE.md §7).
  defp epic_takes(feat, count) do
    for level <- 21..(20 + count)//1, into: %{}, do: {level, %{general: feat}}
  end

  defp own(build, ruleset, ability) do
    build |> Abilities.breakdown(ruleset) |> Map.fetch!(ability) |> Map.fetch!(:own_bonus)
  end

  describe "семейство Great * — задача 3.1, главный кейс" do
    # 🔴 Обязательная проверка задания: десять взятий дают +10 к силе, +5 к
    # бонусу атаки, и общая оговорка про непосчитанную прибавку уходит.
    test "Great strength ×10 поднимает силу на 10, атаку на 5 и снимает оговорку", %{
      ruleset: ruleset
    } do
      levels = List.duplicate(:fighter, 41)
      plain = Rules.compute(build(levels, base_abilities: %{@flat | str: 16}), ruleset)

      ten =
        Rules.compute(
          build(levels,
            base_abilities: %{@flat | str: 16},
            feats: epic_takes(:great_strength, 10)
          ),
          ruleset
        )

      assert plain.abilities.str == 16
      assert ten.abilities.str == 26
      assert ten.attack_bonus == plain.attack_bonus + 5

      # Оговорка «прибавку от фита в статы не считаем» спорила бы с числом,
      # которое игрок видит в разборе, — и потому снимается.
      refute {:not_modelled, {:feat_bonus, :great_strength}} in ten.gaps

      # ⚠️ Положительный контроль: механизм оговорок жив.
      #
      # ⚠️ **ЧЕТВЁРТАЯ замена подряд, и каждая по своей причине.** Сперва стоял
      # `Epic weapon focus` — задача 3.5 (часть B) научила ядро считать его
      # прибавку к атаке. Потом `Epic weapon specialization`, и его снесла
      # задача 3.93: его эффект — УРОН, которого калькулятор не считает вовсе.
      # Потом `Favored enemy`, и его снесла задача 3.95: прибавка падает в наше
      # число, но узка по условию, а описание фита говорит об этом лучше нас.
      #
      # 🔴 После третьей замены живого носителя не осталось НИ ОДНОГО: у всех
      # восемнадцати повторяемых фитов оговорка снята — у шестнадцати меткой
      # получателя, у двух решением владельца. Поэтому контроль перевёрнут:
      # у ruleset'а отбирается решение по ОДНОМУ фиту, и оговорка обязана
      # вернуться. Пустым он стать не может — первая строка требует, чтобы
      # запись, которую снимают, действительно была.
      assert Map.has_key?(ruleset.feat_effect_receivers, :favored_enemy)

      talkative = Map.update!(ruleset, :feat_effect_receivers, &Map.delete(&1, :favored_enemy))

      hunter = build(levels, feats: epic_takes(:favored_enemy, 1))

      assert {:not_modelled, {:feat_bonus, :favored_enemy}} in Rules.compute(hunter, talkative).gaps

      refute {:not_modelled, {:feat_bonus, :favored_enemy}} in Rules.compute(hunter, ruleset).gaps
    end

    # ⚠️ Потолок стоит на ЭФФЕКТЕ («to a maximum of +10»), а не на числе
    # взятий, поэтому применяется к сумме: одиннадцатое взятие не даёт
    # одиннадцатой единицы. Рядом — положительный контроль на десятом, иначе
    # тест зеленел бы и при полностью сломанном подсчёте.
    test "одиннадцатое взятие упирается в потолок +10", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)

      ten = build(levels, feats: epic_takes(:great_strength, 10))
      eleven = build(levels, feats: epic_takes(:great_strength, 11))

      assert own(ten, ruleset, :str) == 10
      assert own(eleven, ruleset, :str) == 10

      # …и упор назван, а не молчит: разбор помечает терм как упёршийся.
      [term] = AbilityBonuses.terms(eleven, ruleset, 41)
      assert term.takes == 11
      assert term.capped?

      [under] = AbilityBonuses.terms(ten, ruleset, 41)
      refute under.capped?
    end

    # Все шесть — одной таблицей: имя фита, характеристика, и то, что соседние
    # характеристики не двигаются (перепутанный ключ выглядел бы правильно на
    # тесте по одной строке).
    for {feat, ability} <- [
          great_strength: :str,
          great_dexterity: :dex,
          great_constitution: :con,
          great_intelligence: :int,
          great_wisdom: :wis,
          great_charisma: :cha
        ] do
      test "#{feat} поднимает #{ability} и ничего больше", %{ruleset: ruleset} do
        feat = unquote(feat)
        ability = unquote(ability)

        stats =
          Rules.compute(
            build(List.duplicate(:fighter, 41), feats: epic_takes(feat, 3)),
            ruleset
          )

        assert Map.fetch!(stats.abilities, ability) == 13

        for other <- Abilities.keys(), other != ability do
          assert Map.fetch!(stats.abilities, other) == 10, "#{feat} задел #{other}"
        end
      end
    end
  end

  describe "таблица Ученика красного дракона" do
    # 🔴 Обязательная проверка задания. Итог на потолке класса — +8 STR, +2
    # CON, +2 INT, +2 CHA (fandom:Dragon abilities revid 70475).
    test "десять уровней класса дают ровно то, что напечатано в таблице", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, 10)),
          ruleset
        )

      assert stats.abilities == %{str: 18, dex: 10, con: 12, int: 12, wis: 10, cha: 12}
    end

    # ⚠️ Ступени СУММИРУЮТСЯ, а не заменяют друг друга: «+2 к силе» стоит и на
    # 2-м уровне класса, и на 4-м. Прочтение «итог на ступени» (как у AC
    # рядом) дало бы здесь +2 вместо +4 — поэтому проверяется вся лесенка,
    # а не одно число.
    test "по уровням класса: 1 → 0, 2 → +2, 4 → +4, 7 → +4 и +2 CON", %{ruleset: ruleset} do
      table = [{1, 0, 0}, {2, 2, 0}, {3, 2, 0}, {4, 4, 0}, {6, 4, 0}, {7, 4, 2}, {9, 4, 2}]

      for {class_levels, str, con} <- table do
        levels =
          List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, class_levels)

        stats = Rules.compute(build(levels), ruleset)

        assert stats.abilities.str == 10 + str, "РДД #{class_levels}: сила"
        assert stats.abilities.con == 10 + con, "РДД #{class_levels}: телосложение"
      end
    end

    # ⚠️ Здесь стояло «hp остаётся nil, а характеристики считаются» — растущий
    # хит-дайс не был выражен схемой, и HP всего билда приходило `nil`. Задача
    # 3.37 это закрыла, и кейс переехал на СОСЕДНЕЕ утверждение той же пары:
    # прибавка к телосложению из этой же таблицы обязана доехать до HP.
    # Проверка сильнее прежней — она ловит и «HP не считается», и «считается,
    # но без +2 CON».
    test "прибавка к телосложению из таблицы доезжает до HP", %{ruleset: ruleset} do
      levels = List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, 10)
      stats = Rules.compute(build(levels), ruleset)

      # Колдун 5 × d4 = 20, РДД 10 = 6+6+6+8+8+10+10+10+10+10 = 84,
      # телосложение 12 (+2 на 7-м уровне класса) → мод +1 × 15 = 15,
      # «Дух Сиалы» +20. Ни колдун, ни РДД Toughness не выдают.
      assert stats.abilities.con == 12
      assert stats.hp == 20 + 84 + 15 + 20
      assert stats.abilities.str == 18
    end

    # Гейт — владение фитом, величина — уровни класса, и эти два факта
    # проверяются порознь: фит выдаётся на 2-м уровне класса, значит на первом
    # прибавки нет ни по одной из двух причин.
    test "один уровень класса не даёт ничего", %{ruleset: ruleset} do
      stats = Rules.compute(build([:sorcerer, :sorcerer, :red_dragon_disciple]), ruleset)
      assert stats.abilities.str == 10
      assert AbilityBonuses.terms(build([:sorcerer, :red_dragon_disciple]), ruleset, 2) == []
    end

    # Колонка таблицы класса записана в данных вторым, независимым источником
    # (вердикт `counted_elsewhere`) — и не считается вторично.
    test "колонка таблицы класса не задваивает прибавку фита", %{ruleset: ruleset} do
      levels = List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, 10)

      terms = AbilityBonuses.terms(build(levels), ruleset, 15)
      assert Enum.map(terms, & &1.source) |> Enum.uniq() == [{:feat, :dragon_abilities}]
      assert Enum.map(terms, &{&1.ability, &1.bonus}) == [cha: 2, con: 2, int: 2, str: 8]
    end
  end

  describe "каскад в производные — самое ценное и самое опасное" do
    # 🔴 Обязательная проверка задания. +2 CON это +1 к модификатору, то есть
    # +1 HP на КАЖДОМ уровне: 41 хит на капе Сиалы. Источник говорит это про
    # ту же механику прямым текстом — «+1 per total character level».
    test "Great constitution ×2 добавляет по хиту на каждый уровень", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)
      plain = Rules.compute(build(levels), ruleset)
      raised = Rules.compute(build(levels, feats: epic_takes(:great_constitution, 2)), ruleset)

      assert raised.abilities.con == 12
      assert raised.hp == plain.hp + 41

      # …и слагаемое видно в разборе, а не растворено в итоге: ядро отдаёт
      # его отдельным термом с именем источника и числом взятий (подпись
      # рисует веб — `Summary.ability_summary/2`, под тестом там же).
      row = Abilities.breakdown(build(levels, feats: epic_takes(:great_constitution, 2)), ruleset)
      assert [%{id: :great_constitution, bonus: 2, takes: 2}] = row.con.own_terms
    end

    # То же для РДД: +2 CON на 7-м уровне класса — это ретроактивные хиты за
    # весь билд. ⚠️ Здесь их не видно (у РДД нет хит-дайса), поэтому кейс
    # проверяется через модификатор и спасбросок стойкости, которые считаются.
    test "+2 CON от РДД доезжают до спасброска стойкости", %{ruleset: ruleset} do
      short = List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, 6)
      long = List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, 7)

      before = Rules.compute(build(short), ruleset)
      after_seventh = Rules.compute(build(long), ruleset)

      assert before.ability_modifiers.con == 0
      assert after_seventh.ability_modifiers.con == 1

      # ⚠️ Весь прирост — от телосложения: по таблице класса база стойкости
      # на 6-м и 7-м уровнях РДД одна и та же (+5), так что сам уровень
      # не даёт ничего и не смазывает проверку.
      assert after_seventh.base_fort == before.base_fort
      assert after_seventh.fort == before.fort + 1
    end

    # DEX → AC и рефлексы, и обе половины проверяются на одном билде: одна
    # могла бы сойтись при сломанной другой.
    test "Great dexterity доезжает до AC и до рефлексов", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)
      plain = Rules.compute(build(levels), ruleset)
      raised = Rules.compute(build(levels, feats: epic_takes(:great_dexterity, 4)), ruleset)

      assert raised.ac_naked == plain.ac_naked + 2
      assert raised.ac_geared == plain.ac_geared + 2
      assert raised.ref == plain.ref + 2
    end

    # WIS → круг заклинаний. Клирик с мудростью 10 не кастует выше нулевого
    # круга (10 + круг), а два взятия `Great wisdom` открывают первый.
    test "Great wisdom открывает клирику круг заклинаний", %{ruleset: ruleset} do
      levels = List.duplicate(:cleric, 41)
      plain = Rules.compute(build(levels), ruleset)
      raised = Rules.compute(build(levels, feats: epic_takes(:great_wisdom, 4)), ruleset)

      assert plain.abilities.wis == 10
      assert raised.abilities.wis == 14

      # «10 + круг» — правило из данных, поэтому круг здесь считается по нему,
      # а не по таблице слотов: слоты у клирика 41 есть до девятого круга
      # независимо от мудрости, и сравнивать надо ровно ту половину правила,
      # на которую характеристика влияет.
      assert castable_circle(plain, ruleset) == 0
      assert castable_circle(raised, ruleset) == 4
    end
  end

  describe "уровень взятия: прибавка не пересчитывает прошлое" do
    # 🔴 Табличный кейс прямо из источника: девятый уровень РДД, взятый как
    # можно раньше (14-й уровень персонажа), даёт **27** лишних скилл-поинтов
    # к 40-му. 27 = 40 − 14 + 1, то есть по очку за каждый уровень начиная
    # с того, где прибавка получена, и ни одного за прошлые.
    #
    # ⚠️ Ожидание опирается на источник, а не на «в NWN, кажется, так» — но
    # замер `GAME_CHECKS.md` E4 остаётся: источник говорит про `dragon
    # abilities`, а не про `Great intelligence`.
    test "27 лишних скилл-поинтов у РДД, ровно как пишет источник", %{ruleset: ruleset} do
      levels =
        List.duplicate(:sorcerer, 5) ++
          List.duplicate(:red_dragon_disciple, 10) ++ List.duplicate(:sorcerer, 25)

      int_12 = [base_abilities: %{@flat | int: 12}]
      with_rdd = build(levels, int_12)
      without = build(List.duplicate(:sorcerer, 40), int_12)

      # Оба класса дают по 2 скилл-поинта за уровень, поэтому вся разница —
      # от интеллекта.
      assert Rules.compute(with_rdd, ruleset).skill_points.earned -
               Rules.compute(without, ruleset).skill_points.earned == 27
    end

    # Та же цитата с другой стороны, по одному уровню: на 12-м (седьмой
    # уровень РДД) очков столько же, сколько у билда без прибавки вовсе,
    # на 14-м (девятый, где +2 INT) — на одно больше.
    test "прибавка работает с уровня получения и не раньше", %{ruleset: ruleset} do
      levels =
        List.duplicate(:sorcerer, 5) ++
          List.duplicate(:red_dragon_disciple, 10) ++ List.duplicate(:sorcerer, 25)

      with_rdd = build(levels, base_abilities: %{@flat | int: 12})
      without = build(List.duplicate(:sorcerer, 40), base_abilities: %{@flat | int: 12})

      assert Build.class_level_at(with_rdd, 14) == 9
      assert Skills.points_at(with_rdd, ruleset, 12) == Skills.points_at(without, ruleset, 12)
      assert Skills.points_at(with_rdd, ruleset, 13) == Skills.points_at(without, ruleset, 13)
      assert Skills.points_at(with_rdd, ruleset, 14) == Skills.points_at(without, ruleset, 14) + 1
    end

    # И то же про фит: взятый на 22-м, он не имеет права менять то, что
    # считалось на 21-м. Оба взятия здесь по одному на уровень (21 и 22),
    # поэтому лесенка видна по шагам.
    test "второе взятие не задевает уровень, на котором его ещё не было", %{ruleset: ruleset} do
      b = build(List.duplicate(:fighter, 41), feats: epic_takes(:great_strength, 2))

      assert Abilities.scores_at(b, ruleset, 20).str == 10
      assert Abilities.scores_at(b, ruleset, 21).str == 11
      assert Abilities.scores_at(b, ruleset, 22).str == 12
      assert Abilities.scores_at(b, ruleset, 41).str == 12
    end
  end

  describe "порядок применения и два разных потолка" do
    # Развилка 1, решённая по источнику: фит даёт **base score**, значит
    # попадает в «голого». `fandom:Ability score`: «certain feats … can
    # increase base scores», отдельным абзацем — «Items, spells, etc.
    # ("magical means") … subject to the +12 ability cap».
    test "прибавка от фита есть в «голом» значении, а вещевая — нет", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 41),
            feats: epic_takes(:great_strength, 4),
            gear: Gear.new(abilities: %{str: 6})
          ),
          ruleset
        )

      assert stats.abilities_naked.str == 14
      assert stats.abilities.str == 20
    end

    # Развилка 2: два потолка, и они про разное. Кап +12 режет вещи и не
    # трогает фиты — иначе билд с `Great strength` ×10 и +12 с вещей потерял
    # бы десять очков.
    test "кап +12 режет вещи и не касается фитов", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 41),
            base_abilities: %{@flat | str: 18},
            feats: epic_takes(:great_strength, 10),
            gear: Gear.new(abilities: %{str: 20})
          ),
          ruleset
        )

      assert stats.abilities_naked.str == 28
      assert stats.abilities.str == 40
      assert :gear_abilities in stats.capped
    end

    # Тот же вопрос числом из источника: «The highest ability score achievable
    # by a player character through normal means is 57 (strength). The highest
    # score achievable without bonuses from feats and race is 40.» Оба числа
    # получаются только при этом порядке слоёв — 18 покупка + 10 уровней + 12
    # вещей = 40, плюс 2 расы, 7 взятий `Great strength` (столько эпических
    # общих слотов есть) и 8 от РДД = 57.
    test "предельная сила 57, и 40 без фитов и расы", %{ruleset: ruleset} do
      levels =
        List.duplicate(:sorcerer, 5) ++
          List.duplicate(:red_dragon_disciple, 10) ++ List.duplicate(:sorcerer, 26)

      increases =
        for level <- [4, 8, 12, 16, 20, 24, 28, 32, 36, 40], into: %{}, do: {level, :str}

      full =
        Build.new(
          levels: levels,
          race: :half_orc,
          base_abilities: %{@flat | str: 18},
          ability_increases: increases,
          feats: epic_takes(:great_strength, 7),
          gear: Gear.new(abilities: %{str: 12})
        )

      assert Rules.compute(full, ruleset).abilities.str == 57

      # …и вторая половина цитаты, тем же билдом без расы и без фитов.
      bare = %Build{full | race: :human, feats: %{}, levels: List.duplicate(:sorcerer, 41)}
      assert Rules.compute(bare, ruleset).abilities.str == 40
    end

    # Развилка 3: пять слагаемых разбора всегда дают ровно `score`. Инвариант
    # задачи 3.2, и задача 3.1 обязана была прийти ПЯТЫМ полем, а не подмешать
    # прибавку в «уровни» — иначе итог был бы верным, а объяснение ложным.
    test "поинт-бай + раса + уровни + собственные + вещи == значение", %{ruleset: ruleset} do
      levels =
        List.duplicate(:sorcerer, 5) ++
          List.duplicate(:red_dragon_disciple, 10) ++ List.duplicate(:sorcerer, 20)

      b =
        Build.new(
          levels: levels,
          race: :half_orc,
          base_abilities: %{@flat | str: 14},
          ability_increases: %{4 => :str, 8 => :str},
          feats: epic_takes(:great_strength, 3),
          gear: Gear.new(abilities: %{str: 4, con: 6})
        )

      for {_ability, row} <- Abilities.breakdown(b, ruleset) do
        assert row.point_buy + row.race_bonus + row.level_bonus + row.own_bonus + row.gear_bonus ==
                 row.score
      end

      str = Abilities.breakdown(b, ruleset).str
      assert %{point_buy: 14, race_bonus: 2, level_bonus: 2, own_bonus: 11, gear_bonus: 4} = str
    end
  end

  describe "двойной счёт: четыре старых источника и один новый" do
    # Раса, уровни и вещи остаются собой — прибавка от фита не подмешивается
    # ни в один из них. Проверяется на билде, где есть все четыре сразу.
    test "раса, уровни и вещи не изменились от появления пятого слагаемого", %{ruleset: ruleset} do
      b =
        Build.new(
          levels: List.duplicate(:fighter, 41),
          race: :half_orc,
          base_abilities: %{@flat | str: 14},
          ability_increases: %{4 => :str, 8 => :str, 12 => :str},
          feats: epic_takes(:great_strength, 2),
          gear: Gear.new(abilities: %{str: 6})
        )

      row = Abilities.breakdown(b, ruleset).str
      assert row.race_bonus == 2
      assert row.level_bonus == 3
      assert row.gear_bonus == 6
      assert row.own_bonus == 2
      assert row.score == 27
    end

    # 🔴 Отрицательный контроль задания: билд БЕЗ этих фитов не изменился ни
    # в одном числе. Каскад задевает всё, и это самая вероятная форма
    # регрессии — поэтому сравнивается вся структура целиком, а не отдельные
    # поля.
    test "билд без прибавок совпадает с эталоном во всех числах", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(List.duplicate(:fighter, 41), base_abilities: %{@flat | str: 16, con: 14}),
          ruleset
        )

      assert stats.abilities == %{str: 16, dex: 10, con: 14, int: 10, wis: 10, cha: 10}

      # 533 — число из HANDOFF, которым закрывалась задача 1.9: воин 41 с
      # CON 14. Плюс 20 от «Духа Сиалы» (задача, волна 12, 09.08.2026) — 553.
      # Если каскад 3.1 или волна 12 задели кого-то мимо, ломается оно.
      assert stats.hp == 553
      assert stats.base_attack == 31
      assert stats.attack_bonus == 34
      assert {stats.fort, stats.ref, stats.will} == {24, 16, 16}
      assert stats.ac_naked == 10
      assert stats.skill_points.earned == 132
      refute Enum.any?(stats.gaps, &match?({:not_modelled, {:ability_bonus, _}}, &1))
    end

    # Положительный контроль к строке выше: тот же билд с одним взятием
    # действительно меняется — иначе «ничего не изменилось» доказывало бы
    # только то, что расчёт не работает вовсе.
    test "тот же билд с одним взятием меняется", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 41)
      fields = [base_abilities: %{@flat | str: 16, con: 14}]

      plain = Rules.compute(build(levels, fields), ruleset)

      one =
        Rules.compute(build(levels, fields ++ [feats: epic_takes(:great_strength, 1)]), ruleset)

      assert one.abilities.str == plain.abilities.str + 1
      assert one.hp == plain.hp
    end
  end

  # ⚠️ Блок назывался «условные прибавки: считать нельзя, молчать тоже» и
  # проверял ровно это: прибавка не в числе И названа поимённо. Вторая половина
  # ПЕРЕСМОТРЕНА 17.08.2026 — не тестом, а решением Dan от 10.08.2026, которое
  # до ядра доехало только теперь: «то, что включается и кончается, — не наше».
  # Все четыре отвергнутые записи этого файла помечены `affects: ["buff"]`, то
  # есть гэпа в НАШЕМ ответе не образуют (CLAUDE.md §9).
  #
  # Первая половина не тронута и осталась главной: прибавка по-прежнему не в
  # числе, и молчание про неё — решение, а не потерянный терм.
  describe "условные прибавки: считать нельзя, а называть — по получателю" do
    # Ярость, стойка и право сотворить заклинание — все три включаются, все три
    # временные, и ни одна не двигает характеристику билда.
    for {levels, id, note} <- [
          {List.duplicate(:barbarian, 5), :barbarian_rage, "ярость варвара"},
          {List.duplicate(:fighter, 10) ++ List.duplicate(:dwarven_defender, 5),
           :defensive_stance, "стойка Гномьего защитника"},
          {List.duplicate(:fighter, 6) ++ List.duplicate(:blackguard, 4), :bulls_strength_feat,
           "Bull's strength Чёрного стража"}
        ] do
      test "#{note} не посчитана и на Сиале не названа", %{ruleset: ruleset, vanilla: vanilla} do
        levels = unquote(Macro.escape(levels))
        id = unquote(id)

        b = build(levels)
        stats = Rules.compute(b, ruleset)

        # Главное: прибавка не приехала в число ни одним путём.
        assert own(b, ruleset, :str) == 0
        assert own(b, ruleset, :con) == 0

        refute {:not_modelled, {:ability_bonus, id}} in stats.gaps

        # 🔴 Отрицательный контроль: запись жива, и единственное, что её здесь
        # снимает, — словарь получателей. У ванили его нет вовсе, и та же
        # прибавка на том же билде называется поимённо.
        assert {:not_modelled, {:ability_bonus, id}} in Rules.compute(b, vanilla).gaps
      end
    end

    # ⚠️ Положительный контроль к трём `assert … in vanilla` выше: на билде без
    # этих классов гэпа нет и на ванили. Без него они зеленели бы и при
    # оговорке, приклеенной ко всем билдам подряд.
    test "у билда без таких умений оговорки нет ни там, ни там", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      wizard = build(List.duplicate(:wizard, 20))

      refute Enum.any?(Rules.compute(wizard, ruleset).gaps, &ability_gap?/1)
      refute Enum.any?(Rules.compute(wizard, vanilla).gaps, &ability_gap?/1)
    end
  end

  defp ability_gap?(gap), do: match?({:not_modelled, {:ability_bonus, _}}, gap)

  describe "границы: уровни 1, 20/21, 41 и четыре класса" do
    # `Great *` требует 21-го уровня, поэтому граница проверяется там, где она
    # есть: на 20-м уровне прибавки нет, потому что фита ещё нет.
    test "на 1-м и 20-м уровнях прибавки нет, на 21-м есть, на 41-м держится", %{
      ruleset: ruleset
    } do
      b = build(List.duplicate(:fighter, 41), feats: epic_takes(:great_strength, 7))

      assert Abilities.scores_at(b, ruleset, 1).str == 10
      assert Abilities.scores_at(b, ruleset, 20).str == 10
      assert Abilities.scores_at(b, ruleset, 21).str == 11
      assert Abilities.scores_at(b, ruleset, 41).str == 17
    end

    # Мультикласс на четыре класса — предел Сиалы. РДД среди них, значит
    # таблица считается от уровней СВОЕГО класса, а не от уровня персонажа.
    test "билд из четырёх классов считает таблицу РДД по её собственным уровням", %{
      ruleset: ruleset
    } do
      levels =
        List.duplicate(:sorcerer, 5) ++
          List.duplicate(:red_dragon_disciple, 10) ++
          List.duplicate(:fighter, 10) ++ List.duplicate(:weapon_master, 16)

      b = build(levels, feats: epic_takes(:great_strength, 3))
      stats = Rules.compute(b, ruleset)

      assert map_size(stats.class_levels) == 4
      assert stats.character_level == 41

      # +8 от таблицы РДД (десять уровней класса) и +3 от трёх взятий.
      assert own(b, ruleset, :str) == 11
      assert stats.abilities.str == 21
    end
  end

  describe "ваниль и Сиала" do
    # Шард про эти прибавки молчит, значит действует ваниль (CLAUDE.md §3), и
    # числа обязаны совпасть. ⚠️ Это НЕ «мы применили одно и то же дважды»:
    # ruleset'ы разные, и совпадение здесь — утверждение о данных.
    test "числа одинаковы на обоих ruleset'ах", %{ruleset: ruleset, vanilla: vanilla} do
      b =
        build(
          List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, 10),
          feats: epic_takes(:great_strength, 3)
        )

      assert Rules.compute(b, ruleset).abilities == Rules.compute(b, vanilla).abilities
    end

    # А вот потолок ЧИСЛА ВЗЯТИЙ есть только у шарда (со слов Dan), и
    # ванильный билд честно несёт оговорку. Потолок эффекта при этом стоит на
    # обоих — он со страницы.
    test "у ванили нет потолка взятий, а потолок эффекта есть", %{vanilla: vanilla} do
      b = build(List.duplicate(:fighter, 41), feats: epic_takes(:great_strength, 11))
      stats = Rules.compute(b, vanilla)

      assert {:missing_data, {:feat_max_takes, :great_strength}} in stats.gaps
      assert stats.abilities.str == 20
    end
  end

  describe "требования фитов считаются от базового значения" do
    # «It is this unmodified score (the base score) that matters when meeting
    # the prerequisite of a feat» — значит прибавка от фита в требование
    # входит, а вещевая нет. Первое проверяется на РДД, второе рядом.
    test "прибавка от РДД открывает фит, требующий силу 13", %{ruleset: ruleset} do
      levels = List.duplicate(:sorcerer, 5) ++ List.duplicate(:red_dragon_disciple, 10)
      with_rdd = build(levels, base_abilities: %{@flat | str: 12})
      without = build(List.duplicate(:sorcerer, 15), base_abilities: %{@flat | str: 12})

      assert Rules.validate_feat(with_rdd, %{feat: :power_attack, at: 15}, ruleset) == :ok

      assert {:error, reasons} =
               Rules.validate_feat(without, %{feat: :power_attack, at: 15}, ruleset)

      assert {:requires_ability, :str, 13} in reasons
    end

    # «Второе рядом» из комментария выше стояло обещанием с 04.08.2026 и
    # проверялось НИЧЕМ: требование читало `stats.abilities`, то есть значение
    # вместе с вещами, и вещевая прибавка фит открывала. Поправлено 16.08.2026
    # по факту от Dan (`GAME_CHECKS.md` S1): «статы с вещей не работают при
    # выборе фитов. Только поинт бай + левел апы».
    #
    # ⚠️ Тот же самый пояс при этом СЧИТАЕТСЯ везде, где считался: сила в листе
    # 24, и AB от неё вырос. Требование и эффект — разные вопросы, и вещь
    # отвечает на них по-разному (та же форма, что у замера H7 про фиты).
    test "прибавка с вещи тот же фит НЕ открывает, хотя в статах она есть", %{ruleset: ruleset} do
      levels = List.duplicate(:sorcerer, 15)
      fields = [base_abilities: %{@flat | str: 12}]
      without = build(levels, fields)
      geared = build(levels, fields ++ [gear: %Gear{abilities: %{str: 12}}])

      assert {:error, reasons} =
               Rules.validate_feat(geared, %{feat: :power_attack, at: 15}, ruleset)

      assert {:requires_ability, :str, 13} in reasons

      # Положительный контроль в обе стороны: пояс до статов доезжает (сила 24
      # против 12 базовых) и в производных считается — иначе тест зеленел бы
      # на билде, у которого вещей нет вовсе.
      plain = Rules.compute(without, ruleset)
      stats = Rules.compute(geared, ruleset)

      assert {stats.abilities.str, stats.abilities_naked.str} == {24, 12}
      assert stats.attack_bonus - plain.attack_bonus == 6
    end
  end

  # Самый высокий круг, который пускает МУДРОСТЬ: «10 + круг»
  # (`Rules.Spells.minimum_ability_score/2`, число из данных).
  defp castable_circle(stats, ruleset) do
    Enum.reduce(0..9, 0, fn circle, highest ->
      minimum = Spells.minimum_ability_score(ruleset, circle)
      if minimum && minimum <= stats.abilities.wis, do: circle, else: highest
    end)
  end
end
