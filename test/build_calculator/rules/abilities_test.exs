defmodule BuildCalculator.Rules.AbilitiesTest do
  @moduledoc """
  `breakdown/2` — the ability score as term by term, the way `Skills.value/4`
  already does for a skill row (CLAUDE.md §6, task 3.2).

  The whole honesty check the totals panel's ability summary leans on is that
  the four terms always sum to `score`; these tests exist to keep that true
  under gear, race, and multiple level-up increases at once, and to fail loudly
  the day a fifth addend (task 3.1 — feats, Red Dragon Disciple) arrives
  without a field of its own.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, Build, Gear}

  setup_all do
    %{ruleset: Data.ruleset!()}
  end

  describe "breakdown/2" do
    test "покупка + раса + уровни + вещи всегда складываются в score", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          levels: List.duplicate(:fighter, 8),
          base_abilities: %{str: 14, dex: 10, con: 12, int: 10, wis: 10, cha: 8},
          ability_increases: %{4 => :str, 8 => :str},
          gear: Gear.new(abilities: %{con: 4, str: -2})
        )

      breakdown = Abilities.breakdown(build, ruleset)

      for {ability, row} <- breakdown do
        sum = row.point_buy + row.race_bonus + row.level_bonus + row.gear_bonus

        assert sum == row.score,
               "#{ability}: #{row.point_buy} покупка + #{row.race_bonus} раса + " <>
                 "#{row.level_bonus} уровни + #{row.gear_bonus} вещи = #{sum}, а score #{row.score}"
      end
    end

    test "score и modifier совпадают с тем, что Rules.compute кладёт в stats", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          levels: List.duplicate(:wizard, 12),
          base_abilities: %{str: 8, dex: 14, con: 12, int: 16, wis: 10, cha: 10},
          ability_increases: %{4 => :int, 8 => :int, 12 => :con},
          gear: Gear.new(abilities: %{int: 6})
        )

      stats = Rules.compute(build, ruleset)
      breakdown = Abilities.breakdown(build, ruleset)

      for ability <- ruleset.abilities do
        row = Map.fetch!(breakdown, ability)
        assert row.score == Map.fetch!(stats.abilities, ability), "#{ability}: score"

        assert row.modifier == Map.fetch!(stats.ability_modifiers, ability),
               "#{ability}: modifier"
      end
    end

    test "уровни считает только для СВОЕЙ характеристики, а не для всех разом", %{
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 16),
          ability_increases: %{4 => :str, 8 => :con, 12 => :str, 16 => :str}
        )

      breakdown = Abilities.breakdown(build, ruleset)

      assert breakdown.str.level_bonus == 3
      assert breakdown.con.level_bonus == 1
      assert breakdown.dex.level_bonus == 0
    end

    test "уровневая прибавка после конца билда не считается", %{ruleset: ruleset} do
      # `ability_increases` хранит только реально взятые уровни — `Build.new`
      # ничего не обрезает сама, поэтому это тест на то, что `breakdown/2`
      # смотрит на `character_level`, а не слепо суммирует всю карту.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 4),
          ability_increases: %{4 => :str, 24 => :str}
        )

      assert Abilities.breakdown(build, ruleset).str.level_bonus == 1
    end

    test "вещи — уже применённый бонус, после капа, а не введённое число", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          gear: Gear.new(abilities: %{str: 30})
        )

      row = Abilities.breakdown(build, ruleset).str

      assert row.gear_typed == 30
      assert row.gear_bonus == ruleset.gear.ability_bonus_cap
      assert row.gear_capped?
    end

    test "вещи меньше потолка проходят как есть, и кап не срабатывает", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          gear: Gear.new(abilities: %{str: 2})
        )

      row = Abilities.breakdown(build, ruleset).str

      assert row.gear_bonus == 2
      assert row.gear_typed == 2
      refute row.gear_capped?
    end

    # Кап описан для БОНУСА (fandom "Ability cap"), а не для штрафа — тот же
    # инвариант, что уже держит `Rules.Gear.ability_bonuses/2`.
    test "штраф с вещей проходит без капа", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          gear: Gear.new(abilities: %{str: -4})
        )

      row = Abilities.breakdown(build, ruleset).str

      assert row.gear_bonus == -4
      refute row.gear_capped?
    end

    test "без расы и без вещей — только покупка", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 15, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      row = Abilities.breakdown(build, ruleset).str

      assert row.point_buy == 15
      assert row.race_bonus == 0
      assert row.level_bonus == 0
      assert row.gear_bonus == 0
      assert row.score == 15
      refute row.gear_capped?
    end
  end

  describe "creation_floor/2 — минимум ключевой характеристики кастера" do
    # ИСТОЧНИК: Dan, тестовый сервер Сиалы, 03.08.2026 (`source: user`).
    # Записано в `priv/rules/siala_41/overrides.json` →
    # `_vanilla_constants_confirmed.caster_minimum_ability` вместе с замером.
    #
    # Минимум ИТОГОВЫЙ, то есть после расовых модификаторов, и обеспечивается
    # принудительной покупкой: очки списываются, опустить нельзя.
    #
    # ⚠️ Класс здесь не «список кастеров», а `casting_ability` из данных: семь
    # классов замера и семь классов с этим полем совпадают поимённо. Строка
    # таблицы, которая перестанет сходиться, — это находка в данных, а не
    # в тесте.
    @measured [
      # раса, класс, характеристика, что покупается
      {:human, :bard, :cha, 11},
      {:human, :sorcerer, :cha, 11},
      {:human, :cleric, :wis, 11},
      {:human, :druid, :wis, 11},
      {:human, :wizard, :int, 11},
      # ⚠️ Полукастеры: заклинания только с 8-го уровня класса, а WIS 11
      # требуется уже на первом. Значит критерий — «у класса есть ключевая
      # характеристика», а не «кастует на первом уровне».
      {:human, :paladin, :wis, 11},
      {:human, :ranger, :wis, 11},
      # Дословный кейс замера: полуорк-соркерер, −2 CHA, покупается 13.
      {:half_orc, :sorcerer, :cha, 13},
      # Та же арифметика другой расой — дварф тоже −2 CHA.
      {:dwarf, :sorcerer, :cha, 13},
      # А там, где штрафа нет, раса ничего не двигает: у полуорка −2 к INT и CHA,
      # но не к WIS.
      {:half_orc, :cleric, :wis, 11}
    ]

    for {race, class, ability, base} <- @measured do
      test "#{race} + #{class}: #{ability} не ниже 11 итоговых, покупается #{base}", %{
        ruleset: ruleset
      } do
        build = Build.new(race: unquote(race), levels: [unquote(class)])
        floor = Abilities.creation_floor(build, ruleset)

        assert floor.ability == unquote(ability)
        assert floor.class == unquote(class)
        assert floor.minimum == 11
        assert floor.base == unquote(base)
        assert floor.base + floor.racial == floor.minimum
      end
    end

    # Положительный контроль: без него «минимум работает» зеленело бы и у
    # реализации, которая подняла пол всем классам разом.
    test "у не-кастера пола нет вовсе", %{ruleset: ruleset} do
      for class <- [:fighter, :barbarian, :monk, :rogue] do
        build = Build.new(race: :human, levels: [class])
        assert Abilities.creation_floor(build, ruleset) == nil, "#{class}"
      end
    end

    # Обратный пример Dan: воин с WIS 8, взявший клирика ВТОРЫМ уровнем, класс
    # получает — и не кастует. Второе проверяет `casts_spell_level`, здесь его
    # не дублируем.
    test "класс не первого уровня пола не ставит", %{ruleset: ruleset} do
      build = Build.new(race: :human, levels: [:fighter, :cleric])

      assert Abilities.creation_floor(build, ruleset) == nil
    end

    test "пока класс не выбран, пола нет, но правило известно", %{ruleset: ruleset} do
      build = Build.new(race: :human)

      assert Abilities.creation_floor(build, ruleset) == nil

      # ⚠️ Эти два ответа обязаны различаться: «пола нет» и «правила не знаем»
      # выглядят одинаково, если оба сводить к nil, а интерфейсу надо сказать
      # игроку, что бюджет ещё не окончателен.
      assert %{value: 11} = Abilities.creation_minimum(ruleset)
    end

    # Без расы считать нечего — но и падать не на чем: раса просто даёт 0.
    test "без расы пол равен самому минимуму", %{ruleset: ruleset} do
      build = Build.new(levels: [:sorcerer])

      assert %{base: 11, racial: 0} = Abilities.creation_floor(build, ruleset)
    end

    test "ruleset без правила отвечает nil, а не числом" do
      assert Abilities.creation_minimum(%{point_buy: nil}) == nil
      assert Abilities.creation_minimum(%{}) == nil

      # И тогда пола нет ни у кого — правило не подставляется «по умолчанию».
      ruleset = %{Data.ruleset!() | point_buy: nil}
      assert Abilities.creation_floor(Build.new(levels: [:sorcerer]), ruleset) == nil
    end
  end
end
