defmodule BuildCalculator.Rules.ArmorClassTest do
  @moduledoc """
  AC от собственных умений билда — задача 3.11.

  До неё калькулятор собирал AC **только из вещей**: `base_ac + DEX + введённое
  под «Вещи»`. Классовые умения, фиты, навыки и расовые склонности терялись
  целиком, и — хуже числа — **молча**: в словаре гэпов не было ни одной формы
  про них. Клирик 35 / Монах 4 (тест-кейс Dan, билд, который на шарде берут
  ровно ради AC) показывал 10 и пустой список оговорок.

  Источники, по которым здесь считаются ожидания:

    * `fandom:Monk AC bonus` (revid 60287) — «Monks add their wisdom modifier
      to their armor class»;
    * `siala:Monk AC bonus` (revid 17883) — фит перенесён на 4-й уровень
      класса, и «Монах теряет этот бонус, если носит доспехи или использует
      щит»;
    * `fandom:Monk` (revid 71589) — колонка «AC bonus» таблицы класса: +1 на
      5-м уровне и далее каждые пять, до +8 на 40-м. ⚠️ Это ДРУГАЯ прибавка,
      не фит: Сиала сдвинула фит и про колонку не сказала ничего;
    * `fandom:Bone skin` (revid 48990) — +2 на уровнях Бледного мастера 1, 4,
      8, 12, 16, 20, 24, 28, то есть до +16, и колонка таблицы класса
      (`fandom:Pale master`, revid 71581) печатает те же итоги;
    * `fandom:Draconic armor` (revid 67677) — природный AC РДД от +1 до +8;
    * `fandom:Armor skin` (revid 68039) — природный +2, обычный эпический фит;
    * `fandom:Tumble` (revid 68560) — +1 за каждые 5 БАЗОВЫХ рангов;
    * `fandom:Gnome` (revid 65710) / `fandom:Halfling` (revid 71190) —
      «+1 size modifier to armor class».
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Caps, Gear}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(levels, fields \\ []) do
    Build.new([levels: levels, base_abilities: @flat, race: :human] ++ fields)
  end

  defp terms(stats), do: for(term <- stats.ac_own_terms, do: {term.id, term.ac})
  defp ac_gaps(stats), do: Enum.filter(stats.gaps, &(&1 |> inspect() |> String.contains?("ac_")))

  # Уровни навыка кладутся по одному рангу на уровень: покупку никто здесь не
  # проверяет, а потолок ранга на первых уровнях меньше нужного числа.
  defp ranks(skill, count) do
    for level <- 1..count, into: %{}, do: {level, %{skill => 1}}
  end

  describe "тест-кейс Dan: 35 клирик / 4 монах" do
    # 🔴 Билд, ради которого задача заведена. Четыре уровня монаха, а не один,
    # именно потому, что на Сиале AC-бонус монаха сдвинут с 1-го уровня на 4-й.
    test "мудрость доезжает до AC, и это видно на 4-м уровне монаха", %{ruleset: ruleset} do
      levels = List.duplicate(:cleric, 35) ++ List.duplicate(:monk, 4)
      stats = Rules.compute(build(levels, base_abilities: %{@flat | wis: 18}), ruleset)

      assert terms(stats) == [monk_ac_bonus: 4]
      assert stats.ac_naked == 14
      assert stats.ac_own_bonus == 4
    end

    # ⚠️ Положительный контроль к строке выше и главная проверка сиальского
    # сдвига: тот же билд с ТРЕМЯ уровнями монаха не получает ничего. Без этой
    # пары «14» ничего не доказывала бы — она вышла бы и при выдаче с первого.
    test "на 3-м уровне монаха не даётся ничего", %{ruleset: ruleset} do
      levels = List.duplicate(:cleric, 35) ++ List.duplicate(:monk, 3)
      stats = Rules.compute(build(levels, base_abilities: %{@flat | wis: 18}), ruleset)

      assert terms(stats) == []
      assert stats.ac_naked == 10
      assert ac_gaps(stats) == []
    end

    # И обратная сторона сдвига: в ванили тот же монах 1 бонус получает. Пара
    # доказывает, что 4-й уровень — правило ШАРДА, а не наша выдумка.
    test "в ванили тот же бонус приходит на 1-м уровне монаха", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      levels = List.duplicate(:cleric, 35) ++ [:monk]
      build = build(levels, base_abilities: %{@flat | wis: 18})

      assert Rules.compute(build, vanilla).ac_naked == 14
      assert Rules.compute(build, ruleset).ac_naked == 10
    end
  end

  describe "«голым» значит голым, но не «без себя»" do
    # ⚠️ Требование CLAUDE.md §6 и задачи: классовое умение — часть билда, а не
    # экипировки, значит оно обязано попадать в «голого».
    #
    # ⚠️ Тип вещи здесь `deflection`, а не `armor`, и это не косметика: с
    # 09.08.2026 надетый доспех у монаха обе его прибавки ЛОМАЕТ (см. describe
    # «монах в доспехах и со щитом» ниже), и на броне этот тест проверял бы уже
    # не «классовое в голом, вещевое в шмоте», а само условие. Отклонение
    # монашеских прибавок не касается ничем.
    test "классовая прибавка есть в AC голым, а вещевая — нет", %{ruleset: ruleset} do
      gear = Gear.new(ac: %{deflection: 8})

      stats =
        Rules.compute(
          build(List.duplicate(:monk, 20), base_abilities: %{@flat | wis: 16}, gear: gear),
          ruleset
        )

      # 10 базы + 3 мудрости + 4 колонки таблицы на 20-м уровне класса.
      assert stats.ac_naked == 17
      assert stats.ac_geared == 25
      assert stats.ac_own_bonus == 7
      assert stats.ac_gear_bonus == 8
    end

    # Каскад: `+12 WIS` с вещей — это +6 к модификатору, то есть +6 к AC
    # монаха, и в «голом» числе их быть не должно.
    test "мудрость с вещей поднимает AC в шмоте и не трогает голого", %{ruleset: ruleset} do
      gear = Gear.new(abilities: %{wis: 12})

      stats =
        Rules.compute(
          build(List.duplicate(:monk, 4), base_abilities: %{@flat | wis: 10}, gear: gear),
          ruleset
        )

      assert stats.ac_own_bonus == 0
      assert stats.ac_own_bonus_geared == 6
      assert stats.ac_naked == 10
      assert stats.ac_geared == 16
    end
  end

  describe "таблица по уровню класса читается как ИТОГ, а не как ступени" do
    # Монах: +1 на 5-м, +2 на 10-м … +8 на 40-м. Ступени между ними держат
    # предыдущее значение, ниже первой — ноль.
    test "монах на границах ступеней", %{ruleset: ruleset} do
      for {class_level, expected} <- [{4, 0}, {5, 1}, {9, 1}, {10, 2}, {20, 4}, {40, 8}] do
        stats = Rules.compute(build(List.duplicate(:monk, class_level)), ruleset)
        table = Keyword.get(terms(stats), :monk, 0)

        assert table == expected, "монах #{class_level}: ожидали +#{expected}, вышло +#{table}"
      end
    end

    # 🔴 source: уточнение Dan, 09.08.2026 (GAME_CHECKS.md, кейс C5). Формулировка
    # «монах получает AC за каждые 5 уровней в билде» прозвучала при ответе на C4
    # и прошла бы в модель незаметно: у ЧИСТОГО монаха уровень класса равен уровню
    # персонажа, поэтому оба чтения предсказывают одно и то же на каждом кейсе
    # выше. Различает только мультикласс — Dan подтвердил, что это уровни МОНАХА
    # («я описался, за каждые 5 уровней монаха»).
    test "колонка считается по уровням МОНАХА, а не персонажа", %{ruleset: ruleset} do
      dip = build(List.duplicate(:monk, 4) ++ List.duplicate(:fighter, 36))
      stats = Rules.compute(dip, ruleset)

      assert stats.character_level == 40
      assert Keyword.get(terms(stats), :monk, 0) == 0

      # ⚠️ Положительный контроль: те же 40 уровней персонажа, но все монашеские,
      # дают +8. Без него «0» зеленел бы и при выключенной колонке вообще.
      assert Keyword.fetch!(
               terms(Rules.compute(build(List.duplicate(:monk, 40)), ruleset)),
               :monk
             ) ==
               8
    end

    # ⚠️ Кап Сиалы 41, а таблица Fandom кончается на 40-м. Продолжать её мы не
    # имеем права — держим последнюю названную ступень.
    test "на 41-м уровне класса держится ступень 40-го", %{ruleset: ruleset} do
      stats = Rules.compute(build(List.duplicate(:monk, 41)), ruleset)

      assert Keyword.fetch!(terms(stats), :monk) == 8
    end

    # Bone skin: восемь ступеней по +2. Бэклог писал «выдаётся дважды — на 1 и
    # 12», и это описание НАШИХ granted_feats, а не правила.
    test "Bone skin растёт до +16 к 28-му уровню Бледного мастера", %{ruleset: ruleset} do
      for {pale_master, expected} <- [{1, 2}, {3, 2}, {4, 4}, {12, 8}, {28, 16}, {31, 16}] do
        levels = List.duplicate(:wizard, 3) ++ List.duplicate(:pale_master, pale_master)
        stats = Rules.compute(build(levels), ruleset)

        assert Keyword.fetch!(terms(stats), :bone_skin) == expected
      end
    end
  end

  describe "красный дракон: AC и HP развязаны" do
    # ⚠️ Здесь стояло «hp = nil, а AC от Draconic armor есть»: у РДД не было
    # хит-дайса, и билд честно оставался без HP, а AC считался целиком —
    # асимметрия была смыслом кейса. Задача 3.37 её сняла: хит-дайс у класса
    # теперь есть, растущий (d6 → d8 → d10 → d12), и оба числа считаются.
    # Кейс оставлен и проверяет ОБА — иначе правка тихо унесла бы единственное
    # место, где AC этого класса стоит рядом со своим HP.
    test "и AC от Draconic armor, и HP по растущему хит-дайсу", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 5) ++ List.duplicate(:red_dragon_disciple, 10)
      stats = Rules.compute(build(levels), ruleset)

      assert terms(stats) == [draconic_armor: 4]
      assert stats.ac_naked == 14

      # Воин 5 × d10 = 50, РДД 10 = 6+6+6+8+8+10+10+10+10+10 = 84,
      # телосложение 12 (база 10 плюс +2 от `dragon_abilities` на 7-м уровне
      # класса) → мод +1 × 15 уровней = 15, Toughness воина +15 (по одному
      # за уровень персонажа), «Дух Сиалы» +20.
      assert stats.abilities.con == 12
      assert stats.hp == 50 + 84 + 15 + 15 + 20
      refute Enum.any?(stats.gaps, &match?({:missing_data, {:hit_die, _}}, &1))
    end

    # 🔴 Единственное столкновение СОБСТВЕННЫХ прибавок в корпусе: `Armor skin`
    # и `Draconic armor` оба природные, и они СКЛАДЫВАЮТСЯ — это замер, а не
    # умолчание: Dan 16.08.2026, `GAME_CHECKS.md` E5, «замер был с 7 уровнями
    # РДД, что даёт мне от draconic armor 2 AC. Ещё 2 AC я получил от armor
    # skin… AC в чарлисте у меня 18».
    #
    # ⚠️ До задачи 3.39 здесь стояла оговорка `{:not_modelled,
    # :ac_same_type_stacking}` — «сложили, а игра не складывает». Замер сказал
    # обратное, и оговорка снята: печатать «не смоделировано» про измеренное
    # и совпавшее — ложная неопределённость (CLAUDE.md §6).
    test "Armor skin рядом с Draconic armor складывается, и оговорки нет", %{
      ruleset: ruleset
    } do
      levels = List.duplicate(:fighter, 5) ++ List.duplicate(:red_dragon_disciple, 10)
      build = build(levels, feats: %{4 => %{general: :armor_skin}})
      stats = Rules.compute(build, ruleset)

      assert terms(stats) == [draconic_armor: 4, armor_skin: 2]
      assert stats.ac_naked == 16
      assert ac_gaps(stats) == []
    end

    # Тот же билд на числах самого замера: бард 14 / РДД 7, DEX 18 →
    # 10 база + 2 Draconic armor + 2 Armor skin + 4 DEX = 18.
    test "числа замера E5 воспроизводятся термом в терм", %{ruleset: ruleset} do
      levels = List.duplicate(:bard, 14) ++ List.duplicate(:red_dragon_disciple, 7)

      stats =
        Rules.compute(
          build(levels,
            base_abilities: %{@flat | dex: 18},
            feats: %{21 => %{epic_general: :armor_skin}}
          ),
          ruleset
        )

      assert terms(stats) == [draconic_armor: 2, armor_skin: 2]
      assert stats.ac_naked == 18
    end

    # 🔴 И вписанное игроком число того же типа СКЛАДЫВАЕТСЯ с фитом —
    # задача 3.91, решение Dan 25.08.2026: «вот амулет + 5 и armor skin
    # стакаются, должна быть сумма. Тут фит + натур АЦ с амулета».
    #
    # ⚠️ Здесь стояло обратное — «не складывается, берётся большее», и число
    # было 15. Правило пришло из цитаты про РАСОВЫЙ щитовой бонус Карлика
    # и было распространено на все собственные прибавки; оно осталось верным
    # ровно там, откуда пришло (`describe` ниже), и снято с фитов.
    test "тот же тип с вещей складывается с фитом", %{ruleset: ruleset} do
      build =
        build([:fighter],
          feats: %{1 => %{general: :armor_skin}},
          gear: Gear.new(ac: %{natural: 5})
        )

      stats = Rules.compute(build, ruleset)

      # Своё голым осталось — вещей там нет вовсе.
      assert terms(stats) == [armor_skin: 2]
      assert stats.ac_naked == 12

      # А в шмоте — 10 + 2 своего + 5 вписанного. До задачи 3.91 было 15.
      assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac}) == [armor_skin: 2]
      assert stats.ac_geared == 17
      assert stats.ac_by_type[:natural] == 5
      assert stats.ac_superseded_types == []

      # ⚠️ И оговорка про базу предмета ушла вместе с состязанием: складывать
      # нечего и терять нечего — вписанное число доехало целиком.
      refute {:not_modelled, {:ac_gear_base, :natural}} in stats.gaps
      refute {:not_modelled, :ac_same_type_stacking} in stats.gaps
    end

    # ⚠️ Отрицательный контроль к строке выше и главный смысл правки: сумма
    # растёт вместе с вписанным числом, а не «перещёлкивается» на большее из
    # двух. При старом правиле 1 проигрывала фиту (13), а 5 выигрывала (16).
    test "сумма растёт с вписанным числом, а не перещёлкивается", %{ruleset: ruleset} do
      for {typed, expected} <- [{0, 13}, {1, 14}, {5, 18}] do
        stats =
          Rules.compute(
            build(List.duplicate(:fighter, 21),
              base_abilities: %{@flat | dex: 12},
              feats: %{21 => %{epic_general: :armor_skin}},
              gear: Gear.new(ac: %{natural: typed})
            ),
            ruleset
          )

        assert stats.ac_geared == expected, "вписано #{typed}: AC в шмоте #{stats.ac_geared}"
        assert stats.ac_naked == 13, "вписано #{typed}: голое число поехало"
      end
    end

    # И то же на РДД, где цена ошибки была самой крупной: собственная прибавка
    # растёт до +8, то есть при старом правиле амулет на +5 отбирал у билда
    # до восьми очков. Проверяются обе стороны — и число, и терм на месте.
    test "Draconic armor складывается с природным AC с вещей", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 5) ++ List.duplicate(:red_dragon_disciple, 10)
      stats = Rules.compute(build(levels, gear: Gear.new(ac: %{natural: 5})), ruleset)

      # 10 + 4 (РДД 10) + 5 вписанного. До задачи 3.91 было 15.
      assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac}) == [draconic_armor: 4]
      assert stats.ac_geared == 19
      assert stats.ac_naked == 14
      assert stats.ac_by_type[:natural] == 5
    end

    # ⚠️ Положительный контроль к обеим строкам выше: без второго источника
    # ни оговорки, ни конкуренции нет.
    test "один природный источник оговорки не приносит", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :armor_skin}}), ruleset)

      assert terms(stats) == [armor_skin: 2]
      assert ac_gaps(stats) == []
    end
  end

  describe "навык и раса" do
    # +1 за каждые 5 БАЗОВЫХ рангов. Граница проверяется парой: 4 ранга не
    # дают ничего, 5 дают +1.
    test "Кувырок: 4 ранга ничего, 5 рангов +1, 40 рангов +8", %{ruleset: ruleset} do
      for {bought, expected} <- [{4, 0}, {5, 1}, {9, 1}, {40, 8}] do
        stats =
          Rules.compute(build(List.duplicate(:monk, 41), skills: ranks(:tumble, bought)), ruleset)

        assert Keyword.get(terms(stats), :tumble, 0) == expected
      end
    end

    # Карлик (Gnome) и Гоблин (Halfling) малы. ⚠️ Помнить коллизию имён:
    # Гном = Dwarf, Карлик = Gnome.
    #
    # 🔴 ПЕРЕВОРОТ 30.08.2026 (задача 3.143): здесь стояло «малые расы получают
    # +1 за размер» и `terms(stats) == [small_stature: 1]`. Цитата в разметке
    # была обрезана перед условием — фит называет его прямо: «gain bonuses…
    # when dealing with LARGER creatures». Число не безусловно, а посчитать
    # его нечем (противник неизвестен заранее), поэтому `small_stature` стал
    # `not_modelled` в ac_bonuses.json (и в feat_attack_bonuses.json той же
    # правкой). ✅ Подтверждено движком: Dan, тестовый сервер, 30.08.2026 —
    # бонус в чарлисте не печатается ни у Карлика, ни у Гоблина.
    test "Small stature термом не считается ни у одной расы", %{ruleset: ruleset} do
      for race <- [:gnome, :halfling, :human, :dwarf, :elf, :half_elf, :half_orc] do
        stats = Rules.compute(build([:fighter], race: race), ruleset)

        assert terms(stats) == [], "#{race}: размерного терма быть не должно"
        assert stats.ac_own_bonus == 0

        # ⚠️ И оговорки тоже нет: `not_a_gap` (basis `feat_description`) гасит
        # её — описание фита само называет условие точнее нашей фразы, и оно
        # доступно игроку (конструктор, задача 3.87; экран просмотра, 3.94).
        assert ac_gaps(stats) == [], "#{race}: оговорка о small_stature не должна печататься"
      end

      # ⚠️ 10, а не 11: базовое AC без DEX и без размерного терма.
      assert Rules.compute(build([:fighter], race: :gnome), ruleset).ac_naked == 10
    end

    # ⚠️ Расовая склонность НЕ читается через `feats_owned/3` — расовых фитов
    # там нет вовсе. Проверка тому, что гейт именно расовый: тот же id, взятый
    # в слот человеком, ничего не даёт (и не может: фит нельзя выбрать).
    test "размерный бонус привязан к расе, а не к владению фитом", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :small_stature}}), ruleset)

      assert terms(stats) == []
    end
  end

  describe "оговорки называют себя" do
    # ⚠️ Здесь стояло «условные умения не идут в число, но и не молчат» и
    # `assert` на оговорку про Ярость. Вторая половина пересмотрена 17.08.2026:
    # Ярость помечена `affects: ["buff"]`, а бафф — не наш ответ (решение Dan
    # 10.08.2026, CLAUDE.md §9). Первая половина не тронута и осталась главной:
    # в число прибавка не идёт ни на одном ruleset'е.
    test "ярость варвара не в числе и на Сиале не названа", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      barbarian = build(List.duplicate(:barbarian, 10))
      stats = Rules.compute(barbarian, ruleset)

      assert terms(stats) == []
      refute {:not_modelled, {:ac_bonus, :barbarian_rage}} in stats.gaps

      # 🔴 Отрицательный контроль: запись жива, снимает её только словарь
      # получателей, которого у ванили нет вовсе.
      vanilla_stats = Rules.compute(barbarian, vanilla)
      assert {:not_modelled, {:ac_bonus, :barbarian_rage}} in vanilla_stats.gaps
      assert terms(vanilla_stats) == []
    end

    # ⚠️ Положительный контроль: у билда без такого умения оговорки нет.
    test "у воина оговорок про AC нет вовсе", %{ruleset: ruleset} do
      assert ac_gaps(Rules.compute(build(List.duplicate(:fighter, 10)), ruleset)) == []
    end

    # Умение, взятое В СЛОТ: число в AC не идёт, и с задачи 3.95 (25.08.2026)
    # оговорки про него тоже нет.
    #
    # ⚠️ Здесь стояло `assert {:not_modelled, {:ac_bonus, :dodge}} in stats.gaps`
    # со словами «"Итого" не должно выглядеть полным». Решение владельца
    # (`not_a_gap`, довод `feat_description`) эту половину сняло: описание фита
    # говорит «+1 dodge bonus to AC against attacks from his current target or
    # latest attacker» — то есть и число, и условие, и точнее нашей фразы, —
    # и видно оно в конструкторе (3.87) и на экране просмотра (3.94).
    #
    # 🔴 Первая половина не менялась и проверяется здесь же: AC остался прежним.
    # Правка про признание, а не про расчёт. Механизм самой оговорки жив
    # и проверяется СИНТЕТИЧЕСКОЙ записью в `describe` про столкновение типов —
    # живой пример здесь был бы ловушкой того же рода.
    test "Dodge в слоте не считается и не оговаривается", %{ruleset: ruleset} do
      naked = Rules.compute(build([:fighter]), ruleset)
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :dodge}}), ruleset)

      assert stats.ac_naked == naked.ac_naked
      assert ac_gaps(stats) == []
    end

    # ⚠️ Условие «в доспехах и со щитом» с 09.08.2026 ПРАВИЛО, а не оговорка, и
    # печатать «условие не проверяем» про проверенное запрещено так же прямо, как
    # обратное (CLAUDE.md §6). Здесь стояло `assert` на обе формы — теперь
    # `refute`, а сама механика проверяется числами в describe ниже.
    #
    # 🔴 И третий `refute` пришёл задачей 3.90 (25.08.2026). Здесь стояло
    # `assert {:assumed, :ac_bonus_types_unstated} in stats.gaps` с доводом
    # «замер подтвердил величину и условие, но не ТИП». Довод остался верным —
    # тип не назван ни одной из двух вики и поле `type` у обеих записей
    # по-прежнему `nil`, — но закрылось его СЛЕДСТВИЕ: обе прибавки монаха
    # складываются (замер на живом билде владельца, потеря 12 очков при
    # надетом доспехе; общий тип стоил бы 6).
    #
    # ⚠️ Положительный контроль поэтому переехал на СИНТЕТИЧЕСКУЮ запись —
    # `describe` ниже. Держать его на живой нельзя: живая назавтра получает
    # отметку, и тест молча перестаёт что-либо проверять (урок задачи 3.85,
    # пять контролей подряд).
    test "у монаха нет ни оговорок про условие, ни допущения про тип", %{
      ruleset: ruleset
    } do
      stats =
        Rules.compute(
          build(List.duplicate(:monk, 20), base_abilities: %{@flat | wis: 16}),
          ruleset
        )

      refute {:not_modelled, {:ac_bonus_scope, :monk_ac_bonus}} in stats.gaps
      refute {:not_modelled, {:ac_bonus_scope, :monk}} in stats.gaps
      refute {:assumed, :ac_bonus_types_unstated} in stats.gaps

      # ⚠️ Положительный контроль другого рода, и он обязателен: без него
      # «оговорок нет» сошлось бы и на билде, у которого нет самих прибавок.
      assert Keyword.fetch!(terms(stats), :monk_ac_bonus) == 3
      assert Keyword.fetch!(terms(stats), :monk) == 4
    end

    # ⚠️ И честная половина: оговорка не удалена, а стала недостижимой из данных.
    # Условие, которого ядро проверить не умеет, обязано оставлять прибавку в
    # числе и называть себя — иначе следующее неформализуемое условие станет
    # молчанием. Проверяется подменой `kind` в копии ruleset'а, потому что
    # в самих данных такой записи сегодня нет ни одной.
    test "условие незнакомой формы оставляет число и приносит оговорку", %{ruleset: ruleset} do
      doctored =
        update_in(ruleset.ac_bonuses.applied, fn records ->
          for record <- records do
            if record.id == :monk_ac_bonus,
              do: %{record | scope: %{kind: :mounted, ac_types: []}},
              else: record
          end
        end)

      build = build(List.duplicate(:monk, 20), base_abilities: %{@flat | wis: 16})
      stats = Rules.compute(build, doctored)

      assert {:not_modelled, {:ac_bonus_scope, :monk_ac_bonus}} in stats.gaps
      assert Keyword.fetch!(terms(stats), :monk_ac_bonus) == 3

      # ...и у колонки таблицы, чьё условие ядро понимает, оговорки по-прежнему нет
      refute {:not_modelled, {:ac_bonus_scope, :monk}} in stats.gaps
    end

    # ⚠️ Оговорка про тип висит только там, где посчитанная прибавка без типа
    # действительно есть: у `Armor skin` тип назван, значит и оговорки быть
    # не должно.
    test "оговорка про неназванный тип не висит на прибавке с типом", %{ruleset: ruleset} do
      stats = Rules.compute(build([:fighter], feats: %{1 => %{general: :armor_skin}}), ruleset)

      refute {:assumed, :ac_bonus_types_unstated} in stats.gaps
    end

    # Песня барда — прибавка от НАВЫКА, и она условная. Оговорка обязана
    # появляться только у того, кто в навык вложился.
    #
    # ⚠️ Ruleset поменялся 17.08.2026 на ваниль, и это не подгонка под зелёный:
    # песня — бафф (Dan, 10.08.2026: «песня и все заклинания у нас баффы»), и
    # на Сиале запись помечена `buff`. Проверяется здесь ГЕЙТ ПО НАВЫКУ
    # (`held?({:skill, id})`) — единственная запись такого вида во всём файле, —
    # а он от ruleset'а не зависит. Ваниль — тот же файл разметки без словаря
    # получателей, то есть ровно то место, где этот гейт ещё виден.
    test "песня барда: оговорка у барда с рангами и ни у кого больше", %{vanilla: vanilla} do
      bard = build(List.duplicate(:bard, 10), skills: ranks(:perform, 5))
      assert {:not_modelled, {:ac_bonus, :perform}} in Rules.compute(bard, vanilla).gaps

      without = build(List.duplicate(:bard, 10))
      refute {:not_modelled, {:ac_bonus, :perform}} in Rules.compute(without, vanilla).gaps
    end

    # ...и та же песня на Сиале не называется вовсе — гейт по навыку пройден,
    # снимает её получатель. Без этой строки правка выше читалась бы как
    # «тест переехал на ваниль, потому что на Сиале сломалось».
    test "песня барда на Сиале — бафф, оговорки нет и с рангами", %{ruleset: ruleset} do
      bard = build(List.duplicate(:bard, 10), skills: ranks(:perform, 5))

      refute {:not_modelled, {:ac_bonus, :perform}} in Rules.compute(bard, ruleset).gaps
    end
  end

  # Задача 3.90 (25.08.2026). Допущение про неназванный тип снято не
  # вычёркиванием, а ОТМЕТКОЙ НА ЗАПИСИ: у каждой из четырёх прибавок без типа
  # подтверждено, как она ведёт себя рядом с соседями, и отметка несёт свой
  # источник. Тип при этом по-прежнему неизвестен — поле `type` осталось `nil`.
  #
  # 🔴 Здесь проверяется МЕХАНИЗМ, а не сегодняшнее состояние `priv/`. Все
  # положительные контроли — на СИНТЕТИЧЕСКОЙ записи: живая назавтра получает
  # отметку, и тест, стоявший на ней, молча перестаёт что-либо проверять. Так
  # за неделю сгорели пять контролей подряд (задача 3.85), и это уже не
  # совпадение, а метод.
  describe "отметка о подтверждённом складывании — на записи, а не на механизме" do
    # Запись, которой нет и никогда не было в `ac_bonuses.json`: прибавка
    # к AC за уровни волшебника, без типа и без отметки. Ни один живой факт
    # её не держит, поэтому правка данных её не «починит».
    defp synthetic(ruleset, fields) do
      record =
        Map.merge(
          %{
            id: :wizard,
            source: {:class, :wizard},
            verdict: :applied,
            type: nil,
            amount: %{kind: :flat, ac: 3},
            scope: nil,
            stacking_confirmed: nil,
            owned_by: nil,
            why: nil,
            affects: nil,
            not_a_gap: nil
          },
          fields
        )

      update_in(ruleset.ac_bonuses.applied, &(&1 ++ [record]))
    end

    @synthetic_mark %{
      "what" => ["складывается со всем, с чем мы её складываем"],
      "why" => "синтетическая запись теста",
      "source" => %{"kind" => "user", "who" => "Dan", "date" => "2026-08-25"},
      "status" => "verified"
    }

    test "прибавка без типа и без отметки приносит оговорку", %{ruleset: ruleset} do
      doctored = synthetic(ruleset, %{})
      stats = Rules.compute(build(List.duplicate(:wizard, 5)), doctored)

      assert {:assumed, :ac_bonus_types_unstated} in stats.gaps

      # ...и она действительно посчитана: оговорка без числа значила бы, что
      # тест поймал не тот механизм.
      assert Keyword.fetch!(terms(stats), :wizard) == 3
    end

    test "та же запись с отметкой оговорки не приносит", %{ruleset: ruleset} do
      doctored = synthetic(ruleset, %{stacking_confirmed: @synthetic_mark})
      stats = Rules.compute(build(List.duplicate(:wizard, 5)), doctored)

      refute {:assumed, :ac_bonus_types_unstated} in stats.gaps
      assert Keyword.fetch!(terms(stats), :wizard) == 3
    end

    # ⚠️ Оговорка живёт на ПОСЧИТАННОЙ прибавке, а не на существовании записи
    # в файле: волшебника в билде нет — терма нет — говорить не о чем.
    test "чужая запись без типа не приносит оговорку тому, кто её не держит", %{
      ruleset: ruleset
    } do
      doctored = synthetic(ruleset, %{})
      stats = Rules.compute(build(List.duplicate(:fighter, 5)), doctored)

      refute {:assumed, :ac_bonus_types_unstated} in stats.gaps
    end

    # 🔴 Главное следствие «отметка на записи»: ОДНА неотмеченная прибавка
    # возвращает оговорку билду, у которого все остальные отмечены. Именно так
    # парсер вернёт её сам, принеся новую прибавку к AC с вики.
    test "одна неотмеченная прибавка возвращает оговорку билду, где всё остальное отмечено",
         %{ruleset: ruleset} do
      # Монах 30 / волшебник 11: три живые прибавки без типа (мудрость,
      # колонка монаха, Кувырок) — все с отметкой, — и синтетическая четвёртая
      # за уровни волшебника, у которой отметки нет.
      build =
        build(List.duplicate(:monk, 30) ++ List.duplicate(:wizard, 11),
          base_abilities: %{@flat | wis: 16},
          skills: for(level <- 1..20, into: %{}, do: {level, %{tumble: 1}})
        )

      clean = Rules.compute(build, ruleset)
      refute {:assumed, :ac_bonus_types_unstated} in clean.gaps
      assert Keyword.keys(terms(clean)) == [:monk_ac_bonus, :monk, :tumble]

      dirty = Rules.compute(build, synthetic(ruleset, %{}))
      assert {:assumed, :ac_bonus_types_unstated} in dirty.gaps

      # ⚠️ И оговорка вернулась ОТ НЕЁ, а не от того, что три остальные вдруг
      # перестали считаться: список термов отличается ровно на одну запись.
      assert Keyword.keys(terms(dirty)) == [:monk_ac_bonus, :monk, :tumble, :wizard]
      assert clean.ac_naked + 3 == dirty.ac_naked
    end

    # И обратная сторона: отметка снимает оговорку и НЕ трогает число. Проверено
    # на всех четырёх живых записях сразу — монах даёт две, Кувырок третью,
    # `Bone skin` четвёртую.
    test "у живых записей отметка стоит, а числа те же", %{ruleset: ruleset} do
      monk =
        build(List.duplicate(:monk, 41),
          base_abilities: %{@flat | wis: 18},
          skills: for(level <- 1..40, into: %{}, do: {level, %{tumble: 1}})
        )

      stats = Rules.compute(monk, ruleset)

      assert terms(stats) == [monk_ac_bonus: 4, monk: 8, tumble: 8]
      assert stats.ac_naked == 30
      refute {:assumed, :ac_bonus_types_unstated} in stats.gaps

      pale = build(List.duplicate(:wizard, 13) ++ List.duplicate(:pale_master, 28))
      pale_stats = Rules.compute(pale, ruleset)

      assert terms(pale_stats) == [bone_skin: 16]
      assert pale_stats.ac_naked == 26
      refute {:assumed, :ac_bonus_types_unstated} in pale_stats.gaps
    end
  end

  describe "монах в доспехах и со щитом теряет ОБА своих бонуса" do
    # 🔴 Два наблюдения Dan, и второе СУЖАЕТ первое, а не отменяет его.
    #
    # 09.08.2026, тестовый сервер (GAME_CHECKS.md, заход C, кейс C4 вместе с его
    # «открытой половиной»): «можно бегать только в робе, которая даёт 0 AC сама
    # по себе … наручи не мешают бонусу. Бонус на AC монаха от мудрости
    # „ломается“, если надеть любой щит, или если надеть любой доспех, который
    # даёт AC» и «Ещё монах получает AC за каждые 5 уровней монаха, этот бонус
    # работает полностью аналогично».
    #
    # 19.08.2026, собственный персонаж Dan (задача 3.59): «бонусы монаха … 
    # отключаются, если надет любой щит или если надеть любой доспех-"не
    # нулевку". Т.е. по сути если доспех не роба, то бонус отключается. У меня
    # как раз надета роба, которая даёт 6ац» и, во втором сообщении, без
    # остатка: «бонусы монаха опираются ИСКЛЮЧИТЕЛЬНО на надетый щит и доспех,
    # числа в "AC по типам" не влияют».
    #
    # ⚠️ Три прочтения в порядке появления: вики говорят про ВИД надетого,
    # замер 09.08 — про AC, которое надетое ДАЁТ, наблюдение 19.08 — про БАЗУ
    # выбранного предмета. Каждое следующее точнее, и последнее стало выразимым
    # только потому, что задача 3.41 сделала надетое предметом: роба Dan даёт
    # 6 AC и бонусов не ломает, то есть по «даёт AC» правило не могло быть
    # верным до конца.
    #
    # Числа буквальные, а не «стало меньше»: монах 5 с WIS 14 (+2) и колонкой
    # таблицы +1 на 5-м уровне класса.
    @monk5_wis14 [base_abilities: %{@flat | wis: 14}]

    test "таблица «предмет против вписанного числа»: буквальные числа", %{ruleset: ruleset} do
      cases = [
        # ничего не надето и ничего не вписано
        {%{}, %{}, 13, 13, [monk_ac_bonus: 2, monk: 1]},
        # роба выбрана предметом: её база 0 — «как раз то что надо»
        {%{armor: :none}, %{}, 13, 13, [monk_ac_bonus: 2, monk: 1]},
        # 🔴 (а) роба + вписанные «Броня 8» (усиление той же робы): 10 + 8 + 3,
        # и оба терма НА МЕСТЕ. До 19.08.2026 здесь было 18 и пустой список —
        # ровно двенадцать очков, потерянных билдом Dan, в миниатюре.
        {%{armor: :none}, %{armor: 8}, 13, 21, [monk_ac_bonus: 2, monk: 1]},
        # ...и то же самое без выбранного предмета вовсе: вписанное число
        # доспехом не является ни при каких условиях
        {%{}, %{armor: 8}, 13, 21, [monk_ac_bonus: 2, monk: 1]},
        # 🔴 (г) вписанный «Щит 4» без выбранного щита: 10 + 4 + 3 = 17,
        # термы целы. Число под типом shield — это бонус, а не надетый щит
        {%{}, %{shield: 4}, 13, 17, [monk_ac_bonus: 2, monk: 1]},
        # 🔴 (б) стёганый доспех ПРЕДМЕТОМ: база 1 — теряются ОБА терма, и ни
        # одного числа игрок не вписывал
        {%{armor: :padded}, %{}, 13, 11, []},
        # латы предметом плюс вписанные 6 сверх: 10 + 8 базы + 6, термов нет
        {%{armor: :full_plate}, %{armor: 6}, 13, 24, []},
        # 🔴 (в) малый щит ПРЕДМЕТОМ: база 1, те же −3
        {%{shield: :small}, %{}, 13, 11, []},
        # и вместе, чтобы условие не оказалось «или/или»
        {%{armor: :padded, shield: :small}, %{}, 13, 12, []}
      ]

      for {worn, ac, naked, geared, own_geared} <- cases do
        stats =
          Rules.compute(
            build(
              List.duplicate(:monk, 5),
              @monk5_wis14 ++ [gear: Gear.new(worn: worn, ac: ac)]
            ),
            ruleset
          )

        label = "надето #{inspect(worn)}, вписано #{inspect(ac)}"

        assert stats.ac_naked == naked, "#{label}: AC голым"
        assert stats.ac_geared == geared, "#{label}: AC в шмоте"

        assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac}) == own_geared,
               "#{label}: собственные термы в шмоте"

        # ⚠️ «Голым» значит голым, и условие там выполнено по построению: список
        # собственных термов БЕЗ вещей одинаков во всех девяти строках.
        assert for(term <- stats.ac_own_terms, do: {term.id, term.ac}) == [
                 monk_ac_bonus: 2,
                 monk: 1
               ],
               "#{label}: AC голым поехал от надетого"
      end
    end

    # 🔴 Контрольный кейс с ЖИВОГО билда Dan, ради которого задача и заведена:
    # монах 33 / Мастер оружия 7 на 40-м уровне, WIS 22, надета роба, а под
    # «Вещами» вписано пять чисел, включая «Броня 6» (усиление той же робы) и
    # «Щит 8». До правки вписанные числа глушили и колонку таблицы класса (+6),
    # и мудрость (+6) — двенадцать очков AC на пустом месте.
    #
    # ⚠️ Билд собран ЛЕВЕЛАПАМИ и проверен `validate_level_up/3` на каждом:
    # список классов, засунутый прямо в `Build.new/1`, валидацию не проходит
    # вовсе, и так уже предлагался невозможный сценарий замера (CLAUDE.md §3).
    # Всё, что здесь не из билда Dan (раса, мировоззрение, лишние
    # характеристики, порядок фитов и Устрашение 4), — минимальная законная
    # обвязка, чтобы Мастер оружия открылся; AC она не двигает ничем.
    test "живой билд Dan: монах 33 / Мастер оружия 7 в робе получает свои 12 очков", %{
      ruleset: ruleset
    } do
      levels = List.duplicate(:monk, 33) ++ List.duplicate(:weapon_master, 7)

      dan =
        Build.new(
          race: :human,
          alignment: :lawful_good,
          levels: levels,
          base_abilities: %{str: 10, dex: 13, con: 10, int: 13, wis: 22, cha: 10},
          # Требования Мастера оружия: шесть фитов, Устрашение 4 и BAB 5.
          # Человеку хватает общих слотов 1/3/6/9/12 плюс расового на 1-м.
          feats: %{
            1 => %{general: :dodge, racial: :expertise},
            3 => %{general: :mobility},
            6 => %{general: :spring_attack},
            9 => %{general: :whirlwind_attack},
            12 => %{general: {:weapon_focus, :kama}}
          },
          skills: for(level <- 2..5, into: %{}, do: {level, %{intimidate: 1}}),
          gear:
            Gear.new(
              ac: %{armor: 6, shield: 8, natural: 5, dodge: 6, deflection: 5},
              worn: %{armor: :none}
            )
        )

      refused =
        for {class, level} <- Enum.with_index(dan.levels, 1),
            before = Build.truncate(dan, level - 1),
            {:error, reasons} <- [Rules.validate_level_up(before, class, ruleset)],
            do: {level, class, reasons}

      assert refused == []

      stats = Rules.compute(dan, ruleset)

      # WIS 22 → +6, монах 33 → ступень 30 таблицы класса → +6.
      assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac}) == [
               monk_ac_bonus: 6,
               monk: 6
             ]

      # 10 базы + 1 ловкости + 12 своих + 30 вписанного (6 + 8 + 5 + 6 + 5).
      # До правки здесь было 41.
      assert stats.ac_geared == 53
      assert stats.ac_naked == 23
    end

    # 🔴 Ловушка, ради которой кейс и заведён отдельно: щитовой AC Карлика — это
    # РАСОВЫЙ бонус Сиалы (задача 3.12) типа `shield`, а не надетый щит. Правило,
    # читающее итоговую сумму по типу, отобрало бы у гнома-монаха его бонусы
    # просто за то, что он гном.
    #
    # ⚠️ 40-й уровень, а не любой: ниже 40-го расовый бонус неизвестен и терма
    # не будет вовсе, то есть на монахе 5 ловушка не воспроизводится.
    #
    # ⚠️ **Меч в руках — условие самого расового бонуса** (замер Dan 15.08.2026,
    # `GAME_CHECKS.md` Q1/Q4): без оружия терма нет вовсе, и ловушка не
    # воспроизводится. Меч монаху бонусов не ломает — их ломает НАДЕТОЕ, дающее
    # AC, а не то, что в руках.
    #
    # 🔴 **И с задачи 3.35 ловушка стала ДВОЙНОЙ: щитовых терма два.** Клинковое
    # оружие само даёт щитовой AC (+6), причём кому угодно, независимо от расы, —
    # то есть у Карлика с мечом рядом стоят `gnome` и `longsword`, оба типа
    # `shield`. Правило монаха обязано не заметить ни того, ни другого: оно
    # смотрит на ВЫБРАННЫЙ ПРЕДМЕТ (`Worn.base_ac/2`), а не на сумму по типу и
    # не на вписанное число.
    #
    # ⚠️ Поэтому проверяется список «в шмоте»: голое число считается по билду
    # с пустыми вещами (`Rules.compute/2` гоняет голый проход по `%Gear{}`),
    # то есть и без оружия, — а значит расового щита там нет и быть не должно.
    test "Карлик-монах 40 с мечом: расовый щит бонусов монаха не ломает", %{ruleset: ruleset} do
      armed = Gear.new(weapon: :longsword, feats: [:siala_blade_proficiency])

      stats =
        Rules.compute(
          build(List.duplicate(:monk, 40), [race: :gnome, gear: armed] ++ @monk5_wis14),
          ruleset
        )

      # ⚠️ До задачи 3.143 (30.08.2026) здесь стоял ещё `{:small_stature, :size,
      # 1}` между `monk` и `gnome`: applied по обрезанной цитате, теперь
      # not_modelled — своего терма не даёт вовсе.
      assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.type, term.ac}) == [
               {:monk_ac_bonus, nil, 2},
               {:monk, nil, 8},
               {:gnome, :shield, 6},
               {:longsword, :shield, 6}
             ]

      # Голым ни расового, ни оружейного щита нет — оружие это вещь:
      # 10 + 2 + 8 = 20.
      assert stats.ac_naked == 20

      # В шмоте есть оба, и бонусы монаха при этом целы: 20 + 6 + 6.
      assert stats.ac_geared == 32

      # ⚠️ И оба щитовых бонуса — от расы и от типа оружия — с базовым числом,
      # а не сагровским: билд из монахов в группу Сагры не входит.
      assert stats.gaps |> Enum.filter(&match?({_, {:weapon_type_bonus_level, _}}, &1)) == []

      # 🔴 Отрицательный контроль, ставший таким 19.08.2026: тот же Карлик-монах
      # с ВПИСАННЫМ «Щит 4» бонусы монаха сохраняет — число под типом это бонус,
      # а не надетый щит. До правки здесь стоял `assert` на пустой список своих
      # монашеских термов, и это было ровно то, что съедало 12 очков у билда Dan.
      typed =
        Rules.compute(
          build(
            List.duplicate(:monk, 40),
            [
              race: :gnome,
              gear:
                Gear.new(
                  ac: %{shield: 4},
                  weapon: :longsword,
                  feats: [:siala_blade_proficiency]
                )
            ] ++ @monk5_wis14
          ),
          ruleset
        )

      assert for(term <- typed.ac_own_terms_geared, do: {term.id, term.ac}) == [
               monk_ac_bonus: 2,
               monk: 8,
               gnome: 6,
               longsword: 6
             ]

      # 🔴 Правило задачи 3.39 при этом не тронуто: 10 + 10 монашеских + 12
      # своего щитового (6 расового + 6 за клинок), а вписанные 4 в число НЕ
      # идут — своё больше, берётся большее. До 19.08.2026 здесь было 23, потому
      # что монашеские десять отбирались вписанной четвёркой; до 30.08.2026
      # (задача 3.143) — 33, потому что складывался ещё размерный терм.
      assert typed.ac_geared == 32
      assert typed.ac_superseded_types == [:shield]
      refute {:not_modelled, {:ac_gear_base, :shield}} in typed.gaps

      # ⚠️ Положительный контроль: тот же Карлик-монах, надевший щит ПРЕДМЕТОМ,
      # бонусы монаха теряет — то есть правило работает и отличает расовое от
      # надетого, а не выключено вовсе.
      #
      # ⚠️ Меч здесь КОРОТКИЙ, а не длинный (задача 3.43): длинный для Карлика
      # двуручен, и щит рядом с ним был бы ОТБИТ, а не надет, — то есть контроль
      # проверял бы запрет вместо условия. Группа владения та же (blade), число
      # за тип оружия то же +6, меч в руках остаётся обязательным: без него не
      # было бы и расового терма.
      worn =
        Rules.compute(
          build(
            List.duplicate(:monk, 40),
            [
              race: :gnome,
              gear:
                Gear.new(
                  worn: %{shield: :small},
                  weapon: :shortsword,
                  feats: [:siala_blade_proficiency]
                )
            ] ++ @monk5_wis14
          ),
          ruleset
        )

      assert for(term <- worn.ac_own_terms_geared, do: {term.id, term.ac}) == [
               gnome: 6,
               shortsword: 6
             ]

      # 10 + 12 своего щитового + 1 база малого щита (база всегда складывается
      # поверх победителя, задача 3.41). ⚠️ Было 24 (с +1 размера) до задачи
      # 3.143 (30.08.2026).
      assert worn.ac_geared == 23
    end

    # Мудрость с вещей и условие — две разные механики, и обе обязаны работать
    # одновременно: `+12 WIS` с предмета даёт +6 к AC монаха, а надетый доспех
    # отбирает всё вместе с прибавкой.
    #
    # ⚠️ Доспех здесь ПРЕДМЕТ (латы, база 8), а не вписанные «Броня 8»: с
    # 19.08.2026 число условия не нарушает. Число получилось то же самое, и это
    # не совпадение — база лат равна той цифре, которую тест вписывал раньше.
    test "мудрость с вещей поднимает бонус, доспех отбирает его целиком", %{ruleset: ruleset} do
      levels = List.duplicate(:monk, 5)

      with_wis =
        Rules.compute(
          build(levels, @monk5_wis14 ++ [gear: Gear.new(abilities: %{wis: 12})]),
          ruleset
        )

      # 10 + (2 + 6) мудрости с вещей + 1 колонка
      assert with_wis.ac_geared == 19
      assert with_wis.ac_own_bonus_geared == 9

      and_armor =
        Rules.compute(
          build(
            levels,
            @monk5_wis14 ++
              [gear: Gear.new(abilities: %{wis: 12}, worn: %{armor: :full_plate})]
          ),
          ruleset
        )

      assert and_armor.ac_own_bonus_geared == 0
      assert and_armor.ac_geared == 18
    end

    # Условие принадлежит записи, а не классу: у Кувырка его нет, значит
    # доспех его не задевает. Иначе «монах в броне» читалось бы как «в броне
    # не работает ничего».
    #
    # ⚠️ Доспех ПРЕДМЕТОМ (латы), а не вписанным числом: с 19.08.2026 условие
    # смотрит на базу выбранного предмета.
    #
    # ⚠️ До задачи 3.143 (30.08.2026) заголовок называл ещё «и размерный
    # бонус», а список — `[tumble: 1, small_stature: 1]`: Карлик демонстрировал
    # заодно, что доспех не трогает и `Small stature`. Small stature стал
    # `not_modelled` безусловно (не из-за доспеха — из-за противника, которого
    # билд не описывает), своего терма не даёт ни в каком доспехе, и
    # демонстрировать здесь стало нечего — эта половина теста ушла вместе
    # с записью, а не потому что правило про доспех перестало быть верным.
    test "доспех не трогает Кувырок", %{ruleset: ruleset} do
      build =
        build(List.duplicate(:monk, 5),
          race: :gnome,
          skills: ranks(:tumble, 5),
          gear: Gear.new(worn: %{armor: :full_plate})
        )

      stats = Rules.compute(build, ruleset)

      assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac}) == [
               tumble: 1
             ]
    end
  end

  # 🔴 Задачи 3.39 и 3.91. Правило от Dan, 16.08.2026, дословно: «а вот с АЦ
  # щитовым с вещей это не складывается, только с базой щита. Вообще никакое АЦ
  # не складывается, когда дело касается вещей, всегда берется максимальное,
  # за исключением dodge АЦ, оно складывается, но имеет кап 20».
  #
  # 🔴 Вторая фраза оказалась ШИРЕ, чем её источник, и 25.08.2026 тот же
  # человек её сузил: «обычно не стакаются АЦ с вещей и баффов, там берется
  # максимальный. АЦ с фитов всегда стакаются все». То есть максимум остался
  # ровно у того бонуса, про который говорила ПЕРВАЯ фраза, — расового щитового
  # AC Карлика и его оружейного близнеца: «раса карлика работает немного
  # по-другому и перекрывает бонус щита (не базу щита(1/2/3), а именно бонус)».
  #
  # ⚠️ Части правила разной природы, и каждая под своим тестом: своё со своим
  # складывается (замер E5 и страница «Расы»), фит с вписанным складывается
  # (describe выше), сиальский щитовой бонус с вписанным — максимум (здесь),
  # уклонение — исключение с одним клипом (ниже).
  describe "вписанное с вещей против сиальского щитового: максимум" do
    # Билд приёмки: Карлик 40 чистым воином (то есть сагровик — расовый бонус
    # берётся сагровским, +9), клинковое оружие в руках, щит 4 в «Вещах».
    defp gnome_sagra(ac) do
      Build.new(
        levels: List.duplicate(:fighter, 40),
        base_abilities: @flat,
        race: :gnome,
        gear: Gear.new(ac: ac, weapon: :katana, feats: [:siala_blade_proficiency])
      )
    end

    test "щитового становится 18 (раса 9 + оружие 9), вписанные 4 проигрывают", %{
      ruleset: ruleset
    } do
      stats = Rules.compute(gnome_sagra(%{shield: 4}), ruleset)

      # ⚠️ До задачи 3.143 (30.08.2026) тут стоял ещё `{:small_stature, :size,
      # 1}` перед `gnome`: applied по обрезанной цитате, теперь not_modelled.
      assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.type, term.ac}) == [
               {:gnome, :shield, 9},
               {:katana, :shield, 9}
             ]

      # 10 базы + 18 щитового. До задачи 3.39 здесь было 33: вписанные 4
      # прибавлялись сверху, то есть щитового выходило 22. До 3.143 — 29,
      # с размерным термом Карлика.
      assert stats.ac_geared == 28
      assert stats.ac_by_type[:shield] == 0
      assert stats.ac_superseded_types == [:shield]

      # ⚠️ Введённое число при этом не потеряно: игрок обязан узнать его
      # обратно, и «AC в шмоте» не должен схлопнуться в «?».
      assert stats.ac_gear_bonus == 4

      # ⚠️ Здесь стояла оговорка «базу щита (1/2/3) из одного введённого числа
      # не вычесть». Задача 3.41 сделала щит предметом с размером — база
      # известна, оговорка снята (см. describe «надетое» ниже).
      refute {:not_modelled, {:ac_gear_base, :shield}} in stats.gaps
    end

    test "вписанные 20 выигрывают, и собственные 18 в число не идут", %{ruleset: ruleset} do
      stats = Rules.compute(gnome_sagra(%{shield: 20}), ruleset)

      # Своих термов в «шмоте» нет вовсе: щитовые перебило надетым, а
      # размерного (`small_stature`) с задачи 3.143 (30.08.2026) не бывает
      # ни при каком раскладе — applied по обрезанной цитате, теперь
      # not_modelled.
      assert for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac}) == []

      # 10 базы + 20 вписанного, а не 20 + 18. Было 31 (с размерным термом)
      # до задачи 3.143.
      assert stats.ac_geared == 30
      assert stats.ac_by_type[:shield] == 20
      assert stats.ac_superseded_types == []
      refute {:not_modelled, {:ac_gear_base, :shield}} in stats.gaps
    end

    # ⚠️ Отрицательный контроль ко всему describe: голое число не задето ни на
    # одном из билдов. Оно считается по билду с пустыми вещами, то есть
    # конкурировать там не с чем — но проверить это надо, а не предположить.
    test "ac_naked не меняется ни от вписанного, ни от его величины", %{ruleset: ruleset} do
      for ac <- [%{}, %{shield: 4}, %{shield: 20}, %{shield: 4, natural: 8}] do
        stats = Rules.compute(gnome_sagra(ac), ruleset)

        # ⚠️ 10, а не 11 — задача 3.143 (30.08.2026) сняла размерный терм
        # Карлика (`small_stature` стал not_modelled), own_terms пуст всегда.
        assert stats.ac_naked == 10, "#{inspect(ac)}: голое число поехало"
        assert for(term <- stats.ac_own_terms, do: {term.id, term.ac}) == []
      end
    end

    # Тип, на котором столкновения нет, проходит как проходил: разные типы
    # складываются между собой, и правило про максимум их не касается.
    #
    # ⚠️ Оговорка про базу с задачи 3.41 висит только на типах, под которые
    # игрок НЕ выбирает предмет: у щита база известна, у отклонения — нет.
    # Здесь столкновение ровно на щите, значит список пуст.
    test "разные типы складываются, и оговорка про базу висит только там, где предмета нет", %{
      ruleset: ruleset
    } do
      stats = Rules.compute(gnome_sagra(%{shield: 4, deflection: 5}), ruleset)

      # 10 + 18 щитового + 5 отклонения. Было 34 (с +1 размера) до задачи
      # 3.143 (30.08.2026).
      assert stats.ac_geared == 33
      assert stats.ac_by_type[:deflection] == 5

      assert Enum.filter(stats.gaps, &match?({_, {:ac_gear_base, _}}, &1)) == []

      # 🔴 И ПРИРОДНЫЙ тип у того же билда оговорки тоже не приносит — с задачи
      # 3.91 фит с вписанным числом не состязается вовсе, значит терять нечего.
      # ⚠️ Здесь стояло обратное: `Armor skin` в слоте против вписанных 5
      # давал `{:not_modelled, {:ac_gear_base, :natural}}`, и это была честная
      # оговорка при честном тогда правиле. Ушло правило — ушла оговорка.
      %Build{} = base = gnome_sagra(%{shield: 4, natural: 5})
      natural = Rules.compute(%Build{base | feats: %{1 => %{general: :armor_skin}}}, ruleset)

      assert Enum.filter(natural.gaps, &match?({_, {:ac_gear_base, _}}, &1)) == []

      # 🔴 И числом, а не только оговоркой: на ОДНОМ билде два типа ведут себя
      # по-разному. Щитовой — состязание (18 своих против 4 вписанных, вписанное
      # не доехало), природный — сумма (2 фита + 5 вписанных). Это и есть
      # проверка того, что расовое исключение не расползлось обратно на фиты.
      assert natural.ac_by_type[:shield] == 0
      assert natural.ac_by_type[:natural] == 5
      assert natural.ac_superseded_types == [:shield]

      # 10 базы + 18 щитового + 2 Armor skin + 5 вписанного природного.
      # Было 36 (с +1 размера) до задачи 3.143 (30.08.2026).
      assert natural.ac_geared == 35

      # ⚠️ Положительный контроль к строке выше: оговорка не «выключена
      # навсегда», а не срабатывает, потому что состязания не было. Механизм
      # жив — тот же билд с конкурирующим видом на типе БЕЗ предмета его
      # печатает. Вид объявляется ruleset'ом, поэтому подменяется он, а не код.
      competing =
        ruleset
        |> put_in([Access.key!(:gear), :ac_same_type, :gear], :max)
        |> put_in([Access.key!(:gear), :ac_same_type, :gear_by_kind], %{})

      contested = Rules.compute(%Build{base | feats: %{1 => %{general: :armor_skin}}}, competing)

      assert {:not_modelled, {:ac_gear_base, :natural}} in contested.gaps
    end

    # ⚠️ Штраф не конкурирует: правило сформулировано про бонусы, пола не
    # называет ни один источник, и `max/2` съел бы введённый минус целиком.
    test "вписанный минус не съедается максимумом, а вычитается", %{ruleset: ruleset} do
      stats = Rules.compute(gnome_sagra(%{shield: -3}), ruleset)

      # 10 + (18 − 3). Было 26 (с +1 размера) до задачи 3.143 (30.08.2026).
      assert stats.ac_geared == 25
      assert stats.ac_by_type[:shield] == -3
      assert Enum.filter(stats.gaps, &match?({_, {:ac_gear_base, _}}, &1)) == []
    end
  end

  describe "уклонение — исключение: складывается, и клип один на сумму" do
    # ⚠️ Прибавок типа `dodge` в данных нет ни одной: все шесть источников,
    # которые называют это слово, условные и лежат в `not_modelled`. Поэтому
    # правило проверяется на подменённом ruleset'е — тот же приём, что у
    # незнакомой формы условия выше. Механизм от этого не становится мёртвым:
    # он держит решение `_dodge_cap_decision` («потолок принадлежит ТИПУ, а не
    # полю ввода») на тот день, когда такая запись появится.
    defp with_dodge(ruleset, ac) do
      update_in(ruleset.ac_bonuses.applied, fn records ->
        for record <- records do
          if record.id == :armor_skin,
            do: %{record | type: :dodge, amount: %{kind: :flat, ac: ac}},
            else: record
        end
      end)
    end

    defp dodging(gear), do: build([:fighter], feats: %{1 => %{general: :armor_skin}}, gear: gear)

    test "собственное и вписанное складываются, а не конкурируют", %{ruleset: ruleset} do
      stats = Rules.compute(dodging(Gear.new(ac: %{dodge: 5})), with_dodge(ruleset, 4))

      # 10 + 4 своего + 5 вписанного — сумма, потому что тип объявлен
      # складывающимся (`gear.ac_types.same_type.cumulative_types`).
      assert stats.ac_geared == 19
      assert stats.ac_by_type[:dodge] == 5
      assert stats.ac_capped_types == []

      # ⚠️ И оговорки про базу здесь нет: столкновения не было, был сложение.
      assert Enum.filter(stats.gaps, &match?({_, {:ac_gear_base, _}}, &1)) == []
    end

    test "потолок +20 режет СУММУ, а не каждую половину", %{ruleset: ruleset} do
      cap = Caps.cap(ruleset, :dodge_ac)
      stats = Rules.compute(dodging(Gear.new(ac: %{dodge: 18})), with_dodge(ruleset, 5))

      # 5 своего + 18 вписанных = 23, потолок 20 → 10 + 20.
      # 🔴 Клип по половинке дал бы 10 + 5 + 18 = 33: ровно та ошибка,
      # которой однажды болели сейвы (+40 при потолке +20).
      assert stats.ac_geared == 10 + cap
      assert stats.ac_capped_types == [:dodge]
      assert :gear_ac in stats.capped

      # Собственная сторона считается первой, вписанное добирает остаток —
      # и разбор сходится с числом: 10 + 5 + 15.
      assert stats.ac_by_type[:dodge] == 15
      assert stats.ac_own_bonus_geared == 5
      assert stats.ac_cap_clipped == 0
    end

    # ⚠️ Единственный случай, когда потолок режет СОБСТВЕННУЮ сторону: её
    # одной хватило, чтобы его пробить. Тогда потеря обязана лежать отдельным
    # числом, иначе разбор (термы печатаются как есть) перестанет сходиться
    # со своим итогом — та же форма, что `attack_cap_clipped`.
    test "своё сверх потолка режется, и срез назван отдельным числом", %{ruleset: ruleset} do
      stats = Rules.compute(dodging(Gear.new()), with_dodge(ruleset, 25))

      assert stats.ac_geared == 10 + Caps.cap(ruleset, :dodge_ac)
      assert stats.ac_own_bonus_geared == 25
      assert stats.ac_cap_clipped == -5
      assert stats.ac_capped_types == [:dodge]
    end

    # 🔴 Порядок двух исключений: складывающийся ТИП сильнее конкурирующего
    # ВИДА (задача 3.91). «Ну dodge АЦ еще стакается до капа в 20» сказано без
    # оговорок про источник, поэтому вид, объявленный конкурирующим, внутри
    # такого типа всё равно складывается.
    #
    # ⚠️ Проверяется подменой ruleset'а с двух концов сразу: тип, на котором
    # живёт сиальский щитовой бонус, объявляется складывающимся. Своих
    # `dodge`-прибавок в данных нет, а конкурирующий вид типа `dodge` завести
    # нельзя вовсе — вид приходит из сиальского слоя вместе со своим типом.
    test "объявленный складывающимся тип сильнее конкурирующего вида", %{ruleset: ruleset} do
      cumulative_shield =
        update_in(ruleset.gear.ac_same_type.cumulative, &[:shield | &1])

      build =
        Build.new(
          levels: List.duplicate(:fighter, 40),
          base_abilities: @flat,
          race: :gnome,
          gear: Gear.new(ac: %{shield: 4}, weapon: :katana, feats: [:siala_blade_proficiency])
        )

      contested = Rules.compute(build, ruleset)
      cumulative = Rules.compute(build, cumulative_shield)

      # Как есть: 10 + 18 щитового, вписанные 4 проиграли. Было 29 (с +1
      # размера) до задачи 3.143 (30.08.2026).
      assert contested.ac_geared == 28
      assert contested.ac_superseded_types == [:shield]

      # А объявленный складывающимся тип берёт обе стороны: 28 + 4.
      assert cumulative.ac_geared == 32
      assert cumulative.ac_by_type[:shield] == 4
      assert cumulative.ac_superseded_types == []
    end
  end

  describe "граничные уровни и мультикласс" do
    # 1, 20/21 и кап 41 — плюс билд из четырёх классов, каждый со своим
    # источником AC.
    test "четыре класса приносят четыре разных источника", %{ruleset: ruleset} do
      levels =
        List.duplicate(:monk, 10) ++
          List.duplicate(:wizard, 5) ++
          List.duplicate(:pale_master, 20) ++ List.duplicate(:red_dragon_disciple, 6)

      build =
        build(levels,
          race: :gnome,
          base_abilities: %{@flat | wis: 14},
          skills: ranks(:tumble, 10)
        )

      stats = Rules.compute(build, ruleset)

      assert stats.character_level == 41
      assert map_size(stats.class_levels) == 4

      # монах 10 → мудрость +2 и колонка +2; Бледный мастер 20 → +12;
      # РДД 6 → +2; 10 рангов Кувырка → +2.
      #
      # ⚠️ Седьмого источника — щитового AC расы Карлика — в ГОЛОМ списке нет,
      # и это правка 15.08.2026, а не потеря: бонус включается оружием в руках
      # (замер Dan, `GAME_CHECKS.md` Q1/Q4), а голое число считается по билду
      # с пустыми вещами. Он появляется в «шмоте», как только меч взят, —
      # проверено сразу под списком.
      #
      # ⚠️ До задачи 3.143 (30.08.2026) здесь был ещё `small_stature: 1`
      # (Карлик → +1 за размер): applied по обрезанной цитате, теперь
      # not_modelled.
      assert terms(stats) == [
               monk_ac_bonus: 2,
               monk: 2,
               bone_skin: 12,
               draconic_armor: 2,
               tumble: 2
             ]

      armed =
        Rules.compute(
          %Build{build | gear: Gear.new(weapon: :longsword, feats: [:siala_blade_proficiency])},
          ruleset
        )

      # ⚠️ Седьмой источник (был восьмым до задачи 3.143) — щитовой AC за
      # КЛИНКОВОЕ оружие в руках (задача 3.35). Он не расовый: тот же +6
      # получил бы любой билд с мечом, и рядом с расовым он стоит отдельной
      # строкой ровно потому, что это два разных терма одной системы, а не
      # одно число, напечатанное дважды.
      assert for(term <- armed.ac_own_terms_geared, do: {term.id, term.ac}) == [
               monk_ac_bonus: 2,
               monk: 2,
               bone_skin: 12,
               draconic_armor: 2,
               tumble: 2,
               gnome: 6,
               longsword: 6
             ]

      # Голое число — без расового щита: 10 базы + 2 + 2 + 12 + 2 + 2.
      # Было `10 + 21` (с +1 размера) до задачи 3.143.
      assert stats.ac_naked == 10 + 20

      # И с мечом оно не меняется: голое значит голое, оружие едет в «шмоте».
      assert armed.ac_naked == 10 + 20

      # А в «шмоте» щитовых бонуса ДВА: расовый Карлика и оружейный за клинок.
      assert armed.ac_geared == 10 + 20 + 6 + 6
    end

    test "на 1-м и на 41-м уровне чистый воин остаётся при базовом AC", %{ruleset: ruleset} do
      for level <- [1, 20, 21, 41] do
        stats = Rules.compute(build(List.duplicate(:fighter, level)), ruleset)

        assert stats.ac_naked == 10
        assert stats.ac_own_terms == []
      end
    end
  end

  describe "дельта" do
    # Дельта — разность двух полных `compute`, отдельного пути нет. Уровень,
    # на котором открывается ступень, обязан быть виден именно как разность.
    test "пятый уровень монаха стоит ровно +1 AC", %{ruleset: ruleset} do
      before = Rules.compute(build(List.duplicate(:monk, 4)), ruleset)
      later = Rules.compute(build(List.duplicate(:monk, 5)), ruleset)

      assert later.ac_naked - before.ac_naked == 1
    end

    # А четвёртый — ровно модификатор мудрости, потому что на нём Сиала
    # выдаёт фит.
    test "четвёртый уровень монаха стоит ровно модификатор мудрости", %{ruleset: ruleset} do
      abilities = %{@flat | wis: 18}
      before = Rules.compute(build(List.duplicate(:monk, 3), base_abilities: abilities), ruleset)
      later = Rules.compute(build(List.duplicate(:monk, 4), base_abilities: abilities), ruleset)

      assert later.ac_naked - before.ac_naked == 4
    end
  end
end
