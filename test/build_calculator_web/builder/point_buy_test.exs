defmodule BuildCalculatorWeb.Builder.PointBuyTest do
  @moduledoc """
  The point buy table — the one we got wrong once and must not get wrong again.

  Source: fandom "Point buy" (revid 57460), quoted in
  `priv/rules/siala_41/overrides.json` under `_vanilla_constants_confirmed`:
  *"it costs 2 points to increment a score to 15 or 16, and 3 points to
  increment it to 17 or 18"*. The shortcut "one point up to 14, two above"
  priced an 18 at 14 points instead of 16 — two points off on nearly every real
  build, because nearly every real build takes something to 17 or 18.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.Abilities
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{Labels, PointBuy}

  setup_all do
    %{ruleset: Data.ruleset!()}
  end

  defp build(race, levels, scores \\ nil)
  defp build(race, levels, nil), do: Build.new(race: race, levels: levels)

  defp build(race, levels, scores),
    do: Build.new(race: race, levels: levels, base_abilities: scores)

  # Свежесозданный персонаж: каждая характеристика на своём полу, ничего сверх
  # него не потрачено — ровно то состояние, в котором Dan снимал остаток очков.
  defp fresh(ruleset, race, levels) do
    build(race, levels, PointBuy.starting_scores(ruleset, build(race, levels)))
  end

  describe "цены шагов" do
    test "накопительная таблица совпадает с вики до последнего очка", %{ruleset: ruleset} do
      expected = %{
        8 => 0,
        9 => 1,
        10 => 2,
        11 => 3,
        12 => 4,
        13 => 5,
        14 => 6,
        15 => 8,
        16 => 10,
        17 => 13,
        18 => 16
      }

      for {score, cost} <- expected do
        assert PointBuy.cost(ruleset, score) == cost, "цена #{score} должна быть #{cost}"
      end
    end

    test "15 и 16 стоят по 2 за шаг, 17 и 18 — по 3", %{ruleset: ruleset} do
      assert Enum.map(15..18, &PointBuy.step_cost(ruleset, &1)) == [2, 2, 3, 3]

      # Всё, что ниже, по одному — именно на этом и строился неверный ярлык.
      assert Enum.map(9..14, &PointBuy.step_cost(ruleset, &1)) == [1, 1, 1, 1, 1, 1]
    end

    test "18 обходится в 16 очков, а не в 14", %{ruleset: ruleset} do
      assert PointBuy.cost(ruleset, 18) == 16
    end
  end

  describe "бюджет" do
    test "старт 8 во всех шести, бюджет 30 очков", %{ruleset: ruleset} do
      assert PointBuy.budget(ruleset) == 30
      assert PointBuy.min_score(ruleset) == 8
      assert PointBuy.max_score(ruleset) == 18
      assert PointBuy.spent(ruleset, PointBuy.starting_scores(ruleset)) == 0
      assert PointBuy.remaining(ruleset, PointBuy.starting_scores(ruleset)) == 30
    end

    test "два 18 в бюджет не влезают: 32 > 30", %{ruleset: ruleset} do
      scores = %{PointBuy.starting_scores(ruleset) | str: 18, con: 17}

      assert PointBuy.spent(ruleset, scores) == 29

      # На 18 не хватает: шаг стоит 3, а свободного очка одно.
      refute PointBuy.can_raise?(ruleset, scores, 17)
    end

    test "ниже пола очко не возвращается", %{ruleset: ruleset} do
      b = build(:human, [:fighter])
      floor = PointBuy.min_score(ruleset)

      refute PointBuy.can_lower?(ruleset, b, :str, floor)
      assert PointBuy.can_lower?(ruleset, b, :str, floor + 1)
    end
  end

  describe "минимум ключевой характеристики кастера" do
    # ИСТОЧНИК: Dan, тестовый сервер Сиалы, 03.08.2026 (`source: user`), замер
    # целиком лежит в `priv/rules/siala_41/overrides.json` →
    # `_vanilla_constants_confirmed.caster_minimum_ability`.
    #
    # Столбец «очков осталось» — это ровно то, что Dan увидел на экране
    # создания персонажа, когда ключевая характеристика стояла на минимуме.
    @measured [
      {:human, :bard, :cha, 11, 27},
      {:human, :sorcerer, :cha, 11, 27},
      {:human, :cleric, :wis, 11, 27},
      {:human, :druid, :wis, 11, 27},
      {:human, :wizard, :int, 11, 27},
      {:human, :paladin, :wis, 11, 27},
      {:human, :ranger, :wis, 11, 27},
      # Дословный кейс замера, и единственный, где итоговые 11 ≠ купленным.
      {:half_orc, :sorcerer, :cha, 13, 25},
      # Та же арифметика другой расой: у дварфа тоже −2 CHA.
      {:dwarf, :sorcerer, :cha, 13, 25},
      # ⚠️ Замер 04.08.2026, и это кейс, который мог опровергнуть правило:
      # у полуорка штраф на INT и CHA, но НЕ на WIS. Если бы пол считался
      # «раса со штрафом → минус 5», здесь было бы 13 и 25. В игре — 11 и 27,
      # то есть пол считается по СВОЕЙ характеристике.
      {:half_orc, :cleric, :wis, 11, 27}
    ]

    for {race, class, ability, bought, left} <- @measured do
      test "#{race} + #{class}: #{ability} стартует с #{bought}, свободных #{left}", %{
        ruleset: ruleset
      } do
        b = fresh(ruleset, unquote(race), [unquote(class)])

        assert PointBuy.floor(ruleset, b, unquote(ability)) == unquote(bought)
        assert Map.fetch!(b.base_abilities, unquote(ability)) == unquote(bought)
        assert PointBuy.remaining(ruleset, b.base_abilities) == unquote(left)

        # Бюджет остался 30 — уменьшилось не он, а свободная часть. Это два
        # разных числа, и панель печатает оба («27 очков осталось из 30»).
        assert PointBuy.budget(ruleset) == 30
        assert PointBuy.forced(ruleset, b).free == unquote(left)
      end
    end

    # ⚠️ Второй вопрос, закрытый тем же замером 04.08.2026: пол РОВНО ОДИН.
    # Dan увидел у полуорка-клирика «11 мудрости, 10 силы, 6 инты и 6 харизмы» —
    # то есть неключевые остались на купленных 8 (6 = 8 − 2 расовых), а STR 10 =
    # 8 + 2. Тест держит все четыре числа: без него «пол на ключевой» зеленело бы
    # и у реализации, которая подняла бы до 11 каждую характеристику кастера.
    test "у полуорка-клирика поднялась только WIS: 11 / 10 / 6 / 6", %{ruleset: ruleset} do
      b = fresh(ruleset, :half_orc, [:cleric])
      scores = Abilities.scores(b, ruleset)

      assert scores.wis == 11
      assert scores.str == 10
      assert scores.int == 6
      assert scores.cha == 6

      # ...и куплены при этом восьмёрки, кроме ключевой: раса добавляется поверх
      assert b.base_abilities == %{str: 8, dex: 8, con: 8, int: 8, wis: 11, cha: 8}
    end

    # Положительный контроль: без него «минимум работает» зеленело бы и
    # у реализации, которая подняла пол всем классам разом.
    test "у воина характеристика опускается до 8, а бюджет остаётся 30", %{ruleset: ruleset} do
      b = fresh(ruleset, :human, [:fighter])

      assert PointBuy.floor(ruleset, b, :cha) == 8
      assert PointBuy.floor(ruleset, b, :wis) == 8
      assert PointBuy.remaining(ruleset, b.base_abilities) == 30
      assert PointBuy.forced(ruleset, b) == nil
      assert Labels.point_buy_floor(ruleset, b) == nil
    end

    # Обратный пример Dan: воин с WIS 8, взявший клирика вторым уровнем.
    # Класс он получает (это проверяет `level_up_test`), а минимума нет —
    # каст ему запрещает уже существующая проверка `casts_spell_level`.
    test "клирик вторым уровнем пола не ставит и очков не отнимает", %{ruleset: ruleset} do
      b = fresh(ruleset, :human, [:fighter, :cleric])

      assert PointBuy.floor(ruleset, b, :wis) == 8
      assert Map.fetch!(b.base_abilities, :wis) == 8
      assert PointBuy.remaining(ruleset, b.base_abilities) == 30
    end

    test "пол не отдаёт очко обратно", %{ruleset: ruleset} do
      b = fresh(ruleset, :half_orc, [:sorcerer])

      refute PointBuy.can_lower?(ruleset, b, :cha, 13)
      # ...а всё, что выше пола, отдаёт
      assert PointBuy.can_lower?(ruleset, b, :cha, 14)
      # ...и соседние характеристики он не трогает
      assert PointBuy.can_lower?(ruleset, b, :str, 9)
      refute PointBuy.can_lower?(ruleset, b, :str, 8)
    end

    test "принудительная покупка докупает недостающее и только вверх", %{ruleset: ruleset} do
      # Билд, собранный «в обратном игре порядке»: статы поставлены до класса.
      low = build(:half_orc, [:sorcerer], %{str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 8})

      raised = PointBuy.enforce_floor(ruleset, low)
      assert raised.base_abilities.cha == 13
      assert raised.base_abilities.str == 8

      # Идемпотентно: второй прогон ничего не меняет.
      assert PointBuy.enforce_floor(ruleset, raised) == raised

      # Уже купленное выше пола не срезается.
      high = build(:half_orc, [:sorcerer], %{low.base_abilities | cha: 16})
      assert PointBuy.enforce_floor(ruleset, high).base_abilities.cha == 16

      # Смена класса на не-кастера очки НЕ возвращает: игрок мог положить их
      # туда сам, и отбирать их не наше дело.
      swapped = build(:half_orc, [:fighter], raised.base_abilities)
      assert PointBuy.enforce_floor(ruleset, swapped).base_abilities.cha == 13
    end

    # ⚠️ Наши экраны спрашивают класс ПОСЛЕ характеристик, поэтому перебор
    # достижим: игра такого состояния не знает, а мы обязаны его показать.
    test "потраченный бюджет плюс принудительная покупка уходят в минус", %{ruleset: ruleset} do
      spent = build(:half_orc, [:sorcerer], %{str: 18, dex: 14, con: 14, int: 8, wis: 8, cha: 8})

      assert PointBuy.remaining(ruleset, spent.base_abilities) == 2

      raised = PointBuy.enforce_floor(ruleset, spent)
      assert raised.base_abilities.cha == 13
      assert PointBuy.remaining(ruleset, raised.base_abilities) == -3
    end
  end

  describe "сброс распределения, когда пол не помещается в свободные (задача 3.17)" do
    # Решение Dan, уточнение краёв — координатор: порог «свободных не хватает»,
    # а не «свободных нет вовсе». Три теста ниже держат ровно эту границу.
    test "нужно 3, свободно 22 — просто списываем, сброс не нужен", %{ruleset: ruleset} do
      b = build(:human, [:sorcerer], %{str: 15, dex: 8, con: 8, int: 8, wis: 8, cha: 8})

      assert PointBuy.remaining(ruleset, b.base_abilities) == 22
      refute PointBuy.reset_needed?(ruleset, b)
    end

    test "нужно 3, свободно ровно 3 — этого хватает, сброс не нужен", %{ruleset: ruleset} do
      b = build(:human, [:sorcerer], %{str: 18, dex: 15, con: 11, int: 8, wis: 8, cha: 8})

      assert PointBuy.remaining(ruleset, b.base_abilities) == 3
      refute PointBuy.reset_needed?(ruleset, b)
    end

    test "нужно 3, свободно 0 — не хватает, нужен сброс", %{ruleset: ruleset} do
      b = build(:human, [:sorcerer], %{str: 18, dex: 12, con: 16, int: 8, wis: 8, cha: 8})

      assert PointBuy.remaining(ruleset, b.base_abilities) == 0
      assert PointBuy.reset_needed?(ruleset, b)
    end

    # Кастер → кастер (соркерер → клирик): пол переезжает CHA → WIS. CHA уже
    # выкуплена под свой пол, но это не освобождает очков для WIS.
    test "кастер → кастер: переехавший пол тоже может не поместиться", %{ruleset: ruleset} do
      sorcerer =
        build(:human, [:sorcerer], %{str: 18, dex: 15, con: 11, int: 8, wis: 8, cha: 11})

      cleric = %{sorcerer | levels: [:cleric]}

      assert PointBuy.remaining(ruleset, cleric.base_abilities) == 0
      assert PointBuy.reset_needed?(ruleset, cleric)
    end

    # «Кастер → не-кастер: сброса нет никогда» — `forced/2` возвращает `nil`,
    # и вопрос о свободных очках не задаётся вовсе.
    test "не-кастер никогда не просит сброса, сколько бы ни было потрачено", %{ruleset: ruleset} do
      b = build(:human, [:fighter], %{str: 18, dex: 18, con: 8, int: 8, wis: 8, cha: 8})

      refute PointBuy.reset_needed?(ruleset, b)
    end

    test "reset_to_floor кладёт все шесть характеристик на табличный пол", %{ruleset: ruleset} do
      b = build(:half_orc, [:sorcerer], %{str: 18, dex: 12, con: 16, int: 8, wis: 8, cha: 8})
      floor = PointBuy.min_score(ruleset)

      assert PointBuy.reset_to_floor(ruleset, b).base_abilities ==
               %{str: floor, dex: floor, con: floor, int: floor, wis: floor, cha: floor}
    end

    # Гарантия, ради которой пара функций вообще устроена именно так: сброс
    # плюс новая покупка минимума ВСЕГДА укладываются в бюджет — это ровно то,
    # что измерил Dan (худший случай — полуорк, 5 из 30).
    test "сброс + enforce_floor никогда не уходят в минус", %{ruleset: ruleset} do
      b = build(:half_orc, [:sorcerer], %{str: 18, dex: 12, con: 16, int: 8, wis: 8, cha: 8})

      settled =
        ruleset |> PointBuy.reset_to_floor(b) |> then(&PointBuy.enforce_floor(ruleset, &1))

      assert settled.base_abilities.cha == 13
      assert PointBuy.remaining(ruleset, settled.base_abilities) >= 0
    end
  end

  describe "почему очков 27, а не 30" do
    test "строка называет класс, характеристику и цену", %{ruleset: ruleset} do
      text = Labels.point_buy_floor(ruleset, fresh(ruleset, :human, [:sorcerer]))

      assert text =~ "Sorcerer"
      assert text =~ "CHA"
      assert text =~ "11"
      assert text =~ "27"
    end

    test "у расы со штрафом называет и купленное значение", %{ruleset: ruleset} do
      text = Labels.point_buy_floor(ruleset, fresh(ruleset, :half_orc, [:sorcerer]))

      assert text =~ "−2"
      assert text =~ "13"
      assert text =~ "25"
    end

    # ⚠️ Пока класс первого уровня не выбран, доступный бюджет НЕИЗВЕСТЕН:
    # 30, 27 или 25 — решают раса и класс вместе. Печатать 30 как факт нельзя,
    # поэтому строка говорит, что бюджет не окончательный.
    test "до выбора класса бюджет назван неокончательным", %{ruleset: ruleset} do
      text = Labels.point_buy_floor(ruleset, build(:human, []))

      assert text =~ "не окончательный"
      assert text =~ "11"
    end

    # А там, где правила в данных нет, интерфейс не заявляет ничего —
    # про это говорит гэп {:missing_data, :caster_minimum_ability}.
    test "ruleset без правила молчит", %{ruleset: ruleset} do
      without = %{ruleset | point_buy: %{ruleset.point_buy | caster_minimum: nil}}

      assert Labels.point_buy_floor(without, build(:human, [])) == nil
      assert Labels.point_buy_floor(without, build(:human, [:sorcerer])) == nil
    end
  end
end
