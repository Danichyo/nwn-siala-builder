defmodule BuildCalculator.Rules.ResistancesTest do
  @moduledoc """
  Поглощение стихийного урона (задача 3.210) — таблица кейсов по четырём
  источникам и двум правилам их сведения.

      резист(стихия) = фиты(стихия) + max(эффект расы/топоров, вещь)

  ## ✅ Что ИЗМЕРЕНО в игре, а что синтетика — названо у каждого кейса

  Измерено ровно одно состояние, и оно живое: **Хнюпиус**, кейс `AV1`,
  слово Dan 18.09.2026 — «У Хнюпиуса действительно 45 от огня и 30 от всего
  остального. 30 идет от расы дварфа + 7 мини-сетов, а еще 15 от фита epic
  energy resistance - fire». Билд и вся его экипировка читаются ОДНИМ
  `GameLogImport.parse/2` из `test/fixtures/game_logs_plus/hnyupius.log` —
  ни одного числа руками.

  🔴 **Этот замер убил ОБА конкурирующих чтения сразу:** «эффект плюс вещь»
  дало бы 60 на огне и 45 на холоде, «вещь вместо фита» — 30 на огне.

  Всё остальное — **синтетика**, и каждый такой кейс подписан: внутренний кап
  36, удвоение топором у Гнома, бонус топоров у не-Гнома, `Resist energy`
  и его замещение эпическим, «вещь больше эффекта», ванильные 10/100, снятие
  удвоения оружием другой категории во второй руке.

  ## Три потолка, и ни один не потолок другого

  `max_total` фита (150 на Сиале, 100 в ваниле, по сумме слотов и вещей),
  внутренний кап исполнителя (36, только на эффект расы и топоров) и
  `ruleset.stat_caps`, который про поглощение НЕ ГОВОРИТ ВОВСЕ. Поэтому 150 + 36
  — это арифметика, а не забытый клип, и это закреплено кейсом.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, GearFeats, Resistances}
  alias BuildCalculatorWeb.Builder.GameLogImport

  # Все пять владений сразу — тем же приёмом и по той же причине, что
  # в `mini_sets_test.exs`: кейсы этого файла про поглощение, а не про допуск
  # к оружию, и отказ по владению превратил бы половину из них в ложно-зелёные
  # нули.
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
  # барда выводит билд из группы, и ровно это отличает строки таблиц друг
  # от друга.
  defp pure(n), do: List.duplicate(:fighter, n)
  defp mixed(n), do: List.duplicate(:fighter, n - 1) ++ [:bard]

  defp build(opts) do
    gear =
      Gear.new(
        weapon: opts[:weapon],
        off_hand_weapon: opts[:off_hand],
        feats: @proficiencies ++ (opts[:gear_feats] || []),
        mini_sets: opts[:sets] || [],
        resistances: opts[:resistances] || %{}
      )

    Build.new(
      race: opts[:race] || :human,
      levels: opts[:levels] || pure(40),
      feats: opts[:feats] || %{},
      gear: gear
    )
  end

  defp resistances(ruleset, opts), do: Rules.compute(build(opts), ruleset).resistances

  defp counted(ruleset, opts, type), do: Resistances.total(resistances(ruleset, opts), type)

  # Фит, взятый слотами `n` раз на одну и ту же стихию. ⚠️ Уровни настоящие
  # и эпические: фит эпический, и на 1-м уровне слота под него нет.
  defp epic_takes(n, type) do
    for i <- 1..n, into: %{} do
      {20 + i, %{{:general, 20 + i} => {:epic_energy_resistance, type}}}
    end
  end

  # ------------------------------------- ✅ ИЗМЕРЕНО: Хнюпиус, кейс AV1 --

  describe "✅ Хнюпиус — сверка с игрой (замер AV1, Dan 18.09.2026)" do
    setup %{ruleset: ruleset} do
      text =
        "../../fixtures/game_logs_plus/hnyupius.log" |> Path.expand(__DIR__) |> File.read!()

      result = GameLogImport.parse(text, ruleset)

      %{build: result.build, stats: Rules.compute(result.build, ruleset)}
    end

    # 🔴 ГЛАВНЫЙ КЕЙС ЗАДАЧИ. Числа — слова Dan, а не наш вывод:
    # «45 от огня и 30 от всего остального».
    test "огонь 45, холод 30, остальные пять 30", %{stats: stats} do
      assert Resistances.total(stats.resistances, :fire) == 45

      for type <- [:cold, :acid, :electrical, :sonic, :negative_energy, :positive_energy] do
        assert Resistances.total(stats.resistances, type) == 30, "#{type}"
      end
    end

    # Разбор того же числа по слагаемым — чтобы «45» не могло сойтись случайно
    # из других частей. Цитата Dan разбирает его ровно так же: «30 идет от расы
    # дварфа + 7 мини-сетов, а еще 15 от фита epic energy resistance - fire».
    test "45 собралось из фита 15 и эффекта 30, а вещь 15 в него НЕ вошла", %{stats: stats} do
      fire = stats.resistances.fire

      assert fire.feats == 15
      assert [%{id: :epic_energy_resistance, takes: 1, bonus: 15}] = fire.feat_terms
      assert fire.effect == 30
      assert fire.gear == 15
      assert fire.rule == :max
      assert fire.superseded == :gear
      assert fire.counted == 45
    end

    # 🔴 Холод — это и есть тот замер, который убил чтение «эффект + вещь»:
    # у Хнюпиуса на мече `Damage Resistance (Cold) 15`, а в игре холод 30.
    test "холод: вещь 15 против эффекта 30 — максимум, а не сумма", %{stats: stats} do
      cold = stats.resistances.cold

      assert cold.feats == 0
      assert cold.gear == 15
      assert cold.effect == 30
      assert cold.counted == 30
      assert cold.superseded == :gear
    end

    # Эффект 30 — арифметика тира, классовой группы и кусков, и она проверяется
    # отдельно, потому что в неё входят три независимых правила разом:
    # 2·тир6 = 12, ×3/2 сагровику = 18, += floor(18·7/10) = 12.
    test "эффект 30 = 18 сагровика плюс 12 от семи кусков", %{stats: stats} do
      assert stats.mini_set_pieces == 7
      assert stats.racial_bonus.counted == 18

      assert %{base: 18, added: 12, clipped: 0, total: 30, capped?: false} =
               stats.resistances.fire.effect_term
    end

    # ⚠️ Оружие у него МЕЧ, не топор, и это часть замера: расовый эффект
    # включается ЛЮБЫМ оружием в руках, а оружейный терм даёт только своя
    # группа. Без этой проверки кейс сошёлся бы и у модели, которая приписывает
    # мечу бонус топоров.
    test "меч даёт расовый терм и НЕ даёт оружейного", %{stats: stats} do
      assert stats.resistances.fire.effect_term.base == 18

      refute Enum.any?(stats.weapon_type_bonuses, &(&1.kind == :damage_resistance))
    end

    # И ни одной оговорки: всё посчитано. ⚠️ Признание про посчитанное — та же
    # ложь, что молчание про непосчитанное, только наоборот (CLAUDE.md §6).
    test "ни одной оговорки про поглощение", %{stats: stats} do
      resist_gaps =
        for gap <- stats.gaps,
            inspect(gap) =~ "resist" or inspect(gap) =~ "resistance",
            do: gap

      assert resist_gaps == []
    end
  end

  # ------------------------------------------- эффект расы и топоров --

  describe "эффект расы и топоров (синтетика — замером НЕ покрыто)" do
    # ⚠️ НЕ ИЗМЕРЕНО. Кейс `AV1` снят на мече и без топора, так что удвоение
    # за расовое оружие здесь — арифметика двух термов, которую подтверждает
    # замер `AM1` на ДРУГОМ виде того же исполнителя (атака) и кап 36
    # в самом скрипте.
    test "Гном с топором и десятью кусками упирается в кап 36", %{ruleset: rs} do
      opts = [race: :dwarf, levels: pure(40), weapon: :battleaxe, sets: [10]]

      assert counted(rs, opts, :fire) == 36

      term = resistances(rs, opts).fire.effect_term
      assert term.base == 36
      assert term.added == 36
      assert term.clipped == -36
      assert term.capped?
    end

    # 🔴 И максимальному билду сеты не дают НИЧЕГО — он упирается в кап и без
    # них. Выглядит багом, поэтому под тестом (то же, что у атаки в 3.184).
    test "сагровик-Гном с топором упёрт в 36 и БЕЗ кусков", %{ruleset: rs} do
      opts = [race: :dwarf, levels: pure(40), weapon: :battleaxe]

      assert counted(rs, opts, :fire) == 36
      assert counted(rs, Keyword.put(opts, :sets, [10]), :fire) == 36
    end

    # Не-Гном с топором получает ТОЛЬКО оружейный терм: 12 обычному билду,
    # 18 сагровику. ⚠️ Синтетика.
    test "не-Гном с топором: 12, сагровику 18", %{ruleset: rs} do
      assert counted(rs, [race: :human, levels: mixed(40), weapon: :battleaxe], :fire) == 12
      assert counted(rs, [race: :human, levels: pure(40), weapon: :battleaxe], :fire) == 18
    end

    # Гном без оружия в руках не получает НИЧЕГО, и это правило активации
    # (замер 15.08.2026 на другом виде того же бонуса): бонус включается
    # оружием в руке.
    test "Гном с пустыми руками — поглощения нет вовсе", %{ruleset: rs} do
      assert resistances(rs, race: :dwarf, levels: pure(40)) == %{}
    end

    # 🔴 Удвоение снимается оружием ДРУГОЙ категории во второй руке (замер
    # `AN1`, задача 3.198) — и здесь это видно по ЧИСЛУ, а не только
    # по признаку: у Гнома с топором остаётся один терм из двух.
    # ⚠️ Само снятие измерено на щитовом AC Карлика; что оно действует и на
    # поглощении — перенос правила на соседний вид того же эффекта.
    test "дубина во второй руке снимает удвоение: 36 → 18", %{ruleset: rs} do
      both = [race: :dwarf, levels: pure(40), weapon: :battleaxe]

      assert counted(rs, both, :fire) == 36
      assert counted(rs, Keyword.put(both, :off_hand, :club), :fire) == 18
    end
  end

  # ------------------------------------------------------- фиты --

  describe "прибавка от фитов (синтетика — замером покрыто одно взятие)" do
    # Взятие за взятием, и потолок эффекта на сумме. ⚠️ Замер `AV1` покрывает
    # только ОДНО взятие (15); девять и десять — синтетика.
    test "15 за взятие, десять взятий — 150", %{ruleset: rs} do
      for {takes, expected} <- [{1, 15}, {2, 30}, {9, 135}, {10, 150}] do
        got = resistances(rs, race: :human, levels: pure(41), feats: epic_takes(takes, :fire))

        assert Resistances.total(got, :fire) == expected, "#{takes} взятий"
      end
    end

    # 🔴 Потолок ВЗЯТИЙ и потолок ЭФФЕКТА — разные числа и разные счёты
    # (слово Dan 14.08.2026). Одиннадцатое взятие отбивает `Rules.FeatChoices`,
    # а не арифметика поглощения.
    test "одиннадцатое взятие отказано, а не посчитано", %{ruleset: rs} do
      build = build(race: :human, levels: pure(41), feats: epic_takes(10, :fire))

      reasons =
        Rules.validate_feat_pick(
          build,
          %{
            level: 41,
            slot: {:general, 41},
            feat: :epic_energy_resistance,
            choice: :fire
          },
          rs
        )

      assert {:error, errors} = reasons
      assert {:max_takes, :epic_energy_resistance, 10} in errors
    end

    # Стихии независимы: взятия огня к холоду не идут.
    test "взятия одной стихии не идут в другую", %{ruleset: rs} do
      got = resistances(rs, race: :human, levels: pure(41), feats: epic_takes(3, :fire))

      assert Resistances.total(got, :fire) == 45
      assert Resistances.total(got, :cold) == 0
      assert Map.keys(got) == [:fire]
    end

    # `Resist energy` — плоские +5, и число взятий его не двигает.
    test "Resist energy даёт 5 на своей стихии", %{ruleset: rs} do
      feats = %{3 => %{{:general, 3} => {:resist_energy, :cold}}}
      got = resistances(rs, race: :human, levels: pure(9), feats: feats)

      assert Resistances.total(got, :cold) == 5
      assert Map.keys(got) == [:cold]
    end

    # 🔴 ЗАМЕЩЕНИЕ: эпический отменяет обычный на ТОЙ ЖЕ стихии и не касается
    # другой. ⚠️ На Сиале правило ПЕРЕНЕСЕНО с ванили (её пять страниц про
    # `Resist energy` молчат), поэтому билд получает оговорку — и она проверена
    # следующим кейсом.
    test "эпический замещает обычный на своей стихии и НЕ трогает чужую",
         %{ruleset: rs} do
      feats =
        Map.merge(epic_takes(1, :fire), %{
          3 => %{{:general, 3} => {:resist_energy, :fire}},
          6 => %{{:general, 6} => {:resist_energy, :cold}}
        })

      got = resistances(rs, race: :human, levels: pure(41), feats: feats)

      # огонь: 15 эпического, а не 20
      assert Resistances.total(got, :fire) == 15
      assert [%{id: :epic_energy_resistance}] = got.fire.feat_terms

      # холод: обычный фит цел
      assert Resistances.total(got, :cold) == 5
      assert [%{id: :resist_energy}] = got.cold.feat_terms
    end

    test "замещение на Сиале — перенос с ванили, и билд об этом говорит",
         %{ruleset: rs} do
      feats =
        Map.merge(epic_takes(1, :fire), %{3 => %{{:general, 3} => {:resist_energy, :fire}}})

      stats = Rules.compute(build(race: :human, levels: pure(41), feats: feats), rs)

      assert {:assumed, :resist_energy_superseded_by_epic} in stats.gaps
    end

    # Оговорка про вопрос, который не возникает, — шум: у билда, где замещения
    # не случилось, её нет.
    test "без второго фита на той же стихии оговорки нет", %{ruleset: rs} do
      stats =
        Rules.compute(build(race: :human, levels: pure(41), feats: epic_takes(1, :fire)), rs)

      refute {:assumed, :resist_energy_superseded_by_epic} in stats.gaps
    end

    # 🔴 И оговорки НЕТ у ванили — там правило процитировано дословно обеими
    # страницами. Статус лежит в данных по ruleset'ам, а не выводится кодом.
    test "у ванили того же билда оговорки нет — правило процитировано",
         %{vanilla: vanilla} do
      feats =
        Map.merge(epic_takes(1, :fire), %{3 => %{{:general, 3} => {:resist_energy, :fire}}})

      stats = Rules.compute(build(race: :human, levels: pure(41), feats: feats), vanilla)

      refute {:assumed, :resist_energy_superseded_by_epic} in stats.gaps

      # ...а замещение при этом РАБОТАЕТ — статус про провенанс, не про правило
      assert Resistances.total(stats.resistances, :fire) == 10
    end
  end

  # ---------------------------------------------- фит с вещи (3.29) --

  describe "фит с вещи: ступень — номер взятия (решение Dan 18.09.2026)" do
    # ✅ РЕШЕНИЕ, а не замер: «подтверждаю твое предложение» — считать
    # `Epic energy resistance` с предмета как `Epic toughness` в 3.204.
    test "две записи пары с вещей — два взятия, 30", %{ruleset: rs} do
      gear_feats = [{:epic_energy_resistance, :fire}, {:epic_energy_resistance, :fire}]

      assert counted(rs, [race: :human, levels: pure(41), gear_feats: gear_feats], :fire) == 30
    end

    test "разные стихии с вещей — по одному взятию каждой", %{ruleset: rs} do
      gear_feats = [{:epic_energy_resistance, :fire}, {:epic_energy_resistance, :cold}]
      got = resistances(rs, race: :human, levels: pure(41), gear_feats: gear_feats)

      assert Resistances.total(got, :fire) == 15
      assert Resistances.total(got, :cold) == 15
    end

    # 🔴 Потолок ЭФФЕКТА считает СУММУ слотов и вещей (слово Dan 14.08.2026):
    # десять слотовых взятий плюс вещь — одиннадцать взятий и всё те же 150.
    test "потолок 150 считает слоты И вещи вместе", %{ruleset: rs} do
      opts = [
        race: :human,
        levels: pure(41),
        feats: epic_takes(10, :fire),
        gear_feats: [{:epic_energy_resistance, :fire}]
      ]

      got = resistances(rs, opts)

      assert Resistances.total(got, :fire) == 150
      assert [%{takes: 11, bonus: 150, capped?: true}] = got.fire.feat_terms
    end

    # ⚠️ Объявление БЕЗ значения законно (так выглядит каждая ссылка,
    # расшаренная до задачи 3.97) и не даёт ни одной стихии ничего — а билд
    # говорит об этом своей оговоркой, а не выдуманной стихией.
    test "объявление без стихии не даёт ничего и называет себя", %{ruleset: rs} do
      stats =
        Rules.compute(
          build(race: :human, levels: pure(41), gear_feats: [:epic_energy_resistance]),
          rs
        )

      assert stats.resistances == %{}

      assert {:not_modelled, {:gear_feat_choice, :epic_energy_resistance}} in stats.gaps
    end

    # И счёт взятий — по ПАРЕ, а не по имени: это и есть то, чем `takes/4`
    # отличается от `takes/3`.
    test "takes/4 считает пару, takes/3 — имя", %{ruleset: rs} do
      gear =
        Gear.new(feats: [{:epic_energy_resistance, :fire}, {:epic_energy_resistance, :cold}])

      assert GearFeats.takes(gear, rs, :epic_energy_resistance, :fire) == 1
      assert GearFeats.takes(gear, rs, :epic_energy_resistance, :cold) == 1
      assert GearFeats.takes(gear, rs, :epic_energy_resistance, nil) == 0

      # 🔴 А `/3` отвечает **1**, и это НЕ сумма двух стихий и не ошибка:
      # у него свой вопрос — «одалживает ли предмет этот фит», — и он остался
      # ровно тем, чем был до задачи 3.210 (`stackable?/2` для фита с выбором
      # по-прежнему `false`). Складывать взятия разных стихий в одно число
      # означало бы, что у огня их два.
      assert GearFeats.takes(gear, rs, :epic_energy_resistance) == 1
    end
  end

  # ------------------------------------------------- вещи против эффекта --

  describe "вещь против эффекта (синтетика — замер видел только «вещь меньше»)" do
    # ⚠️ НЕ ИЗМЕРЕНО: у Хнюпиуса вещь всегда МЕНЬШЕ эффекта. Обратная сторона
    # правила — синтетика, и она обязана быть, иначе «максимум» зеленел бы
    # и у модели, которая всегда берёт эффект.
    test "вещь больше эффекта — берётся вещь, эффект не вошёл", %{ruleset: rs} do
      opts = [
        race: :dwarf,
        levels: mixed(5),
        weapon: :longsword,
        resistances: %{fire: 40}
      ]

      got = resistances(rs, opts)

      assert got.fire.gear == 40
      assert got.fire.effect == 2
      assert got.fire.counted == 40
      assert got.fire.superseded == :effect
    end

    # Вещь без всякого эффекта — просто вещь, и сравнивать было нечего.
    test "вещь у расы без поглощения — ровно вписанное число", %{ruleset: rs} do
      got = resistances(rs, race: :human, levels: pure(40), resistances: %{acid: 15})

      assert got.acid.counted == 15
      assert got.acid.effect == 0
      assert got.acid.superseded == nil
    end

    # 🔴 А ФИТ с вещью СКЛАДЫВАЕТСЯ — это и есть третья независимая цитата
    # («предмет −15 к кислоте плюс умение Acid I = −30»), и она проверяется
    # на билде без расового эффекта, чтобы максимум в неё не примешивался.
    test "фит плюс вещь складываются: 15 + 15 = 30", %{ruleset: rs} do
      got =
        resistances(rs,
          race: :human,
          levels: pure(41),
          feats: epic_takes(1, :acid),
          resistances: %{acid: 15}
        )

      assert got.acid.counted == 30
    end
  end

  # ------------------------------------------------------------ ваниль --

  describe "ваниль: те же фиты, другие числа, и никакого эффекта расы" do
    # 10 за взятие и потолок 100 — числа Fandom; сиальских 15/150 у ванили
    # быть не должно.
    test "10 за взятие, потолок 100", %{vanilla: v} do
      for {takes, expected} <- [{1, 10}, {5, 50}, {10, 100}, {11, 100}] do
        got = counted(v, [race: :human, levels: pure(41), feats: epic_takes(takes, :fire)], :fire)

        assert got == expected, "#{takes} взятий"
      end
    end

    # Ни расового, ни оружейного эффекта у ванили нет вовсе — системы нет.
    test "Гном с топором на ванили получает НОЛЬ", %{vanilla: v} do
      assert resistances(v, race: :dwarf, levels: pure(40), weapon: :battleaxe) == %{}
    end

    # ...и мини-сеты там тоже ничего не усиливают, потому что усиливать нечего.
    test "куски на ванили ничего не меняют", %{vanilla: v} do
      opts = [race: :dwarf, levels: pure(40), weapon: :battleaxe, sets: [10]]

      assert resistances(v, opts) == %{}
    end
  end

  # ------------------------------------------------------- форма ответа --

  describe "форма ответа" do
    # 🔴 Стихия без единого источника в мапе ОТСУТСТВУЕТ, а не лежит нулём:
    # «здесь ничего» и «вообще ничего» — разные утверждения.
    test "пустой билд — пустая мапа, а не семь нулей", %{ruleset: rs} do
      assert resistances(rs, race: :human, levels: pure(1)) == %{}
    end

    test "у Гнома с оружием все семь стихий", %{ruleset: rs} do
      got = resistances(rs, race: :dwarf, levels: pure(40), weapon: :longsword)

      assert Enum.sort(Map.keys(got)) ==
               Enum.sort([
                 :acid,
                 :cold,
                 :electrical,
                 :fire,
                 :negative_energy,
                 :positive_energy,
                 :sonic
               ])
    end

    # У порядка печати один источник — словарь ruleset'а, а не ключи мапы.
    test "словарь стихий отдаёт порядок, и он ровно семь", %{ruleset: rs} do
      ids = for %{id: id} <- rs.resistance_energy_types, do: id

      assert length(ids) == 7
      assert Enum.take(ids, 5) == [:acid, :cold, :electrical, :fire, :sonic]
    end

    # ⚠️ Потолка на ИТОГ не называет ни один ruleset, поэтому 150 + 36 = 186 —
    # арифметика, а не забытый клип. Под тестом, потому что число выглядит
    # неправдоподобно большим.
    test "потолка на итог нет: 150 фита плюс 36 эффекта = 186", %{ruleset: rs} do
      opts = [
        race: :dwarf,
        levels: pure(41),
        weapon: :battleaxe,
        sets: [10],
        feats: epic_takes(10, :fire)
      ]

      assert counted(rs, opts, :fire) == 186
      refute Map.has_key?(rs.stat_caps, :damage_resistance)
    end
  end

  # ----------------------------------------------- снапшот без правила --

  describe "снапшот без правила сведения (синтетика — живых носителей нет)" do
    # 🔴 Форму `{:assumed, :resistance_effect_vs_gear}` держит СИНТЕТИКА,
    # а не живая запись: на поставляемых данных правило `verified` (слово Dan
    # плюс замер `AV1`), и контроль на живой записи назавтра получил бы отметку
    # и молча перестал что-либо проверять (урок задачи 3.85).
    test "правила нет — берётся максимум, и билд об этом говорит", %{ruleset: rs} do
      without = Map.put(rs, :resistance_stacking, nil)

      opts = [race: :dwarf, levels: pure(40), weapon: :longsword, resistances: %{fire: 40}]
      stats = Rules.compute(build(opts), without)

      # максимум — нижняя граница обоих чтений
      assert Resistances.total(stats.resistances, :fire) == 40
      assert {:assumed, :resistance_effect_vs_gear} in stats.gaps
    end

    # ⚠️ Оговорка только там, где сравнение СОСТОЯЛОСЬ: без вещи сравнивать
    # нечего, и молчать надо.
    test "без вещи оговорки нет даже без правила", %{ruleset: rs} do
      without = Map.put(rs, :resistance_stacking, nil)
      stats = Rules.compute(build(race: :dwarf, levels: pure(40), weapon: :longsword), without)

      refute {:assumed, :resistance_effect_vs_gear} in stats.gaps
    end

    # И правило `sum`, если снапшот однажды его назовёт, читается тоже —
    # иначе «максимум» был бы зашит, а не прочитан.
    test "правило sum читается: эффект и вещь складываются", %{ruleset: rs} do
      summing = put_in(rs.resistance_stacking.effect_vs_gear, :sum)

      opts = [race: :dwarf, levels: pure(40), weapon: :longsword, resistances: %{fire: 40}]
      got = resistances(summing, opts)

      assert got.fire.counted == 40 + got.fire.effect
      assert got.fire.superseded == nil
    end
  end

  # --------------------------------------------- непосчитанный источник --

  describe "источник, который модель считать отказывается (синтетика)" do
    # 🔴 `{:not_modelled, {:resistance_bonus, id}}` не производит ни один билд:
    # в файле разметки нет ни одной записи с этим вердиктом. Механизм при этом
    # жив, и держит его подменённая разметка — ровно как у сопротивления
    # заклинаниям.
    test "запись с вердиктом not_modelled доезжает до гэпа", %{ruleset: rs} do
      [applied | rest] = rs.resistance_bonuses.applied

      rejected =
        rs
        |> put_in([:resistance_bonuses, :applied], rest)
        |> put_in([:resistance_bonuses, :unmodelled], [
          %{applied | verdict: :not_modelled, affects: nil}
        ])

      feats = %{3 => %{{:general, 3} => {:resist_energy, :cold}}}
      stats = Rules.compute(build(race: :human, levels: pure(9), feats: feats), rejected)

      assert {:not_modelled, {:resistance_bonus, :resist_energy}} in stats.gaps
      # ...и число при этом НЕ посчитано
      assert stats.resistances == %{}
    end
  end
end
