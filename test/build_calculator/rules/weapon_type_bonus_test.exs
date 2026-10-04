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
    #
    # ⚠️ ЗДЕСЬ СТОЯЛ И `:magic_staff`, и заголовок говорил «топор, молот и посох
    # молчат». Про посох это было НЕВЕРНО с самого начала: он молчал не потому,
    # что получателя нет, а потому, что записи в данных не было вовсе, — и все
    # четыре утверждения этого кейса оставались истинными, то есть тест зеленел
    # на дыре. Выведен в свой describe задачей 3.183.
    test "топор, молот и дубинка молчат: получателя у их бонусов нет", %{ruleset: ruleset} do
      for weapon <- [:battleaxe, :warhammer, :club] do
        stats = Rules.compute(build(nil, 40, weapon, ranks: 4), ruleset)

        assert stats.weapon_type_attack_bonus == 0, "#{weapon}"
        assert stats.ac_own_terms_geared == [], "#{weapon}"
        assert stats.skill_values.discipline.weapon_type_bonus == 0, "#{weapon}"
        assert weapon_gaps(stats) == [], "#{weapon}"
      end

      # Отрицательный контроль к самому этому списку: у посоха получатель ЕСТЬ,
      # и три его навыка обязаны сдвинуться. Стоит рядом, чтобы тот же кейс
      # нельзя было снова «починить» дописыванием посоха обратно.
      staff = Rules.compute(build(nil, 40, :magic_staff, staff_ranks: 4), ruleset)

      assert staff.skill_values.spellcraft.weapon_type_bonus == 18
      assert staff.skill_values.discipline.weapon_type_bonus == 0
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

  # 🔴 ВОСЬМОЙ ТИП ОРУЖИЯ ДВИЖКА (задача 3.183). Страница «Система оружия»,
  # revid 20527, раздел «Оружие, не требующее фитов»:
  #
  #   «Одевая любой такой посох, персонаж на 40 уровне получает бонус
  #    +12 к спеллкрафту, +12 к концентрации и +12 к эмпатии. Этот бонус
  #    складывается с остальными бонусами к навыкам, но входит в кап +50.»
  #
  # ⚠️ До 11.09.2026 посох не давал калькулятору РОВНО НИЧЕГО: числа лежали
  # в данных со статусом verified с 01.08.2026, а записи, через которую их
  # применить, не было — в `weapons.json` у посоха
  # `siala_proficiency_group: no_proficiency_required`, то есть правило
  # «группа → бонус» про него не знает.
  describe "магический посох — три навыка одним предметом" do
    # ⚠️ `impure?` — потому что билд из одних воинов по умолчанию сагровик,
    # а +12 это БАЗОВОЕ число страницы.
    test "на 40-м +12 каждому из трёх названных навыков", %{ruleset: ruleset} do
      stats = Rules.compute(build(nil, 40, :magic_staff, staff_ranks: 4, impure?: true), ruleset)

      for skill <- [:spellcraft, :concentration, :animal_empathy] do
        assert stats.skill_values[skill].weapon_type_bonus == 12, "#{skill}"
        assert stats.skill_values[skill].total == 16, "#{skill}"
      end
    end

    # Второе число страница не печатает — оно получается тем же шагом
    # `class_group`, которым считаются все вторые числа этой системы:
    # floor(12 × 3/2) = 18. Выведено, не процитировано.
    test "воину Сагры +18, и это тот же шаг, что у остальных строк", %{ruleset: ruleset} do
      sagra = Rules.compute(build(nil, 40, :magic_staff, staff_ranks: 4), ruleset)
      mixed = Rules.compute(build(nil, 40, :magic_staff, staff_ranks: 4, impure?: true), ruleset)

      assert sagra.skill_values.spellcraft.weapon_type_bonus == 18
      assert mixed.skill_values.spellcraft.weapon_type_bonus == 12
    end

    # 🔴 Фита владения посох не требует вовсе, и это половина его смысла:
    # «некоторые маги могут ничего не брать, бегать с посохом» (Dan,
    # `weapons.json` → magic_staff). Билд БЕЗ единого фита владения обязан
    # получить все три бонуса.
    test "фита владения не нужно ни одного", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(nil, 40, :magic_staff, staff_ranks: 4, no_proficiency?: true),
          ruleset
        )

      assert stats.skill_values.spellcraft.weapon_type_bonus == 18

      # Положительный контроль на сам стенд: клинковое без фита не считается
      # вовсе, то есть ноль у посоха означал бы отказ по владению, а не
      # отсутствие бонуса.
      blade =
        Rules.compute(build(nil, 40, :longsword, ranks: 4, no_proficiency?: true), ruleset)

      assert blade.weapon_type_bonuses == []
    end

    test "растёт по тиру, как и всё в этой системе", %{ruleset: ruleset} do
      table = [
        {1, 2},
        {7, 2},
        {8, 4},
        {16, 4},
        {17, 6},
        {23, 6},
        {24, 8},
        {31, 8},
        {32, 10},
        {39, 10},
        {40, 12},
        {41, 12}
      ]

      for {level, expected} <- table do
        stats = Rules.compute(build(nil, level, :magic_staff, staff_ranks: 4), ruleset)

        # ⚠️ Билд из одних воинов — сагровик, поэтому здесь `impure?`: таблица
        # выше про БАЗОВОЕ число.
        base =
          Rules.compute(build(nil, level, :magic_staff, staff_ranks: 4, impure?: true), ruleset)

        assert base.skill_values.concentration.weapon_type_bonus == expected,
               "уровень #{level}"

        assert stats.skill_values.concentration.weapon_type_bonus == div(expected * 3, 2),
               "уровень #{level}, сагровик"
      end
    end

    # 🔴 ДИСЦИПЛИНА ПОСОХОМ НЕ ЗАДЕТА, И С 12.09.2026 ЭТО ИЗМЕРЕНО. У Человека
    # посох по странице даёт «ещё и дисциплины» — без числа, и вопрос был
    # не в величине, а в том, прибавляется она к расовой Дисциплине Человека
    # или ЗАМЕЩАЕТ её: 12 против 24 на живом билде.
    #
    # ✅ Замер `AO1` (Dan, 12.09.2026): «дисциплина человека с дубиной и
    # с магическим посохом одинаковая, равна 12» — замещение. Модель отдавала
    # 12 всегда, то есть не сдвинулась ни на очко; сменился статус факта
    # (`magic_staff_skill_bonus.human_extra` → `stacking: replaces_racial_
    # discipline`).
    # ⚠️ Контроль — не пустые руки, а ДУБИНКА, и ровно по этой паре замер
    # и заказывали: расовый бонус включается оружием в руках (задача 3.36),
    # и голый Человек Дисциплины не имеет вовсе. Дубинка его включает, а своей
    # Дисциплины не даёт — значит равенство этих двух чисел и есть ответ.
    # ⚠️ ЧЕГО ЗАМЕР НЕ ДАЛ: собственной величины посоховой Дисциплины. При
    # замещении наблюдаем ИТОГ, а слагаемое ненаблюдаемо вовсе.
    test "Дисциплина Человека остаётся расовой и не удваивается", %{ruleset: ruleset} do
      with_staff = Rules.compute(build(:human, 40, :magic_staff, staff_ranks: 4), ruleset)
      control = Rules.compute(build(:human, 40, :club, staff_ranks: 4), ruleset)

      assert control.skill_values.discipline.shard_race_bonus == 18
      assert with_staff.skill_values.discipline.weapon_type_bonus == 0
      assert with_staff.skill_values.discipline.total == control.skill_values.discipline.total
    end

    # «Этот бонус складывается с остальными бонусами к навыкам, но входит
    # в кап +50» — то самое предложение, из которого взят сам потолок
    # (`overrides.json` → `stat_caps.skill_bonus`). Клип ОДИН на весь пул.
    test "входит в кап +50 вместе с вписанным, одним клипом", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          build(nil, 40, :magic_staff, staff_ranks: 4, gear_skills: %{spellcraft: 45}),
          ruleset
        )

      value = stats.skill_values.spellcraft

      assert value.weapon_type_bonus == 18
      assert value.gear_bonus == 45
      assert value.bonus_capped?
      assert value.bonus_clipped == -13
      assert value.total == 54
    end

    # Оговорок посох не приносит ни одной: числа названы, уровень любой,
    # вариант не читается из предложения.
    test "ни одной оговорки", %{ruleset: ruleset} do
      for level <- [1, 17, 40, 41] do
        stats = Rules.compute(build(nil, level, :magic_staff, staff_ranks: 4), ruleset)
        assert weapon_gaps(stats) == [], "уровень #{level}"
      end
    end

    # ⚠️ «Посохи» сводной таблицы страницы — это quarterstaff, ДРЕВКОВОЕ
    # оружие с Дисциплиной; «Магические посохи» — magic_staff, три навыка
    # и никакого владения. Перепутать их — значит дать волшебнику +12
    # Дисциплины вместо трёх его навыков.
    test "боевой посох — не магический: Дисциплина, а не три навыка", %{ruleset: ruleset} do
      staff = Rules.compute(build(nil, 40, :quarterstaff, staff_ranks: 4), ruleset)

      assert staff.skill_values.discipline.weapon_type_bonus == 18
      assert staff.skill_values.spellcraft.weapon_type_bonus == 0
    end
  end

  describe "уровень, на котором число известно" do
    # 🔴 **ЭТОТ БЛОК ПЕРЕПИСАН 11.09.2026 (задача 3.181), и переписан целиком.**
    # Здесь стоял кейс «1, 20 и 21 — гэп; 40 и 41 — число»: ниже 40-го бонус
    # не считался вовсе, потому что функции роста не знал никто. Теперь знает —
    # администрация шарда прислала разбор серверных скриптов со ступенчатой
    # таблицей, и решение Dan 11.09.2026 — считать по нарастающей.
    #
    # ⚠️ Утверждение, которое блок проверял, НЕ отменено, оно сузилось: гэп
    # про уровень обязан появляться у снапшота БЕЗ таблицы тиров. Кейс на это
    # стоит ниже, на синтетическом ruleset'е (урок 3.85: контроль на живой
    # записи назавтра получает данные и молча перестаёт проверять).
    #
    # Таблица: `sl_s_wp_inc.nss:85–108`, границы 1–7 · 8–16 · 17–23 · 24–31 ·
    # 32–39 · 40+. Дальнобойное — исполнитель `attack`, единица = тир; билд
    # набран воином, то есть сагровик, значит `floor(тир × 3 / 2)`.
    test "бонус растёт ступенями по уровню персонажа", %{ruleset: ruleset} do
      # {уровень, сагровик, не-сагровик}
      table = [
        {1, 1, 1},
        {7, 1, 1},
        {8, 3, 2},
        {16, 3, 2},
        {17, 4, 3},
        {20, 4, 3},
        {21, 4, 3},
        {23, 4, 3},
        {24, 6, 4},
        {31, 6, 4},
        {32, 7, 5},
        {39, 7, 5},
        {40, 9, 6},
        {41, 9, 6}
      ]

      for {level, in_group, base} <- table do
        pure = Rules.compute(build(nil, level, :longbow), ruleset)
        mixed = Rules.compute(build(nil, level, :longbow, impure?: true), ruleset)

        assert pure.weapon_type_attack_bonus == in_group, "сагровик, уровень #{level}"
        assert mixed.weapon_type_attack_bonus == base, "не сагровик, уровень #{level}"

        # и про уровень больше не оговариваются: число известно на любом
        assert weapon_gaps(pure) == [], "уровень #{level}"
      end
    end

    # 🔴 Единственная точка таблицы выше, которую ВИДЕЛИ В ИГРЕ ниже 40-го
    # (замер `AM1`, Dan 11.09.2026): светлый эльф Варвар 17, STR 14 / DEX 12 —
    # голым 19, длинный меч +5 → 28, праща +5 → 31. Значит терм оружия +4
    # и расовый +4, вместе +8.
    #
    # ⚠️ Здесь проверяется ровно оружейная половина; расовая — в
    # `racial_bonus_test.exs`, тем же замером.
    test "замер AM1: праща у светлого эльфа Варвара 17 даёт +4 оружием", %{ruleset: ruleset} do
      build = %Build{
        build(:half_elf, 17, :sling)
        | base_abilities: %{@flat | str: 14, dex: 12}
      }

      stats = Rules.compute(build, ruleset)

      assert stats.weapon_type_attack_bonus == 4
      assert stats.race_attack_bonus == 4

      # 17 BAB варвара + 1 ловкости + 4 + 4 = 26; в игре было 31, и разница
      # ровно в +5 самой пращи, которых билд здесь не несёт.
      assert {stats.base_attack, stats.attack_bonus} == {17, 26}
    end

    # ⚠️ Тиры 1 и 5 — ВЫВОД, а не наблюдение: замерен один тир (3) и один вид
    # бонуса (атака). Кейс назван так, чтобы следующий читатель не принял его
    # за второй замер.
    test "тир 1 и тир 5 посчитаны формулой, а не замерены", %{ruleset: ruleset} do
      assert Rules.compute(build(nil, 5, :longbow), ruleset).weapon_type_attack_bonus == 1
      assert Rules.compute(build(nil, 35, :longbow), ruleset).weapon_type_attack_bonus == 7

      assert Rules.compute(build(nil, 5, :longbow, impure?: true), ruleset).weapon_type_attack_bonus ==
               1

      assert Rules.compute(build(nil, 35, :longbow, impure?: true), ruleset).weapon_type_attack_bonus ==
               5
    end

    # 🔴 Двулезвийный меч растёт НЕ ПО ТИРУ — у него в скриптах своя ветка
    # («AC, override»): `floor(min(HD, 40) × 9 / 40)`, минуя классовый и
    # расовый множители. На 40-м обе формулы дают 9, поэтому до 3.181 разницы
    # не было видно нигде; ниже они расходятся, и тир-машинерия дала бы
    # сагровику 4 там, где в игре 3.
    test "у двулезвийного меча щитовой AC растёт линейно, а не ступенями", %{ruleset: ruleset} do
      # {уровень, щитовой AC}; `floor(уровень × 9 / 40)`
      for {level, ac} <- [{1, 0}, {17, 3}, {20, 4}, {31, 6}, {39, 8}, {40, 9}, {41, 9}] do
        pure = Rules.compute(build(nil, level, :two_bladed_sword, ranks: 4), ruleset)

        mixed =
          Rules.compute(build(nil, level, :two_bladed_sword, impure?: true, ranks: 4), ruleset)

        assert counted(pure, :shield_ac) == ac, "сагровик, уровень #{level}"

        # и сагровику он тот же — «одинаковый для всех билдов»
        assert counted(mixed, :shield_ac) == ac, "не сагровик, уровень #{level}"
      end
    end

    # Положительный контроль к предыдущему: Дисциплина ТОГО ЖЕ оружия идёт
    # обычной ступенчатой веткой. Без этой пары кейс выше зеленел бы и у кода,
    # который выключил бы рост у всей записи целиком.
    test "у того же оружия Дисциплина растёт ступенями", %{ruleset: ruleset} do
      for {level, discipline} <- [{1, 3}, {17, 9}, {39, 15}, {40, 18}] do
        stats = Rules.compute(build(nil, level, :two_bladed_sword, ranks: 4), ruleset)

        assert stats.skill_values.discipline.weapon_type_bonus == discipline, "уровень #{level}"
      end
    end

    # 🔴 Снапшот БЕЗ таблицы тиров считает по-старому и говорит об этом гэпом.
    # Умолчание направлено в сторону оговорки: данные, которые о росте молчат,
    # не имеют права молча начать его считать.
    #
    # ⚠️ Ruleset здесь СИНТЕТИЧЕСКИЙ — таблица вынута из слоя вызовом, а не
    # найдена живой записью: живая запись назавтра получает данные и контроль
    # перестаёт что-либо проверять (урок 3.85, пять контролей подряд).
    test "без таблицы тиров всё как до 3.181: гэп ниже 40-го", %{ruleset: ruleset} do
      without = put_in(ruleset.weapon_type_bonuses.scaling, nil)

      for level <- [1, 20, 21, 39] do
        stats = Rules.compute(build(nil, level, :longbow), without)

        assert stats.weapon_type_attack_bonus == 0, "уровень #{level}"

        assert {:missing_data, {:weapon_type_bonus_level, :longbow}} in stats.gaps,
               "уровень #{level}"
      end

      for level <- [40, 41] do
        stats = Rules.compute(build(nil, level, :longbow), without)

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

    # Дельта выводится из двух полных `compute` (CLAUDE.md §5), поэтому рост
    # бонуса на ступени виден в превью сам, без единой строки про оружие
    # в дельте. ⚠️ Раньше здесь проверялось появление бонуса из нуля; теперь —
    # ШАГ ступени, и это то же самое утверждение о механизме дельты.
    test "шаг ступени виден в дельте 39 → 40 сам", %{ruleset: ruleset} do
      %{before: before, after: later} =
        Rules.preview_level_up(build(nil, 39, :longbow), :fighter, ruleset)

      assert before.weapon_type_attack_bonus == 7
      assert later.weapon_type_attack_bonus == 9

      # 40-й чётный, базовой атаки он не даёт — значит вся разница это бонус
      assert later.attack_bonus - before.attack_bonus == 2
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
        skills: ranks(opts),
        gear: gear(weapon, opts)
      )
  end

  # ⚠️ Ранги нужны, чтобы навык вообще попал в `skill_values`: собственная
  # прибавка билда навык в панель не приводит (решение Dan 16.08.2026,
  # CLAUDE.md §6), и без рангов кейс про посох сравнивал бы `%{}` с `%{}`.
  defp ranks(opts) do
    cond do
      opts[:staff_ranks] ->
        %{
          1 => %{
            spellcraft: opts[:staff_ranks],
            concentration: opts[:staff_ranks],
            animal_empathy: opts[:staff_ranks],
            discipline: opts[:staff_ranks]
          }
        }

      opts[:ranks] ->
        %{1 => %{discipline: opts[:ranks]}}

      true ->
        %{}
    end
  end

  # ⚠️ `no_proficiency?` — не удобство, а сам кейс: магический посох фита
  # владения не требует вовсе, и раздавать ему пять фитов значило бы проверять
  # бонус на билде, которого игроку собирать не нужно.
  defp gear(nil, _opts), do: Gear.new([])

  defp gear(weapon, opts) do
    feats = if opts[:no_proficiency?], do: [], else: @proficiencies
    Gear.new([weapon: weapon, feats: feats] ++ gear_skills(opts))
  end

  defp gear_skills(opts), do: if(opts[:gear_skills], do: [skills: opts[:gear_skills]], else: [])

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
      root = BuildCalculator.TmpDir.unique_path!()
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

  # ---------------------------------------------------------------------------
  # 🔴 СТОРОЖ ФОРМУЛЫ РОСТА (задача 3.181).
  #
  # Число 40-го уровня осталось в данных и сменило роль: из источника значения
  # стало **сверкой**. Загрузчик прогоняет формулу по всем 56 числам обоих
  # файлов и роняет сборку на первом расхождении — тот же приём, что у
  # `bonus_spell_slots` (234 ячейки) и у таблицы прогрессии ПДК (40 ячеек).
  #
  # ⚠️ Проверяется НАМЕРЕННОЙ ПОЛОМКОЙ на копии `priv/rules`: сторож, который
  # никто не пробовал уронить, — это сторож, про который неизвестно, работает
  # ли он вообще.
  describe "сторож формулы роста: сверка с числами 40-го уровня" do
    @describetag :tmp_dir

    setup do
      root = BuildCalculator.TmpDir.unique_path!()
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    defp patch_weapon_fact(root, what, fun) do
      path = Path.join(root, "siala_41/systems.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["systems"], fn systems ->
          for system <- systems do
            if system["id"] == "weapon_system" do
              update_in(system["facts"], fn facts ->
                for fact <- facts, do: if(fact["what"] == what, do: fun.(fact), else: fact)
              end)
            else
              system
            end
          end
        end)

      File.write!(path, Jason.encode!(patched))
    end

    defp patch_races(root, fun) do
      path = Path.join(root, "siala_41/races.json")
      raw = path |> File.read!() |> Jason.decode!()
      File.write!(path, Jason.encode!(fun.(raw)))
    end

    # Контроль на сам стенд: нетронутая копия грузится молча. Без него любой
    # кейс ниже зеленел бы и от поломки, к делу не относящейся.
    test "нетронутая копия грузится", %{root: root} do
      assert %{"siala_41" => %{}} = Loader.load!(root)
    end

    test "подменённое число строки группы роняет сборку", %{root: root} do
      patch_weapon_fact(root, "bonuses_at_level_40", fn fact ->
        put_in(fact["value"]["ranged"]["sagra"], 10)
      end)

      assert_raise RuntimeError, ~r/growth formula gives 9/, fn -> Loader.load!(root) end
    end

    test "подменённое число расы роняет сборку", %{root: root} do
      patch_races(root, fn raw ->
        update_in(raw["races"], fn races ->
          for race <- races do
            if race["vanilla_id"] == "human",
              do: put_in(race["racial_bonus"]["at_level_40"]["base"], 13),
              else: race
          end
        end)
      end)

      assert_raise RuntimeError, ~r/states 13 for base/, fn -> Loader.load!(root) end
    end

    # 🔴 И у ВАРИАНТОВ, которых ядро не считает (расовое оружие), сверка тоже
    # идёт: именно на них держится доказательство, что четыре числа страницы —
    # одна арифметика, а не четыре отдельных факта.
    test "подменённое число НЕсчитаемого варианта роняет сборку тоже", %{root: root} do
      patch_races(root, fn raw ->
        update_in(raw["races"], fn races ->
          for race <- races do
            if race["vanilla_id"] == "half_orc",
              do: put_in(race["racial_bonus"]["at_level_40"]["racial_weapon"], 27),
              else: race
          end
        end)
      end)

      assert_raise RuntimeError, ~r/states 27 for racial_weapon/, fn -> Loader.load!(root) end
    end

    # Своя ветка двулезвийного меча: линейная, а не ступенчатая. Убрать её —
    # значит посчитать его чужой формулой, и на 40-м это видно сразу (6 против
    # написанных 9), то есть сторож ловит и подмену ИСПОЛНИТЕЛЯ, а не только
    # числа.
    test "снятая своя ветка двулезвийного меча роняет сборку", %{root: root} do
      patch_weapon_fact(root, "weapon_specific_bonus_overrides", fn fact ->
        update_in(fact["value"], fn entries ->
          for entry <- entries do
            if entry["weapon_id"] == "two_bladed_sword" do
              update_in(entry["bonuses"], fn bonuses ->
                for bonus <- bonuses,
                    do:
                      if(bonus["kind"] == "shield_ac",
                        do: Map.delete(bonus, "executor"),
                        else: bonus
                      )
              end)
            else
              entry
            end
          end
        end)
      end)

      assert_raise RuntimeError, ~r/growth formula gives 6/, fn -> Loader.load!(root) end
    end

    # ⚠️ Лестница тиров обязана быть СПЛОШНОЙ. Дыра между ступенями означала бы
    # уровень, на котором бонуса нет вовсе, и заметить это можно было бы только
    # по числу у игрока.
    test "разрыв в лестнице тиров роняет сборку", %{root: root} do
      patch_weapon_fact(root, "bonuses_level_tiers", fn fact ->
        update_in(fact["value"]["tiers"], fn tiers ->
          for tier <- tiers, do: if(tier["tier"] == 2, do: %{tier | "to" => 15}, else: tier)
        end)
      end)

      assert_raise RuntimeError, ~r/tier ladder jumps/, fn -> Loader.load!(root) end
    end

    # Закрытый шаг: снапшот, назвавший шаг, которого ядро не знает, посчитал бы
    # бонус БЕЗ него — то есть тихо занизил бы число, а не упал.
    test "неизвестный шаг множителя роняет сборку", %{root: root} do
      patch_weapon_fact(root, "bonuses_level_tiers", fn fact ->
        put_in(fact["value"]["variant_multipliers"]["sagra"], ["minisets"])
      end)

      assert_raise RuntimeError, ~r/step "minisets"/, fn -> Loader.load!(root) end
    end

    # Забытый вариант — та же тихая потеря, только у половины чисел записи.
    test "забытый вариант множителей роняет сборку", %{root: root} do
      patch_weapon_fact(root, "bonuses_level_tiers", fn fact ->
        update_in(fact["value"]["variant_multipliers"], &Map.delete(&1, "sagra"))
      end)

      assert_raise RuntimeError, ~r/says nothing about in_group/, fn -> Loader.load!(root) end
    end

    # Исполнителя нет, а число есть — запись молча вернулась бы к прежнему
    # «считаем только на 40-м», то есть правка выглядела бы сделанной.
    test "число без исполнителя роняет сборку", %{root: root} do
      patch_weapon_fact(root, "bonuses_level_tiers", fn fact ->
        update_in(fact["value"]["executor_by_kind"], &Map.delete(&1, "attack_bonus"))
      end)

      assert_raise RuntimeError, ~r/executor_by_kind says nothing about it/, fn ->
        Loader.load!(root)
      end
    end

    # Магический посох (задача 3.183) — его числа держит тот же сторож, что
    # и остальные 52. Сверка идёт по БАЗОВОМУ числу, а сагровское страница
    # не печатает вовсе, поэтому кейсов два: подмена базы ловится сторожем
    # ПЕРЕНОСА (он стоит раньше), подмена второго числа — формулой.
    test "подменённое второе число посоха роняет сборку", %{root: root} do
      patch_weapon_fact(root, "weapon_specific_bonus_overrides", fn fact ->
        patch_staff(fact, fn bonus ->
          if bonus["kind"] == "concentration_skill", do: %{bonus | "sagra" => 19}, else: bonus
        end)
      end)

      assert_raise RuntimeError, ~r/growth formula gives 18/, fn -> Loader.load!(root) end
    end

    # Единица исполнителя — «тир × 2», как у Дисциплины и поглощения. Сбей её,
    # и на 40-м выйдет 6 вместо написанных 12.
    test "подменённая единица исполнителя посоха роняет сборку", %{root: root} do
      patch_weapon_fact(root, "bonuses_level_tiers", fn fact ->
        put_in(fact["value"]["executors"]["magic_staff"]["unit"], 1)
      end)

      assert_raise RuntimeError, ~r/growth formula gives 6/, fn -> Loader.load!(root) end
    end

    test "снятый исполнитель посоха роняет сборку", %{root: root} do
      patch_weapon_fact(root, "bonuses_level_tiers", fn fact ->
        update_in(fact["value"]["executor_by_kind"], &Map.delete(&1, "spellcraft_skill"))
      end)

      assert_raise RuntimeError, ~r/executor_by_kind says nothing about it/, fn ->
        Loader.load!(root)
      end
    end

    # ⚠️ Базу посоха сторож переноса ловит раньше формулы, поэтому здесь
    # перенос снят: иначе кейс зеленел бы от ДРУГОГО сторожа и ничего
    # не говорил бы про формулу.
    test "база посоха без переноса ловится формулой", %{root: root} do
      path = Path.join(root, "siala_41/systems.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["systems"], fn systems ->
          for system <- systems do
            if system["id"] == "weapon_system" do
              update_in(system["facts"], fn facts ->
                facts
                |> Enum.reject(&(&1["what"] == "magic_staff_skill_bonus"))
                |> Enum.map(fn fact ->
                  if fact["what"] == "weapon_specific_bonus_overrides" do
                    patch_staff(fact, fn bonus ->
                      if bonus["kind"] == "spellcraft_skill",
                        do: %{bonus | "base" => 13},
                        else: bonus
                    end)
                  else
                    fact
                  end
                end)
              end)
            else
              system
            end
          end
        end)

      File.write!(path, Jason.encode!(patched))

      assert_raise RuntimeError, ~r/states 13 for base/, fn -> Loader.load!(root) end
    end
  end

  # ---------------------------------------------------------------------------
  # 🔴 СТОРОЖ ДВУХ НАПИСАНИЙ ОДНОГО ПРЕДЛОЖЕНИЯ (задача 3.183).
  #
  # Бонус магического посоха перенесён дважды: фактом `magic_staff_skill_bonus`
  # (предложение страницы целиком — навыки, число, кап) и записью в таблице
  # по оружию (то, что считает ядро). Первое нужно потому, что это единственная
  # цитата вики Сиалы про сложение бонусов к навыкам и про сам потолок +50;
  # второе — потому что считает только оно.
  #
  # Две копии одного числа расходятся молча, и проект на этом горел
  # (`bonus_feat_pool`, задача 3.85). Поэтому расхождение роняет сборку.
  describe "сторож двух написаний: перенос против применяемой записи" do
    @describetag :tmp_dir

    setup do
      root = BuildCalculator.TmpDir.unique_path!()
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    test "число переноса разошлось с записью", %{root: root} do
      patch_weapon_fact(root, "magic_staff_skill_bonus", fn fact ->
        put_in(fact["value"]["at_level_40"], 14)
      end)

      assert_raise RuntimeError, ~r/states 14 to spellcraft/, fn -> Loader.load!(root) end
    end

    test "кап переноса разошёлся с записью", %{root: root} do
      patch_weapon_fact(root, "magic_staff_skill_bonus", fn fact ->
        put_in(fact["value"]["within_cap"], 40)
      end)

      assert_raise RuntimeError, ~r/counts towards 40/, fn -> Loader.load!(root) end
    end

    # 🔴 ГЛАВНЫЙ КЕЙС: ровно то состояние, в котором данные простояли полтора
    # месяца, — перенос с числами есть, применять его нечем. Сборка обязана
    # падать вслух, а не молча считать посох пустым.
    test "перенос есть, применяемой записи нет", %{root: root} do
      patch_weapon_fact(root, "weapon_specific_bonus_overrides", fn fact ->
        update_in(fact["value"], fn entries ->
          Enum.reject(entries, &(&1["weapon_ru"] == "Магические посохи"))
        end)
      end)

      assert_raise RuntimeError, ~r/carries none/, fn -> Loader.load!(root) end
    end

    test "навык переноса, которого у записи нет", %{root: root} do
      patch_weapon_fact(root, "weapon_specific_bonus_overrides", fn fact ->
        patch_staff(fact, fn bonus ->
          if bonus["kind"] == "animal_empathy_skill", do: nil, else: bonus
        end)
      end)

      assert_raise RuntimeError, ~r/bonus to animal_empathy/, fn -> Loader.load!(root) end
    end

    # Контроль на сам стенд: снапшот БЕЗ факта-переноса законен (так выглядели
    # данные до 01.08.2026), и сторож обязан молчать, а не требовать его.
    test "переноса нет вовсе — сборка проходит", %{root: root} do
      path = Path.join(root, "siala_41/systems.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["systems"], fn systems ->
          for system <- systems do
            if system["id"] == "weapon_system" do
              update_in(system["facts"], fn facts ->
                Enum.reject(facts, &(&1["what"] == "magic_staff_skill_bonus"))
              end)
            else
              system
            end
          end
        end)

      File.write!(path, Jason.encode!(patched))

      assert %{"siala_41" => %{}} = Loader.load!(root)
    end

    # Одна правка на оба describe: patch_weapon_fact/3 объявлен выше и виден
    # здесь же, а posoh-специфичный обход записи — вот он.
    defp patch_staff(fact, fun) do
      update_in(fact["value"], fn entries ->
        for entry <- entries do
          if entry["weapon_ru"] == "Магические посохи" do
            update_in(entry["bonuses"], fn bonuses ->
              bonuses |> Enum.map(fun) |> Enum.reject(&is_nil/1)
            end)
          else
            entry
          end
        end
      end)
    end
  end
end
