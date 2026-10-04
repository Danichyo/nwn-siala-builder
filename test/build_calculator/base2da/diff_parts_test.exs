defmodule BuildCalculator.Base2da.DiffPartsTest do
  @moduledoc """
  Части сверки базовых `.2da` (задача 4.5), которые проверяются без файлов игры:
  расшифровка мировоззрения, сопоставление имён строк `feat.2da` с нашими id,
  классификация, печать. Сама сверка на выгрузке в CI не гоняется — выгрузки
  там нет (`priv/base_2da` не публикуется); её положительный контроль — прогон
  с порчей значений, описанный в `docs/base2da_diff.md`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{
    Classification,
    CompareClasses,
    Finding,
    Ids,
    Report,
    Source,
    Tally
  }

  alias BuildCalculator.GameFiles.TwoDA

  @all ~w(lawful_good neutral_good chaotic_good lawful_neutral true_neutral
          chaotic_neutral lawful_evil neutral_evil chaotic_evil)a

  describe "allowed_by_mask/3 — семь известных ванильных фактов" do
    test "Barbarian: не законный (0x02 по оси закона)" do
      assert CompareClasses.allowed_by_mask(0x02, 0x1, 0) ==
               MapSet.new(@all -- [:lawful_good, :lawful_neutral, :lawful_evil])
    end

    test "Monk и Dwarven Defender: только законные (0x05 — нейтральность и хаос запрещены)" do
      assert CompareClasses.allowed_by_mask(0x05, 0x1, 0) ==
               MapSet.new([:lawful_good, :lawful_neutral, :lawful_evil])
    end

    test "Paladin: только Lawful Good (0x15 по обеим осям)" do
      assert CompareClasses.allowed_by_mask(0x15, 0x3, 0) == MapSet.new([:lawful_good])
    end

    test "Druid: нейтральность хотя бы на одной оси (0x01, обе оси, инверсия)" do
      assert CompareClasses.allowed_by_mask(0x01, 0x3, 1) ==
               MapSet.new([
                 :neutral_good,
                 :lawful_neutral,
                 :true_neutral,
                 :chaotic_neutral,
                 :neutral_evil
               ])
    end

    test "Assassin: только злые (0x09 — нейтральность и добро по оси добра)" do
      assert CompareClasses.allowed_by_mask(0x09, 0x2, 0) ==
               MapSet.new([:lawful_evil, :neutral_evil, :chaotic_evil])
    end

    test "Pale Master: не добрый; Harper Scout: не злой" do
      refute MapSet.member?(CompareClasses.allowed_by_mask(0x08, 0x2, 0), :chaotic_good)
      assert MapSet.size(CompareClasses.allowed_by_mask(0x08, 0x2, 0)) == 6

      assert CompareClasses.allowed_by_mask(0x10, 0x2, 0) ==
               MapSet.new(@all -- [:lawful_evil, :neutral_evil, :chaotic_evil])
    end

    test "маска без осей ничего не запрещает (Fighter: 0x00, ось 1)" do
      assert CompareClasses.allowed_by_mask(0x00, 0x1, 0) == MapSet.new(@all)
    end
  end

  describe "Ids.feats/2 — строки feat.2da по игровому имени" do
    setup do
      names = [
        {"WeapFocShortSword", "Weapon Focus (short sword)"},
        {"FEAT_EPIC_GREAT_STRENGTH_3", "Great Strength III"},
        {"KiStrike2", "Ki Strike +2"},
        {"FE_Dwarf", "Favored Enemy: Dwarves"},
        {"FEAT_EPIC_ENERGY_RESISTANCE_COLD_4", "Energy Resistance, Cold IV"},
        {"ResistEnergyFire", "Resist Fire Energy"},
        {"FEAT_BULLS_STRENGTH", "Bull's Strength"},
        {"BarbarianRage7", "Greater Rage"},
        {"DM_TOOL_03", "DM Tool 3"},
        {"FEAT_EPIC_FIGHTER", "Epic Fighter"}
      ]

      text =
        "2DA V2.0\n\nLABEL FEAT\n" <>
          Enum.map_join(Enum.with_index(names), "\n", fn {{label, _}, i} ->
            "#{i} #{label} #{100 + i}"
          end)

      source = %Source{
        tables: %{"feat" => TwoDA.parse!(text)},
        names: Map.new(Enum.with_index(names), fn {{_, name}, i} -> {100 + i, name} end)
      }

      %{mapping: Ids.feats(source, BuildCalculator.Data.ruleset!("vanilla"))}
    end

    test "семейства сворачиваются: выбор, ступень, +N, двоеточие", %{mapping: {found, _}} do
      assert found[0] == :weapon_focus
      assert found[1] == :great_strength
      assert found[2] == :ki_strike
      assert found[3] == :favored_enemy
      assert found[4] == :epic_energy_resistance
      assert found[5] == :resist_energy
    end

    test "страница-фит Fandom с хвостом (feat); ступень с чужим именем — поимённо", %{
      mapping: {found, _}
    } do
      assert found[6] == :bulls_strength_feat
      assert found[7] == :barbarian_rage
      assert found[8] == :dm_tool
    end

    test "несопоставленное не выдумывается, а возвращается списком", %{mapping: {found, missing}} do
      refute Map.has_key?(found, 9)
      assert missing == [{9, "Epic Fighter"}]
    end
  end

  describe "Classification" do
    test "у каждого правила вид из закрытого списка и непустой довод" do
      for rule <- Classification.rules() do
        # Три элемента — правило по ключу; четвёртый (задача 4.50) — имя
        # предиката по значениям находки.
        assert tuple_size(rule) in [3, 4], inspect(rule)
        {matcher, kind, note} = {elem(rule, 0), elem(rule, 1), elem(rule, 2)}
        assert kind in [:a, :b, :c, :d], inspect(matcher)
        assert is_binary(note) and String.length(note) > 20, inspect(matcher)
        if tuple_size(rule) == 4, do: assert(is_atom(elem(rule, 3)), inspect(matcher))
      end
    end

    test "правило перекрывает вид сравнения; находка без правила остаётся без вида" do
      ranks = %Finding{
        area: :class_feats,
        subject: "bard",
        field: "granted_ranks/bard_song",
        kind: nil
      }

      assert %{kind: :b, note: note} = Classification.classify(ranks)
      assert note =~ "ступени"

      unknown = %Finding{area: :classes, subject: "wizard", field: "hit_die", kind: nil}
      assert %{kind: nil, note: nil} = Classification.classify(unknown)
    end
  end

  test "Report.plural/4 — русские формы на числах, где их путают" do
    forms =
      for n <- [0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111, 6233],
          do: {n, Report.plural(n, "одна", "две", "пять")}

    assert forms == [
             {0, "пять"},
             {1, "одна"},
             {2, "две"},
             {4, "две"},
             {5, "пять"},
             {11, "пять"},
             {12, "пять"},
             {14, "пять"},
             {21, "одна"},
             {22, "две"},
             {25, "пять"},
             {101, "одна"},
             {111, "пять"},
             {6233, "две"}
           ]
  end

  test "Tally: большое множество печатается разностью, малое — целиком" do
    big = MapSet.new(1..12)

    tally =
      Tally.new(:x, "x")
      |> Tally.check(big, MapSet.delete(big, 7), subject: "s", field: "big")
      |> Tally.check(MapSet.new([1]), MapSet.new([2]), subject: "s", field: "small")

    assert tally.checks == 2

    assert [
             %{base: "12 шт.; нет у нас: 7", ours: "11 шт.; нет в .2da: ∅"},
             %{base: "1", ours: "2"}
           ] = tally.findings
  end
end
