defmodule BuildCalculator.Rules.SialaLevel41BonusFeatTest do
  @moduledoc """
  Сиала: эпический бонусный фит базовых классов на 41-м уровне КЛАССА —
  задача 4.51, решение Dan `BC1` («41 уровень подчиняется всем обычным
  правилам»), данные — `siala_41/class_bonus_feat_levels.json`.

  У шести базовых классов (бард, священник, паладин, рейнджер, колдун,
  волшебник) строка-позиция 40 таблиц игры `cls_bfeat_*.2da` даёт Bonus 1;
  у остальных пяти — 0. Слот считается по уровню КЛАССА, поэтому его даёт
  только класс, взятый на всех 41 уровне персонажа: бард 40 + воин 1 —
  это 41-й уровень персонажа, но 40-й уровень барда, и бонусного слота барда
  на нём нет.

  🔴 Каждый билд собран по одному левелапу (`Rules.validate_level_up/3`),
  как его пройдёт игрок: билд из списка классов в `Build.new(levels: …)`
  валидацию не проходит вовсе (CLAUDE.md §3).

  ⚠️ Это решение, а не замер: статус записей `assumed`, и строку 40 в игре
  никто не видел (вики Сиалы описывает отклонение 41-го уровня класса для
  заклинаний). Ошибётся — правка одна: удалить запись.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp start(version, alignment),
    do:
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: alignment,
        base_abilities: @flat
      )

  # Лестница: каждый уровень проверен ядром до того, как взят.
  defp ladder(build, classes, ruleset) do
    Enum.reduce(classes, build, fn class, acc ->
      level = Build.character_level(acc) + 1

      assert Rules.validate_level_up(acc, class, ruleset) == :ok,
             "#{class} на #{level}-м уровне персонажа отказан"

      Build.add_level(acc, class)
    end)
  end

  defp pure(class, levels, ruleset, alignment),
    do: ladder(start(ruleset.version, alignment), List.duplicate(class, levels), ruleset)

  defp bonus_slots(build, ruleset, level),
    do: for(%{kind: :class_bonus} = slot <- FeatSlots.at(build, ruleset, level), do: slot)

  defp bonus_slot(build, ruleset, level, class) do
    case Enum.filter(bonus_slots(build, ruleset, level), &(&1.class == class)) do
      [slot] -> slot
      other -> flunk("уровень #{level}: бонусных слотов #{class} — #{length(other)}, ждали один")
    end
  end

  # Уровни, на которых у класса бонусный фит, до 41-го: бард, священник,
  # паладин, колдун — каждые три после 20-го; волшебник — плюс 5/10/15/20;
  # рейнджер — плюс каждые пять после 20-го и доэпические 1/5/10/15/20.
  @six [
    {:bard, :chaotic_good, 38},
    {:cleric, :true_neutral, 38},
    {:paladin, :lawful_good, 38},
    {:ranger, :neutral_good, 40},
    {:sorcerer, :true_neutral, 38},
    {:wizard, :true_neutral, 38}
  ]

  describe "шесть классов: чистый класс 41 — бонусный слот на 41-м, пул тот же" do
    for {class, alignment, previous} <- @six do
      @class class
      @alignment alignment
      @previous previous

      test "#{class} 41", %{siala: siala} do
        build = pure(@class, 41, siala, @alignment)

        slot41 = bonus_slot(build, siala, 41, @class)
        slot_prev = bonus_slot(build, siala, @previous, @class)

        assert slot41.id == {:class_bonus, @class}
        assert slot41.epic?
        # Один слот, не два: Bonus 1 в строке 40.
        assert length(bonus_slots(build, siala, 41)) == 1

        candidates = FeatSlots.candidates(siala, slot41)
        assert candidates != []
        assert candidates == FeatSlots.candidates(siala, slot_prev)

        # И ядро в ответе печатает его тем же слотом: дельта 40 → 41.
        before = pure(@class, 40, siala, @alignment)
        %{before: b, after: a} = Rules.preview_level_up(before, @class, siala)
        refute Map.has_key?(b.feat_slots, 41)

        assert Enum.any?(a.feat_slots[41], &(&1.id == {:class_bonus, @class}))
      end
    end

    test "в слот 41-го уровня барда ставится фит его пула — билд законен", %{siala: siala} do
      build = pure(:bard, 41, siala, :chaotic_good)
      slot = bonus_slot(build, siala, 41, :bard)

      assert :great_charisma in FeatSlots.candidates(siala, slot)

      picked = %{build | feats: %{41 => %{{:class_bonus, :bard} => :great_charisma}}}

      assert Rules.validate_feat_pick(
               picked,
               %{feat: :great_charisma, at: 41, slot: slot.id},
               siala
             ) ==
               :ok

      assert Rules.illegal_feats(picked, siala) == []
    end

    test "священник 41: на 41-м — эпические заклинания, как на 38-м (пул Сиалы)", %{siala: siala} do
      build = pure(:cleric, 41, siala, :true_neutral)
      candidates = FeatSlots.candidates(siala, bonus_slot(build, siala, 41, :cleric))

      assert Enum.any?(candidates, &(siala.feats[&1].type == "epic spell"))
    end

    test "паладин 41: на 41-м — владения оружием Сиалы, как на 38-м (замер AK1)", %{siala: siala} do
      build = pure(:paladin, 41, siala, :lawful_good)
      candidates = FeatSlots.candidates(siala, bonus_slot(build, siala, 41, :paladin))

      assert :siala_blade_proficiency in candidates
    end
  end

  describe "без нового слота" do
    for {class, alignment} <- [
          fighter: :true_neutral,
          barbarian: :chaotic_neutral,
          monk: :lawful_neutral,
          druid: :true_neutral,
          rogue: :true_neutral
        ] do
      @class class
      @alignment alignment

      test "#{class} 41 — на 41-м бонусного слота нет", %{siala: siala} do
        build = pure(@class, 41, siala, @alignment)

        assert bonus_slots(build, siala, 41) == []
        refute 41 in siala.classes[@class].epic_bonus_feat_levels
      end
    end

    # 41-й уровень персонажа, но 40-й уровень барда: таблица считает уровни
    # КЛАССА, строка 39 у барда — 0. Слот на 41-м — воина (его 1-й уровень).
    test "бард 40 + воин 1 — бонусного слота барда на 41-м нет", %{siala: siala} do
      build =
        ladder(start("siala_41", :chaotic_good), List.duplicate(:bard, 40) ++ [:fighter], siala)

      ids = for slot <- bonus_slots(build, siala, 41), do: slot.id

      assert ids == [{:class_bonus, :fighter}]
    end

    # Тот же состав в другом порядке: 41-й уровень персонажа — бард, но 40-го
    # уровня класса. Слота нет вовсе.
    test "воин 1 + бард 40 — на 41-м бонусного слота нет", %{siala: siala} do
      build =
        ladder(start("siala_41", :chaotic_good), [:fighter | List.duplicate(:bard, 40)], siala)

      assert bonus_slots(build, siala, 41) == []
    end
  end

  describe "ваниль не сдвинута" do
    test "бард 40 — потолок; 41-го уровня нет, и в данных его нет", %{vanilla: vanilla} do
      build = pure(:bard, 40, vanilla, :chaotic_good)

      assert {:error, _} = Rules.validate_level_up(build, :bard, vanilla)
      refute 41 in vanilla.classes[:bard].epic_bonus_feat_levels
      assert bonus_slot(build, vanilla, 38, :bard).id == {:class_bonus, :bard}
    end
  end
end
