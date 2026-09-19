defmodule BuildCalculator.Rules.GearHitPointsTest do
  @moduledoc """
  Процент к HP за надетое (задача 3.186) — таблица кейсов по одному источнику:
  разбор серверных скриптов шарда
  `docs/research/2026-09-11-miniset-scaling-system.md`, раздел 3 «Maximum-HP
  Scaling Formula» (коммит `550bf26`), перенесённый в
  `priv/rules/siala_41/systems.json` → `mini_sets` → `hp_percent_by_item_count`.

  Правило одной строкой:

      Ctotal = Cgear + Nmini
      HPbonus = floor(Hbase · (100 + P(Ctotal)) / 100) − Hbase

  ## Таблица процентов

  | `Ctotal` | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | **10** | **11+** |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | `P`, % | 15 | 21 | 28 | 36 | 45 | 55 | 66 | 78 | 91 | **105** | **0** |

  Цитата: «`Ctotal` selects the following HP percentage … 10 → 105%, greater
  than 10 → 0%».

  🔴 **Обрыв в ноль на одиннадцатой вещи — не опечатка, так написан switch**,
  и он стоит здесь под тестом **с обеих сторон**: правка, которая «починит»
  его по смыслу, обязана падать вслух. При базе 400 HP это разница между
  **+420** и **+0**.

  ## Примеры источника, воспроизведённые точка в точку

  `Hbase = 400`, раздел 3 документа:

  | надето | `Nmini` | `P` | прибавка |
  |---|---|---|---|
  | один одиночка | 0 | 0 % | 0 |
  | два куска одного набора | 2 | 21 % | 84 |
  | три куска одного набора | 3 | 28 % | 112 |
  | по два куска двух наборов | 4 | 36 % | 144 |
  | десять кусков в счёт | 10 | 105 % | 420 |
  | два куска + три именные вещи | 5 | 45 % | 180 |
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, GearHitPoints}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp build(sets, named, gear \\ []) do
    Build.new(
      race: :half_elf,
      levels: List.duplicate(:fighter, 40),
      base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
      gear: Gear.new(Keyword.merge([mini_sets: sets, named_items: named], gear))
    )
  end

  describe "арифметика: примеры источника при Hbase = 400" do
    # Считается `term/3` напрямую, а не через билд, ровно ради этой таблицы:
    # база 400 названа документом, и билда с такой базой в корпусе может
    # не оказаться. Числа — из раздела 3, столбец «HP bonus».
    test "шесть строк документа воспроизводятся точка в точку", %{ruleset: rs} do
      cases = [
        # Одинокий кусок не считается вовсе: `Ctotal` ноль, значит и терма нет —
        # «One singleton | 0 | 0% | 0».
        {[1], 0, nil},
        {[2], 0, {21, 84}},
        {[3], 0, {28, 112}},
        {[2, 2], 0, {36, 144}},
        {[10], 0, {105, 420}},
        {[2], 3, {45, 180}}
      ]

      for {sets, named, expected} <- cases do
        term = GearHitPoints.term(build(sets, named), rs, 400)

        got = term && {term.percent, term.amount}

        assert got == expected,
               "#{inspect(sets)} + #{named} именных: ожидалось #{inspect(expected)}, " <>
                 "вышло #{inspect(got)}"
      end
    end

    # 🔴 ЦЕЛОЧИСЛЕННО, А НЕ УМНОЖЕНИЕМ НА ДРОБЬ. `401 · 1.21 = 485.21`, и любое
    # округление дало бы либо 485, либо 486; `div(401 · 121, 100)` даёт 485
    # ВСЕГДА, потому что усекает, — ровно как NWScript.
    test "база, не делящаяся на сто, усекается вниз", %{ruleset: rs} do
      assert %{amount: 84} = GearHitPoints.term(build([2], 0), rs, 401)
      assert %{amount: 84} = GearHitPoints.term(build([2], 0), rs, 400)

      # И не «на единицу больше у большей базы»: у 409 при тех же 21 %
      # прибавка уже 85, и это не округление, а тот же div.
      assert %{amount: 85} = GearHitPoints.term(build([2], 0), rs, 409)
    end
  end

  describe "обрыв на одиннадцатой вещи" do
    # 🔴 ОБЕ СТОРОНЫ ОДНИМ ТЕСТОМ, иначе он будет потерян при первой же правке:
    # «Counts 0 and above 10 select 0%».
    test "десять вещей дают +105 %, одиннадцать — ноль", %{ruleset: rs} do
      assert %{count: 10, percent: 105, amount: 420, cut_off?: false} =
               GearHitPoints.term(build([10], 0), rs, 400)

      assert %{count: 11, percent: 0, amount: 0, cut_off?: true} =
               GearHitPoints.term(build([11], 0), rs, 400)
    end

    # То же самое по-настоящему — через `compute/2`, на живом билде: игрок,
    # надевший одиннадцатый кусок, теряет ВСЮ прибавку, а не её долю.
    test "билд с одиннадцатью кусками имеет ровно «голое» HP", %{ruleset: rs} do
      naked = Rules.compute(build([], 0), rs)
      ten = Rules.compute(build([10], 0), rs)
      eleven = Rules.compute(build([11], 0), rs)

      assert ten.hp == naked.hp + div(naked.hp * 105, 100)
      assert eleven.hp == naked.hp
      assert eleven.hp_breakdown.gear_bonus.cut_off?
    end

    # Счёт складывается из ДВУХ входов, и обрыв не различает, каким из них
    # набрана одиннадцатая вещь: девять кусков плюс две именные — те же 11.
    test "обрыв набирается и смесью входов", %{ruleset: rs} do
      assert %{count: 11, cut_off?: true} = GearHitPoints.term(build([9], 2), rs, 400)

      assert %{count: 10, cut_off?: false, percent: 105} =
               GearHitPoints.term(build([9], 1), rs, 400)
    end

    # Число, с которого начинается обрыв, отдаётся геттером: интерфейс обязан
    # предупредить игрока, у которого вещей девять, а игровых чисел веб-слой
    # не выдумывает (CLAUDE.md §5).
    test "cut_off_at/1 называет то же число, на котором обрывается term/3",
         %{ruleset: rs, vanilla: vanilla} do
      at = GearHitPoints.cut_off_at(rs)

      assert is_integer(at) and at > 1
      assert %{cut_off?: true} = GearHitPoints.term(build([at], 0), rs, 400)
      refute GearHitPoints.term(build([at - 1], 0), rs, 400).cut_off?

      assert GearHitPoints.cut_off_at(vanilla) == nil
    end
  end

  describe "именные и уникальные вещи — второй вход" do
    # Куски не нужны вовсе: одна именная вещь это уже +15 %.
    test "только именные вещи, без единого куска", %{ruleset: rs} do
      assert %{pieces: 0, named: 1, count: 1, percent: 15} =
               GearHitPoints.term(build([], 1), rs, 400)
    end

    # 🔴 Клип потолком СЛОТОВ, и число берётся из данных, а не из кода:
    # пятнадцать вещей надеть некуда, но ввод игрока хранится как введён
    # (расшаренная ссылка обязана открываться).
    test "ввод сверх числа слотов клипается потолком из данных", %{ruleset: rs} do
      slots = GearHitPoints.named_item_slots(rs)

      assert is_integer(slots) and slots > 0
      assert %{named: ^slots, count: ^slots} = GearHitPoints.term(build([], slots + 5), rs, 400)

      # ⚠️ И это НЕ тот же потолок, которым клипается `Nmini`: у кусков слотов
      # одиннадцать (правая рука считается), у именных вещей десять (её счёт
      # в скрипте закомментирован). Два числа, два слова источника.
      assert %{count: 11} = GearHitPoints.term(build([15], 0), rs, 400)
    end

    test "named_item_slots/1 у ванили отвечает nil", %{vanilla: vanilla} do
      assert GearHitPoints.named_item_slots(vanilla) == nil
    end

    # Блок «Вещи» обязан считать себя непустым: иначе «Из этого следует»
    # и «HP голым» промолчат на билде, у которого HP выросло вдвое.
    test "объявленная именная вещь делает экипировку непустой" do
      refute Gear.any?(Gear.new())
      assert Gear.any?(Gear.new(named_items: 1))
    end
  end

  describe "«голым» и «в экипировке»" do
    # 🔴 ГЛАВНЫЙ КОНТРОЛЬ ЗАДАЧИ: билд без кусков и без именных вещей
    # не сдвинулся ни на единицу.
    test "без надетого hp_naked равно hp, а терма разбора нет", %{ruleset: rs} do
      stats = Rules.compute(build([], 0), rs)

      assert stats.hp == stats.hp_naked
      assert stats.hp_breakdown.gear_bonus == nil
    end

    # 🔴 ВТОРОЙ ПРОХОД, А НЕ ВЫЧИТАНИЕ. Телосложение с вещей двигает HP
    # ретроактивно на всех уровнях (+12 CON превратили 760 в 1000, замер
    # 16.08.2026), и процент за надетое умножает итог, В КОТОРЫЙ ЭТО ВХОДИТ.
    # «Итог минус проценты» вернул бы число с вещевым телосложением внутри.
    test "hp_naked не знает ни вещевого телосложения, ни кусков", %{ruleset: rs} do
      plain = Rules.compute(build([], 0), rs)
      geared = Rules.compute(build([2], 0, abilities: %{con: 12}), rs)

      assert geared.hp_naked == plain.hp

      # Положительный контроль: в «одетом» числе вещевое телосложение есть,
      # и процент считается уже от него.
      con_grown = plain.hp + 6 * 40
      assert geared.hp == con_grown + div(con_grown * 21, 100)
    end

    test "hp_naked приходит nil ровно тогда, когда nil сам hp", %{ruleset: rs} do
      stats = Rules.compute(Build.new(levels: []), rs)

      assert stats.hp == 0
      assert stats.hp_naked == 0
    end
  end

  describe "разбор" do
    # Инвариант «сумма термов равна итогу» — с НЕнулевым термом за надетое.
    # Тот же инвариант на билде без вещей держит `compute_test.exs`.
    test "сумма термов разбора равна hp", %{ruleset: rs} do
      stats = Rules.compute(build([2, 2], 1, abilities: %{con: 4}), rs)
      breakdown = stats.hp_breakdown

      assert breakdown.gear_bonus.count == 5
      assert breakdown.gear_bonus.amount > 0

      assert Enum.sum(Enum.map(breakdown.by_class, & &1.subtotal)) +
               breakdown.con_term +
               Enum.sum(Enum.map(breakdown.by_feat, & &1.subtotal)) +
               breakdown.innate.amount +
               breakdown.gear_bonus.amount +
               breakdown.floor_adjustment == stats.hp
    end

    # Терм стоит РЯДОМ с `Toughness` и «Духом Сиалы», а не внутри них: иначе
    # разбор назвал бы чужое число именем фита.
    test "терм не подмешан ни в один соседний", %{ruleset: rs} do
      without = Rules.compute(build([], 0), rs)
      with_gear = Rules.compute(build([2], 0), rs)

      assert with_gear.hp_breakdown.by_class == without.hp_breakdown.by_class
      assert with_gear.hp_breakdown.by_feat == without.hp_breakdown.by_feat
      assert with_gear.hp_breakdown.innate == without.hp_breakdown.innate
      assert with_gear.hp_breakdown.con_term == without.hp_breakdown.con_term
    end

    # Оба входа названы по отдельности, а не одной суммой: разбор обязан уметь
    # ответить, откуда взялся счёт, — и это то, чем интерфейс объяснит обрыв.
    test "разбор называет куски и именные вещи по отдельности", %{ruleset: rs} do
      stats = Rules.compute(build([3], 2), rs)

      assert %{pieces: 3, named: 2, count: 5, percent: 45} = stats.hp_breakdown.gear_bonus
    end
  end

  describe "ваниль" do
    # У ванили ни мини-сетов, ни именных вещей шарда нет вовсе — заявленные
    # там вещи не значат НИЧЕГО и не приносят ни одной оговорки. ⚠️ Это НЕ то
    # же, что снапшот Сиалы без таблицы: там оговорка есть, см. describe ниже.
    test "ни числа, ни оговорки", %{vanilla: rs} do
      stats = Rules.compute(build([2, 2], 5), rs)

      assert stats.hp == stats.hp_naked
      assert stats.hp_breakdown.gear_bonus == nil
      assert Enum.filter(stats.gaps, &match?({_, :mini_set_hp_table}, &1)) == []
    end
  end

  # Снапшот Сиалы БЕЗ таблицы процентов: считать прибавку нечем, и билд
  # говорит об этом. ⚠️ Держится СИНТЕТИЧЕСКИМ ruleset'ом, а не живой записью,
  # — контроль на живой назавтра получает данные и молча перестаёт что-либо
  # проверять (урок задачи 3.85, пять контролей подряд).
  describe "снапшот без таблицы процентов" do
    @describetag :tmp_dir

    setup do
      root = BuildCalculator.TmpDir.unique_path!("rules_hp_")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    test "считает как до задачи и говорит об этом", %{root: root} do
      drop_hp_table(root)
      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.gear_hit_points == nil

      stats = Rules.compute(build([2, 2], 3), ruleset)

      # Прибавки нет — число ровно то же, что было до задачи 3.186...
      assert stats.hp == stats.hp_naked
      assert stats.hp_breakdown.gear_bonus == nil

      # ...и об этом сказано, а не умолчано.
      assert {:missing_data, :mini_set_hp_table} in stats.gaps

      # ⚠️ Усиление бонусов при этом на месте: таблица процентов и правило
      # счёта кусков — два разных факта, и снятие одного не уносит второй.
      assert stats.mini_set_pieces == 4
    end

    # Оговорка приходит ровно тогда, когда игроку есть что терять: ничего
    # не надето — сказать нечего.
    test "без надетого оговорки нет", %{root: root} do
      drop_hp_table(root)
      ruleset = Loader.load!(root)["siala_41"]

      assert Rules.compute(build([], 0), ruleset).gaps
             |> Enum.filter(&match?({_, :mini_set_hp_table}, &1)) == []

      # Одинокий кусок — тоже: `Nmini` у него ноль, терять нечего.
      assert Rules.compute(build([1], 0), ruleset).gaps
             |> Enum.filter(&match?({_, :mini_set_hp_table}, &1)) == []
    end

    # 🔴 И СТОРОЖА ЗАГРУЗЧИКА. Таблица лежит таблицей, а формула — сверкой:
    # порча любой ячейки роняет сборку, а не всплывает числом у игрока.
    test "испорченная ячейка таблицы роняет сборку", %{root: root} do
      patch_hp_table(root, fn fact -> put_in(fact["value"]["percent_by_count"]["7"], 67) end)

      assert_raise RuntimeError, ~r/which gives 66 there/, fn -> Loader.load!(root) end
    end

    # Ячейка 0 формуле НЕ подчиняется (дала бы 10) и проверяется отдельным
    # равенством — иначе сверку пришлось бы подгонять под обе.
    test "ненулевой процент за ноль вещей роняет сборку", %{root: root} do
      patch_hp_table(root, fn fact -> put_in(fact["value"]["percent_by_count"]["0"], 10) end)

      assert_raise RuntimeError, ~r/wearing nothing of the sort/, fn -> Loader.load!(root) end
    end

    # 🔴 И САМ ОБРЫВ: «поправить» его на 105 «по смыслу» — значит соврать
    # ровно на 105 %.
    test "above_max не ноль роняет сборку", %{root: root} do
      patch_hp_table(root, fn fact -> put_in(fact["value"]["above_max"], 105) end)

      assert_raise RuntimeError, ~r/instead of 0/, fn -> Loader.load!(root) end
    end

    # Лестница обязана быть сплошной: дыра посередине — это счёт, на котором
    # прибавки нет вовсе, и заметить её можно было бы только по числу у игрока.
    test "дыра в лестнице роняет сборку", %{root: root} do
      patch_hp_table(root, fn fact ->
        update_in(fact["value"]["percent_by_count"], &Map.delete(&1, "4"))
      end)

      assert_raise RuntimeError, ~r/skips a count/, fn -> Loader.load!(root) end
    end

    # 🔴 ДВА ИСТОЧНИКА ОБ ОДНОМ ЧИСЛЕ НЕ ИМЕЮТ ПРАВА РАЗОЙТИСЬ МОЛЧА: ряд
    # 15…91 снят со страницы «Мини Сэты» независимо и на четыре недели раньше
    # разбора скриптов, и девять общих ячеек сверяются.
    test "расхождение вики со скриптом роняет сборку", %{root: root} do
      patch_fact(root, "hp_percent_bonus", fn fact -> put_in(fact["value"]["5"], 46) end)

      assert_raise RuntimeError, ~r/the two statements of the HP percentage/, fn ->
        Loader.load!(root)
      end
    end

    test "потолок слотов нулём роняет сборку", %{root: root} do
      patch_hp_table(root, fn fact -> put_in(fact["value"]["named_item_slots"], 0) end)

      assert_raise RuntimeError, ~r/not a positive number of slots/, fn -> Loader.load!(root) end
    end

    defp drop_hp_table(root) do
      patch_system(root, fn system ->
        update_in(system["facts"], fn facts ->
          Enum.reject(facts, &(&1["what"] == "hp_percent_by_item_count"))
        end)
      end)
    end

    defp patch_hp_table(root, fun), do: patch_fact(root, "hp_percent_by_item_count", fun)

    defp patch_fact(root, what, fun) do
      patch_system(root, fn system ->
        update_in(system["facts"], fn facts ->
          for fact <- facts, do: if(fact["what"] == what, do: fun.(fact), else: fact)
        end)
      end)
    end

    defp patch_system(root, fun) do
      path = Path.join(root, "siala_41/systems.json")
      raw = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(raw["systems"], fn systems ->
          for system <- systems,
              do: if(system["id"] == "mini_sets", do: fun.(system), else: system)
        end)

      File.write!(path, Jason.encode!(patched))
    end
  end
end
