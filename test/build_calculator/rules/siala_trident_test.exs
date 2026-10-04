defmodule BuildCalculator.Rules.SialaTridentTest do
  @moduledoc """
  Трезубец на Сиале — задача 4.42, замер `AY1` (Dan, 27.09.2026, сервер Сиалы):
  «Трезубец одноручный, причём его можно взять в левую руку тоже». Человек
  с трезубцем в правой руке надевает щит; трезубец надевается и в левую руку.

  Сдвинули его две записи данных, и нужны обе:

    * **хват** — колонка «Системы оружия» решена замером в пользу страницы фита
      (`siala_41/generated/weapons.json` → `siala_grip: one_handed`);
    * **размер** — хак шарда делает трезубец средним (`siala_41/weapons.json`,
      `baseitems.2da:95`, `WeaponSize 3`; у базы и Fandom — `large`). Правило
      размеров делает хват только тяжелее, и без этой записи ванильный `large`
      вернул бы человеку двуручный сам (контроль —
      `weapon_size_hak_test.exs`, «без файла Сиала берёт ванильный размер»).

  Сценарии постановки, по одному describe:

    1. человек, трезубец и щит — легально;
    2. трезубец во второй руке у человека — легально, и штраф боя двумя
       оружиями тот, что положен СРЕДНЕМУ оружию во второй руке. Число
       приходит из ядра и сравнивается с контролем того же размера — боевым
       молотом, у которого `dual_wield_test.exs` уже держит итог источника
       («The normal penalty of -6 to the primary hand and -10 to the off-hand»,
       `fandom:Two-weapon fighting`); лёгкая булава — отрицательный контроль;
    3. малая раса — по правилу размеров: средний трезубец на категорию крупнее
       малого владельца, то есть ДВУРУЧНЫЙ (замеры R2, R2b на длинном мече
       и катане), а не «нельзя вовсе», как до задачи. ⚠️ На трезубце это
       не мерено — вывод из правила, а не наблюдение.

  И ваниль не сдвинулась: у неё трезубец большой — человеку двуручный, малой
  расе не по руке.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, DualWield, Gear, Wield}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @abilities %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 10}

  # Сиальские фиты владения разом: задача не про владение, и без них отказ
  # пришёл бы не тот. ⚠️ У ванили этих фитов нет, а воин 1-го уровня владеет
  # воинским оружием сам — тот же билд годится обоим ruleset'ам.
  @proficiencies [
    :siala_blade_proficiency,
    :siala_hammer_proficiency,
    :siala_polearm_proficiency
  ]

  defp armed(race, main, opts \\ []) do
    Build.new(
      race: race,
      levels: List.duplicate(:fighter, Keyword.get(opts, :levels, 1)),
      base_abilities: @abilities,
      gear:
        Gear.new(
          weapon: main,
          off_hand_weapon: Keyword.get(opts, :off_hand),
          worn: Keyword.get(opts, :worn, %{}),
          feats: @proficiencies ++ Keyword.get(opts, :feats, [])
        )
    )
  end

  defp shield_reasons(build, ruleset) do
    for {_category, _item, reason} <- Rules.illegal_worn(build, ruleset), do: reason
  end

  describe "1. человек: трезубец и щит" do
    test "легально: щит надевается, трезубец в главной руке законен", %{siala: siala} do
      build = armed(:human, :trident, worn: %{shield: :large})

      assert Wield.grip(build, :trident, siala) == :one_handed
      assert Rules.validate_gear_weapon(build, :trident, siala) == :ok
      assert Rules.illegal_gear_weapon(build, siala) == []
      assert shield_reasons(build, siala) == []
    end

    # Щит засчитывается в AC, а не только «не отказан». Контроль — тот же щит
    # с ПУСТЫМИ руками: трезубец бонуса за тип оружия не даёт («Трезубцы не дают
    # никакого бонуса», «Система оружия»), поэтому AC обязан совпасть. Число
    # здесь не пишется.
    #
    # ⚠️ Длинный меч контролем быть не может: клинковое добавляет щитовой AC
    # своим бонусом за тип оружия (`weapon_type_bonuses`, `kind: :shield_ac`),
    # и AC разошёлся бы ровно на него — первая версия этого теста на том и упала.
    test "щит засчитан в AC: как с пустыми руками и больше, чем без щита", %{siala: siala} do
      with_trident = Rules.compute(armed(:human, :trident, worn: %{shield: :large}), siala)
      empty_hands = Rules.compute(armed(:human, nil, worn: %{shield: :large}), siala)
      no_shield = Rules.compute(armed(:human, :trident), siala)

      assert with_trident.weapon_type_bonuses == []
      assert with_trident.ac_geared == empty_hands.ac_geared
      assert with_trident.ac_geared > no_shield.ac_geared
    end
  end

  describe "2. человек: трезубец во второй руке" do
    test "легально в обе стороны: во второй руке и в главной рядом со вторым оружием", %{
      siala: siala
    } do
      off = armed(:human, :longsword, off_hand: :trident)
      main = armed(:human, :trident, off_hand: :longsword)

      assert Rules.validate_gear_weapon(armed(:human, nil), :trident, siala, :off) == :ok
      assert Rules.illegal_gear_weapon(off, siala) == []
      assert Rules.illegal_gear_weapon(main, siala) == []
      refute Wield.main_hand_only?(:trident, siala)
    end

    # 🔴 Штраф — тот, что у любого СРЕДНЕГО оружия во второй руке: трезубец
    # у человека того же размера, что владелец, и лёгким не считается
    # («A melee weapon at least one size smaller than the wielder is considered
    # a light weapon», `fandom:Weapon size`). Контроль того же размера — боевой
    # молот; отрицательный — лёгкая булава (small), которой штраф снимают.
    test "штраф боя двумя оружиями — как у среднего оружия во второй руке", %{siala: siala} do
      for feats <- [[], [:two_weapon_fighting, :ambidexterity]] do
        trident = DualWield.of(armed(:human, :longsword, off_hand: :trident, feats: feats), siala)

        hammer =
          DualWield.of(armed(:human, :longsword, off_hand: :warhammer, feats: feats), siala)

        mace = DualWield.of(armed(:human, :longsword, off_hand: :mace, feats: feats), siala)

        assert trident.light_off_hand? == false, "#{inspect(feats)}"
        assert trident.terms == hammer.terms, "#{inspect(feats)}"
        assert DualWield.penalty(trident) == DualWield.penalty(hammer), "#{inspect(feats)}"
        assert trident.off_hand_attacks == 1

        assert mace.light_off_hand? == true
        refute DualWield.penalty(trident) == DualWield.penalty(mace), "#{inspect(feats)}"
      end

      # Итог без фитов — ровно напечатанный источником «normal penalty»:
      # `dual_wield_test.exs` держит его на молоте, здесь он приходит с трезубцем.
      assert armed(:human, :longsword, off_hand: :trident)
             |> DualWield.of(siala)
             |> DualWield.penalty() == %{main: -6, off: -10}
    end

    # До задачи трезубец во второй руке отбивался как двуручный, и штрафа
    # не было вовсе — оружие не считалось. Теперь оно считается: AB главной
    # руки падает на штраф главной руки.
    test "второе оружие теперь считается: AB главной руки меньше на штраф", %{siala: siala} do
      single = Rules.compute(armed(:human, :longsword, levels: 20), siala)
      paired = Rules.compute(armed(:human, :longsword, levels: 20, off_hand: :trident), siala)
      penalty = armed(:human, :longsword, levels: 20, off_hand: :trident) |> DualWield.of(siala)

      assert paired.attack_bonus == single.attack_bonus + DualWield.penalty(penalty).main
    end
  end

  describe "3. малая раса: по правилу размеров" do
    test "Карлик и Гоблин держат трезубец двумя руками: щит и вторая рука — нет", %{
      siala: siala
    } do
      for race <- [:gnome, :halfling] do
        build = armed(race, :trident, worn: %{shield: :large})

        assert Wield.refusal(build, :trident, siala) == nil, "#{race}: не взять вовсе"
        assert Wield.grip(build, :trident, siala) == :two_handed, "#{race}"
        assert Wield.light?(build, :trident, siala) == false, "#{race}"
        assert Rules.validate_gear_weapon(build, :trident, siala) == :ok, "#{race}"
        assert shield_reasons(build, siala) == [{:two_handed_weapon, :trident}], "#{race}"

        assert Rules.validate_gear_weapon(armed(race, nil), :trident, siala, :off) ==
                 {:error, [{:two_handed_in_off_hand, :trident}]},
               "#{race}"
      end
    end
  end

  describe "ваниль не сдвинулась" do
    test "трезубец большой: человеку двуручный, малой расе не по руке", %{vanilla: vanilla} do
      human = armed(:human, :trident, worn: %{shield: :large})

      assert vanilla.weapons[:trident].size == :large
      assert Wield.grip(human, :trident, vanilla) == :two_handed
      assert shield_reasons(human, vanilla) == [{:two_handed_weapon, :trident}]

      assert Rules.validate_gear_weapon(armed(:human, nil), :trident, vanilla, :off) ==
               {:error, [{:two_handed_in_off_hand, :trident}]}

      for race <- [:gnome, :halfling] do
        assert Wield.refusal(armed(race, :trident), :trident, vanilla) ==
                 {:weapon_too_large, race}
      end
    end
  end
end
