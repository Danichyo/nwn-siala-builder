defmodule BuildCalculator.Rules.ClassStepsTest do
  @moduledoc """
  `Rules.class_steps_at/3` — какой фит класс поднимает на ступень на этом уровне,
  хотя список выдач класса его не называет (задача 4.40, пункт 6).

  Строка «Класс даёт сам» читала только список выдач (`granted_feats`), а таблицы
  по уровню класса, из которых считаются числа, растут чаще: `Enchant arrow`
  выдан на Тайном лучнике 1 и растёт на каждом нечётном уровне класса, у Сиалы
  ступень Мастера оружия 31 (+8, решение `BC1`, задача 4.46) лежит в колонке
  класса без строки выдачи. Билды собраны по одному левелапу (CLAUDE.md §3).

  Контроль с другой стороны — колонка AC Монаха: тоже запись класса, и ни один
  фит не выдан на двух её ступенях подряд, поэтому продолжать нечего.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  @flat %{str: 10, dex: 10, con: 10, int: 16, wis: 10, cha: 10}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp ladder(build, classes, ruleset) do
    Enum.reduce(classes, build, fn class, acc ->
      level = Build.character_level(acc) + 1

      assert Rules.validate_level_up(acc, class, ruleset) == :ok,
             "#{class} на #{level}-м уровне персонажа отказан"

      Build.add_level(acc, class)
    end)
  end

  # Воин 6 / Мастер оружия 10 / Воин 4 / Мастер оружия на всех эпических — у Сиалы
  # Мастер оружия 31 на 41-м. Требования класса — те же фиты, что
  # в `prestige_epic_scales_test.exs` (там же разбор).
  defp weapon_master(version, ruleset, epic_levels) do
    {first_bonus, second_bonus, third_general} =
      case version do
        "siala_41" -> {:siala_blade_proficiency, {:weapon_focus, :longsword}, :mobility}
        "vanilla" -> {{:weapon_focus, :longsword}, :mobility, :power_attack}
      end

    start =
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: :lawful_neutral,
        base_abilities: %{str: 14, dex: 13, con: 12, int: 13, wis: 10, cha: 10},
        feats: %{
          1 => %{
            :general => :dodge,
            :racial => :expertise,
            {:class_bonus, :fighter} => first_bonus
          },
          2 => %{{:class_bonus, :fighter} => second_bonus},
          3 => %{general: third_general},
          4 => %{{:class_bonus, :fighter} => :spring_attack},
          6 => %{general: :whirlwind_attack},
          7 => %{{:class_bonus, :weapon_master} => {:weapon_of_choice, :longsword}}
        },
        skills: %{1 => %{intimidate: 4}}
      )

    ladder(
      start,
      List.duplicate(:fighter, 6) ++
        List.duplicate(:weapon_master, 10) ++
        List.duplicate(:fighter, 4) ++ List.duplicate(:weapon_master, epic_levels),
      ruleset
    )
  end

  # Воин 6 / волшебник 1 / Тайный лучник 10 / воин 3 / Тайный лучник на эпических.
  defp archer(version, ruleset, epic_levels) do
    start =
      Build.new(
        ruleset_version: version,
        race: :elf,
        alignment: :true_neutral,
        base_abilities: %{@flat | dex: 14},
        feats: %{1 => %{general: {:weapon_focus, :longbow}}, 3 => %{general: :point_blank_shot}}
      )

    ladder(
      start,
      List.duplicate(:fighter, 6) ++
        [:wizard] ++
        List.duplicate(:arcane_archer, 10) ++
        List.duplicate(:fighter, 3) ++ List.duplicate(:arcane_archer, epic_levels),
      ruleset
    )
  end

  # Бард 10 / РДД 20.
  defp dragon_disciple(version, ruleset) do
    start =
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{@flat | cha: 16},
        skills: %{
          1 => %{lore: 4},
          2 => %{lore: 1},
          3 => %{lore: 1},
          4 => %{lore: 1},
          5 => %{lore: 1}
        }
      )

    ladder(
      start,
      List.duplicate(:bard, 10) ++ List.duplicate(:red_dragon_disciple, 20),
      ruleset
    )
  end

  defp monk(version, ruleset, levels) do
    ladder(
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: :lawful_neutral,
        base_abilities: @flat
      ),
      List.duplicate(:monk, levels),
      ruleset
    )
  end

  describe "колонка класса продолжает фит, выданный на двух ступенях подряд" do
    test "Сиала: Мастер оружия 31 — Epic superior weapon focus с рангом 28-го", %{siala: siala} do
      build = weapon_master("siala_41", siala, 21)
      assert Build.class_level_at(build, 41) == 31

      assert Rules.class_steps_at(build, siala, 41) == [
               %{feat: :epic_superior_weapon_focus, step: {:rank, "(+1 AB)"}}
             ]

      # На ступенях 13 … 28 фит назван списком выдач — колонка там молчит,
      # а на 30-м ступени нет вовсе.
      for level <- [23, 26, 38, 40] do
        assert Rules.class_steps_at(build, siala, level) == [], "#{level}"
      end
    end

    test "ваниль: Мастер оружия 30 — ступени 31 нет, ни на одном уровне ничего", %{
      vanilla: vanilla
    } do
      build = weapon_master("vanilla", vanilla, 20)
      assert Build.class_level_at(build, 40) == 30

      for level <- 1..40,
          do: assert(Rules.class_steps_at(build, vanilla, level) == [], "#{level}")
    end

    test "синтетика: без выдачи на 25-м — продолжать нечего, 31-й молчит", %{siala: siala} do
      build = weapon_master("siala_41", siala, 21)

      cut =
        update_in(siala, [:classes, :weapon_master, :granted_feats], &Map.delete(&1, 25))

      assert Rules.class_steps_at(build, cut, 41) == []
    end

    test "колонка AC Монаха не называет ничего — ни на ванили, ни на Сиале", %{
      vanilla: vanilla,
      siala: siala
    } do
      for {version, ruleset, cap} <- [{"vanilla", vanilla, 40}, {"siala_41", siala, 41}] do
        build = monk(version, ruleset, cap)

        for level <- 1..cap,
            do: assert(Rules.class_steps_at(build, ruleset, level) == [], "#{version} #{level}")
      end
    end
  end

  describe "таблица фита: ступень, которую список выдач не называет" do
    test "Enchant arrow — на каждом нечётном уровне лучника, значение ступени", %{
      vanilla: vanilla,
      siala: siala
    } do
      for {version, ruleset, epic} <- [{"vanilla", vanilla, 20}, {"siala_41", siala, 21}] do
        build = archer(version, ruleset, epic)

        steps =
          for level <- 1..Build.character_level(build),
              [%{feat: :enchant_arrow, step: {:total, total}}] <- [
                Rules.class_steps_at(build, ruleset, level)
              ],
              do: {Build.class_level_at(build, level), total}

        odd = Enum.filter(1..(10 + epic), &(rem(&1, 2) == 1))
        assert steps == Enum.map(odd, &{&1, div(&1 + 1, 2)}), version
      end
    end

    test "РДД: Draconic armor и Dragon abilities — там, где растут", %{siala: siala} do
      build = dragon_disciple("siala_41", siala)

      at = fn class_level -> Rules.class_steps_at(build, siala, 10 + class_level) end

      assert at.(4) == [%{feat: :dragon_abilities, step: {:gains, %{str: 2}}}]
      assert at.(5) == [%{feat: :draconic_armor, step: {:total, 2}}]
      assert at.(6) == []

      assert at.(10) == [
               %{feat: :draconic_armor, step: {:total, 4}},
               %{feat: :dragon_abilities, step: {:gains, %{str: 4, cha: 2}}}
             ]
    end

    test "за концом лестницы класса нет — и ступеней нет", %{siala: siala} do
      build = archer("siala_41", siala, 0)
      assert Rules.class_steps_at(build, siala, Build.character_level(build) + 1) == []
    end
  end
end
