defmodule BuildCalculator.Rules.WeaponTypeBonusTest do
  @moduledoc """
  Бонус Сиалы за ТИП оружия в руках (задача 3.35) — таблица кейсов по одному
  источнику: `Система оружия`, revid 20527, перенесена в
  `priv/rules/siala_41/systems.json` → `weapon_system`.

  | тип оружия      | бонус                 | base | сагровик | наш получатель |
  |-----------------|-----------------------|------|----------|----------------|
  | клинковое       | щитовой AC            |   +6 |       +9 | AC типа shield |
  | древковое       | Дисциплина            |  +12 |      +18 | значение навыка|
  | дальнего боя    | к атаке               |   +6 |       +9 | AB, кап +20    |
  | топоры          | поглощение урона      |  +12 |      +18 | **нет**        |
  | молоты          | урон звуком           |   +6 |       +9 | **нет**        |
  | щиты            | иммунитет к физ.урону|  18 %|     36 % | **нет**        |

  ⚠️ **Три вида из шести получателя не имеют, и это НЕ гэп** — по правилу
  CLAUDE.md §9 калькулятор про урон и поглощение ответа не даёт вовсе, значит и
  дырки там нет (Dan, 16.08.2026: «мы поглоты не отображаем, так что нам на этот
  бонус пока что всё равно»). Проверяется положительным контролем ниже: билд
  с топором молчит про свой бонус, а не жалуется на него.

  ⚠️ **Числа верны ровно для 40-го уровня**, ниже — гэп. То же правило и по той
  же причине, что у расового бонуса: функции роста нет ни на одной странице,
  а добывать её решено не надо (решение Dan 15.08.2026, `GAME_CHECKS.md` Q2).

  ⚠️ **Бонус НЕ функция группы владения.** Восемь предметов страница описывает
  поимённо, и их таблица ПЕРЕКРЫВАЕТ правило «группа → бонус»: алебарда даёт и
  Дисциплину, и щитовой AC; великий топор — щитовой AC, не будучи клинковым;
  у двулезвийного меча щитовой AC зафиксирован на +9 и сагровику не удваивается.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, WeaponTypeBonus}

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  # Какой фит владения нужен каждому оружию — берём все пять сразу: кейсы этого
  # файла про бонус, а не про допуск к оружию (это `gear_weapon_test.exs`), и
  # отказ по владению превратил бы половину из них в ложно-зелёные нули.
  @proficiencies [
    :siala_blade_proficiency,
    :siala_polearm_proficiency,
    :siala_ranged_proficiency,
    :siala_axe_proficiency,
    :siala_hammer_proficiency
  ]

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "замер Dan 15.08.2026 (GAME_CHECKS.md, кейс Q1)" do
    # 🔴 ГЛАВНЫЙ КЕЙС ЗАДАЧИ. Три числа одного персонажа, каждое разложено самим
    # Dan: светлый эльф-сагровик 40, DEX 28 (мод +9), STR 8 (мод −1).
    #
    #   пусто в руках — 29 = 30 БАБ − 1 сила
    #   меч +5        — 43 = 30 − 1 + 5 меч + 9 эльф
    #   лук +5        — 59 = 30 + 9 ловкость + СРЕЗ 20 из (5 лук + 9 эльф + 9 ТИП)
    #                     (лист игры показывал 62 — несрезанную сумму; см. ниже)
    #
    # ⚠️ Все три в одном тесте намеренно: два первых — это положительный
    # контроль к третьему. Правка, которая начислила бы бонус за тип оружия
    # кому попало, сломала бы строку с мечом (клинок даёт AC, а не атаку), а
    # правка, начислившая бы его без оружия, — строку «голым».
    # ✅ ОТЛОЖЕННОСТЬ СНЯТА 24.08.2026 ЗАМЕРОМ ИЗ БОЕВОГО ЛОГА (кейс Q5b).
    # Число третьей строки правлено 62 → **59**, и вот на каком основании.
    #
    # Тест был отложен 18.08.2026 по указанию Dan: он решил, что attack bonus
    # оружия ВНУТРИ капа +20 («инфа 100%»), данные исправили, и модель стала
    # давать 59 против наблюдавшихся в ЛИСТЕ 62. Спор держали открытым, а тест
    # не переписывали под модель: 62 наблюдалось в игре, и подгонять его значило
    # бы стереть единственное свидетельство.
    #
    # 🔴 Свидетельство оказалось ЛОЖНЫМ, и это свойство источника, а не числа.
    # Dan 24.08.2026: «в логе на 3 меньше, 62 лист → 59 лог. Лог всегда вернее
    # чарлиста, поэтому 59 это верная цифра и у нас должна быть она».
    #
    # ⚠️ Подтвердилось не только число, но и СОСТАВ капа: разница ровно 3 —
    # то есть игра режет 5 (лук) + 9 (расовый) + 9 (группа оружия) = 23 до 20
    # тем же одним клипом, что и мы. Значит решение Dan от 18.08 было верным,
    # а замер Q5 от 15.08, объявивший оружие ВНЕ капа, стоял на том же
    # завышенном листе — и переоткрывать его больше не нужно.
    #
    # 🔴 Урок про ранг источников: «игрок наблюдал в игре» (CLAUDE.md §3) — это
    # не один источник, а два, и они разного качества. Лист персонажа и боевой
    # лог разошлись на 3, и верен лог. Замер, снятый с листа, слабее замера,
    # снятого с лога, — впервые в проекте это различие оказалось решающим.
    #
    # ⚠️ Первые два числа (голым 29, с мечом 43) капа не касаются вовсе
    # и верны при любом исходе — они лежат в этом же тесте как положительный
    # контроль к третьему, и разносить их значило бы потерять смысл связки.
    test "три числа одного персонажа сходятся до единицы", %{ruleset: ruleset} do
      naked = archer(ruleset, nil)
      sword = archer(ruleset, :longsword)
      bow = archer(ruleset, :longbow)

      assert naked.attack_bonus == 29
      assert sword.attack_bonus == 43
      assert bow.attack_bonus == 59

      # и разложение третьего числа — по слагаемым, а не «сошлось же»
      assert bow.base_attack == 30
      assert bow.attack_ability == :dex
      assert bow.ability_modifiers.dex == 9
      assert bow.weapon_attack_bonus == 5
      assert bow.race_attack_bonus == 9
      assert bow.weapon_type_attack_bonus == 9
    end

    # ⚠️ Половина замера, ради которой заведён отдельный тест: расовый бонус и
    # бонус за тип оружия — ДВА НЕЗАВИСИМЫХ ТЕРМА. У лука они складываются
    # (9 + 9), у меча работает только расовый (9 + 0), потому что клинковый
    # бонус ложится в AC, а не в атаку.
    test "расовый и оружейный — два терма, а не один", %{ruleset: ruleset} do
      bow = archer(ruleset, :longbow)
      sword = archer(ruleset, :longsword)

      assert {bow.race_attack_bonus, bow.weapon_type_attack_bonus} == {9, 9}
      assert {sword.race_attack_bonus, sword.weapon_type_attack_bonus} == {9, 0}
    end

    # 🔴 Следствие, которое обязано проверяться АРИФМЕТИКОЙ, а не отдельным
    # правилом: варианты расового бонуса `racial_weapon` и
    # `racial_weapon_and_sagra_warrior` — это СУММЫ двух термов. Заведи кто-нибудь
    # третье чтение «надето расовое оружие» в `Rules.RacialBonus`, и каждый
    # светлый эльф с луком получил бы бонус дважды; этот тест — сторож ровно на
    # такую правку.
    #
    # ⚠️ Проверяется на всех трёх расах с посчитанным видом бонуса и в обеих
    # вариантах чистоты — на одной расе совпадение могло бы быть случайным.
    test "варианты racial_weapon получаются суммой, а не отдельным правилом", %{ruleset: ruleset} do
      table = [
        {:half_elf, :longbow, :attack_bonus},
        {:gnome, :longsword, :shield_ac},
        {:human, :spear, :skill_bonus}
      ]

      # ⚠️ Ранги нужны не сами по себе: панель печатает только те навыки, во что
      # билд вложился, и без единого ранга Дисциплины строка Человека просто
      # не появилась бы — а кейс зеленел бы на нуле.
      for {race, weapon, kind} <- table do
        pure = Rules.compute(build(race, 40, weapon, ranks: 4), ruleset)
        mixed = Rules.compute(build(race, 40, weapon, ranks: 4, impure?: true), ruleset)

        variants = pure.racial_bonus.variants

        assert pure.racial_bonus.counted + counted(pure, kind) ==
                 variants.racial_weapon_and_sagra_warrior,
               "#{race}: сагровик"

        assert mixed.racial_bonus.counted + counted(mixed, kind) == variants.racial_weapon,
               "#{race}: не сагровик"
      end
    end
  end

  describe "кап атаки +20" do
    # ⚠️ **Кап кусает: под ним ТРИ источника, а не два.** Расовый бонус +9,
    # бонус за тип оружия +9 и число самого предмета +5 — это 23 из 20,
    # срез на 3.
    #
    # 🔴 Здесь стояло «9 + 9 = 18 из 20 — не срезано»: числа предмета лежали
    # СНАРУЖИ капа по замеру Q5 (15.08.2026). 18.08.2026 Dan решил обратное
    # («нам на 100% надо attack bonus засунуть внутрь капа 20»), и спор с его
    # же замером держали открытым.
    #
    # ✅ ЗАКРЫТ 24.08.2026 замером из БОЕВОГО ЛОГА (кейс Q5b): «в логе на 3
    # меньше, 62 лист → 59 лог. Лог всегда вернее чарлиста». Срез на 3 —
    # ровно то, что проверяет этот тест, — наблюдается в игре. Замер Q5 стоял
    # на завышенном листе, решение Dan от 18.08 было верным, и отложенность
    # соседнего теста снята.
    test "9 + 9 + 5 = 23 из 20 — срез на 3, и все три под капом", %{ruleset: ruleset} do
      stats = archer(ruleset, :longbow)

      assert ruleset.stat_caps.attack_bonus == 20
      assert stats.race_attack_bonus + stats.weapon_type_attack_bonus == 18
      assert stats.attack_cap_clipped == -3
      assert :attack_bonus in stats.capped

      # ...и все три действительно внутри
      assert Rules.Caps.covers_source?(ruleset, :attack_bonus, :weapon_bonus)
      assert Rules.Caps.covers_source?(ruleset, :attack_bonus, :racial_bonus)
      assert Rules.Caps.covers_source?(ruleset, :attack_bonus, :gear_weapon)
    end

    # ⚠️ Потолок опускается искусственно — иначе проверять нечего: на настоящих
    # данных 18 < 20. Смысл кейса в том, что клип ОДИН на оба источника, а не по
    # клипу на каждый: с раздельными клипами каждый прошёл бы 9 ≤ 12 и срез не
    # случился бы вовсе. Та же поломка, которой сейвы однажды несли +40
    # (CLAUDE.md §9), и та же форма теста, что у расового бонуса.
    test "клип ОДИН на расовый бонус и на бонус за тип оружия", %{ruleset: ruleset} do
      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :attack_bonus, 12)}
      stats = Rules.compute(build(:half_elf, 40, :longbow), tight)

      # предпосылка: каждый источник сам по себе НИЖЕ потолка
      assert stats.race_attack_bonus == 9
      assert stats.weapon_type_attack_bonus == 9

      # 18 предложено потолку 12 → 12, а не 18 и не 12 + 12
      assert stats.attack_extra_bonus == 12
      assert stats.attack_cap_clipped == -6
      assert :attack_bonus in stats.capped
    end
  end

  describe "алебарда — бонус двух групп сразу" do
    # 🔴 Кейс, ради которого в данных заведена таблица по конкретному оружию.
    # Алебарда — древковое, и по общему правилу дала бы только Дисциплину;
    # страница же называет у неё ВТОРОЙ бонус, щитовой AC. Правило «группа →
    # бонус» потеряло бы половину.
    # ✅ **ВЕЛИЧИНА ИЗМЕРЕНА Dan 16.08.2026** (кейс Q3): «было 20 АЦ голым, надел
    # алебарду получил 29 АЦ» — то есть **+9 у сагровика**, ровно сагровская
    # величина щитового бонуса КЛИНКОВОЙ группы (6/9). Комбинированное оружие
    # получает не своё особое число, а обычный бонус клинковых.
    #
    # ⚠️ Здесь стояло «величины не знает никто, и об этом сказано вслух» —
    # оговорка снята, число посчитано. ⚠️ Измерена САГРОВСКАЯ половина; база 6
    # взята из чисел самой клинковой группы, несагровика Dan не мерил.
    test "оба бонуса посчитаны: Дисциплина +18 и щитовой AC +9", %{ruleset: ruleset} do
      stats = Rules.compute(build(nil, 40, :halberd, ranks: 4), ruleset)

      assert stats.skill_values.discipline.weapon_type_bonus == 18
      assert stats.skill_values.discipline.total == 4 + 18

      assert for(t <- stats.ac_own_terms_geared, do: {t.id, t.type, t.ac}) == [
               {:halberd, :shield, 9}
             ]

      # оговорки про неизвестную величину больше нет — печатать «не знаем»
      # о посчитанном запрещено так же прямо, как обратное (CLAUDE.md §6)
      refute {:missing_data, {:weapon_type_bonus_amount, :halberd, :shield_ac}} in stats.gaps

      assert for(e <- stats.weapon_type_bonuses, do: {e.kind, e.counted, e.stated?}) == [
               {:skill_bonus, 18, true},
               {:shield_ac, 9, true}
             ]
    end

    # 🔴 Контроль из того же замера, и он важнее самого числа: **копьё щитового
    # AC не даёт вовсе** («АЦ оно не даёт, древковое даёт только дисциплину»).
    # Считай мы бонус ПО ГРУППЕ, копьё получило бы AC вместе с алебардой —
    # то есть этот кейс и оправдывает таблицу по конкретному оружию.
    test "копьё — то же древковое, но щитового AC не даёт", %{ruleset: ruleset} do
      stats = Rules.compute(build(nil, 40, :spear, ranks: 4), ruleset)

      assert stats.skill_values.discipline.weapon_type_bonus == 18
      assert stats.ac_own_terms_geared == []
    end

    # 🔴 Великий топор — единственное оружие, у которого ЕДИНСТВЕННЫЙ возможный
    # получатель как раз неизвестен: собственный бонус (поглощение урона) наш
    # калькулятор не показывает вовсе, а щитовой AC назван без числа. То есть
    # сегодня он не даёт нам ничего, хотя в игре явно даёт, — и это обязано быть
    # сказано, а не промолчано.
    # ✅ **ИЗМЕРЕНО Dan 16.08.2026** (кейс Q3): «с 20 увеличило до 29 на сагровике,
    # в общем, полный аналог Алебарды в плане АЦ». ⚠️ Здесь стояло «не даёт
    # калькулятору НИЧЕГО и говорит почему» — теперь даёт ровно одно число,
    # и оно верное.
    #
    # ⚠️ Слова Dan «полный аналог алебарды» — самое ценное в замере: они говорят,
    # что это ОДНО правило, а не два совпавших числа.
    test "великий топор: поглощение не наше, но щитовой AC +9 посчитан", %{ruleset: ruleset} do
      stats = Rules.compute(build(nil, 40, :greataxe), ruleset)

      assert stats.weapon_type_attack_bonus == 0

      assert for(t <- stats.ac_own_terms_geared, do: {t.id, t.type, t.ac}) == [
               {:greataxe, :shield, 9}
             ]

      # ⚠️ И НИ ОДНОЙ оговорки: величина теперь известна, а поглощение урона
      # получателя не имеет и по CLAUDE.md §9 гэпом не является. Без этой
      # половины кейс зеленел бы у кода, который жалуется на всё подряд.
      assert weapon_gaps(stats) == []
    end

    # Двулезвийный меч — единственная запись, где ОБА наших получателя известны
    # числом, и единственная, где второе число сагровику НЕ удваивается:
    # «Данный бонус не модифицируется. Он одинаковый для всех билдов».
    #
    # ✅ **ЧТЕНИЕ ПОДТВЕРЖДЕНО ЗАМЕРОМ Dan 16.08.2026** (кейс Q3): «даёт 9 АЦ
    # ВСЕМ билдам, а не только сагровикам». ⚠️ До замера это было НАШЕ чтение
    # фразы «не модифицируется» — слова «сагра» в предложении страницы нет, —
    # и оговорка была честной ровно до этого дня.
    test "двулезвийный меч: +9 щита сагровику НЕ удваивается, и это оговорено", %{
      ruleset: ruleset
    } do
      pure = Rules.compute(build(nil, 40, :two_bladed_sword, ranks: 4), ruleset)
      mixed = Rules.compute(build(nil, 40, :two_bladed_sword, ranks: 4, impure?: true), ruleset)

      # Дисциплина сагровику удваивается как обычно...
      assert pure.skill_values.discipline.weapon_type_bonus == 18
      assert mixed.skill_values.discipline.weapon_type_bonus == 12

      # ...а щитовой AC — нет: +9 у обоих
      assert for(t <- pure.ac_own_terms_geared, do: {t.id, t.type, t.ac}) == [
               {:two_bladed_sword, :shield, 9}
             ]

      assert for(t <- mixed.ac_own_terms_geared, do: {t.id, t.type, t.ac}) == [
               {:two_bladed_sword, :shield, 9}
             ]

      # оговорки больше нет ни у кого: чтение стало измеренным фактом
      refute {:assumed, {:weapon_type_bonus_variant, :two_bladed_sword, :in_group}} in pure.gaps
      refute {:assumed, {:weapon_type_bonus_variant, :two_bladed_sword, :in_group}} in mixed.gaps
    end
  end

  describe "исключения, названные страницей поимённо" do
    # «Трезубцы не дают никакого бонуса», «Метательные топоры не дают никакого
    # бонуса». ⚠️ Это ЗНАНИЕ, а не дырка: оговорки быть не должно, иначе список
    # неточностей наполнится тем, что мы как раз знаем.
    test "трезубец и метательный топор не дают ничего и не жалуются", %{ruleset: ruleset} do
      for weapon <- [:trident, :throwing_axe] do
        stats = Rules.compute(build(nil, 40, weapon, ranks: 4), ruleset)

        assert stats.weapon_type_bonuses == [], "#{weapon}"
        assert stats.weapon_type_attack_bonus == 0, "#{weapon}"
        assert stats.skill_values.discipline.weapon_type_bonus == 0, "#{weapon}"
        assert weapon_gaps(stats) == [], "#{weapon}"
      end

      # Положительный контроль: их одногруппники бонус дают, то есть исключение
      # именно поимённое, а не «вся группа выключена».
      spear = Rules.compute(build(nil, 40, :spear, ranks: 4), ruleset)
      bow = Rules.compute(build(nil, 40, :longbow), ruleset)

      assert spear.skill_values.discipline.weapon_type_bonus == 18
      assert bow.weapon_type_attack_bonus == 9
    end

    # Виды бонуса, у которых получателя в билде нет вовсе. По CLAUDE.md §9 это
    # не гэп, а вопрос, которого мы не задаём (Dan, 16.08.2026).
    test "топор, молот и посох молчат: получателя у их бонусов нет", %{ruleset: ruleset} do
      for weapon <- [:battleaxe, :warhammer, :magic_staff, :club] do
        stats = Rules.compute(build(nil, 40, weapon, ranks: 4), ruleset)

        assert stats.weapon_type_attack_bonus == 0, "#{weapon}"
        assert stats.ac_own_terms_geared == [], "#{weapon}"
        assert stats.skill_values.discipline.weapon_type_bonus == 0, "#{weapon}"
        assert weapon_gaps(stats) == [], "#{weapon}"
      end
    end

    # Пустые руки — не «бонус ноль», а «бонуса нет»: разница видна в списке,
    # который отдаёт ядро, и в отсутствии любой оговорки.
    test "без оружия в руках нет ни бонуса, ни оговорки", %{ruleset: ruleset} do
      stats = Rules.compute(build(nil, 40, nil), ruleset)

      assert stats.weapon_type_bonuses == []
      assert stats.weapon_type_attack_bonus == 0
      assert weapon_gaps(stats) == []
    end
  end

  describe "уровень, на котором число известно" do
    # Граничные уровни: 1, 20/21 и кап 41. Ниже 40-го числа не знает никто,
    # и вместо тихого нуля — названная причина.
    test "1, 20 и 21 — гэп; 40 и 41 — число", %{ruleset: ruleset} do
      for level <- [1, 20, 21, 39] do
        stats = Rules.compute(build(nil, level, :longbow), ruleset)

        assert stats.weapon_type_attack_bonus == 0, "уровень #{level}"

        assert {:missing_data, {:weapon_type_bonus_level, :longbow}} in stats.gaps,
               "уровень #{level}"
      end

      for level <- [40, 41] do
        stats = Rules.compute(build(nil, level, :longbow), ruleset)

        assert stats.weapon_type_attack_bonus == 9, "уровень #{level}"
        assert weapon_gaps(stats) == [], "уровень #{level}"
      end
    end

    # ⚠️ Главное про 41-й: бонус НЕ вырос. «Бонус становится максимальным на 40
    # уровне», значит на 41-м он тот же, а растёт только сама база атаки.
    test "на 41-м бонус тот же, что на 40-м", %{ruleset: ruleset} do
      at_40 = Rules.compute(build(nil, 40, :longbow), ruleset)
      at_41 = Rules.compute(build(nil, 41, :longbow), ruleset)

      assert at_41.weapon_type_attack_bonus == at_40.weapon_type_attack_bonus
      assert at_41.attack_bonus - at_40.attack_bonus == 1
    end

    # Дельта выводится из двух полных `compute` (CLAUDE.md §5), поэтому появление
    # бонуса на 40-м видно в превью само, без единой строки про оружие в дельте.
    test "бонус появляется в дельте 39 → 40 сам", %{ruleset: ruleset} do
      %{before: before, after: later} =
        Rules.preview_level_up(build(nil, 39, :longbow), :fighter, ruleset)

      assert before.weapon_type_attack_bonus == 0
      assert later.weapon_type_attack_bonus == 9

      # 40-й чётный, базовой атаки он не даёт — значит вся разница это бонус
      assert later.attack_bonus - before.attack_bonus == 9
    end
  end

  describe "вариант выбирается составом билда" do
    # Один уровень чужого класса отменяет группу — и вместе с ней полуторный
    # бонус. ⚠️ Парный кейс обязателен: без него всё зеленело бы и у кода,
    # который всегда берёт вариант сагровика.
    test "сагровик получает больше, один уровень барда это отменяет", %{ruleset: ruleset} do
      pure = Rules.compute(build(nil, 40, :longbow), ruleset)
      mixed = Rules.compute(build(nil, 40, :longbow, impure?: true), ruleset)

      assert pure.weapon_type_attack_bonus == 9
      assert mixed.weapon_type_attack_bonus == 6

      assert hd(pure.weapon_type_bonuses).variant == :in_group
      assert hd(mixed.weapon_type_bonuses).variant == :base

      # лестницы одной длины — сравниваются одинаковые билды, а не 40 с 39
      assert pure.character_level == mixed.character_level
    end

    # Мультикласс на четыре класса: сагровиком такой билд быть не может по
    # определению (в группе четыре класса, и Бледный мастер не из них), значит
    # вариант базовый — и это тот же кейс, что «граничные уровни» у соседей.
    test "билд из четырёх классов получает базовый вариант", %{ruleset: ruleset} do
      levels =
        List.duplicate(:fighter, 10) ++
          List.duplicate(:wizard, 5) ++
          List.duplicate(:pale_master, 20) ++ List.duplicate(:red_dragon_disciple, 6)

      stats =
        Rules.compute(
          %Build{build(nil, 41, :longbow) | levels: levels},
          ruleset
        )

      assert stats.character_level == 41
      assert map_size(stats.class_levels) == 4
      assert stats.class_groups == []
      assert stats.weapon_type_attack_bonus == 6
    end

    # Условие варианта читается ИЗ ДАННЫХ: страница называет группу заголовком
    # («для Воинов Сагры»), а кто в неё входит — говорят страницы классов. Ядро
    # только сопоставляет; развались связка — вариант перестанет применяться,
    # а не «применится к кому попало».
    test "группа для второго числа связана данными", %{ruleset: ruleset} do
      assert ruleset.weapon_type_bonuses.class_group == :sagra_warriors
      assert ruleset.weapon_type_bonuses.stated_for_level == 40
      assert ruleset.weapon_type_bonuses.max_at_level == 40
      assert ruleset.weapon_type_bonuses.formula == nil
    end
  end

  describe "куда ложится посчитанное" do
    # Щитовой AC — типа `shield`, и это не украшение: он обязан встретиться и
    # с расовым щитом Карлика, и с числом, которое игрок вписал в «Вещи».
    # ⚠️ Две встречи — РАЗНЫЕ по правилу (задача 3.39): с расовым он
    # СКЛАДЫВАЕТСЯ (страница «Расы»: у Карлика с клинком +12, у сагровика +18),
    # с вписанным — КОНКУРИРУЕТ, и берётся большее.
    test "с расовым щитом складывается, а с вписанным конкурирует", %{ruleset: ruleset} do
      # Карлик с мечом: ДВА щитовых терма по +9, каждый со своим именем.
      # ⚠️ До задачи 3.143 (30.08.2026) тут стоял ещё терм `small_stature`
      # (+1 размер): запись была applied по обрезанной цитате, теперь
      # not_modelled (условие «крупнее персонажа» посчитать нечем).
      gnome = Rules.compute(build(:gnome, 40, :longsword), ruleset)

      assert for(t <- gnome.ac_own_terms_geared, do: {t.id, t.type, t.ac}) == [
               {:gnome, :shield, 9},
               {:longsword, :shield, 9}
             ]

      # Складываются: 10 базы + 9 + 9. И оговорки нет вовсе — собственные
      # прибавки одного типа складываются, это измерено (E5).
      assert gnome.ac_geared == 28
      assert Enum.filter(gnome.gaps, &match?({_, {:ac_gear_base, _}}, &1)) == []

      # Безрасовый билд с мечом и вписанным щитом — а вот здесь конкуренция:
      # то есть терм попал в общий механизм, а не мимо него.
      with_shield =
        Rules.compute(
          %Build{
            build(nil, 40, :longsword)
            | gear: Gear.new(weapon: :longsword, feats: @proficiencies, ac: %{shield: 4})
          },
          ruleset
        )

      # Своё +9 больше вписанных 4 → вписанное не идёт в число.
      assert with_shield.ac_by_type[:shield] == 0
      assert with_shield.ac_superseded_types == [:shield]

      # ⚠️ Здесь стоял `assert {:not_modelled, {:ac_gear_base, :shield}}` —
      # оговорка «базу щита из одного введённого числа не вычесть». Задача 3.41
      # сделала щит ПРЕДМЕТОМ с размером, то есть база стала известной, и
      # печатать «посчитать не можем» про посчитанное запрещено так же прямо,
      # как обратное (CLAUDE.md §6). Щит здесь не выбран — значит его и нет,
      # а не «неизвестно какой».
      refute {:not_modelled, {:ac_gear_base, :shield}} in with_shield.gaps

      # ⚠️ Положительный контроль к `refute`: правило столкновения никуда не
      # делось, и выбранный щит даёт свою базу СВЕРХ победившего собственного
      # бонуса — 10 базы + 9 своего щитового + 2 базы среднего щита.
      with_item =
        Rules.compute(
          %Build{
            build(nil, 40, :longsword)
            | gear:
                Gear.new(
                  weapon: :longsword,
                  feats: @proficiencies,
                  ac: %{shield: 4},
                  worn: %{shield: :large}
                )
          },
          ruleset
        )

      assert with_item.ac_by_type[:shield] == 2
      assert with_item.ac_geared == with_shield.ac_geared + 2

      # ...и обратный контроль: доспех другого типа складывается как складывался
      with_armor =
        Rules.compute(
          %Build{
            build(nil, 40, :longsword)
            | gear: Gear.new(weapon: :longsword, feats: @proficiencies, ac: %{armor: 8})
          },
          ruleset
        )

      assert with_armor.ac_by_type[:armor] == 8
      assert Enum.filter(with_armor.gaps, &match?({_, {:ac_gear_base, _}}, &1)) == []
    end

    # ⚠️ «Голым» значит голым: оружие — вещь, значит в `ac_naked` бонуса за тип
    # оружия нет и быть не должно. Ровно то же, что у расового бонуса с 15.08.2026.
    test "в «AC голым» бонуса за тип оружия нет", %{ruleset: ruleset} do
      stats = Rules.compute(build(:gnome, 41, :longsword), ruleset)

      # ⚠️ Пуст, а не [:small_stature] — задача 3.143 (30.08.2026) перевела
      # размерный модификатор Карлика в not_modelled, своего терма он
      # больше не даёт вовсе.
      assert for(t <- stats.ac_own_terms, do: t.id) == []
      assert stats.ac_naked == 10
      assert stats.ac_geared == 10 + 9 + 9
    end

    # Бонус к Дисциплине лежит ВНУТРИ капа навыка +50, вместе с расовым бонусом
    # и вписанным числом, и клип на пул ОДИН.
    #
    # ⚠️ На настоящем потолке пул не упирается (18 + 18 = 36 < 50), поэтому
    # потолок опускается — иначе проверять нечего. Смысл в том, что с раздельными
    # клипами каждое слагаемое прошло бы 18 ≤ 20 и среза не было бы вовсе.
    test "Дисциплина: один клип на расовый бонус, оружие и вещи", %{ruleset: ruleset} do
      build = %Build{
        build(:human, 40, :spear, ranks: 4)
        | gear: Gear.new(weapon: :spear, feats: @proficiencies, skills: %{discipline: 10})
      }

      real = Map.fetch!(Rules.compute(build, ruleset).skill_values, :discipline)

      # предпосылка: три слагаемых, каждое ненулевое
      assert {real.shard_race_bonus, real.weapon_type_bonus, real.gear_bonus} == {18, 18, 10}
      assert real.bonus_clipped == 0
      assert real.total == 4 + 18 + 18 + 10

      tight = %{ruleset | stat_caps: Map.put(ruleset.stat_caps, :skill_bonus, 20)}
      clipped = Map.fetch!(Rules.compute(build, tight).skill_values, :discipline)

      # 46 предложено потолку 20 → 20, а не 46 и не 20 × 3
      assert {clipped.shard_race_bonus, clipped.weapon_type_bonus} == {18, 18}
      assert clipped.bonus_clipped == -26
      assert clipped.bonus_capped?
      assert clipped.total == 4 + 20
    end

    # Бонус ложится ровно на тот навык, который называет страница.
    test "бонус за древковое ложится только на Дисциплину", %{ruleset: ruleset} do
      build = build(nil, 40, :spear)

      assert WeaponTypeBonus.skill_bonus(build, ruleset, :discipline) == 18
      assert WeaponTypeBonus.skill_bonus(build, ruleset, :tumble) == 0
      assert WeaponTypeBonus.skill_bonus(build, ruleset, :spot) == 0
    end
  end

  describe "ваниль" do
    # Система оружия — сиальская. У ванильного ruleset'а её нет вовсе, и это
    # проверяется числом, а не «не падает»: билд с луком на 41-м уровне обязан
    # получить ноль и ни одной оговорки.
    test "ванильный ruleset этой системы не знает", %{vanilla: vanilla} do
      assert vanilla.weapon_type_bonuses == nil

      stats = Rules.compute(build(nil, 41, :longbow), vanilla)

      assert stats.weapon_type_bonuses == []
      assert stats.weapon_type_attack_bonus == 0
      assert stats.ac_own_terms_geared == []
      assert weapon_gaps(stats) == []
    end
  end

  # ------------------------------------------------------------------ helpers --

  # Персонаж замера Q1: светлый эльф, 40 уровней воина (значит сагровик),
  # DEX 28 (мод +9), STR 8 (мод −1).
  defp archer(ruleset, weapon) do
    build = %Build{
      build(:half_elf, 40, weapon)
      | base_abilities: %{@flat | str: 8, dex: 28},
        gear: bow_gear(weapon)
    }

    Rules.compute(build, ruleset)
  end

  defp bow_gear(nil), do: Gear.new([])

  defp bow_gear(weapon),
    do: Gear.new(weapon: weapon, weapon_attack: 5, feats: @proficiencies)

  # ⚠️ Уровни ВОИНА, то есть по умолчанию собирается воин Сагры — как и в
  # `racial_bonus_test.exs`, и по той же причине: вариант виден в каждом числе,
  # поэтому у каждого кейса есть пара через `impure?: true`.
  defp build(race, levels, weapon, opts \\ []) do
    classes =
      if opts[:impure?],
        do: List.duplicate(:fighter, levels - 1) ++ [:bard],
        else: List.duplicate(:fighter, levels)

    %Build{} =
      Build.new(
        race: race,
        levels: classes,
        base_abilities: @flat,
        skills: if(opts[:ranks], do: %{1 => %{discipline: opts[:ranks]}}, else: %{}),
        gear: if(weapon, do: Gear.new(weapon: weapon, feats: @proficiencies), else: Gear.new([]))
      )
  end

  defp weapon_gaps(stats),
    do: for(gap <- stats.gaps, inspect(gap) =~ "weapon_type_bonus", do: gap)

  # Сколько бонус за тип оружия дал ИМЕННО ТОМУ числу, куда его кладёт раса, —
  # чтобы сумма двух термов сравнивалась с вариантом расового бонуса.
  defp counted(stats, :attack_bonus), do: stats.weapon_type_attack_bonus

  defp counted(stats, :shield_ac) do
    Enum.find_value(stats.ac_own_terms_geared, 0, fn term ->
      match?({:weapon, _}, term.source) && term.ac
    end)
  end

  defp counted(stats, :skill_bonus) do
    Enum.find_value(stats.skill_values, 0, fn {_id, value} ->
      value.weapon_type_bonus != 0 && value.weapon_type_bonus
    end)
  end

  # ---------------------------------------------------------------------------
  # 🔴 СТОРОЖ ОТМЕТКИ О ПОДТВЕРЖДЕНИИ (задача 3.132, ответ Dan по кейсу AH2).
  #
  # Отметка `same_kind_confirmed` — единственный способ убрать оговорку с экрана
  # игрока, НИЧЕГО не посчитав. Поэтому она обязана назвать, что подтверждено,
  # почему это снимает оговорку, и кем и когда сказано; полу-записанная отметка
  # роняет сборку. Тот же состав и тот же довод, что у `stacking_confirmed`
  # (задача 3.90) и у `not_a_gap` (3.74/3.95).
  describe "отметка о подтверждении: сторож загрузчика" do
    @describetag :tmp_dir

    setup do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    defp patch_mark(root, fun) do
      path = Path.join(root, "siala_41/systems.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["systems"], fn systems ->
          for system <- systems do
            if system["id"] == "weapon_system" do
              update_in(system["facts"], fn facts ->
                for fact <- facts do
                  if fact["what"] == "bonuses_from_both_hands",
                    do: fun.(fact),
                    else: fact
                end
              end)
            else
              system
            end
          end
        end)

      File.write!(path, Jason.encode!(patched))
    end

    # 🔴 ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ НА САМО ПРАВИЛО: без отметки оговорка
    # возвращается САМА, ничего не выключено флагом в коде.
    test "снятая отметка возвращает оговорку", %{root: root} do
      patch_mark(root, &Map.delete(&1, "same_kind_confirmed"))

      layer = Loader.load!(root)["siala_41"].weapon_type_bonuses

      assert layer.both_hands.same_kind_confirmed == nil

      # ...и правило при этом на месте: вернулась ОГОВОРКА, а не поведение.
      assert layer.both_hands.same_kind == :max
    end

    test "отметка без источника роняет сборку", %{root: root} do
      patch_mark(root, fn fact ->
        update_in(fact["same_kind_confirmed"], &Map.delete(&1, "source"))
      end)

      assert_raise RuntimeError, ~r/without a `source`/, fn -> Loader.load!(root) end
    end

    test "отметка без автора роняет сборку", %{root: root} do
      patch_mark(root, fn fact ->
        put_in(fact["same_kind_confirmed"]["source"]["who"], "")
      end)

      assert_raise RuntimeError, ~r/no non-empty `who`/, fn -> Loader.load!(root) end
    end

    test "отметка со статусом кроме verified роняет сборку", %{root: root} do
      patch_mark(root, fn fact ->
        put_in(fact["same_kind_confirmed"]["status"], "assumed")
      end)

      assert_raise RuntimeError, ~r/only "verified" takes a caveat off/, fn ->
        Loader.load!(root)
      end
    end

    # ⚠️ `what` списком, и пустой список — это отметка «нам сказали, что всё
    # хорошо»: она не называет, ЧТО подтверждено, в том числе границу
    # наблюдения (видели на клинковых, распространили словом владельца).
    test "отметка без `what` роняет сборку", %{root: root} do
      patch_mark(root, fn fact -> put_in(fact["same_kind_confirmed"]["what"], []) end)

      assert_raise RuntimeError, ~r/non-empty `what`/, fn -> Loader.load!(root) end
    end
  end
end
