defmodule BuildCalculatorWeb.Builder.GearImportEngineTest do
  @moduledoc """
  Свод экипировки против самого движка — четыре лога `.билд+` (задачи 3.187,
  3.206, 3.213).

  🔴 **Это сверка ОДЕТОГО персонажа с печатью игры, целиком из одного лога.**
  До `.билд+` производные статы проверялись четырьмя безвещевыми логами
  (`timonall`, `trina`, `nicha`, `hana` — `game_log_import_test.exs`), потому что
  блок «Вещи» заполнял игрок руками и сверять было не с чем. Здесь билд и вся
  экипировка читаются ОДНИМ `GameLogImport.parse/2` — ни одного числа руками, —
  и сверяются с `COMBAT STATS` и `CURRENT ABILITIES` того же файла.

  ## Что сошлось точка в точку (18.09.2026, третье поколение печати)

    * **AB, все три спаса и все шесть характеристик — у всех четырёх**;
    * **AC — у всех четырёх** (63 / 36 / 72 / 41). Здесь стояло «у двоих
      из четырёх»: у Хнюпиуса и Бора число отставало РОВНО на базу доспеха,
      которой лог не печатал, и это была пятая просьба к серверу. Третье
      поколение печатает `[CHEST] … [BaseAC:8]`, и обе разницы закрылись;
    * **HP** Хнюпиуса **1503** и Бора **1438** — оба измерены игрой.

  🔴 **Хнюпиус закрывает вопрос, ради которого заводилась правка модели спасов.**
  У него `Saving Throw Bonus (Universal)` 16 и `Specific (Fortitude)` 12 —
  28 при потолке 20. Игра печатает Стойкость **59**, модель даёт 59 при
  ОДНОМ клипе на сейв; чтение «у каждого поля свой +20» дало бы **67**.

  ⚠️ **Бор доказывает вторую половину: раздельная прибавка вообще считается.**
  Стойкость 3 + 11 = 14, до потолка далеко; выбрось раздельные — получилось бы
  45 вместо 56.

  ⚠️ **Единственное расхождение — и оно НЕ наше: шапка Брунны печатает AC 40
  при 36 в листе.** Слово Dan 18.09.2026 (кейс `AU1` закрыт): «У Брунны
  в чарлисте 36 АЦ, похоже на нее действовал haste, поэтому в шапке было 40.
  В общем все ок, это был бафф». То есть `COMBAT STATS` — **состояние
  на момент команды**, а не голый лист: активные эффекты в него входят, а баффы
  модель не считает вовсе (CLAUDE.md §9). Закреплено обоими числами и разностью.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Resistances, Skills}
  alias BuildCalculatorWeb.Builder.GameLogImport

  @ruleset Data.ruleset!("siala_41")

  defp geared(name) do
    text =
      "../../fixtures/game_logs_plus/#{name}.log" |> Path.expand(__DIR__) |> File.read!()

    result = GameLogImport.parse(text, @ruleset)

    %{
      log: result.log,
      build: result.build,
      stats: Rules.compute(result.build, @ruleset),
      report: result.gear_report
    }
  end

  defp build(name), do: geared(name).build

  # ------------------------------------------------- сквозная сверка --

  # Числа справа — `COMBAT STATS` и `CURRENT ABILITIES` самих логов, и тест
  # сверяет их же со своим источником, а не с набранной второй раз копией.
  for {name, ab, fort, ref, will} <- [
        {"hnyupius", 57, 59, 45, 48},
        {"brunna", 25, 50, 22, 28},
        {"moxie", 31, 50, 45, 63},
        {"bor", 50, 56, 22, 22}
      ] do
    test "#{name}: AB, все три спаса и шесть характеристик совпадают с игрой — из одного лога" do
      %{log: log, stats: stats} = geared(unquote(name))

      assert log.combat_stats.ab == unquote(ab)
      assert stats.attack_bonus == unquote(ab)
      assert {stats.fort, stats.ref, stats.will} == {unquote(fort), unquote(ref), unquote(will)}
      assert stats.abilities == log.current_abilities
    end
  end

  # 🔴 РАДИ ЧЕГО ЗАДАЧА 3.213: AC сходится у ВСЕХ, у кого шапка печатает голый
  # лист. У Хнюпиуса и Бора он отставал ровно на базу доспеха (58 против 63,
  # 34 против 41), и закрыла разницу одна строка печати — `[BaseAC:8]`
  # и `[BaseAC:7]`. ⚠️ Роба и одеяние несут `[BaseAC:0]`, и это ЗНАЧАЩИЙ ноль:
  # AC-бонусы монаха гасит надетый предмет с НЕНУЛЕВОЙ базой, поэтому 72 Мокси
  # — положительный контроль на то, что нулевая база их не погасила.
  for {name, ac, armor} <- [
        {"hnyupius", 63, :full_plate},
        {"moxie", 72, :none},
        {"bor", 41, :half_plate}
      ] do
    test "#{name}: AC в экипировке совпадает с игрой — база доспеха из лога" do
      %{log: log, stats: stats, build: build} = geared(unquote(name))

      assert build.gear.worn[:armor] == unquote(armor)
      assert log.combat_stats.ac == unquote(ac)
      assert stats.ac_geared == unquote(ac)
    end
  end

  # ⚠️ ЧЕТВЁРТЫЙ ЛОГ — ЕДИНСТВЕННЫЙ, ГДЕ ШАПКА И ЛИСТ РАЗОШЛИСЬ, И ЭТО НЕ НАШЕ
  # РАСХОЖДЕНИЕ. Слово Dan 18.09.2026 (кейс `AU1`): «У Брунны в чарлисте 36 АЦ,
  # похоже на нее действовал haste, поэтому в шапке было 40. В общем все ок, это
  # был бафф». `haste` как свойство предмета — всегда бонус уклонения
  # (`fandom:Armor class` называет его единственным исключением из правила
  # «тип решает предмет»), и +4 — ровно разница.
  #
  # 🔴 Урок шире одного лога: `COMBAT STATS` шапки — СОСТОЯНИЕ НА МОМЕНТ
  # КОМАНДЫ, а не голый лист персонажа. Сверять с ней можно только зная, что
  # на персонаже ничего не висело; у остальных трёх логов не висело.
  test "Брунна: модель 36 — как в листе, шапка 40 — с баффом, разница ровно 4" do
    %{log: log, stats: stats, build: build} = geared("brunna")

    assert stats.ac_geared == 36
    assert log.combat_stats.ac == 40
    assert log.combat_stats.ac - stats.ac_geared == 4

    # ⚠️ Доспех при этом прочитан и надет — туника с `[BaseAC:0]`: расхождение
    # не про базу, и это надо было различить.
    assert build.gear.worn[:armor] == :none
  end

  # 🔴 Тот самый разбор: 16 universal + 12 к Стойкости = 28, потолок 20.
  test "Хнюпиус: 28 вещевых в Стойкость превращаются в 20, а не в 28" do
    %{stats: stats, build: build} = geared("hnyupius")

    assert {build.gear.saves, build.gear.saves_specific} == {16, %{fort: 12, will: 3}}
    assert stats.gear_save_bonuses.fort == 28
    assert stats.save_cap_clipped.fort == -8

    # Конкурирующее чтение «у каждого поля свой +20» дало бы на восемь больше,
    # и игра его не подтверждает.
    assert stats.fort == 59
    refute stats.fort == 67
  end

  test "Бор: раздельная прибавка к Стойкости считается — иначе было бы 45" do
    %{stats: stats, build: build} = geared("bor")

    assert build.gear.saves_specific == %{fort: 11, will: 3}
    assert stats.fort == 56
    assert stats.fort - 11 == 45
  end

  # 🔴 **ЧЕТВЁРТЫЙ ЛОГ СОШЁЛСЯ ПО СПАСАМ с 12.09.2026, задача 3.197.** Здесь
  # стоял тест «Брунна: расхождение целиком объясняется прибавкой Spellcraft»:
  # 42 ранга давали +8 ко всем трём спасам, модель печатала 51/30/36 против
  # игровых 50/22/28, и расхождение было ЗАКРЕПЛЕНО, чтобы починка с любой
  # стороны уронила тест вслух. Она и уронила.
  #
  # Ответ Dan на кейс `AQ1` (12.09.2026): «спасы от Spellcraft в листе персонажа
  # не видна». Прибавка условная — против заклинаний, — и в базовые Fort/Refl/
  # Will листа не входит. Число было верным, неверно было то, О ЧЁМ оно.
  #
  # ⚠️ Обе половины в одном тесте намеренно: «сходится» поодиночке зеленело бы
  # и у модели, которая прибавку потеряла вовсе. Условное число обязано давать
  # ровно те 51/30/36, что печатались до задачи, — это положительный контроль
  # на то, что число переложили, а не выбросили.
  test "Брунна: прибавка Spellcraft стоит рядом со спасами, а не внутри них" do
    %{stats: stats} = geared("brunna")

    # 🔴 **ЗДЕСЬ СТОЯЛО 8, ПОТОМ 12, ТЕПЕРЬ 14** — и каждый шаг не «поправка
    # числа», а новое слагаемое. 8 — «42 ранга, восемь предложенных очков»;
    # задача 3.202 стала считать прибавку от ПОЛНОГО значения навыка (42 ранга
    # + 18 модификатора интеллекта = 60, это 12); задача 3.213 положила
    # в руку **посох**, который лог печатает базовым типом, а посох даёт +12
    # к Spellcraft (бонус за тип оружия, задача 3.183) — значение 72, прибавка
    # **14**. До третьего поколения печати оружие в руку не ложилось вовсе,
    # и это слагаемое было нулём не по правилу, а по неполноте лога.
    value = Skills.value(build("brunna"), @ruleset, :spellcraft, 40)

    assert {value.ranks, value.ability_modifier, value.gear_bonus, value.weapon_type_bonus,
            value.total} == {42, 18, 0, 12, 72}

    assert stats.skill_save_bonus == 14

    assert Enum.map(stats.conditional_save_terms, &{&1.skill, &1.scope, &1.bonus}) ==
             [{:spellcraft, "spells", 14}]

    # …и три числа «против заклинаний».
    assert {stats.saves_conditional.fort, stats.saves_conditional.ref,
            stats.saves_conditional.will} == {51, 36, 42}

    # ⚠️ Стойкость получает +1, а не +14, потому что у неё вещевой пул 19
    # и прибавка упирается в потолок 20 — тот самый случай, из-за которого
    # расхождение с игрой было единицей, а не восьмёркой. Число рангов
    # на это не влияет вовсе: свободного очка там ровно одно.
    assert stats.conditional_save_bonus == %{fort: 1, ref: 14, will: 14}

    # Контроль: тот же билд без единого ранга — те же игровые числа и никакой
    # условной прибавки вовсе.
    without_ranks = %Build{build("brunna") | skills: %{}}
    bare = Rules.compute(without_ranks, @ruleset)

    assert {bare.fort, bare.ref, bare.will} == {50, 22, 28}
    assert bare.conditional_save_terms == []
  end

  # ⚠️ **ВТОРОЙ ЛОГ С РАНГАМИ — И У НЕГО ЧИСЛО НЕ СДВИНУЛОСЬ** (задача 3.202).
  # Мокси: 30 рангов, интеллект 16 (модификатор +3) — значение 33, и `div`
  # даёт те же шесть, что давали ранги. Пара с Брунной и есть весь ответ
  # на вопрос «насколько велика правка»: она двигает ровно те билды,
  # у которых модификатор характеристики перешагивает пятёрку.
  #
  # 🔴 А доезжает у Мокси НОЛЬ, и это не потеря: вещевые спасы 22 сами упёрты
  # в потолок +20, свободных очков нет вовсе. Ровно тот случай, ради которого
  # интерфейс печатает «+0 (потолок)» словом, а не молчанием.
  test "Мокси: 30 рангов + мод INT +3 = 33 — прибавка те же 6, а доезжает 0" do
    %{stats: stats} = geared("moxie")

    value = Skills.value(build("moxie"), @ruleset, :spellcraft, 41)

    assert {value.ranks, value.ability_modifier, value.total} == {30, 3, 33}
    assert stats.skill_save_bonus == 6
    assert stats.gear_save_bonuses == %{fort: 22, ref: 22, will: 22}
    assert stats.conditional_save_bonus == %{fort: 0, ref: 0, will: 0}

    # Прибавка при этом НАЗВАНА — «ноль» здесь ответ, а не отсутствие правила.
    assert Enum.map(stats.conditional_save_terms, & &1.bonus) == [6]
  end

  # 🔴 Что осталось «не сложить» после третьего поколения — ОДНА строка на все
  # четыре лога, и она про фит, чей аргумент число урона (`Sneak Attack (+4d6)`).
  # Ни оружия, ни щита, ни доспеха, ни кусков, ни крафта, ни типа AC — больше
  # ни одной просьбы к серверу.
  test "Хнюпиус: в «не сложить» одна строка, и она не про сервер" do
    %{report: report} = geared("hnyupius")

    assert [%{reason: {:feat_unknown, {:unresolved, "Sneak Attack (+4d6)"}}}] = report.unresolved
  end

  for name <- ~w(brunna moxie bor) do
    test "#{name}: «не сложить» пусто целиком" do
      assert geared(unquote(name)).report.unresolved == []
    end
  end

  # ------------------------------------------- поглощение стихий (3.210) --

  # 🔴 ✅ **Числа ИЗМЕРЕНЫ, кейс `AV1`, Dan 18.09.2026:** «У Хнюпиуса
  # действительно 45 от огня и 30 от всего остального». Здесь то же самое
  # ЦЕЛИКОМ ИЗ ЛОГА — вещевое поглощение читается из строк `Damage Resistance
  # (Fire) 15` / `(Cold) 15` на его мече, фит — из лестницы (`Energy
  # Resistance, Fire I` на 39-м), эффект расы и кусков — из расы и шапки.
  # Ни одного числа руками.
  test "Хнюпиус: огонь 45 и холод 30 — из одного лога, как в игре" do
    %{build: build, stats: stats} = geared("hnyupius")

    assert build.gear.resistances == %{fire: 15, cold: 15}

    assert Resistances.total(stats.resistances, :fire) == 45
    assert Resistances.total(stats.resistances, :cold) == 30

    # ...и остальные пять — те же 30 «от всего остального»
    for type <- [:acid, :electrical, :sonic, :negative_energy, :positive_energy] do
      assert Resistances.total(stats.resistances, type) == 30, "#{type}"
    end
  end

  # 🔴 ФИЗИЧЕСКОЕ поглощение — в «не наше» и ПО РЕШЕНИЮ, а не в «не сложить».
  # Разница дорогая: `unresolved` есть список доработок сервера, и строка,
  # которую мы решили не считать, попав туда, отправила бы админов чинить
  # то, что не сломано.
  for {name, lines} <- [{"brunna", 3}, {"bor", 2}] do
    test "#{name}: физическое поглощение — «решением не считаем», #{lines} строки" do
      %{build: build, report: report} = geared(unquote(name))

      physical =
        for entry <- report.not_ours,
            entry.kind == :damage_resistance,
            entry.reason == {:decided_not_modelled, :physical},
            do: entry

      assert length(physical) == unquote(lines)
      assert report.unresolved == []
      # ...и ни одной стихии от них не прибавилось
      assert build.gear.resistances == %{}
    end
  end

  # Божественный урон — тоже «не наше», но ДРУГОЙ фразой: его не поглощают
  # в самой игре, а не мы решили не считать.
  test "Мокси: божественный урон — не наша механика, а не решение" do
    %{report: report} = geared("moxie")

    assert [%{reason: {:property_not_modelled, :divine}}] =
             for(entry <- report.not_ours, entry.kind == :damage_resistance, do: entry)
  end

  # 🔴 Инвариант вёдер на всех четырёх логах и после правки: сумма та же, 278,
  # а состав сдвинулся ровно на две строки Хнюпиуса (`not_ours` → `applied`).
  # Прогон 18.09.2026: было 143 / 134 / 1, стало **145 / 132 / 1**.
  test "вёдра по четырём логам: 145 / 132 / 1, сумма прежняя" do
    totals =
      for name <- ~w(hnyupius brunna moxie bor) do
        report = geared(name).report
        {length(report.applied), length(report.not_ours), length(report.unresolved)}
      end

    {applied, not_ours, unresolved} =
      Enum.reduce(totals, {0, 0, 0}, fn {a, n, u}, {x, y, z} -> {x + a, y + n, z + u} end)

    assert {applied, not_ours, unresolved} == {145, 132, 1}
    assert applied + not_ours + unresolved == 278
  end

  # ------------------------------------------------------------ HP --

  # 🔴 ЗАДАЧА 3.204 — ВТОРОЕ ВЗЯТИЕ `Epic toughness` С ВЕЩЕЙ, И ЭТО ТОТ ЖЕ
  # ПЕРСОНАЖ, ЧТО В РЕПОРТЕ. Хнюпиус — билд владельца (Карлик, воин 10 /
  # защитник 23 / мастер оружия 7); 13.09.2026 он написал: «в игре у меня 1503,
  # а в билдере показывает 1437». Лог `.билд+` HP не печатает вовсе, поэтому
  # число приходит из репорта, а всё остальное — из лога и свода.
  test "Хнюпиус: 1503 HP из одного лога — куски, крафт и фиты с вещей прочитаны сами" do
    %{stats: stats, build: build} = geared("hnyupius")

    assert build.gear.mini_sets == [3, 2, 2]
    assert build.gear.named_items == 0
    assert build.gear.feats == [:blind_fight, :cleave, :epic_toughness, :epic_toughness]
    assert build.gear.weapon == :bastard_sword
    assert build.gear.worn == %{armor: :full_plate, shield: :tower}

    assert stats.hp == 1503
    assert stats.hp_breakdown.gear_bonus.count == 7
    assert stats.hp_breakdown.gear_bonus.percent == 66

    # База без кусков — то самое число, которое даёт обратный счёт от 1503.
    bare = %Build{build | gear: %{build.gear | mini_sets: []}}
    assert Rules.compute(bare, @ruleset).hp == 906

    # Отрицательный контроль: с ОДНИМ взятием было бы 1470, и ровно это
    # печаталось до задачи 3.204 — то есть тест упадёт и если стак пропадёт,
    # и если он вдруг начнёт считать третью строку пояса.
    one = %Build{build | gear: %{build.gear | feats: [:blind_fight, :cleave, :epic_toughness]}}
    assert Rules.compute(one, @ruleset).hp == 1470
  end

  # Бор: четыре куска по шапке без единой строки `[SetID]` (старый персонаж,
  # отметку на вещах добавили позже — слово Dan) — одна группа `[4]`, и HP
  # считается по ячейке 4. ✅ ИЗМЕРЕНО Dan 13.09.2026: «у Бора 1438 HP» — то есть
  # чтение `mini_sets: [header]` подтверждено движком, а не только именем
  # переменной скрипта (кейс `AT2`, первая половина).
  test "Бор: куски из шапки без номеров наборов — ячейка 4, игровые 1438" do
    %{stats: stats, build: build, report: report} = geared("bor")

    assert build.gear.mini_sets == [4]
    assert stats.hp_breakdown.gear_bonus.count == 4
    assert stats.hp_breakdown.gear_bonus.percent == 36
    assert stats.hp == 1438
    assert report.counts.notes == [{:mini_set_groups_unverified, 4, []}]
  end

  # ⚠️ Брунна: шапка называет ШЕСТЬ крафтовых, а замер `AS1` (12.09.2026)
  # снят при ЧЕТЫРЁХ — 813 HP при `Ctotal` 4. Это НЕ спор двух счётов одного
  # состояния: Dan 13.09.2026 — «при замерах я менял вещи, снимал что-то,
  # надевал другое» (кейс `AT1` закрыт снятием посылки). Модель берёт число
  # сервера и печатает 926 для состояния лога; 813 при четырёх остаётся рядом
  # как та же формула на измеренной ячейке — обе строки про одну арифметику.
  test "Брунна: шесть крафтовых по шапке — 926, а не 813 замера AS1 при четырёх" do
    %{stats: stats, build: build} = geared("brunna")

    assert build.gear.named_items == 6
    assert stats.hp == 926
    assert stats.hp_breakdown.gear_bonus.count == 6

    four = %Build{build | gear: %{build.gear | named_items: 4}}
    assert Rules.compute(four, @ruleset).hp == 813
  end

  # 🔴 ЗАМЕР `AS1` (Dan, 12.09.2026) — ПРОЦЕНТ К HP ЗА НАДЕТОЕ, ЧЕТЫРЕ
  # СОСТОЯНИЯ ОДНОГО ПЕРСОНАЖА. До него единственным словом про второй вход
  # формулы (`Ctotal = Cgear + Nmini`) был разбор серверных скриптов и одна
  # фраза вики («бонус ХП, идентичный бонусу от крафта»); кусками мини-сетов
  # проверялся только кейс `AP1`, и крафтовые вещи не проверялись ничем.
  #
  # Дословно: «Замер 1: wizard 10, pale master 30, CON = 26, HP = 813,
  # крафтовых вещей = 4. Замер 2: … CON = 30, HP = 1050, крафтовых вещей = 4,
  # кусков из одного набора мини-сетов 2. фиты не менялись», далее «снял две
  # крафтовые… HP = 922» и «снял еще одну крафтовую вещь… HP = 867».
  #
  # | состояние                        | CON | Ctotal | процент |  HP  |
  # |----------------------------------|-----|--------|---------|------|
  # | 4 крафтовые                      |  26 |      4 |    36 % |  813 |
  # | 4 крафтовые + 2 куска            |  30 |      6 |    55 % | 1050 |
  # | 2 крафтовые + 2 куска            |  30 |      4 |    36 % |  922 |
  # | 1 крафтовая + 2 куска            |  30 |      3 |    28 % |  867 |
  #
  # ⚠️ Третья строка — главная: тот же `Ctotal` набран ДРУГИМ способом и дал
  # тот же процент, то есть крафтовая вещь и кусок мини-сета в счёте
  # взаимозаменяемы. Без неё «сумма двух счётчиков» осталась бы чтением
  # скрипта.
  #
  # ⚠️ Ячейки 5 и 7–10 и ОБРЫВ В НОЛЬ на одиннадцатой вещи не измерены
  # по-прежнему — они держатся на чтении `switch`, и это записано в данных
  # (`systems.json` → `mini_sets.hp_percent_by_item_count`).
  test "Брунна: четыре состояния процента к HP сходятся с игрой" do
    base = build("brunna")

    for {named, pieces, con_gear, hp, count, percent} <- [
          {4, [], 0, 813, 4, 36},
          {4, [2], 4, 1050, 6, 55},
          {2, [2], 4, 922, 4, 36},
          {1, [2], 4, 867, 3, 28}
        ] do
      stats = Rules.compute(with_gear(base, named, pieces, con_gear), @ruleset)

      assert stats.hp == hp, "#{named} крафтовых + #{inspect(pieces)}"
      assert stats.hp_breakdown.gear_bonus.count == count
      assert stats.hp_breakdown.gear_bonus.percent == percent
      refute stats.hp_breakdown.gear_bonus.cut_off?
    end
  end

  # ⚠️ Контроль к таблице выше: без единой вещи в счёте прибавки нет вовсе,
  # и это те самые «база 598 и 678», из которых считаются четыре числа замера.
  test "Брунна: без крафта и кусков прибавки нет, а база видна" do
    base = build("brunna")

    assert Rules.compute(with_gear(base, 0, [], 0), @ruleset).hp == 598
    assert Rules.compute(with_gear(base, 0, [], 4), @ruleset).hp == 678
    assert Rules.compute(with_gear(base, 0, [], 0), @ruleset).hp_breakdown.gear_bonus == nil
  end

  # ⚠️ Телосложение двигается ВЕЩАМИ, а не правкой поинт-бая: замер снят тем
  # же персонажем в другой экипировке, и `+4 CON` — это ретроактивные `+2`
  # к модификатору на каждом из сорока уровней (измерено 16.08.2026).
  defp with_gear(%Build{gear: gear} = build, named, pieces, con) do
    abilities = Map.update(gear.abilities, :con, con, &(&1 + con))

    %Build{build | gear: %{gear | named_items: named, mini_sets: pieces, abilities: abilities}}
  end

  # -------------------------------------------------- URL-код (задача 3.213) --
  #
  # `worn.armor` кодировался и раньше — `Encoding` пишет любую пару категория/
  # предмет как псевдо-слот уровня 0 (`EncodingTest`, «надетое переживает круг»)
  # безотносительно к тому, откуда она взялась, ручной ввод или импорт лога.
  # Этот тест не пробивает новый путь кодека, а закрывает вопрос постановки
  # («если такого ещё нет») для ИМПОРТИРОВАННОГО билда целиком: оружие,
  # вторая рука, куски, крафт и раздельные спасы уже читались с логов
  # раньше — доспех теперь тоже, и весь этот набор обязан пережить круг разом.
  for name <- ~w(hnyupius brunna moxie bor) do
    test "#{name}: импортированный билд переживает encode/decode целиком" do
      %{build: build} = geared(unquote(name))

      assert {:ok, %{build: decoded, dropped: []}} = Encoding.decode(Encoding.encode(build))

      # ⚠️ `class_choices` — ЕДИНСТВЕННОЕ ПОЛЕ, которое круг не обязан вернуть
      # в исходном порядке, и это не наша находка: `EncodingTest` («домены
      # доезжают до билда целиком, отсортированными») давно закрепляет, что
      # кодек сортирует пару при кодировании (`class_key/2`) независимо от
      # того, в каком порядке игрок кликал по доменам. Мокси — клирик
      # с двумя доменами, и лог называет их не по алфавиту (`[:travel, :war]`),
      # так что голое `decoded == build` падало бы на свойстве кодека старше
      # этой задачи, а не на чём-то, что принесла база доспеха.
      assert sorted_class_choices(decoded) == sorted_class_choices(build)
    end
  end

  defp sorted_class_choices(%Build{class_choices: choices} = build),
    do: %Build{
      build
      | class_choices: Map.new(choices, fn {id, values} -> {id, Enum.sort(values)} end)
    }

  test "Хнюпиус: доспех из лога конкретно переживает круг" do
    %{build: build} = geared("hnyupius")

    assert build.gear.worn.armor == :full_plate

    assert {:ok, %{build: decoded}} = Encoding.decode(Encoding.encode(build))
    assert decoded.gear.worn.armor == :full_plate
    assert decoded.gear.worn.shield == :tower
  end
end
