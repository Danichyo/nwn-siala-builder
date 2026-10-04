defmodule BuildCalculator.Rules.GearFeatTakesTest do
  @moduledoc """
  Повторные взятия фита с вещи — задача 3.204, часть A.

  🔴 **Заведён по расхождению с ИГРОЙ, а не по чтению правила.** Репорт Dan
  13.09.2026 по своему билду (Карлик, воин 10 / защитник 23 / мастер оружия 7):
  «цифра HP не сходится с тем, что в игре. В игре у меня 1503. А в билдере
  показывает 1437». Код того билда лежит фикстурой
  (`test/fixtures/dan_build_2026-09-13.code`) и читается здесь тем же
  `Encoding.decode/1`, которым его читает браузер, — то есть проверяется тот
  самый билд, а не набранная руками похожая лестница.

  Три числа, и каждое отвечает на свой вопрос:

  | что объявлено в «Вещах» |   HP | что это значит                       |
  |-------------------------|------|--------------------------------------|
  | ничего                  | 1437 | фиты с вещи не введены вовсе          |
  | `Epic toughness` ×1     | 1470 | одно взятие                           |
  | `Epic toughness` ×2     | **1503** | ровно то, что печатает игра        |

  Обратный счёт от игровых 1503 даёт базу 906 = 866 + 40, то есть **два**
  взятия по +20 (семь кусков мини-сетов дают +66 %: 906 × 1.66 = 1503).

  ⚠️ Правило стака живёт в ДАННЫХ, и здесь оно не повторяется: какие фиты
  стакаются — `repeatable.choice == null` у самого фита, а то, что записи
  считаются поштучно, — `overrides.json` → `gear.feats.takes`. Тест проверяет
  ответы, а не список имён.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Encoding, Rules}
  alias BuildCalculator.Rules.{Build, Gear, GearFeats, Skills}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp dan_build do
    code =
      [File.cwd!(), "test/fixtures/dan_build_2026-09-13.code"]
      |> Path.join()
      |> File.read!()
      |> String.trim()

    {:ok, %{build: build, ruleset: ruleset, dropped: []}} = Encoding.decode(code)
    {build, ruleset}
  end

  defp with_gear_feats(%Build{gear: %Gear{} = gear} = build, feats),
    do: %Build{build | gear: %Gear{gear | feats: feats}}

  defp levels(classes, ruleset_version \\ "siala_41") do
    Enum.reduce(classes, base_build(ruleset_version), &Build.add_level(&2, &1))
  end

  defp base_build(ruleset_version) do
    Build.new(
      ruleset_version: ruleset_version,
      race: :human,
      alignment: :true_neutral,
      base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14}
    )
  end

  describe "билд Dan: 1437 → 1470 → 1503" do
    test "второе взятие с вещи даёт ровно те HP, что печатает игра" do
      {build, ruleset} = dan_build()

      # Билд по ссылке фитов с вещи не несёт вовсе — это первая из двух причин
      # расхождения, и она не наша: игрок их просто не ввёл.
      assert build.gear.feats == []
      assert build.gear.mini_sets == [3, 2, 2]
      assert build.gear.named_items == 0

      hp = fn feats -> Rules.compute(with_gear_feats(build, feats), ruleset).hp end

      assert hp.([]) == 1437
      assert hp.([:epic_toughness]) == 1470
      assert hp.([:epic_toughness, :epic_toughness]) == 1503
    end

    test "разбор HP называет число взятий, а не только сумму" do
      {build, ruleset} = dan_build()

      terms = fn feats ->
        with_gear_feats(build, feats)
        |> Rules.compute(ruleset)
        |> Map.fetch!(:hp_breakdown)
        |> Map.fetch!(:by_feat)
        |> Enum.filter(&(&1.feat == :epic_toughness))
      end

      assert terms.([:epic_toughness]) ==
               [%{feat: :epic_toughness, takes: 1, subtotal: 20, capped?: false}]

      assert terms.([:epic_toughness, :epic_toughness]) ==
               [%{feat: :epic_toughness, takes: 2, subtotal: 40, capped?: false}]

      # ⚠️ База процента — одна и та же, двигается только терм фита: +40 к 866
      # это +66 % сверху, то есть разница в 66 HP на экране за два числа в блоке
      # «Вещи». Проверяется разностью, потому что именно её увидит игрок.
      assert 1503 - 1437 == 66
    end
  end

  describe "какие фиты стакаются — вопрос к данным" do
    test "повторяемый без выбора — да, повторяемый с выбором и обычный — нет", %{
      ruleset: ruleset
    } do
      assert GearFeats.stackable?(:epic_toughness, ruleset)
      assert GearFeats.stackable?(:great_strength, ruleset)
      assert GearFeats.stackable?(:improved_spell_resistance, ruleset)

      # Повторяется ПАРА, а какую копию одалживает предмет, сказать нечем.
      refute GearFeats.stackable?(:epic_energy_resistance, ruleset)
      refute GearFeats.stackable?(:skill_focus, ruleset)

      # Неповторяемый — тем более.
      refute GearFeats.stackable?(:alertness, ruleset)
      refute GearFeats.stackable?(:toughness, ruleset)
    end

    # 🔴 Число названо прогоном, а не памятью (CLAUDE.md §9): шестнадцать
    # на `siala_41` 13.09.2026. Тест не перечисляет их поимённо — он считает
    # тем же способом, каким считала постановка, чтобы следующий пересчёт
    # сошёлся.
    test "их шестнадцать, и все шестнадцать повторяемы без выбора", %{ruleset: ruleset} do
      stackable = for {id, _} <- ruleset.feats, GearFeats.stackable?(id, ruleset), do: id

      assert length(stackable) == 16
      assert :epic_toughness in stackable
      assert Enum.all?(stackable, &is_nil(Rules.feat_choice_domain(&1, ruleset)))
    end
  end

  describe "получатели: HP, характеристики, SR" do
    # Слово Dan 13.09.2026: «если кто-то себе введет х10 Great strength, то нам
    # надо это показать в статах. Ведь мы уже делаем это, если взять great ...
    # при лвл апе». Одно правило на слот и на вещь.
    test "Great strength ×3 с вещей — это +3 к силе", %{ruleset: ruleset} do
      build = levels(List.duplicate(:fighter, 21))
      str = fn feats -> Rules.compute(with_gear_feats(build, feats), ruleset).abilities.str end

      assert str.([]) == 14
      assert str.([:great_strength]) == 15
      assert str.(List.duplicate(:great_strength, 3)) == 17
    end

    # Монах 12 = `Diamond soul` (SR 22). Два объявленных `Improved spell
    # resistance` — +4, а не +2: тот же счёт взятий, другой получатель.
    test "Improved spell resistance ×2 с вещей — это +4 к SR", %{ruleset: ruleset} do
      build = levels(List.duplicate(:monk, 12))
      sr = fn feats -> Rules.compute(with_gear_feats(build, feats), ruleset).spell_resistance end

      assert sr.([]) == 22
      assert sr.([:improved_spell_resistance]) == 24
      assert sr.(List.duplicate(:improved_spell_resistance, 2)) == 26
    end

    # ⚠️ Отрицательный контроль, без которого «стакается» зеленело бы и на
    # модели, которая складывает ВСЁ подряд: фит с выбором, объявленный дважды
    # с одним и тем же значением, остаётся одним взятием и одной прибавкой.
    test "Skill focus одного навыка дважды — одна прибавка", %{ruleset: ruleset} do
      build = levels(List.duplicate(:fighter, 5))
      once = with_gear_feats(build, [{:skill_focus, :discipline}])
      twice = with_gear_feats(build, [{:skill_focus, :discipline}, {:skill_focus, :discipline}])

      assert Build.feat_takes_owned(once, ruleset, :skill_focus, 5) == 1
      assert Build.feat_takes_owned(twice, ruleset, :skill_focus, 5) == 1

      assert Skills.value(twice, ruleset, :discipline, 5).feat_bonus ==
               Skills.value(once, ruleset, :discipline, 5).feat_bonus
    end
  end

  describe "потолок эффекта считает сумму слотов и вещей" do
    # 🔴 Слово Dan 14.08.2026: «как максимум для УЧЁТА там всё равно будет
    # только 10 раз, учитывая СУММУ того, что взяли в билде, и того, что
    # набрали с вещей». Девять слотовых плюс две записи с вещей — одиннадцать
    # взятий, и всё те же 200 хитов.
    test "девять слотовых + две с вещей = 200 HP и (потолок)", %{ruleset: ruleset} do
      nine =
        Enum.reduce(21..29//1, levels(List.duplicate(:fighter, 41)), fn level, acc ->
          Build.put_feat(acc, level, :general, :epic_toughness)
        end)

      assert Build.feat_takes(nine, :epic_toughness, 41) == 9

      two = with_gear_feats(nine, [:epic_toughness, :epic_toughness])
      assert Build.feat_takes_owned(two, ruleset, :epic_toughness, 41) == 11

      # ⚠️ Только терм `Epic toughness`: воин на Сиале выдаёт себе `Toughness`
      # сам, и его строка стоит рядом — её здесь проверяет соседний тест.
      terms = fn b ->
        b
        |> Rules.compute(ruleset)
        |> Map.fetch!(:hp_breakdown)
        |> Map.fetch!(:by_feat)
        |> Enum.filter(&(&1.feat == :epic_toughness))
      end

      assert terms.(two) == [%{feat: :epic_toughness, takes: 11, subtotal: 200, capped?: true}]

      # Десятое взятие (одна запись с вещей) даёт ровно потолок и ещё не режется —
      # положительный контроль к строке выше.
      one = with_gear_feats(nine, [:epic_toughness])

      assert terms.(one) == [%{feat: :epic_toughness, takes: 10, subtotal: 200, capped?: false}]
      assert Rules.compute(one, ruleset).hp == Rules.compute(two, ruleset).hp
    end
  end

  describe "запись взятий в самом билде" do
    test "add_feat/remove_feat считают по одному, toggle_feat остаётся переключателем" do
      gear = Gear.new()

      gear = gear |> Gear.add_feat(:epic_toughness) |> Gear.add_feat(:epic_toughness)
      assert gear.feats == [:epic_toughness, :epic_toughness]
      assert Gear.feat_takes(gear, :epic_toughness) == 2

      gear = Gear.remove_feat(gear, :epic_toughness)
      assert gear.feats == [:epic_toughness]

      # ⚠️ Список отсортирован, как и был: код билда обязан быть одинаковым
      # у одинакового билда, а порядка кликов билд не помнит.
      mixed =
        Gear.new()
        |> Gear.add_feat(:great_strength)
        |> Gear.add_feat(:epic_toughness)
        |> Gear.add_feat(:great_strength)

      assert mixed.feats == [:epic_toughness, :great_strength, :great_strength]

      # Переключатель второй записи не заводит — снимает первую.
      toggled = Gear.new() |> Gear.toggle_feat(:alertness) |> Gear.toggle_feat(:alertness)
      assert toggled.feats == []
    end

    test "ruleset без правила считает по-старому: одна запись на фит", %{ruleset: ruleset} do
      # ⚠️ СИНТЕТИКА, и она тут единственный способ проверить фоллбэк: в обоих
      # поставляемых ruleset'ах ключ есть, поэтому живого носителя у ветки
      # не бывает — а снапшот, потерявший ключ, обязан считать по-старому,
      # а не выдумывать (CLAUDE.md §9, «живыми их держит синтетика»).
      silent = put_in(ruleset.gear.feat_takes, nil)
      gear = Gear.new(feats: [:epic_toughness, :epic_toughness])

      assert GearFeats.takes(gear, ruleset, :epic_toughness) == 2
      assert GearFeats.takes(gear, silent, :epic_toughness) == 1
    end

    test "объявление, которое ruleset отвергает, взятием не считается", %{ruleset: ruleset} do
      # `Devastating critical` шард выключил — две записи о нём не дают ни
      # одного взятия, ровно как не давала одна.
      gear = Gear.new(feats: [:devastating_critical, :devastating_critical])

      assert GearFeats.takes(gear, ruleset, :devastating_critical) == 0
      assert length(GearFeats.illegal(gear, ruleset)) == 2
    end
  end
end
