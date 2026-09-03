defmodule BuildCalculatorWeb.Builder.GearFeatRowsTest do
  @moduledoc """
  Фит с вещи на экране: **своя названная строка**, а не слитое число — задача 3.3.

  Прибавка объявленного фита считается (`Rules.GearFeats`), и ровно поэтому нужна
  эта проверка. Пересечься с тем, что игрок вводит руками, фит может в четырёх
  получателях — характеристики, AC по типам, сейвы и **навыки** (задача 3.20), —
  потому что только у них в наборе «Вещи» есть своё поле. В трёх из четырёх мы
  пересечение не запрещаем и не занижаем: защита в том, что **оба слагаемых
  названы отдельно**, и игрок, вписавший одно и то же дважды, видит это двумя
  строками.

  ⚠️ **AC — четвёртый и особый, с задач 3.39 и 3.91.** У прибавки к AC есть
  ТИП, и внутри одного типа поведение зависит от ВИДА прибавки: фит с вещи
  складывается с вписанным числом того же типа (две строки, как у остальных
  трёх получателей), а сиальский щитовой бонус — перекрывает его (строка одна,
  проигравшая сторона названа в `stats.ac_superseded_types`). Обе половины под
  тестом ниже, парой: поодиночке каждая зеленела бы и при неверной модели.

  У HP и атаки поля в «Вещах» нет вовсе, так что пересечься там не с чем.

  Файл отдельный, а не дописан в `summary_test.exs`, намеренно: тот трогает
  задача про потолок сейвов, идущая параллельно.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}
  alias BuildCalculatorWeb.Builder.Summary

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  defp build(levels, gear) do
    %Build{} =
      Build.new(
        ruleset_version: "siala_41",
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
        levels: levels,
        skills: %{1 => %{spot: 4}},
        gear: gear
      )
  end

  defp labels(rows), do: for(row <- rows, do: row.label)

  # Разбор обязан сходиться со своим итогом — то же правило, что в
  # `summary_test.exs`, и здесь оно ловит ровно правку 3.39.
  defp sum_terms(rows),
    do: Enum.reduce(rows, 0, fn %{value: v}, sum -> sum + (v |> Integer.parse() |> elem(0)) end)

  test "сейвы: Iron will с вещи и введённые вручную +2 — две строки", %{ruleset: ruleset} do
    build = build(List.duplicate(:fighter, 6), Gear.new(feats: [:iron_will], saves: 2))
    stats = Rules.compute(build, ruleset)

    rows = Summary.save_summary_terms(ruleset, stats, :will, :wis, stats.ability_modifiers.wis)

    assert %{label: "Iron will", value: "+2"} in rows
    assert %{label: "вещи", value: "+2"} in rows

    # И оба слагаемых доехали до числа: +4 к Will, а не +2.
    assert stats.will ==
             Rules.compute(build(List.duplicate(:fighter, 6), %Gear{}), ruleset).will + 4
  end

  # 🔴 AC разбирается ДВУМЯ строками, как и все остальные получатели, — и это
  # правка 3.91: фит с вещи даёт +2 природного, вписано тоже 2, в число идут
  # оба («АЦ с фитов всегда стакаются все», Dan 25.08.2026).
  #
  # ⚠️ ИСТОРИЯ строки, и её стоит держать целиком. Сперва здесь были две
  # строки при неизвестном правиле; задача 3.39 свела их в одну («вписанное
  # конкурирует с собственным»); 3.91 вернула две. Вернула не откатом, а
  # сужением: правило про максимум пришло из цитаты про РАСОВЫЙ щитовой бонус
  # Карлика и осталось верным ровно для него — под тестом рядом.
  test "AC: Armor skin с вещи и введённые природные +2 — две строки", %{ruleset: ruleset} do
    build = build(List.duplicate(:fighter, 6), Gear.new(feats: [:armor_skin], ac: %{natural: 2}))
    stats = Rules.compute(build, ruleset)

    rows = Summary.ac_geared_terms(ruleset, stats)

    assert %{label: "Armor skin", value: "+2"} in rows
    assert %{label: "Природный", value: "+2"} in rows

    # И разбор сходится с числом — то, ради чего строку когда-то убирали.
    assert sum_terms(rows) == stats.ac_geared

    # ⚠️ Ни «перебито», ни «базу не отделить»: вписанное доехало целиком,
    # и печатать про него оговорку было бы ложной неопределённостью.
    assert stats.ac_superseded_types == []
    refute {:not_modelled, {:ac_gear_base, :natural}} in stats.gaps
  end

  # 🔴 Положительный контроль к строке выше и вторая половина правки 3.91:
  # у сиальского щитового бонуса правило ДРУГОЕ — он перекрывает вписанный
  # бонус щита («раса карлика… перекрывает бонус щита (не базу щита(1/2/3),
  # а именно бонус)», Dan 25.08.2026). Без этой пары верхний тест зеленел бы
  # и у кода, который просто сложил всё подряд.
  test "AC: расовый щитовой Карлика перекрывает вписанный щит — строка одна", %{
    ruleset: ruleset
  } do
    build =
      Build.new(
        levels: List.duplicate(:fighter, 41),
        base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
        race: :gnome,
        gear:
          Gear.new(
            ac: %{shield: 4},
            weapon: :handaxe,
            feats: [:siala_axe_proficiency]
          )
      )

    stats = Rules.compute(build, ruleset)
    rows = Summary.ac_geared_terms(ruleset, stats)

    assert Enum.any?(rows, &(&1.value == "+9"))
    refute Enum.any?(rows, &(&1.label == "Щит"))

    assert sum_terms(rows) == stats.ac_geared
    assert stats.ac_superseded_types == [:shield]
  end

  test "характеристики: Great strength с вещи и введённый +12 CON — разные строки", %{
    ruleset: ruleset
  } do
    build =
      build(
        List.duplicate(:fighter, 21),
        Gear.new(feats: [:great_strength], abilities: %{str: 12})
      )

    rows = Summary.ability_summary(ruleset, build)
    str = Enum.find(rows, &(&1.id == :str))

    # Разбор характеристики разложен по источникам, и фит стоит отдельной
    # строкой, отличной от числа, введённого руками.
    assert %{label: "Great strength", value: "+1"} in str.terms
    assert %{label: "вещи", value: "+12"} in str.terms
    assert labels(str.terms) == ["база", "Great strength", "вещи"]
  end

  # ⚠️ Четвёртый получатель, появившийся 09.08.2026 (задача 3.20). До неё этот
  # тест утверждал обратное — «у навыков поля нет, пересечься не с чем», — и
  # держалось это утверждение на растяжке `Map.keys(%Gear{}) == [...]` ниже.
  # Растяжка сработала как задумано: поле появилось, тест упал, и вместо того
  # чтобы дописать `:skills` в список, пришлось написать настоящую проверку —
  # ту, которую тест три задачи назад обещал написать, когда поле появится.
  test "навыки: Alertness с вещи и вписанные «Spot +50» — две строки", %{ruleset: ruleset} do
    build =
      build(
        List.duplicate(:wizard, 10),
        Gear.new(feats: [:alertness], skills: %{spot: 50})
      )

    stats = Rules.compute(build, ruleset)
    value = stats.skill_values[:spot]

    # ⚠️ У навыка нет типов прибавки, как у AC, поэтому сложение НЕ ловится
    # данными и не должно: оба утверждения игрока верны по отдельности.
    # Единственная защита — раздельные термы.
    assert value.feat_bonus == 2
    assert value.feat_bonus_from == [:alertness]
    assert value.gear_bonus == 50

    terms = Summary.skill_value_terms(ruleset, value)
    assert %{label: "Alertness", value: "+2"} in terms
    assert %{label: "вещи", value: "+50"} in terms

    # И оба слагаемых доехали до числа, а не одно из них: 4 ранга + WIS 0 + 2 + 50.
    assert value.total == 56
  end

  test "HP: пересечься не с чем, поля в «Вещах» нет", %{ruleset: ruleset} do
    build = build(List.duplicate(:wizard, 10), Gear.new(feats: [:toughness]))
    stats = Rules.compute(build, ruleset)

    assert %{label: "Toughness", value: "+10"} in Summary.hp_terms(ruleset, stats)

    # Положительный контроль, и он же — та самая растяжка. ⚠️ Список полей
    # проверяется целиком, а не через `:hp in keys`: смысл проверки в том, чтобы
    # НОВОЕ поле роняло тест и заставляло дописать к нему кейс про двойной счёт.
    # Так уже произошло один раз, с `:skills` (см. тест выше) — растяжку обновили
    # вместе с кейсом, а не вместо него.
    # ⚠️ И произошло второй раз, 10.08.2026: задача 3.5 (часть B) добавила оружие
    # в руках с двумя его числами. Двойного счёта у них нет и быть не может —
    # ни один фит и ни одно классовое умение не прибавляет к атаке «бонус
    # предмета», это отдельное слагаемое `weapon_attack_bonus`, — а вот фиты на
    # ОРУЖИЕ (`Weapon focus`) считаются отдельными термами рядом, и разбор AB
    # печатает их поимённо, а не сливает с числом предмета.
    # ⚠️ И четвёртый раз, 19.08.2026, впервые В МИНУС: задача 3.52 убрала
    # `:weapon_enhancement`. Кейса про двойной счёт эта правка не требует —
    # поле не появилось, а исчезло, — но растяжка обязана была упасть, чтобы
    # уход поля был осознанным, а не молчаливым.
    # ⚠️ И третий раз, 16.08.2026: задача 3.41 добавила надетое (`:worn`) —
    # доспех и щит как предметы. Кейс про двойной счёт дописан следующим тестом,
    # а не вместо этой строки.
    # ⚠️ И пятый раз, 28.08.2026: задача 3.132 добавила ВТОРУЮ РУКУ
    # (`:off_hand_weapon`, `:off_hand_weapon_attack`). Двойного счёта у них нет
    # по построению — число второй руки живёт в собственном терме второй руки
    # (`stats.off_hand.weapon_attack_bonus`) и в число главной не входит ни при
    # каком оружии, — а вот штраф стиля общий и вычитается КАЖДОЙ руке своим
    # числом, ровно один раз (`Rules.DualWield`).
    assert Map.keys(Map.from_struct(%Gear{})) |> Enum.sort() ==
             [
               :abilities,
               :ac,
               :feats,
               :off_hand_weapon,
               :off_hand_weapon_attack,
               :saves,
               :skills,
               :weapon,
               :weapon_attack,
               :worn
             ]
  end

  # Кейс, которого потребовала растяжка выше. У надетого двойной счёт возможен
  # ровно в одном месте: база предмета и вписанное под тем же типом число — это
  # ДВА разных утверждения игрока, и оба доезжают до AC. Проверяется, что база
  # приходит РОВНО ОДИН раз и не подменяет собой вписанное.
  test "надетое: база предмета и вписанный бонус — два слагаемых, и база не задваивается", %{
    ruleset: ruleset
  } do
    naked = build(List.duplicate(:wizard, 10), Gear.new())
    typed = build(List.duplicate(:wizard, 10), Gear.new(ac: %{shield: 4}))
    worn = build(List.duplicate(:wizard, 10), Gear.new(worn: %{shield: :large}))
    both = build(List.duplicate(:wizard, 10), Gear.new(ac: %{shield: 4}, worn: %{shield: :large}))

    base = Rules.compute(naked, ruleset).ac_geared

    # Вписанное само по себе — +4; средний щит сам по себе — +2 базы;
    # вместе — ровно 6, а не 4 (база потерялась) и не 8 (посчитана дважды).
    assert Rules.compute(typed, ruleset).ac_geared == base + 4
    assert Rules.compute(worn, ruleset).ac_geared == base + 2
    assert Rules.compute(both, ruleset).ac_geared == base + 6

    # И то же самое разложением по типу: у волшебника своих щитовых прибавок
    # нет, значит весь терм пришёл с вещей.
    assert Rules.compute(both, ruleset).ac_by_type[:shield] == 6
  end
end
