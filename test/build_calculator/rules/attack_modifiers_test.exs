defmodule BuildCalculator.Rules.AttackModifiersTest do
  @moduledoc """
  Тайный лучник Сиалы: атаки, которые ваниль объявляет невозможными.

  Источник один и цитируется дословно (`priv/rules/siala_41/classes.json` →
  `arcane_archer` → `extra_attacks`, `status: verified`, страница «Тайный лучник»,
  revid 20405):

      За каждые 10 уровней класс получает одну дополнительную атаку (максимум 3
      за 30 уровней в классе).
      **Персонаж, у которого модификатор мудрости выше, чем модификатор
        ловкости, не получает преимуществ дополнительных атак;
      **Персонаж с классами ШД 4 и более не получает дополнительных атак;
      **Персонаж на коне не получает дополнительных атак.

  Против него — `priv/rules/vanilla/epic.json`: «число атак навсегда фиксируется
  BAB'ом на 20-м уровне», сверено по трём независимым страницам Fandom. Оба
  правила верны каждое на своём шарде, поэтому ядро складывает базу и слой,
  а не переписывает формулу (`Rules.AttackModifiers`).

  ⚠️ **Билды здесь собираются левелапами через `validate_level_up/3`**, а не
  списком классов в `Build.new/1`. Разница не косметическая: Тайный лучник
  требует расу, БАБ +6, два фита с выбранным оружием и уровень арканового
  класса, — и билд, засунутый списком, проходит расчёт, которого игра
  не позволит (ловушка CLAUDE.md §3, на которой координатор уже погорел).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{AttackModifiers, Build, Gear}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  # Лестница, которую игрок реально пройдёт: бард 1–9 набирает БАБ +6 и оба
  # требуемых фита (Стрельба в упор и Владение оружием с выбранным длинным
  # луком), дальше идёт Тайный лучник. Раса — Светлый эльф (half_elf), одна
  # из двух, которые требование называет.
  #
  # ⚠️ Бард, а не волшебник: `hide` / `move_silently` / `tumble` у него классовые,
  # и без этого требование Теневого танцора ниже не набирается вовсе.
  defp archer(ruleset, class_levels, opts \\ []) do
    abilities = Keyword.get(opts, :abilities, %{dex: 16, wis: 10})

    base =
      Build.new(
        ruleset_version: ruleset.version,
        race: :half_elf,
        alignment: :true_neutral,
        base_abilities:
          Map.merge(%{str: 10, dex: 16, con: 12, int: 14, wis: 10, cha: 14}, abilities),
        gear: Keyword.get(opts, :gear, Gear.new()),
        feats: %{
          1 => %{general: :point_blank_shot},
          3 => %{general: :dodge},
          6 => %{general: :mobility},
          9 => %{general: {:weapon_focus, :longbow}}
        },
        # Требование Теневого танцора: Hide 10, Move Silently 8, Tumble 5.
        # Куплены на 9-м уровне барда, где классовый потолок 12.
        skills: %{9 => %{hide: 10, move_silently: 8, tumble: 5}}
      )

    Enum.reduce(class_levels, base, fn class, build ->
      assert Rules.validate_level_up(build, %{class: class}, ruleset) == :ok,
             "#{class} на уровне #{length(build.levels) + 1} — билд собран нелегально"

      Build.add_level(build, class)
    end)
  end

  defp bard_9, do: List.duplicate(:bard, 9)
  defp archer_levels(n), do: bard_9() ++ List.duplicate(:arcane_archer, n)

  defp extra(ruleset, levels, opts \\ []) do
    ruleset
    |> archer(levels, opts)
    |> Rules.compute(ruleset)
    |> Map.fetch!(:attacks_per_round_terms)
    |> AttackModifiers.total()
  end

  describe "«за каждые 10 уровней класса — одна атака, максимум 3»" do
    # source: siala_41/classes.json → arcane_archer → extra_attacks
    # («per_class_levels: 10, attacks_per_step: 1, max: 3»).
    test "ступени: 9 уровней ничего, 10 / 20 / 30 дают 1 / 2 / 3", %{ruleset: ruleset} do
      assert extra(ruleset, archer_levels(9)) == 0
      assert extra(ruleset, archer_levels(10)) == 1

      # ⚠️ 11-й уровень престиж-класса требует 20 уровней персонажа
      # (`fandom:Epic class`), поэтому после десятого лучника лестница
      # добирает уровни барда до 20-го и только тогда идёт дальше.
      assert extra(ruleset, to_twenty() ++ List.duplicate(:arcane_archer, 10)) == 2
      assert extra(ruleset, to_twenty() ++ List.duplicate(:arcane_archer, 20)) == 3
    end

    # Потолок из данных, а не из кода: 31-й уровень класса — предел, который
    # даёт Сиала престиж-классам, и он всё ещё +3.
    test "потолок держит: 31 уровень класса — всё те же 3", %{ruleset: ruleset} do
      assert extra(ruleset, to_twenty() ++ List.duplicate(:arcane_archer, 21)) == 3
    end

    test "билд без единого уровня класса ничего не получает", %{ruleset: ruleset} do
      assert extra(ruleset, bard_9()) == 0
      assert extra(ruleset, bard_9() ++ List.duplicate(:fighter, 11)) == 0
    end

    # Ровно то, ради чего слой отделён от базы: у ванили правило кончается
    # таблицей, и лишний уровень Тайного лучника там не значит ничего.
    test "ванильный ruleset слоя не имеет вовсе", %{vanilla: vanilla} do
      levels = List.duplicate(:fighter, 10) ++ List.duplicate(:arcane_archer, 10)
      stats = Rules.compute(Build.new(levels: levels), vanilla)

      assert vanilla.attack_modifiers == []
      assert stats.attacks_per_round_terms == []
      assert stats.attacks_per_round == 4
    end
  end

  describe "условие «модификатор мудрости выше, чем модификатор ловкости»" do
    # source: та же цитата. ⚠️ «Выше», а не «выше или равно» — сравнение
    # строгое, и обе стороны границы под тестом: при равных модификаторах
    # атаки остаются.
    test "мудрость выше — атак нет; ловкость выше — есть", %{ruleset: ruleset} do
      assert extra(ruleset, archer_levels(10), abilities: %{dex: 16, wis: 10}) == 1
      assert extra(ruleset, archer_levels(10), abilities: %{dex: 16, wis: 18}) == 0
    end

    test "равные модификаторы прибавку НЕ отменяют", %{ruleset: ruleset} do
      # DEX 16 и WIS 16 — оба модификатора +3.
      assert extra(ruleset, archer_levels(10), abilities: %{dex: 16, wis: 16}) == 1

      # И на соседнем значении внутри одного модификатора тоже: WIS 17 — всё
      # ещё +3, потому что модификатор считается floor((17 − 10) / 2).
      assert extra(ruleset, archer_levels(10), abilities: %{dex: 16, wis: 17}) == 1
    end

    # ⚠️ РЕШЕНИЕ, а не прочитанное правило (задача 3.72): источник не говорит,
    # голыми или в шмоте считаются модификаторы, и общего правила у проекта нет
    # — требования фитов вещи игнорируют (замеры S1/S2), бонусные слоты
    # заклинаний их считают (задача 3.70). Взято «в шмоте», и разбор лежит
    # в самих данных, рядом с цитатой, которую он толкует
    # (`read_modifiers: "with_gear"`).
    #
    # Оба направления под тестом: вещь и отнимает прибавку, и возвращает её.
    test "модификаторы читаются В ШМОТЕ, и это видно в обе стороны", %{ruleset: ruleset} do
      # голым ловкость выше — прибавка есть; надел +12 мудрости — пропала
      assert extra(ruleset, archer_levels(10), abilities: %{dex: 16, wis: 10}) == 1

      assert extra(ruleset, archer_levels(10),
               abilities: %{dex: 16, wis: 10},
               gear: Gear.new(abilities: %{wis: 12})
             ) == 0

      # голым мудрость выше — прибавки нет; надел +12 ловкости — появилась
      assert extra(ruleset, archer_levels(10), abilities: %{dex: 16, wis: 18}) == 0

      assert extra(ruleset, archer_levels(10),
               abilities: %{dex: 16, wis: 18},
               gear: Gear.new(abilities: %{dex: 12})
             ) == 1
    end

    # Сторож на данные: сравнение обязано брать характеристики, названные
    # в записи, и стороной, названной в записи. Ни одного имени характеристики
    # в `rules/` нет — и этот тест падает, если оно там появится.
    test "какие характеристики сравнивать — сказано в данных", %{ruleset: ruleset} do
      [modifier] = ruleset.attack_modifiers

      assert %{
               kind: :ability_modifier_exceeds,
               ability: :wis,
               exceeds: :dex,
               read_modifiers: :with_gear,
               modelled?: true
             } in modifier.disabled_if
    end
  end

  describe "условие «персонаж с классами ШД 4 и более»" do
    # source: та же цитата. Сравнение НЕстрогое: три уровня Теневого танцора
    # прибавку оставляют, четвёртый убирает.
    test "три уровня ШД прибавку оставляют, четыре — убирают", %{ruleset: ruleset} do
      assert extra(ruleset, archer_levels(10) ++ List.duplicate(:shadowdancer, 3)) == 1
      assert extra(ruleset, archer_levels(10) ++ List.duplicate(:shadowdancer, 4)) == 0
    end

    test "и на большем числе уровней класса тоже: правило гасит всю прибавку",
         %{ruleset: ruleset} do
      levels = to_twenty() ++ List.duplicate(:arcane_archer, 10)

      assert extra(ruleset, levels) == 2
      assert extra(ruleset, levels ++ List.duplicate(:shadowdancer, 4)) == 0
    end

    test "какой класс и сколько его уровней — сказано в данных", %{ruleset: ruleset} do
      [modifier] = ruleset.attack_modifiers

      assert %{kind: :class_levels_at_least, class: :shadowdancer, levels: 4, modelled?: true} in modifier.disabled_if
    end
  end

  describe "условие «персонаж на коне»" do
    # ⚠️ Решение Dan 21.08.2026: «Конь = бафф на данный момент, так что мы
    # не моделируем на коне персонаж или без коня». Считаем персонажа НЕ на
    # коне, то есть условие не срабатывает никогда.
    #
    # Гэпа на это нет и быть не должно: калькулятор про верховую езду
    # не отвечает вовсе, значит и дырки в ответе нет (CLAUDE.md §9).
    test "объявлено немоделируемым в ДАННЫХ, а не пропущено в коде",
         %{ruleset: ruleset} do
      [modifier] = ruleset.attack_modifiers

      assert %{kind: :mounted, modelled?: false} in modifier.disabled_if
    end

    test "и оговорки за него не платится", %{ruleset: ruleset} do
      stats = Rules.compute(archer(ruleset, archer_levels(10)), ruleset)

      refute Enum.any?(stats.gaps, &match?({:not_modelled, {:mounted, _}}, &1))
      refute Enum.any?(stats.gaps, &match?({:not_modelled, {:extra_attacks, _}}, &1))

      refute Enum.any?(
               ruleset.gaps,
               &match?({:not_modelled, {:class_change, :arcane_archer, _}}, &1)
             )
    end
  end

  describe "точка расширения" do
    # Ни одного игрового числа в ядре: всё, что решает ответ, приходит записью.
    # Тест не про Тайного лучника — про то, что второй такой класс поедет
    # без правки кода.
    test "чужая запись с другими числами считается тем же кодом", %{ruleset: ruleset} do
      # +2 атаки за каждые 5 уровней барда, без потолка и без условий
      invented = %{
        source: {:class, :bard},
        kind: :extra_attacks,
        per_class_levels: 5,
        attacks_per_step: 2,
        max: nil,
        disabled_if: [],
        status: "test"
      }

      ruleset = put_in(ruleset.attack_modifiers, [invented])
      build = archer(ruleset, bard_9())

      context = AttackModifiers.context(build, modifiers(), modifiers())

      # 9 уровней барда — одна полная ступень из пяти уровней, то есть +2
      assert AttackModifiers.terms(ruleset, context) == [
               %{source: {:class, :bard}, kind: :extra_attacks, attacks: 2}
             ]
    end

    # ⚠️ Потолок применяется к АТАКАМ, а не к ступеням, и порядок здесь виден
    # только на записи, где эти два числа расходятся: 4 ступени × 2 атаки = 8,
    # потолок 3 — значит 3, а не 6.
    test "потолок режет атаки, а не ступени", %{ruleset: ruleset} do
      invented = %{
        source: {:class, :bard},
        kind: :extra_attacks,
        per_class_levels: 2,
        attacks_per_step: 2,
        max: 3,
        disabled_if: [],
        status: "test"
      }

      ruleset = put_in(ruleset.attack_modifiers, [invented])
      assert AttackModifiers.total(AttackModifiers.terms(ruleset, no_gear_context(ruleset))) == 3
    end

    # У каждого вида условия, который загрузчик пускает в ruleset, обязана быть
    # ветка в `holds?/2`. Иначе загрузчик примет запись, а расчёт упадёт
    # `FunctionClauseError` на билде игрока.
    test "у каждого вида условия из словаря есть ветка расчёта", %{ruleset: ruleset} do
      context = no_gear_context(ruleset)

      for kind <- AttackModifiers.condition_kinds() do
        fields = AttackModifiers.condition_fields(kind)
        assert match?([_ | _], fields), "у #{kind} не названо ни одного поля"

        condition =
          fields
          |> Map.new(&{&1, condition_stub(&1)})
          |> Map.merge(%{kind: kind, modelled?: true})

        modifier = %{
          source: {:class, :bard},
          kind: :extra_attacks,
          per_class_levels: 1,
          attacks_per_step: 1,
          max: nil,
          disabled_if: [condition],
          status: "test"
        }

        ruleset = put_in(ruleset.attack_modifiers, [modifier])

        assert is_list(AttackModifiers.terms(ruleset, context)),
               "условие #{kind} загрузчик пускает, а `holds?/2` его не знает"
      end
    end
  end

  # Полный набор модификаторов — `holds?/2` спрашивает их `fetch!`, и это
  # намеренно: имя характеристики, которого нет в карте, значит сломанный
  # контекст, а не ноль.
  defp modifiers, do: %{str: 0, dex: 3, con: 1, int: 2, wis: 0, cha: 2}

  defp no_gear_context(ruleset),
    do: AttackModifiers.context(archer(ruleset, bard_9()), modifiers(), modifiers())

  # Заглушки полей: значения не важны, важно, что ветка есть и не падает.
  defp condition_stub(:ability), do: :wis
  defp condition_stub(:exceeds), do: :dex
  defp condition_stub(:read_modifiers), do: :naked
  defp condition_stub(:class), do: :bard
  defp condition_stub(:levels), do: 1

  # Догнать 20-й уровень персонажа уровнями барда: 11-й уровень престиж-класса
  # без этого не берётся вовсе.
  defp to_twenty, do: archer_levels(10) ++ List.duplicate(:bard, 1)
end
