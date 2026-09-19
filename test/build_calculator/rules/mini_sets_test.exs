defmodule BuildCalculator.Rules.MiniSetsTest do
  @moduledoc """
  Мини-сеты (задача 3.184) — таблица кейсов по одному источнику: разбор
  серверных скриптов шарда `docs/research/2026-09-11-miniset-scaling-system.md`
  (коммит `550bf26`), перенесённый в `priv/rules/siala_41/systems.json` →
  `mini_sets` и `weapon_system.bonuses_level_tiers`.

  Правило одной строкой: `B += floor(B · Nmini / 10)` — после уровня, классовой
  группы и расового совпадения, до капа исполнителя.

  ## `Nmini` — счёт КУСКОВ, а не наборов

  | надето         | `Nmini` | почему |
  |----------------|---------|--------|
  | `[A]`          | **0**   | одинокий кусок не считается вовсе |
  | `[A, B]`       | **0**   | два одиночки — тоже ноль |
  | `[A, A]`       | **2**   | |
  | `[A, A, A]`    | **3**   | |
  | `[A, A, B]`    | **2**   | `B` один, его группа в сумму не входит |
  | `[A, A, B, B]` | **4**   | |

  Цитата: «`number_minisets` is a qualifying **piece count**, not the number of
  completed groups: `[A,A] = 2`, `[A,A,A] = 3`, `[A,A,B] = 2`, `[A,A,B,B] = 4`,
  and `[A,B] = 0`».

  ## Что это даёт игроку — билд 40-го уровня, бонус к атаке

  | билд | без сетов | 4 куска | 10 кусков |
  |---|---|---|---|
  | обычный, оружие не расовое | 6 | 8 | **12** |
  | сагровик, оружие не расовое | 9 | 12 | **18** |
  | обычный, расовое оружие | 12 | 16 | **18** |
  | **сагровик + расовое оружие** | **18** | 18 | **18** |

  🔴 **Максимальному билду мини-сеты к этим бонусам не дают НИЧЕГО** — он
  упирается в кап исполнителя и без них. Это не баг, и оно закреплено тестом
  именно потому, что выглядит как баг.

  ## Два исключения

    * **щитовой AC двулезвийного меча** усиления не получает вовсе: его ветка
      линейная, «class, race, and mini-set transforms are bypassed»;
    * **у магического посоха своего капа нет** — единственный такой исполнитель
      из восьми («no scripted cap»), и потолком там остаётся ванильный `+50`
      на пул бонусов к навыку.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, MiniSets, Skills}

  # Все пять владений сразу: кейсы этого файла про усиление, а не про допуск
  # к оружию (это `gear_weapon_test.exs`), и отказ по владению превратил бы
  # половину из них в ложно-зелёные нули. Тот же приём, что в
  # `weapon_type_bonus_test.exs`.
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

  # Сагровик — билд, ВСЕ уровни которого взяты из классов Сагры; один уровень
  # барда выводит билд из группы («любой другой класс в билде нивелирует
  # преимущества»), и ровно это отличает две строки таблицы друг от друга.
  defp pure(n), do: List.duplicate(:fighter, n)
  defp mixed(n), do: List.duplicate(:fighter, n - 1) ++ [:bard]

  defp build(race, levels, weapon, sets) do
    Build.new(
      race: race,
      levels: levels,
      gear: Gear.new(weapon: weapon, feats: @proficiencies, mini_sets: sets)
    )
  end

  # Что система оружия и расы даёт бонусу атаки ВСЯ, тремя своими термами.
  # Именно эту сумму и режет кап исполнителя, поэтому спрашивается она,
  # а не одно слагаемое.
  defp system_attack(stats),
    do: stats.race_attack_bonus + stats.weapon_type_attack_bonus + stats.mini_set_attack_bonus

  describe "Nmini: счёт кусков, а не наборов" do
    # 🔴 ГЛАВНАЯ ЛОВУШКА ПРАВИЛА, и она стоит первой. Ошибиться здесь легко
    # двумя разными способами — прочитать «сколько сетовых вещей надето»
    # (дало бы 3 на `[2,1]`) и прочитать «сколько наборов собрано» (дало бы 1).
    test "таблица примеров источника", %{ruleset: rs} do
      cases = [
        {[], 0},
        {[1], 0},
        {[1, 1], 0},
        {[1, 1, 1], 0},
        {[2], 2},
        {[3], 3},
        {[2, 1], 2},
        {[2, 2], 4},
        {[3, 2], 5},
        {[4, 1, 1], 4}
      ]

      for {sets, expected} <- cases do
        build = build(:human, pure(40), nil, sets)

        assert MiniSets.pieces(build, rs) == expected,
               "#{inspect(sets)} должно давать Nmini #{expected}"
      end
    end

    # Отдельным тестом, а не строкой таблицы: это ровно те два случая, которые
    # постановка задачи назвала «легко сделать неправильно», и падать они
    # обязаны каждый со своим именем.
    test "[A, A, B] это 2, а не 3 — одиночка в счёт не идёт", %{ruleset: rs} do
      assert MiniSets.pieces(build(:human, pure(40), nil, [2, 1]), rs) == 2
    end

    test "[A, B] это 0 — двух одиночек мало", %{ruleset: rs} do
      assert MiniSets.pieces(build(:human, pure(40), nil, [1, 1]), rs) == 0
    end

    # Длина цикла слотов из самого скрипта: больше одиннадцати кусков надеть
    # некуда. ⚠️ Не наше ограничение и не потолок усиления — вики называет
    # максимумом ×2 на десяти, скрипт потолка на Nmini не ставит вовсе,
    # и спор решён рангом источника, а не замером. Цена выбора измерена
    # прогоном: 10 против 11 расходятся в 130 точках из 1078, все — в значениях
    # навыков и на единицу; у атаки и щитового AC расхождений ноль, там кап
    # исполнителя 18 кусает при обоих. Разбор — в самом факте данных.
    test "Nmini клипается одиннадцатью слотами", %{ruleset: rs} do
      assert MiniSets.pieces(build(:human, pure(40), nil, [11]), rs) == 11
      assert MiniSets.pieces(build(:human, pure(40), nil, [12]), rs) == 11
      assert MiniSets.pieces(build(:human, pure(40), nil, [6, 6]), rs) == 11
    end

    # Ванильный ruleset про мини-сеты не знает вовсе — значит усиливать нечем,
    # и Nmini ноль при любом вводе.
    test "у ванили мини-сетов нет вовсе", %{vanilla: rs} do
      assert MiniSets.pieces(build(:human, pure(40), nil, [10]), rs) == 0
      assert MiniSets.receivers(build(:human, pure(40), :longbow, [10]), rs) == []
    end
  end

  describe "бонус к атаке на 40-м уровне: таблица постановки" do
    # 🔴 ЧЕТЫРЕ СТРОКИ ТАБЛИЦЫ, И ЧЕТВЁРТАЯ — САМАЯ ВАЖНАЯ: максимальному
    # билду мини-сеты не дают ничего, потому что он упёрт в кап исполнителя
    # и без них. Без этой строки правку легко «починить» в сторону 36.
    #
    # Светлый эльф = Half-Elf, его расовый бонус — атака; расовое оружие для
    # него дальнобойное (лук), нерасовое — клинковое (меч, он даёт щитовой AC
    # и к атаке не идёт вовсе).
    test "обычный, оружие не расовое: 6 → 8 → 12", %{ruleset: rs} do
      assert_attack(rs, mixed(40), :longsword, [{[], 6}, {[4], 8}, {[10], 12}])
    end

    test "сагровик, оружие не расовое: 9 → 12 → 18", %{ruleset: rs} do
      assert_attack(rs, pure(40), :longsword, [{[], 9}, {[4], 12}, {[10], 18}])
    end

    test "обычный, расовое оружие: 12 → 16 → 18", %{ruleset: rs} do
      assert_attack(rs, mixed(40), :longbow, [{[], 12}, {[4], 16}, {[10], 18}])
    end

    test "сагровик + расовое оружие: 18 → 18 → 18, кап достигнут и без сетов",
         %{ruleset: rs} do
      assert_attack(rs, pure(40), :longbow, [{[], 18}, {[4], 18}, {[10], 18}])
    end

    # 🔴 Усиление считается от СУММЫ двух термов, а не от каждого порознь,
    # и различить два чтения можно только на НЕЧЁТНОМ произведении: у базы 12
    # и трёх кусков от суммы выходит 15, а по термам 6+1 и 6+1 = 14.
    # Целочисленное деление усекает, и два усечения меньше одного.
    test "три куска на базе 12 дают 15, а не 14", %{ruleset: rs} do
      assert_attack(rs, mixed(40), :longbow, [{[3], 15}])
    end

    defp assert_attack(rs, levels, weapon, cases) do
      for {sets, expected} <- cases do
        build = build(:half_elf, levels, weapon, sets)
        stats = Rules.compute(build, rs)

        assert system_attack(stats) == expected,
               "#{inspect(weapon)} + #{inspect(sets)}: ждали #{expected}, вышло " <>
                 "#{system_attack(stats)} (race #{stats.race_attack_bonus} + " <>
                 "wt #{stats.weapon_type_attack_bonus} + ms #{stats.mini_set_attack_bonus})"
      end
    end
  end

  describe "капы исполнителей: с обеих сторон" do
    # 🔴 БЕЗ МИНИ-СЕТОВ МАКСИМУМ РАВЕН КАПУ ТОЧКА В ТОЧКУ — ровно поэтому капы
    # год не были видны и не были перенесены. Эта половина теста ловит правку,
    # которая бы их случайно понизила.
    test "атака: максимум без сетов ровно 18", %{ruleset: rs} do
      stats = Rules.compute(build(:half_elf, pure(41), :longbow, []), rs)

      assert system_attack(stats) == 18
      assert stats.mini_set_attack_bonus == 0
    end

    test "щитовой AC: максимум без сетов ровно 18", %{ruleset: rs} do
      # Карлик = Gnome, его расовый бонус — щитовой AC; клинковое оружие даёт
      # тот же вид, и два терма складываются (страница печатает +12 и +18).
      stats = Rules.compute(build(:gnome, pure(41), :longsword, []), rs)

      assert shard_ac(stats) == 18
    end

    test "Дисциплина: максимум без сетов ровно 36", %{ruleset: rs} do
      value = discipline(rs, pure(41), :halberd, [])

      assert value.shard_race_bonus + value.weapon_type_bonus == 36
      assert value.mini_set_bonus == 0
    end

    # А эта половина — что с сетами кап РЕЖЕТ, и режет он сумму, а не термы.
    test "атака: с десятью кусками не выше 18", %{ruleset: rs} do
      for levels <- [pure(40), mixed(40)], sets <- [[2], [4], [10], [11]] do
        stats = Rules.compute(build(:half_elf, levels, :longbow, sets), rs)

        assert system_attack(stats) <= 18,
               "#{inspect(sets)}: #{system_attack(stats)} выше капа исполнителя"
      end
    end

    test "щитовой AC: с десятью кусками не выше 18", %{ruleset: rs} do
      for levels <- [pure(40), mixed(40)], sets <- [[2], [4], [10], [11]] do
        stats = Rules.compute(build(:gnome, levels, :longsword, sets), rs)

        assert shard_ac(stats) <= 18, "#{inspect(sets)}: #{shard_ac(stats)} выше капа"
      end
    end

    test "Дисциплина: с десятью кусками не выше 36", %{ruleset: rs} do
      for levels <- [pure(40), mixed(40)], sets <- [[2], [4], [10], [11]] do
        value = discipline(rs, levels, :halberd, sets)
        total = value.shard_race_bonus + value.weapon_type_bonus + value.mini_set_bonus

        assert total <= 36, "#{inspect(sets)}: #{total} выше капа"
      end
    end

    # Кап режет ровно там, где перебор: обычный Человек с древковым имеет 24,
    # десять кусков дают ему 48, и остаётся 36 — то есть +12, а не +24.
    test "обычный Человек с древковым: 24 → 36, а не 48", %{ruleset: rs} do
      without = discipline(rs, mixed(40), :halberd, [])
      with_sets = discipline(rs, mixed(40), :halberd, [10])

      assert without.shard_race_bonus + without.weapon_type_bonus == 24
      assert without.mini_set_bonus == 0
      assert with_sets.mini_set_bonus == 12
    end

    defp shard_ac(stats) do
      for %{source: {source, _id}} = term <- stats.ac_own_terms_geared,
          source in [:race, :weapon, :mini_sets],
          reduce: 0 do
        acc -> acc + term.ac
      end
    end

    defp discipline(rs, levels, weapon, sets) do
      build = build(:human, levels, weapon, sets)
      Skills.value(build, rs, :discipline, length(levels))
    end
  end

  describe "исключение 1: щитовой AC двулезвийного меча" do
    # Линейная ветка исполнителя AC проходит мимо ВСЕХ множителей: «class,
    # race, and mini-set transforms are bypassed». Число у неё +9 на 40-м
    # и не растёт ни от группы классов, ни от сетов.
    test "не растёт от сетов ни у сагровика, ни у обычного билда", %{ruleset: rs} do
      for levels <- [pure(40), mixed(40)], sets <- [[], [2], [10], [11]] do
        stats = Rules.compute(build(:human, levels, :two_bladed_sword, sets), rs)

        override =
          for %{executor: :ac_override} = receiver <- stats.mini_sets,
              do: {receiver.base, receiver.added, receiver.clipped}

        assert override == [{9, 0, 0}],
               "#{inspect(sets)}: линейная ветка получила усиление — #{inspect(override)}"
      end
    end

    # И второй половиной — что число на экране тоже не сдвинулось: AC билда
    # с двулезвийным мечом одинаков с сетами и без.
    test "AC билда не сдвигается", %{ruleset: rs} do
      without = Rules.compute(build(:human, pure(40), :two_bladed_sword, []), rs)
      with_sets = Rules.compute(build(:human, pure(40), :two_bladed_sword, [10]), rs)

      assert without.ac_geared == with_sets.ac_geared
    end
  end

  describe "исключение 2: у магического посоха своего капа нет" do
    # Единственный исполнитель из восьми без капа в скрипте («no scripted
    # cap»), и видно это стало только с мини-сетами: без них формула упирается
    # в свой максимум 18, и отличить «кап 18» от «капа нет» было нечем.
    test "три навыка посоха растут вдвое, а 18 не становится потолком", %{ruleset: rs} do
      for skill <- [:spellcraft, :concentration, :animal_empathy] do
        without = staff(rs, pure(40), [], skill)
        with_sets = staff(rs, pure(40), [10], skill)

        assert without.weapon_type_bonus == 18
        assert without.mini_set_bonus == 0
        assert with_sets.mini_set_bonus == 18, "#{skill}: усиление срезано капом, которого нет"
      end
    end

    test "обычный билд: 12 → 24", %{ruleset: rs} do
      value = staff(rs, mixed(40), [10], :spellcraft)

      assert value.weapon_type_bonus == 12
      assert value.mini_set_bonus == 12
    end

    # 🔴 Потолок у посоха всё же есть, и он ВАНИЛЬНЫЙ — +50 на пул бонусов
    # к навыку, названный самой страницей («входит в кап +50»). Своего капа
    # у исполнителя нет, но это не значит «нет потолка вовсе».
    test "ванильный кап +50 на пул остаётся и кусает", %{ruleset: rs} do
      build =
        Build.new(
          race: :human,
          levels: pure(40),
          gear:
            Gear.new(
              weapon: :magic_staff,
              feats: @proficiencies,
              skills: %{spellcraft: 20},
              mini_sets: [10]
            )
        )

      value = Skills.value(build, rs, :spellcraft, 40)

      assert value.weapon_type_bonus + value.mini_set_bonus + value.gear_bonus == 56
      assert value.bonus_capped?
      assert value.bonus_clipped == -6
    end

    defp staff(rs, levels, sets, skill) do
      build = build(:human, levels, :magic_staff, sets)
      Skills.value(build, rs, skill, length(levels))
    end
  end

  describe "усиление ниже 40-го уровня" do
    # Тир растёт по уровню персонажа (задача 3.181), и усиление умножает то,
    # что дал тир, — то есть на промежуточном уровне оно меньше. Две точки
    # взяты там, где тир меняется: 17-й (тир 3, единственная наблюдавшаяся
    # промежуточная точка, замер `AM1`) и 8-й (тир 2).
    test "тир 3 на 17-м уровне: 6 → 12", %{ruleset: rs} do
      assert_attack(rs, mixed(17), :longbow, [{[], 6}, {[10], 12}])
    end

    test "тир 2 на 8-м уровне: 4 → 8", %{ruleset: rs} do
      assert_attack(rs, mixed(8), :longbow, [{[], 4}, {[10], 8}])
    end

    # 🔴 И на 41-м ровно то же, что на 40-м: тир открытый сверху, кап тот же.
    test "41-й ведёт себя как 40-й", %{ruleset: rs} do
      for sets <- [[], [4], [10]] do
        at_40 = Rules.compute(build(:half_elf, mixed(40), :longbow, sets), rs)
        at_41 = Rules.compute(build(:half_elf, mixed(41), :longbow, sets), rs)

        assert system_attack(at_40) == system_attack(at_41)
      end
    end
  end

  describe "билд без мини-сетов" do
    # 🔴 ГЛАВНЫЙ КРИТЕРИЙ ЗАДАЧИ: вход по умолчанию пуст, и ни одно число
    # не сдвинулось. Проверяется не «ms == 0», а совпадение ВСЕХ производных
    # с билдом, у которого поля как не было.
    test "считается ровно как считался", %{ruleset: rs} do
      for race <- [:human, :half_elf, :gnome, :dwarf, :half_orc],
          weapon <- [nil, :longsword, :longbow, :halberd, :magic_staff, :two_bladed_sword],
          levels <- [pure(40), mixed(40), pure(1)] do
        plain =
          Build.new(
            race: race,
            levels: levels,
            gear: Gear.new(weapon: weapon, feats: @proficiencies)
          )

        empty = build(race, levels, weapon, [])

        assert Rules.compute(plain, rs) == Rules.compute(empty, rs)
      end
    end

    test "Nmini ноль, список получателей усиления пуст, оговорок нет", %{ruleset: rs} do
      stats = Rules.compute(build(:half_elf, pure(40), :longbow, []), rs)

      assert stats.mini_set_pieces == 0
      assert stats.mini_set_attack_bonus == 0
      assert Enum.all?(stats.mini_sets, &(&1.added == 0 and &1.clipped == 0))
      assert stats.hp_breakdown.gear_bonus == nil
      assert stats.hp == stats.hp_naked
    end

    # Одинокий кусок — «игрок что-то ввёл», но Nmini ноль: ни одного числа
    # он не двигает и ни одной оговорки не приносит.
    test "одинокий кусок не двигает числа и не приносит оговорок", %{ruleset: rs} do
      without = Rules.compute(build(:half_elf, pure(40), :longbow, []), rs)
      lone = Rules.compute(build(:half_elf, pure(40), :longbow, [1]), rs)

      assert without.attack_bonus == lone.attack_bonus
      assert lone.gaps == without.gaps
    end
  end

  describe "оговорки" do
    # 🔴 ОГОВОРКИ ПРО HP БОЛЬШЕ НЕТ, И ЭТО ПРОВЕРЯЕТСЯ, А НЕ ПОДРАЗУМЕВАЕТСЯ.
    # До задачи 3.186 билд с кусками говорил «в игре они дают ещё +15…+105 % HP,
    # а мы их не считаем». Теперь считаем (`Rules.GearHitPoints`), и оставить
    # признание значило бы пугать игрока тем, что уже сосчитано (CLAUDE.md §6).
    # Положительный контроль рядом: прибавка действительно доехала до числа.
    test "куски в счёт — про HP больше не оговариваемся, а считаем", %{ruleset: rs} do
      without = Rules.compute(build(:half_elf, pure(40), :longbow, []), rs)
      stats = Rules.compute(build(:half_elf, pure(40), :longbow, [2]), rs)

      refute Enum.any?(stats.gaps, fn
               {_, form} when is_atom(form) -> form |> to_string() |> String.contains?("hp")
               _ -> false
             end)

      assert stats.hp == without.hp + div(without.hp * 21, 100)
      assert stats.hp_naked == without.hp
    end

    # Прибавка к HP не зависит от того, нашлось ли что усиливать: куски
    # на персонаже, и HP они двигают даже у билда с пустыми руками.
    test "пустые руки — HP всё равно растёт", %{ruleset: rs} do
      stats = Rules.compute(build(:human, pure(40), nil, [3]), rs)

      assert stats.mini_set_pieces == 3
      assert stats.mini_sets == []
      assert stats.hp_breakdown.gear_bonus.percent == 28
      assert stats.hp > stats.hp_naked
    end

    # Ровно ОДИН терм на билд, а не по одному на получателя: процент считается
    # от HP, а HP у персонажа одно.
    test "один терм разбора, а не по одному на получателя", %{ruleset: rs} do
      stats = Rules.compute(build(:gnome, pure(40), :longsword, [2, 2, 2]), rs)

      assert %{count: 6, percent: 55} = stats.hp_breakdown.gear_bonus
    end

    # ⚠️ Прибавка к СКОРОСТИ оговорки не получает и не должна: скорость бега
    # калькулятор не считает вовсе, получателя нет, и по CLAUDE.md §9 дыры там
    # нет. Положительный контроль на это правило — иначе оговорку добавят
    # «для полноты».
    test "про скорость не говорится ничего", %{ruleset: rs} do
      stats = Rules.compute(build(:half_elf, pure(40), :longbow, [10]), rs)

      refute Enum.any?(stats.gaps, fn
               {_, form} when is_atom(form) -> form |> to_string() |> String.contains?("speed")
               _ -> false
             end)
    end

    # Геттеры правила (задача 3.185). Числа сюда не вписаны литералами —
    # они читаются из того же места, что и `pieces/2`, а тест проверяет
    # ДОГОВОР: у Сиалы ответ есть, у ванили его нет вовсе.
    #
    # ⚠️ Заведены ради веб-слоя: строка «1 кусок в счёт не идёт — нужно ≥ 2»
    # и предупреждение «кусков больше, чем слотов» обязаны называть числа,
    # а игровых чисел веб-слой не выдумывает (CLAUDE.md §5).
    test "slots/1 и minimum_group/1 отдают то же, чем считает pieces/2",
         %{ruleset: rs, vanilla: vanilla} do
      slots = MiniSets.slots(rs)
      smallest = MiniSets.minimum_group(rs)

      assert is_integer(slots) and slots > 0
      assert is_integer(smallest) and smallest > 1

      # `pieces/2` клипает ровно этим числом...
      assert MiniSets.pieces(build(:half_elf, pure(40), :longbow, [slots + 5]), rs) == slots

      # ...и считает группу с `smallest` кусками, а с `smallest - 1` — нет.
      assert MiniSets.pieces(build(:half_elf, pure(40), :longbow, [smallest]), rs) == smallest
      assert MiniSets.pieces(build(:half_elf, pure(40), :longbow, [smallest - 1]), rs) == 0

      # У ванили правила нет вовсе — и это тот же ответ, что у снапшота
      # без правила: показывать зону ввода нечему.
      assert MiniSets.slots(vanilla) == nil
      assert MiniSets.minimum_group(vanilla) == nil
    end

    # У ванили мини-сетов нет вовсе, значит и оговорок нет: заявленные куски
    # там просто не значат ничего. ⚠️ Это НЕ то же, что снапшот Сиалы без
    # правила — там оговорка есть, см. describe ниже.
    test "у ванили оговорок нет", %{vanilla: rs} do
      stats = Rules.compute(build(:half_elf, pure(40), :longbow, [10]), rs)

      refute {:missing_data, :mini_set_counting} in stats.gaps
      refute {:missing_data, :mini_set_hp_table} in stats.gaps

      # И ни одного числа заявленные куски там не двигают — ни бонусов,
      # ни HP: мини-сетов в NWN нет вовсе.
      assert stats.hp == stats.hp_naked
      assert stats.hp_breakdown.gear_bonus == nil
    end
  end

  # Снапшот БЕЗ правила мини-сетов: усиливать нечем, и билд говорит об этом.
  # ⚠️ Держится СИНТЕТИЧЕСКИМ ruleset'ом, а не живой записью, — контроль
  # на живой назавтра получает правило и молча перестаёт что-либо проверять
  # (урок задачи 3.85, пять контролей подряд).
  describe "снапшот без правила мини-сетов" do
    @describetag :tmp_dir

    setup do
      root = BuildCalculator.TmpDir.unique_path!()
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    test "считает как до задачи и говорит об этом", %{root: root} do
      drop_mini_set_facts(root)
      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.shard_bonus_scaling.mini_sets == nil

      build = build(:half_elf, pure(40), :longbow, [10])
      stats = Rules.compute(build, ruleset)

      # Усиления нет — числа ровно те же, что были до задачи 3.184...
      assert MiniSets.pieces(build, ruleset) == 0
      assert stats.mini_set_attack_bonus == 0
      assert system_attack(stats) == 18

      # ...и об этом сказано, а не умолчано.
      assert {:missing_data, :mini_set_counting} in stats.gaps

      # ⚠️ А про HP оговорки здесь НЕТ: таблица процентов у этого снапшота
      # на месте, и она читается своим фактом. Нечего считать — `Nmini` ноль,
      # именных вещей не заявлено, — и это не недостача данных, а ответ.
      refute {:missing_data, :mini_set_hp_table} in stats.gaps
      assert stats.hp == stats.hp_naked
    end

    # Тиры при этом остаются на месте: правило мини-сетов и таблица роста —
    # два разных факта, и снятие одного не должно уносить второй.
    # Геттеры правила (задача 3.185) — `nil`, а не «двойка по умолчанию»:
    # интерфейс по ним решает, показывать ли зону ввода вовсе, и подставленное
    # молча число завело бы игрока в форму, которая ничего не считает.
    test "slots/1 и minimum_group/1 отвечают nil, когда правила нет", %{root: root} do
      drop_mini_set_facts(root)
      ruleset = Loader.load!(root)["siala_41"]

      assert MiniSets.slots(ruleset) == nil
      assert MiniSets.minimum_group(ruleset) == nil
    end

    test "таблица тиров не задета", %{root: root} do
      drop_mini_set_facts(root)
      ruleset = Loader.load!(root)["siala_41"]

      assert is_list(ruleset.shard_bonus_scaling.tiers)

      assert Rules.compute(build(:half_elf, mixed(17), :longbow, []), ruleset).race_attack_bonus ==
               3
    end

    # 🔴 И СТОРОЖ КАПОВ: как только снапшот знает про мини-сеты, ключ `cap`
    # у тирового исполнителя обязателен — `null` («у скрипта его нет») это
    # законный ответ, а отсутствие ключа нет. Иначе забытый кап был бы невидим
    # ровно до первого билда с сетами, а там завысил бы число вдвое.
    test "исполнитель без ключа cap роняет сборку", %{root: root} do
      patch_tiers(root, fn fact ->
        update_in(fact["value"]["executors"]["attack"], &Map.delete(&1, "cap"))
      end)

      assert_raise RuntimeError, ~r/states no `cap`/, fn -> Loader.load!(root) end
    end

    # А без правила мини-сетов ключ не требуется: резать нечего, и требовать
    # заполненное поле, которого никто не читает, значило бы ронять сборку
    # за вопрос без наблюдаемого ответа.
    test "без правила мини-сетов ключ cap не требуется", %{root: root} do
      drop_mini_set_facts(root)

      patch_tiers(root, fn fact ->
        update_in(fact["value"]["executors"]["attack"], &Map.delete(&1, "cap"))
      end)

      assert %{"siala_41" => %{}} = Loader.load!(root)
    end

    # Линейной ветке кап запрещён: та же строка источника, что выводит её
    # из-под множителей, выводит её и из-под мини-сетов, — значит резать там
    # нечего, и кап у такой записи означал бы перенос по аналогии с соседями.
    test "кап у линейной ветки роняет сборку", %{root: root} do
      patch_tiers(root, fn fact ->
        put_in(fact["value"]["executors"]["ac_override"]["cap"], 18)
      end)

      assert_raise RuntimeError, ~r/is linear and states a `cap`/, fn -> Loader.load!(root) end
    end

    test "минимум группы 1 роняет сборку", %{root: root} do
      patch_mini_set_fact(root, "qualifying_piece_count", fn fact ->
        put_in(fact["value"]["minimum_group_size"], 1)
      end)

      assert_raise RuntimeError, ~r/not an integer above 1/, fn -> Loader.load!(root) end
    end

    test "делитель ноль роняет сборку", %{root: root} do
      patch_mini_set_fact(root, "bonus_amplification_arithmetic", fn fact ->
        put_in(fact["value"]["divisor"], 0)
      end)

      assert_raise RuntimeError, ~r/not an integer above 1/, fn -> Loader.load!(root) end
    end

    defp drop_mini_set_facts(root) do
      patch_system(root, "mini_sets", fn system ->
        update_in(system["facts"], fn facts ->
          Enum.reject(
            facts,
            &(&1["what"] in ~w(qualifying_piece_count bonus_amplification_arithmetic))
          )
        end)
      end)
    end

    defp patch_mini_set_fact(root, what, fun) do
      patch_system(root, "mini_sets", fn system ->
        update_in(system["facts"], fn facts ->
          for fact <- facts, do: if(fact["what"] == what, do: fun.(fact), else: fact)
        end)
      end)
    end

    defp patch_tiers(root, fun) do
      patch_system(root, "weapon_system", fn system ->
        update_in(system["facts"], fn facts ->
          for fact <- facts,
              do: if(fact["what"] == "bonuses_level_tiers", do: fun.(fact), else: fact)
        end)
      end)
    end

    defp patch_system(root, id, fun) do
      path = Path.join(root, "siala_41/systems.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["systems"], fn systems ->
          for system <- systems, do: if(system["id"] == id, do: fun.(system), else: system)
        end)

      File.write!(path, Jason.encode!(patched))
    end
  end
end
