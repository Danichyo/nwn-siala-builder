defmodule BuildCalculatorWeb.SkillBudgetUnknownTest do
  @moduledoc """
  Неизвестный бюджет скилл-поинтов не зовёт гида к навыкам (задача 4.65).

  С 4.65 пол и множитель первого уровня скилл-поинтов — числа ruleset'а
  (`vanilla/rules.json` → `character`), и у ruleset'а без них ядро очков
  не считает: `Skills.budget/3` отдаёт `free: nil`. В Elixir `nil > 0` истинно
  (атом больше числа), поэтому прежнее `free > 0` звало бы гида к секции
  навыков вечно. Только синтетика — настоящие ruleset'ы оба числа несут; тест
  держит ветку живой и сверяет её с настоящим ruleset'ом.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.{Build, Skills}
  alias BuildCalculatorWeb.BuilderLive

  test "секция навыков не ждёт решения, когда бюджет неизвестен" do
    ruleset = Data.ruleset!("siala_41")

    build =
      Build.new(
        ruleset_version: ruleset.version,
        levels: [:rogue],
        base_abilities: %{str: 10, dex: 14, con: 10, int: 14, wis: 10, cha: 10}
      )

    for field <- [:skill_points_floor_per_level, :skill_points_first_level_multiplier] do
      unstated = Map.put(ruleset, field, nil)
      assert Skills.budget(build, unstated, 1).free == nil
      refute BuilderLive.section_pending?(%{build: build, ruleset: unstated, active: 1}, "skills")
    end

    # Положительный контроль: на настоящем ruleset'е вор 1 с INT 14 —
    # (8 + 2) × 4 = 40 свободных очков, и секция ждёт.
    assert Skills.budget(build, ruleset, 1).free == 40
    assert BuilderLive.section_pending?(%{build: build, ruleset: ruleset, active: 1}, "skills")
  end
end
