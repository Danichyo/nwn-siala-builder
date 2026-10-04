defmodule BuildCalculator.Rules.HpFloorTest do
  @moduledoc """
  Пол HP за уровень — правило ruleset'а, которое ядро применяет и отдаёт
  в ответе (задача 4.56).

  source: fandom:Hit point, rev 62785 — «There is a minimum of 1 hit point for
  each level, though, after combining the base and bonus hit points associated
  with that level. (Negative bonus hit points can result from a negative
  constitution modifier.)» — `vanilla/rules.json` →
  `character.hit_points_floor_per_level`, оба ruleset'а.

  Хит-дайсы кейсов — из `vanilla/classes.json` (Fandom): Wizard d4 (rev 72067),
  Sorcerer d4 (rev 71586), Rogue d6 (rev 71583), Fighter d10 (rev 71988).
  Модификатор CON 3 → −4, CON 1 → −5 (`floor((score − 10) / 2)`, Fandom «Ability
  modifier»). Такой CON поинт-баем не набрать (минимум 8, раса −2 → 6, −2): на
  законном билде d4 − 2 = 2 и пол не срабатывает, — поэтому база задана прямо.
  Лестницы собираются по одному левелапу (`Rules.validate_level_up/3`).

  На Сиале сверх пола ложится «Дух Сиалы» (+20 единоразово, после пола), и пол
  у неё срабатывает так же: число подпирается на каждом уровне, а не в итоге.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Progression}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp abilities(con), do: %{str: 10, dex: 10, con: con, int: 10, wis: 10, cha: 10}

  # Как игрок: уровень за уровнем, каждый левелап обязан пройти проверку.
  defp level_up!(ruleset, ladder, con) do
    start =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        base_abilities: abilities(con)
      )

    ladder
    |> Enum.flat_map(fn {class, n} -> List.duplicate(class, n) end)
    |> Enum.reduce(start, fn class, build ->
      assert :ok == Rules.validate_level_up(build, class, ruleset),
             "#{ruleset.version}: #{class} на уровне #{length(build.levels) + 1}"

      Build.add_level(build, class)
    end)
  end

  describe "поле floor_per_level — в ответе всегда, на обоих ruleset'ах" do
    test "ruleset несёт пол 1, разбор HP отдаёт его же", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert ruleset.hp_floor_per_level == 1

        for {ladder, con} <- [{[], 10}, {[fighter: 1], 10}, {[wizard: 3], 3}] do
          stats = Rules.compute(level_up!(ruleset, ladder, con), ruleset)
          assert stats.hp_breakdown.floor_per_level == 1, "#{ruleset.version} #{inspect(ladder)}"
        end
      end
    end
  end

  describe "пол срабатывает: d4 при модификаторе CON −4 и ниже" do
    # {ladder, CON, ожидаемое HP ванили, ожидаемое HP Сиалы, floor_adjustment}
    #
    # Wizard d4 при CON 3: 4 − 4 = 0 за уровень → пол 1. HP = число уровней,
    # у Сиалы + 20 («Дух Сиалы» после пола); поправка пола = число уровней.
    # Граничные уровни: 1, 20, 21 (первый эпический), 40 (кап ванили), 41 (кап Сиалы).
    @wizard_floor [
      {[wizard: 1], 3, 1, 21, 1},
      {[wizard: 3], 3, 3, 23, 3},
      {[wizard: 20], 3, 20, 40, 20},
      {[wizard: 21], 3, 21, 41, 21},
      {[wizard: 40], 3, 40, 60, 40}
    ]

    test "Wizard при CON 3: каждый уровень подпёрт полом, на обоих ruleset'ах", %{
      vanilla: vanilla,
      siala: siala
    } do
      for {ladder, con, hp_vanilla, hp_siala, adjustment} <- @wizard_floor,
          {ruleset, hp} <- [{vanilla, hp_vanilla}, {siala, hp_siala}] do
        stats = Rules.compute(level_up!(ruleset, ladder, con), ruleset)
        label = "#{ruleset.version} #{inspect(ladder)}"

        assert stats.hp == hp, label
        assert stats.hp_breakdown.floor_adjustment == adjustment, label
        assert stats.hp_breakdown.floor_per_level == 1, label
      end
    end

    test "41-й уровень — кап Сиалы: Wizard 41 при CON 3 — 41 + 20", %{siala: siala} do
      stats = Rules.compute(level_up!(siala, [wizard: 41], 3), siala)

      assert stats.hp == 61
      assert stats.hp_breakdown.con_term == -164
      assert stats.hp_breakdown.floor_adjustment == 41
    end

    # Четыре класса (лимит Сиалы), CON 1 → −5. Fighter на Сиале выдаёт Toughness
    # (+1 за уровень персонажа, ВНУТРИ пола — feat_hp_bonuses.json → _floor_decision):
    #   Wizard d4:   4 − 5 + 1 = 0 → 1  (+1) ×2
    #   Sorcerer d4: 4 − 5 + 1 = 0 → 1  (+1) ×2
    #   Rogue d6:    6 − 5 + 1 = 2         ×2
    #   Fighter d10: 10 − 5 + 1 = 6        ×2
    # 1+1+1+1+2+2+6+6 = 20, + «Дух Сиалы» 20 = 40; пол добавил 4.
    test "мультикласс на 4 класса: пол подпирает только уровни d4", %{siala: siala} do
      build = level_up!(siala, [wizard: 2, sorcerer: 2, rogue: 2, fighter: 2], 1)
      stats = Rules.compute(build, siala)

      assert Enum.uniq(build.levels) == [:wizard, :sorcerer, :rogue, :fighter]
      assert [%{feat: :toughness, subtotal: 8}] = stats.hp_breakdown.by_feat
      assert stats.hp == 40
      assert stats.hp_breakdown.floor_adjustment == 4
    end

    # Ваниль, три класса (её лимит), Toughness никто не выдаёт:
    #   Wizard d4: 4 − 5 = −1 → 1 (+2) ×2;  Sorcerer d4: то же ×2;  Fighter d10: 5 ×2.
    # 1+1+1+1+5+5 = 14; пол добавил 8.
    test "ваниль, 3 класса при CON 1", %{vanilla: vanilla} do
      stats = Rules.compute(level_up!(vanilla, [wizard: 2, sorcerer: 2, fighter: 2], 1), vanilla)

      assert stats.hp_breakdown.by_feat == []
      assert stats.hp == 14
      assert stats.hp_breakdown.floor_adjustment == 8
    end

    # Пол сравнивается с суммой ПОСЛЕ прибавки уровня: d4 − 4 + Toughness = 1 —
    # ровно пол, и подпирать нечего. Граница «равно — не срабатывает».
    test "Toughness поднимает d4 при CON 3 ровно до пола — поправки нет", %{vanilla: vanilla} do
      build =
        vanilla
        |> level_up!([wizard: 3], 3)
        |> Build.put_feat(1, :general, :toughness)

      assert Rules.illegal_feats(build, vanilla) == []

      stats = Rules.compute(build, vanilla)

      assert stats.hp == 3
      assert stats.hp_breakdown.floor_adjustment == 0
      assert [%{feat: :toughness, subtotal: 3}] = stats.hp_breakdown.by_feat
    end

    test "на законном CON пол молчит: эльф, CON 8 − 2 = 6, Wizard 10", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        build = %{level_up!(ruleset, [wizard: 10], 8) | race: :elf}
        stats = Rules.compute(build, ruleset)

        # d4 − 2 = 2 за уровень.
        assert stats.hp_breakdown.floor_adjustment == 0, ruleset.version
        assert stats.hp_breakdown.con_term == -20, ruleset.version
      end
    end
  end

  describe "ядро читает пол из ruleset'а, а не своим литералом" do
    test "другой пол в ruleset'е — другое HP там, где пол срабатывает", %{
      vanilla: vanilla,
      siala: siala
    } do
      # Пол «другой» — на единицу выше того, что в данных, а не литерал: тест
      # про механизм, и число в записи (его держат именованные тесты выше) он
      # не повторяет. Wizard d4 при CON 3 — 0 за уровень, то есть ровно пол.
      for ruleset <- [vanilla, siala] do
        floored = level_up!(ruleset, [wizard: 3], 3)
        fighter = level_up!(ruleset, [fighter: 1], 10)
        higher = ruleset.hp_floor_per_level + 1
        raised = %{ruleset | hp_floor_per_level: higher}

        stats = Rules.compute(floored, ruleset)
        raised_stats = Rules.compute(floored, raised)

        assert raised_stats.hp == stats.hp + 3, ruleset.version
        assert raised_stats.hp_breakdown.floor_per_level == higher
        assert raised_stats.hp_breakdown.floor_adjustment == 3 * higher

        # Где пол не срабатывает (d10 + 0), число то же — кроме самого поля.
        assert Rules.compute(fighter, raised).hp == Rules.compute(fighter, ruleset).hp
      end
    end

    # Умолчания в ядре нет. Ruleset, чьи слои пола не утвердили
    # (`hp_floor_per_level: nil`, `Loader.Gaps` говорит о том же), HP не
    # считает вовсе — тем же гэпом, что у ruleset'а, как отказ хит-дайса;
    # пустой билд — тоже. Ruleset без ключа или с полом не целым ≥ 1 загрузчик
    # не отдаёт — на таком ядро падает, а не подставляет единицу. `apply/3` —
    # чтобы заведомо неверный вызов не поймал типизатор при компиляции теста.
    test "без пола в ruleset'е ядро HP не считает", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        unstated = %{ruleset | hp_floor_per_level: nil}

        for ladder <- [[], [fighter: 1]] do
          build = level_up!(ruleset, ladder, 10)

          assert Progression.hit_points(build, unstated, 0) ==
                   {:error, {:missing_data, :hp_floor_per_level}}

          stats = Rules.compute(build, unstated)
          assert {stats.hp, stats.hp_naked, stats.hp_breakdown} == {nil, nil, nil}
          assert {:missing_data, :hp_floor_per_level} in stats.gaps
        end
      end

      build = level_up!(vanilla, [fighter: 1], 10)

      for broken <- [Map.delete(vanilla, :hp_floor_per_level), %{vanilla | hp_floor_per_level: 0}] do
        assert_raise FunctionClauseError, fn ->
          apply(Progression, :hit_points, [build, broken, 0])
        end
      end
    end
  end
end
