defmodule BuildCalculatorWeb.Builder.LostSpellPicksTest do
  @moduledoc """
  Задача 4.63: `LostPicks.prune/2` снимает и известное заклинание, чей уровень
  не даёт его слота; заклинание в слоте, который уровень даёт, остаётся — даже
  не из списка нового класса (его называет ⚠, а снимает чип).

  Какие пики потеряли слот, отвечает ядро (`Rules.lost_slot_picks/2`), и снятое
  обязано совпасть с тем, что ядро называет `{:slot_not_granted, slot_id}`
  (`Rules.illegal_spells/2`). Половина про фиты — `prune_lost_slots_test.exs`.

  Оба ruleset'а: таблицы `spells_known` колдуна и барда у них одни.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Spells}
  alias BuildCalculatorWeb.Builder.LostPicks

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @abilities %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18}
  @sorcerer_1 [:electric_jolt, :ray_of_frost, :flare, :daze, :burning_hands, :grease]

  # Колдун 1 / колдун 2 так, как его собирает конструктор: класс —
  # `validate_level_up/3`, заклинания — в слоты уровня по порядку.
  defp sorcerer_2(ruleset) do
    b =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        base_abilities: @abilities
      )

    b = level_up(b, ruleset, @sorcerer_1)
    b = level_up(b, ruleset, [:light])
    assert Rules.illegal_spells(b, ruleset) == []
    b
  end

  defp level_up(build, ruleset, spells) do
    assert Rules.validate_level_up(build, :sorcerer, ruleset) == :ok
    build = Build.add_level(build, :sorcerer)
    level = Build.character_level(build)
    slots = Enum.map(Spells.slots_at(build, ruleset, level), & &1.id)
    %Build{build | spells: Map.put(build.spells, level, Map.new(Enum.zip(slots, spells)))}
  end

  defp not_granted(build, ruleset) do
    for {_level, _slot, _spell, {:spell_slot_not_granted, _, _}} = pick <-
          Rules.illegal_spells(build, ruleset),
        do: pick
  end

  for version <- ["siala_41", "vanilla"] do
    @version version

    describe "#{version}" do
      setup context do
        %{ruleset: if(@version == "vanilla", do: context.vanilla, else: context.siala)}
      end

      test "нечего снимать — билд тот же, без пересборки", %{ruleset: ruleset} do
        build = sorcerer_2(ruleset)
        assert LostPicks.prune(ruleset, build) == {build, %{feats: [], spells: []}}
        assert LostPicks.none?(%{feats: [], spells: []})
      end

      test "1-й уровень → воин: шесть заклинаний сняты, заклинание 2-го на месте", %{
        ruleset: ruleset
      } do
        edited = Build.replace_level(sorcerer_2(ruleset), 1, :fighter)
        {pruned, lost} = LostPicks.prune(ruleset, edited)

        assert lost.feats == []
        assert length(lost.spells) == 6
        assert lost.spells == not_granted(edited, ruleset)
        refute LostPicks.none?(lost)

        # 2-й уровень стал 1-м уровнем колдуна — `{:circle, 0, 0}` у него есть.
        assert pruned.spells == %{2 => %{{:circle, 0, 0} => :light}}
        assert Rules.illegal_spells(pruned, ruleset) == []

        # Следующие уровни колдуна их больше не считают известными.
        assert Spells.known(pruned, 2) == MapSet.new([:light])
      end

      test "1-й уровень → бард: снят только 1-й круг, кантрипы на месте", %{ruleset: ruleset} do
        edited = Build.replace_level(sorcerer_2(ruleset), 1, :bard)
        {pruned, lost} = LostPicks.prune(ruleset, edited)

        assert lost.spells == [
                 {1, {:circle, 1, 0}, :burning_hands, {:spell_slot_not_granted, 1, 0}},
                 {1, {:circle, 1, 1}, :grease, {:spell_slot_not_granted, 1, 0}}
               ]

        assert pruned.spells[1] == %{
                 {:circle, 0, 0} => :electric_jolt,
                 {:circle, 0, 1} => :ray_of_frost,
                 {:circle, 0, 2} => :flare,
                 {:circle, 0, 3} => :daze
               }

        # Не из списка барда — не снято, а названо: это ⚠ лестницы, не чистка.
        assert Rules.illegal_spells(pruned, ruleset) == [
                 {1, {:circle, 0, 0}, :electric_jolt, {:not_on_spell_list, :bard, 0}},
                 {1, {:circle, 0, 1}, :ray_of_frost, {:not_on_spell_list, :bard, 0}}
               ]
      end

      test "фиты и заклинания — одним проходом", %{ruleset: ruleset} do
        human = Build.put_feat(sorcerer_2(ruleset), 1, :racial, :iron_will)
        edited = %Build{Build.replace_level(human, 1, :fighter) | race: :elf}

        {pruned, lost} = LostPicks.prune(ruleset, edited)

        assert lost.feats == [{1, :racial, :iron_will}]
        assert length(lost.spells) == 6
        assert pruned.feats == %{}
        assert Map.keys(pruned.spells) == [2]
      end

      test "уровни 0 и за длиной билда слотов не дают", %{ruleset: ruleset} do
        build = sorcerer_2(ruleset)

        odd = %Build{
          build
          | spells:
              Map.merge(build.spells, %{
                0 => %{{:circle, 0, 0} => :flare},
                5 => %{{:circle, 0, 0} => :daze}
              })
        }

        assert LostPicks.prune(ruleset, odd) ==
                 {build,
                  %{
                    feats: [],
                    spells: [
                      {0, {:circle, 0, 0}, :flare, {:spell_slot_not_granted, 0, 0}},
                      {5, {:circle, 0, 0}, :daze, {:spell_slot_not_granted, 0, 0}}
                    ]
                  }}
      end
    end
  end
end
