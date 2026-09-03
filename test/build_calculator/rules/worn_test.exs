defmodule BuildCalculator.Rules.WornTest do
  @moduledoc """
  Надетое как ПРЕДМЕТ — задачи 3.41 и 3.42.

  До 3.41 блок «Вещи» просил число на каждый тип AC и больше ничего, поэтому два
  факта, которые есть у любого настоящего персонажа, жить было негде: **база**
  класса брони (складывается всегда) и **предел бонуса ловкости**, который
  доспех ставит. Персонаж в латах с DEX 30 получал у нас +10 ловкости там, где
  игра даёт +1. Третью величину — **штраф брони к навыкам** — принесла 3.42.

  Источники, по которым здесь считаются ожидания:

    * `fandom:Armor check penalty` (в кэше, снят 16.08.2026) — колонки `Base AC`
      и `Armor check penalty`. ⚠️ Таблица озаглавлена «Type of armor **or
      shield**», поэтому щиты в ней есть: база 1 / 2 / 3, штраф −1 / −2 / −10.
      Оттуда же правило сложения: «If a character is wearing armor and using a
      shield, **both** armor check penalties apply»;
    * `fandom:Maximum dexterity bonus` (revid 59855, **в кэше НЕТ** — снята через
      `api.php`, как когда-то `Point buy` и `Ability cap`) — колонка `Maximum
      dexterity bonus`. ⚠️ Её таблица озаглавлена «Type of **armor**» и щитов не
      содержит вовсе. Дословно про область действия: «This cap applies only to
      AC; it does not affect the attack bonus for ranged weapons, the attack
      bonus from weapon finesse, reflex saves, nor dexterity-based skills».

  Сиала про все три колонки не говорит нигде (проверен весь кэш 16.08.2026),
  значит ванильное по общему правилу — `CLAUDE.md` §3.

  ⚠️ Здесь проверяется ПРЕДМЕТНАЯ сторона штрафа — сколько отнимает надетое.
  Кому он достаётся (шесть навыков поимённо, `open_lock` и `ride` вне списка) —
  в `BuildCalculator.Rules.SkillsTest`, потому что это факт о навыке.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, Worn}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  @flat %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}

  defp build(levels, fields) do
    Build.new([levels: levels, base_abilities: @flat, race: :human] ++ fields)
  end

  defp geared(levels, gear_fields, fields) do
    build(levels, [gear: Gear.new(gear_fields)] ++ fields)
  end

  describe "справочник: обе колонки, строка в строку по источнику" do
    # Табличный кейс — ровно те девять строк, что стоят на источнике. Проверяется
    # у ЯДРА через ruleset, а не чтением JSON: смысл в том, что число доезжает
    # до расчёта, а не в том, что оно записано.
    #
    # 🔴 Источников СТОЛБЦА «предел ловкости» с 30.08.2026 два, и таблицы поэтому
    # тоже две: у ванили `fandom:Maximum dexterity bonus` (revid 59855), у Сиалы
    # замер Dan (`GAME_CHECKS.md` → AH1, задачи 3.140–3.141). База AC у обоих
    # одна и та же — её тот же замер подтвердил 9 из 9.
    test "девять строк доспеха на Сиале: база AC и ИЗМЕРЕННЫЙ предел ловкости", %{
      ruleset: ruleset
    } do
      expected = [
        {:none, 0, nil},
        {:padded, 1, 8},
        {:leather, 2, 7},
        {:studded_leather, 3, 6},
        {:chain_shirt, 4, 5},
        {:chainmail, 5, 4},
        {:splint_mail, 6, 3},
        {:half_plate, 7, 2},
        {:full_plate, 8, 1}
      ]

      armor = Worn.category(ruleset, :armor)

      assert for(item <- armor.items, do: {item.id, item.base_ac, item.max_dex}) == expected
      assert armor.ac_type == :armor
      assert armor.caps_dexterity?
    end

    # ⚠️ И те же девять строк у ванили — с ванильным пределом. Шесть из девяти
    # отличаются, и это не дрейф данных, а два разных источника про одну колонку.
    test "девять строк доспеха у ванили: тот же base_ac, ВАНИЛЬНЫЙ предел", %{vanilla: vanilla} do
      expected = [
        {:none, 0, nil},
        {:padded, 1, 8},
        {:leather, 2, 6},
        {:studded_leather, 3, 4},
        {:chain_shirt, 4, 4},
        {:chainmail, 5, 2},
        {:splint_mail, 6, 1},
        {:half_plate, 7, 1},
        {:full_plate, 8, 1}
      ]

      armor = Worn.category(vanilla, :armor)

      assert for(item <- armor.items, do: {item.id, item.base_ac, item.max_dex}) == expected
    end

    # 🔴 Требование 2 со стороны данных: у щитов колонки предела ловкости нет
    # ВОВСЕ, а не «стоит пусто». Таблица источника озаглавлена «Type of armor»
    # и щитов не содержит; дописать их туда значило бы выдумать игровое число.
    test "три щита: база есть, предела ловкости нет ни у одного", %{ruleset: ruleset} do
      shield = Worn.category(ruleset, :shield)

      assert for(item <- shield.items, do: {item.id, item.base_ac}) == [
               {:small, 1},
               {:large, 2},
               {:tower, 3}
             ]

      assert shield.ac_type == :shield
      refute shield.caps_dexterity?
      assert Enum.all?(shield.items, &is_nil(&1.max_dex))
    end

    # 🔴 `gear` — ОБЩАЯ секция обоих ruleset'ов, и до задачи 3.141 они видели её
    # байт в байт. ⚠️ Здесь стояло `Worn.categories(vanilla) == Worn.categories
    # (ruleset)` с доводом «числа ванильные»: довод верен для базы AC и штрафа
    # (замер AH1 подтвердил их 9 из 9) и НЕВЕРЕН для предела ловкости — шард
    # переписал его в шести записях. Проверяется теперь то же самое требование
    # с обеих сторон: расходятся ровно два поля и ровно там, где измерено.
    test "ванили достался её собственный предел, а не сиальский", %{
      ruleset: ruleset,
      vanilla: vanilla
    } do
      shared = fn worn ->
        for category <- worn do
          {category.id, category.ac_type, category.caps_dexterity?, category.occupies_off_hand?,
           for(item <- category.items, do: {item.id, item.base_ac, item.armor_check_penalty})}
        end
      end

      assert shared.(Worn.categories(vanilla)) == shared.(Worn.categories(ruleset))
      refute Worn.categories(vanilla) == Worn.categories(ruleset)

      vanilla_armor = Worn.category(vanilla, :armor)
      siala_armor = Worn.category(ruleset, :armor)

      differing =
        for {v, s} <- Enum.zip(vanilla_armor.items, siala_armor.items),
            v.max_dex != s.max_dex,
            do: v.id

      assert differing == [
               :leather,
               :studded_leather,
               :chain_shirt,
               :chainmail,
               :splint_mail,
               :half_plate
             ]

      # ⚠️ Класс брони расходится у ВСЕХ девяти, потому что у ванили его не
      # знает никто: измеряли на Сиале, а переносить по аналогии запрещено —
      # кольчужная рубаха там средняя, а в D&D 3.5 лёгкая.
      assert Enum.all?(vanilla_armor.items, &(&1.weight_class == :unknown))
      refute Enum.any?(siala_armor.items, &(&1.weight_class == :unknown))
    end
  end

  # 🔴 Требование 1 задачи, и самая напрашивающаяся ошибка: срезать ловкость
  # целиком. Она испортила бы рефлекс, дальнюю атаку и навыки заодно.
  describe "предел ловкости режет ТОЛЬКО вклад в AC" do
    # DEX 30 → модификатор +10, латы → предел +1.
    @dex30 %{@flat | dex: 30}

    # `Weapon Finesse` в слоте: атака начинает считаться от ловкости
    # (`CLAUDE.md` §6, третий вид фита). Именно её страница источника называет
    # поимённо среди того, чего потолок НЕ касается.
    defp finesse(gear_fields) do
      geared(List.duplicate(:fighter, 10), gear_fields,
        base_abilities: @dex30,
        feats: %{1 => %{general: :weapon_finesse}},
        skills: for(level <- 1..10, into: %{}, do: {level, %{hide: 1}})
      )
    end

    test "в латах AC получает +1 ловкости, а рефлекс, атака и навык — все +10", %{
      ruleset: ruleset
    } do
      plate = Rules.compute(finesse(worn: %{armor: :full_plate}), ruleset)

      # AC: 10 базы + 1 ловкости (вместо 10) + 8 базы лат.
      assert plate.ac_dexterity == %{modifier: 10, counted: 1, cap: 1, capped?: true}
      assert plate.ac_geared == 19

      # 🔴 И ровно те три числа, которые страница источника называет поимённо.
      # Рефлекс воина 10 = +3 базы, атака = BAB +10 и ловкость через Finesse,
      # Скрытность = 10 рангов + модификатор.
      assert plate.ref == 3 + 10
      assert plate.attack_ability == :dex
      assert plate.attack_bonus == 10 + 10

      # ⚠️ У Скрытности с задачи 3.42 есть ВТОРОЕ слагаемое от тех же лат —
      # штраф брони −8, — и оно ничего не отменяет в утверждении выше, а
      # проверяет его точнее: ловкость входит в навык ЦЕЛИКОМ (+10, а не
      # срезанная до +1), а отнимает отдельный терм со своим числом. Спутать их
      # нельзя: предел ловкости у лат +1, штраф −8, и промах любой из двух
      # величин виден порознь.
      hide = plate.skill_values[:hide]
      assert hide.ability_modifier == 10
      assert hide.armor_penalty == -8
      assert hide.total == 10 + 10 - 8

      # И сам модификатор нетронут: срезан ОТДЕЛЬНЫЙ терм, а не характеристика.
      assert plate.ability_modifiers.dex == 10
    end

    # ⚠️ Отрицательный контроль: без доспеха те же четыре числа считаются от
    # полного модификатора, включая AC. Без него «+1 в AC» зеленело бы и при
    # срезанной наглухо ловкости.
    test "без доспеха все четыре числа считают полный модификатор", %{ruleset: ruleset} do
      bare = Rules.compute(finesse([]), ruleset)

      assert bare.ac_dexterity == %{modifier: 10, counted: 10, cap: nil, capped?: false}
      assert bare.ac_geared == 20
      assert bare.ref == 3 + 10
      assert bare.attack_bonus == 10 + 10

      # Без доспеха нет и штрафа — то же число, что было до задачи 3.42.
      assert bare.skill_values[:hide].total == 10 + 10
      assert bare.skill_values[:hide].armor_penalty == 0
    end

    # Предел зависит от НАДЕТОГО, а не от величины ловкости: у ступеней таблицы
    # разные пределы, и каждый обязан доезжать до числа.
    test "ступени предела: 8 / 7 / 6 / 4 / 1 и «без предела»", %{ruleset: ruleset} do
      for {armor, counted} <- [
            {:none, 10},
            {:padded, 8},
            {:leather, 7},
            {:studded_leather, 6},
            {:chainmail, 4},
            {:full_plate, 1}
          ] do
        stats = Rules.compute(finesse(worn: %{armor: armor}), ruleset)

        assert stats.ac_dexterity.counted == counted,
               "#{armor}: ожидали +#{counted} ловкости в AC, вышло +#{stats.ac_dexterity.counted}"

        # ...и рефлекс в каждой строке остаётся полным.
        assert stats.ref == 3 + 10, "#{armor}: потолок доехал до рефлекса"
      end
    end

    # Потолок про БОНУС, и штраф под него не попадает: пола не называет ни один
    # источник. Ловкость 4 — модификатор −3, латы с пределом +1 его не трогают.
    test "отрицательный модификатор ловкости потолок не трогает", %{ruleset: ruleset} do
      low = %{@flat | dex: 4}

      stats =
        Rules.compute(
          geared(List.duplicate(:fighter, 10), [worn: %{armor: :full_plate}],
            base_abilities: low
          ),
          ruleset
        )

      assert stats.ac_dexterity == %{modifier: -3, counted: -3, cap: 1, capped?: false}
      assert stats.ac_geared == 10 - 3 + 8
    end

    # Флаг для интерфейса: молча уменьшенное число читается как поломка.
    #
    # ⚠️ Флаг СВОЙ (`ac_dexterity.capped?`), а не строка в `stats.capped`: тот
    # список означает «упёрлось в потолок из `ruleset.stat_caps`», а этот предел
    # принадлежит предмету, и в `stat_caps` его нет вовсе. Проверяется и то, и
    # другое — иначе одно из двух утверждений держалось бы на честном слове.
    test "срез назван флагом, и только когда он был", %{ruleset: ruleset} do
      plate = Rules.compute(finesse(worn: %{armor: :full_plate}), ruleset)

      assert plate.ac_dexterity.capped?
      refute :ac_dexterity in plate.capped
      refute :gear_ac in plate.capped

      # Одежда предела не имеет вовсе...
      refute Rules.compute(finesse(worn: %{armor: :none}), ruleset).ac_dexterity.capped?
      refute Rules.compute(finesse([]), ruleset).ac_dexterity.capped?

      # ...а вот граница: предел ЕСТЬ и ровно равен модификатору. Флага быть не
      # должно — резать нечего, и «упёрся ровно» это не срез.
      touching =
        Rules.compute(
          geared(List.duplicate(:fighter, 10), [worn: %{armor: :chainmail}],
            base_abilities: %{@flat | dex: 18}
          ),
          ruleset
        )

      assert touching.ac_dexterity == %{modifier: 4, counted: 4, cap: 4, capped?: false}
    end
  end

  # Третья колонка той же таблицы (задача 3.42) — и единственная, что уходит
  # не в AC, а в навыки. Здесь проверяется ПРЕДМЕТНАЯ половина правила: сколько
  # отнимает надетое. Кому оно достаётся — в `SkillsTest`.
  describe "штраф брони: колонка предмета" do
    # ⚠️ Колонка есть у КАЖДОГО из двенадцати предметов, и это не украшение:
    # «поля нет» и «штрафа нет» иначе выглядели бы одинаково, а загрузчик на
    # отсутствующем поле падает. Проверка тому, что справочник его довозит.
    test "число несёт каждый предмет обеих категорий", %{ruleset: ruleset} do
      for category <- Worn.categories(ruleset), item <- category.items do
        assert is_integer(item.armor_check_penalty),
               "#{category.id}/#{item.id}: штраф не доехал до справочника"

        assert item.armor_check_penalty <= 0,
               "#{category.id}/#{item.id}: штраф положительный, то есть это бонус"
      end
    end

    # 🔴 «If a character is wearing armor and using a shield, both armor check
    # penalties apply» — складываются, а не выбирается больший.
    test "доспех и щит складываются, и голым штрафа нет", %{ruleset: ruleset} do
      # ⚠️ Билд, а не `Gear`: с задачи 3.43 надетое может быть НЕЛЕГАЛЬНЫМ, и
      # решают это раса и оружие в руках — то есть вопрос перестал быть
      # вопросом к одному блоку «Вещи». Здесь человек с пустыми руками, то
      # есть отказывать нечему.
      penalty = fn worn ->
        Worn.armor_check_penalty(build([:fighter], gear: Gear.new(worn: worn)), ruleset)
      end

      assert penalty.(%{}) == 0
      assert penalty.(%{armor: :full_plate}) == -8
      assert penalty.(%{shield: :tower}) == -10
      assert penalty.(%{armor: :full_plate, shield: :tower}) == -18

      # ⚠️ И это именно сумма, а не «берём худшее»: у лат со щитом −18, а
      # максимум из двух дал бы −10. Число, у которого слагаемые не совпадают
      # по величине, — единственная пара, где обе реализации различимы.
      assert penalty.(%{armor: :chain_shirt, shield: :small}) == -3
    end

    # ⚠️ 🔴 Две колонки одной таблицы РАСХОДЯТСЯ в том, что тяжелее: по базе AC
    # башенный щит самый слабый предмет справочника (3 против 8 у лат), по
    # штрафу — самый сильный (−10 против −8). Реализация, перепутавшая колонки
    # местами, зеленела бы на любом доспехе и падала бы здесь.
    test "по базе башенный щит слабее лат, по штрафу — сильнее", %{ruleset: ruleset} do
      plate = Enum.find(Worn.category(ruleset, :armor).items, &(&1.id == :full_plate))
      tower = Enum.find(Worn.category(ruleset, :shield).items, &(&1.id == :tower))

      assert tower.base_ac < plate.base_ac
      assert tower.armor_check_penalty < plate.armor_check_penalty
    end

    # Неизвестный предмет и неизвестная категория не дают ни штрафа, ни падения
    # — ровно как не дают базы и предела (см. describe ниже).
    test "предмет и категория, которых справочник не знает, не штрафуют", %{ruleset: ruleset} do
      unknown = fn worn -> build([:fighter], gear: Gear.new(worn: worn)) end

      assert Worn.armor_check_penalty(unknown.(%{armor: :mithral_shirt}), ruleset) == 0
      assert Worn.armor_check_penalty(unknown.(%{helmet: :full_plate}), ruleset) == 0
    end
  end

  # 🔴 Требование 2 задачи: таблица предела озаглавлена «Type of armor»,
  # в отличие от соседней «Type of armor **or shield**» у штрафа брони.
  describe "предел ловкости зависит ТОЛЬКО от доспеха" do
    @dex30 %{@flat | dex: 30}

    defp nimble(gear_fields) do
      geared(List.duplicate(:fighter, 10), gear_fields, base_abilities: @dex30)
    end

    test "башенный щит без доспеха ловкость не режет", %{ruleset: ruleset} do
      stats = Rules.compute(nimble(worn: %{shield: :tower}), ruleset)

      assert stats.ac_dexterity == %{modifier: 10, counted: 10, cap: nil, capped?: false}
      # 10 базы + 10 ловкости + 3 базы башенного щита.
      assert stats.ac_geared == 23
    end

    # ⚠️ Положительный контроль: доспех на том же билде режет. Без него первая
    # строка зеленела бы и при вовсе неработающем потолке.
    test "тот же билд в латах ловкость теряет", %{ruleset: ruleset} do
      stats = Rules.compute(nimble(worn: %{armor: :full_plate}), ruleset)

      assert stats.ac_dexterity.counted == 1
    end

    # И вместе: предел приходит от доспеха, щит только добавляет базу.
    test "доспех и щит вместе: предел от доспеха, база от обоих", %{ruleset: ruleset} do
      stats = Rules.compute(nimble(worn: %{armor: :leather, shield: :tower}), ruleset)

      # Кожаный даёт предел +7 и базу 2, башенный щит — базу 3.
      assert stats.ac_dexterity.cap == 7
      assert stats.ac_by_type[:armor] == 2
      assert stats.ac_by_type[:shield] == 3
      assert stats.ac_geared == 10 + 7 + 2 + 3
    end
  end

  # 🔴 Требование 3 задачи. Правило «надетое, дающее AC, отключает бонусы
  # монаха» смотрело на введённое игроком ЧИСЛО; малый щит без усиления числа
  # не даёт, и наивная реализация его пропустила бы.
  describe "надетое с базой, но без бонуса, отключает бонусы монаха" do
    # Монах 5 с WIS 14: +2 от мудрости и +1 колонки таблицы класса.
    @monk5 [base_abilities: %{@flat | wis: 14}]

    defp monk(gear_fields) do
      geared(List.duplicate(:monk, 5), gear_fields, @monk5)
    end

    defp own(stats), do: for(term <- stats.ac_own_terms_geared, do: {term.id, term.ac})

    test "малый щит: +1 к AC и оба бонуса монаха пропали", %{ruleset: ruleset} do
      stats = Rules.compute(monk(worn: %{shield: :small}), ruleset)

      # 10 базы + 1 базы щита — и ни мудрости, ни колонки.
      assert stats.ac_geared == 11
      assert own(stats) == []
      assert stats.ac_by_type[:shield] == 1
    end

    # ⚠️ Отрицательный контроль: без щита те же бонусы на месте, то есть
    # проверка выше поймала именно щит, а не выключенные бонусы вообще.
    test "без надетого оба бонуса на месте", %{ruleset: ruleset} do
      stats = Rules.compute(monk([]), ruleset)

      assert stats.ac_geared == 13
      assert own(stats) == [monk_ac_bonus: 2, monk: 1]
    end

    # 🔴 И вторая половина условия, измеренная Dan 09.08.2026: ломает не ВИД
    # надетого, а то, ДАЁТ ЛИ оно AC. Строка «нет / одежда» даёт 0 — робу монах
    # носить и должен.
    test "одежда даёт 0 базы и бонусов не ломает", %{ruleset: ruleset} do
      stats = Rules.compute(monk(worn: %{armor: :none}), ruleset)

      assert stats.ac_geared == 13
      assert own(stats) == [monk_ac_bonus: 2, monk: 1]
    end

    # ...а стёганый доспех даёт 1 и ломает — то есть граница проходит по числу,
    # а не по слову «доспех».
    test "стёганый даёт 1 базы и бонусы ломает", %{ruleset: ruleset} do
      stats = Rules.compute(monk(worn: %{armor: :padded}), ruleset)

      assert stats.ac_geared == 11
      assert own(stats) == []
    end

    # 🔴 Ловушка, которую эта задача обязана НЕ сломать: щитовой AC Карлика —
    # расовый бонус Сиалы (задача 3.12), а не надетый щит. Условие смотрит на
    # введённое игроком, а не на итог по типу, иначе гном-монах терял бы бонусы
    # просто за расу.
    #
    # ⚠️ 40-й уровень и меч в руках: ниже 40-го расовый бонус неизвестен, а без
    # оружия его нет вовсе (замер Q1/Q4).
    test "расовый щит Карлика бонусов монаха не ломает, а надетый щит ломает", %{
      ruleset: ruleset
    } do
      # ⚠️ Меч КОРОТКИЙ, а не длинный (задача 3.43): длинный для Карлика
      # двуручен, и малый щит ниже был бы отбит оружием, а не надет — то есть
      # положительный контроль проверял бы не то. Тот же blade, то же число.
      armed = [
        race: :gnome,
        gear: Gear.new(weapon: :shortsword, feats: [:siala_blade_proficiency])
      ]

      racial =
        Rules.compute(
          build(List.duplicate(:monk, 40), armed ++ @monk5),
          ruleset
        )

      # ⚠️ До задачи 3.143 (30.08.2026) тут ещё стоял `{:small_stature, 1}`
      # (расовый размерный модификатор Карлика) между `monk` и `gnome`:
      # applied по обрезанной цитате, теперь not_modelled — своего терма
      # не даёт вовсе, и щитового бонуса это не касалось никогда (разные
      # типы — `size` и `shield`).
      assert own(racial) == [
               {:monk_ac_bonus, 2},
               {:monk, 8},
               {:gnome, 6},
               {:shortsword, 6}
             ]

      # ⚠️ Положительный контроль: тот же Карлик, надевший малый щит, бонусы
      # монаха теряет — и теряет их за ПРЕДМЕТ, числа он не вписывал вовсе.
      with_item =
        Rules.compute(
          build(
            List.duplicate(:monk, 40),
            [
              race: :gnome,
              gear:
                Gear.new(
                  weapon: :shortsword,
                  feats: [:siala_blade_proficiency],
                  worn: %{shield: :small}
                )
            ] ++ @monk5
          ),
          ruleset
        )

      assert own(with_item) == [{:gnome, 6}, {:shortsword, 6}]
    end
  end

  # Стык с задачей 3.39: своё против вписанного — максимум, а база предмета
  # прибавляется к победителю ВСЕГДА. «а вот с АЦ щитовым с вещей это
  # не складывается, только с базой щита» (Dan, 16.08.2026).
  describe "база складывается всегда, поверх победителя" do
    # Карлик 40 чистым воином — сагровик, расовый щитовой +9, плюс +9 за клинок
    # в руках, итого своё щитовое 18.
    #
    # ⚠️ Меч КОРОТКИЙ, а не катана (задача 3.43): катана среднего размера, то
    # есть для малой расы двуручна, и щит рядом с ней в билде не держится —
    # проверялась бы не база щита, а запрет. Группа владения та же (blade), так
    # что своё щитовое остаётся 18.
    defp gnome_sagra(gear_fields) do
      Build.new(
        levels: List.duplicate(:fighter, 40),
        base_abilities: @flat,
        race: :gnome,
        gear: Gear.new([weapon: :shortsword, feats: [:siala_blade_proficiency]] ++ gear_fields)
      )
    end

    # 🔴 Кейс приёмки: своё щитовое 18, вписан бонус щита 4, размер средний →
    # max(18, 4) + 2 = 20.
    test "своё 18 против вписанных 4 плюс база среднего щита = 20", %{ruleset: ruleset} do
      stats = Rules.compute(gnome_sagra(ac: %{shield: 4}, worn: %{shield: :large}), ruleset)

      entry = Enum.find(stats.ac_types_resolved, &(&1.type == :shield))
      assert %{own: 18, typed: 4, base: 2, counted: 20} = entry

      # 10 базы + 20 щитового. ⚠️ Было «+ 1 размер Карлика + 20» до задачи
      # 3.143 (30.08.2026) — Small stature стал not_modelled, своего терма
      # не даёт (и это отдельный тип, `size`, никогда не складывался
      # с щитовым `shield` — число 18 выше не менялось).
      assert stats.ac_geared == 30
      assert stats.ac_by_type[:shield] == 2

      # Вписанное проиграло — и об этом сказано, а не съедено молча.
      assert stats.ac_superseded_types == [:shield]

      # ⚠️ И оговорки про базу больше нет: она посчитана. Печатать «не можем»
      # про посчитанное запрещено так же прямо, как обратное (CLAUDE.md §6).
      refute {:not_modelled, {:ac_gear_base, :shield}} in stats.gaps
    end

    # ⚠️ Отрицательный контроль к «складывается всегда»: победа вписанного базу
    # не отменяет. Вписано 20 — оно больше своих 18, и база всё равно сверху.
    test "база прибавляется и когда выигрывает вписанное", %{ruleset: ruleset} do
      stats = Rules.compute(gnome_sagra(ac: %{shield: 20}, worn: %{shield: :large}), ruleset)

      assert stats.ac_by_type[:shield] == 22
      # ⚠️ Было `10 + 1 + 22` до задачи 3.143 (30.08.2026) — размерный
      # терм Карлика (`size`) стал not_modelled, отдельно от щитового.
      assert stats.ac_geared == 10 + 22
    end

    # И без вписанного числа вовсе: база одна против своих 18.
    test "щит без усиления даёт ровно свою базу поверх своего бонуса", %{ruleset: ruleset} do
      stats = Rules.compute(gnome_sagra(worn: %{shield: :small}), ruleset)

      assert stats.ac_by_type[:shield] == 1

      # ⚠️ Было `10 + 1 + 18 + 1` до задачи 3.143 (30.08.2026) — тот же размерный
      # терм, тот же уход из applied.
      assert stats.ac_geared == 10 + 18 + 1
      assert stats.ac_superseded_types == []
    end
  end

  # ⚠️ Граница задачи: «AC голым» считается по билду с пустыми вещами, поэтому
  # ни базы, ни предела ловкости там нет по построению. Проверено, а не
  # предположено.
  describe "ac_naked не задет вовсе" do
    test "голое число одинаково при любом надетом", %{ruleset: ruleset} do
      for worn <- [
            %{},
            %{armor: :full_plate},
            %{shield: :tower},
            %{armor: :full_plate, shield: :tower}
          ] do
        stats =
          Rules.compute(
            geared(List.duplicate(:fighter, 10), [worn: worn],
              base_abilities: %{@flat | dex: 30}
            ),
            ruleset
          )

        # 10 базы + 10 ловкости, без единого предмета.
        assert stats.ac_naked == 20, "#{inspect(worn)}: голое число поехало"
      end
    end

    # И то же самое у монаха: голым его бонусы на месте при любом надетом.
    test "бонусы монаха в голом числе не ломаются надетым", %{ruleset: ruleset} do
      for worn <- [%{}, %{shield: :small}, %{armor: :full_plate}] do
        stats =
          Rules.compute(
            geared(List.duplicate(:monk, 5), [worn: worn], base_abilities: %{@flat | wis: 14}),
            ruleset
          )

        assert stats.ac_naked == 13, "#{inspect(worn)}: голое число монаха поехало"
      end
    end
  end

  # Граничные уровни и мультикласс. Утверждение здесь ровно одно, и оно стоит
  # проверки именно потому, что выглядит очевидным: надетое не зависит от
  # уровня и от состава классов ВООБЩЕ. Привязать базу или предел к классу
  # (скажем, «у монаха доспех работает иначе») легко и незаметно — условие
  # монаха, лежащее рядом, устроено ровно так.
  describe "граничные уровни и мультикласс" do
    test "база и предел одинаковы на 1, 20, 21 и 41 уровне", %{ruleset: ruleset} do
      for level <- [1, 20, 21, 41] do
        stats =
          Rules.compute(
            geared(List.duplicate(:fighter, level), [worn: %{armor: :full_plate, shield: :tower}],
              base_abilities: %{@flat | dex: 20}
            ),
            ruleset
          )

        assert stats.ac_dexterity == %{modifier: 5, counted: 1, cap: 1, capped?: true},
               "уровень #{level}: предел ловкости поехал"

        assert stats.ac_by_type[:armor] == 8, "уровень #{level}: база доспеха поехала"
        assert stats.ac_by_type[:shield] == 3, "уровень #{level}: база щита поехала"
      end
    end

    # Билд из четырёх классов — лимит Сиалы, и заодно единственная форма билда,
    # у которой есть собственное правило по составу (штраф к скрытности).
    # Надетое от неё не зависит ничем.
    test "билд из четырёх классов надет так же", %{ruleset: ruleset} do
      levels =
        List.duplicate(:monk, 10) ++
          List.duplicate(:wizard, 5) ++
          List.duplicate(:pale_master, 20) ++ List.duplicate(:red_dragon_disciple, 6)

      stats =
        Rules.compute(
          geared(levels, [worn: %{armor: :chain_shirt}], base_abilities: %{@flat | dex: 22}),
          ruleset
        )

      assert stats.character_level == 41
      assert map_size(stats.class_levels) == 4

      # Кольчужная рубаха на Сиале: база 4, предел +5 — из шести очков ловкости
      # в AC проходят пять.
      assert stats.ac_dexterity == %{modifier: 6, counted: 5, cap: 5, capped?: true}
      assert stats.ac_by_type[:armor] == 4

      # ⚠️ И монашеские бонусы в этом билде сломаны надетым, а не уровнем: без
      # доспеха они на месте.
      bare = Rules.compute(geared(levels, [], base_abilities: %{@flat | dex: 22}), ruleset)

      assert Enum.any?(bare.ac_own_terms_geared, &(&1.id == :monk))
      refute Enum.any?(stats.ac_own_terms_geared, &(&1.id == :monk))
    end
  end

  describe "id, которого справочник не знает" do
    # Ядро на нём не падает и ничего не выдумывает: ни базы, ни предела. Назвать
    # его — дело декодера (`{:unknown_worn, …}`), а не расчёта.
    test "неизвестный предмет не даёт ни базы, ни предела", %{ruleset: ruleset} do
      stats =
        Rules.compute(
          geared(List.duplicate(:fighter, 10), [worn: %{armor: :mithral_shirt}],
            base_abilities: %{@flat | dex: 30}
          ),
          ruleset
        )

      assert stats.ac_geared == 20
      assert stats.ac_dexterity.cap == nil
    end

    # И неизвестная КАТЕГОРИЯ тоже: чужой ключ не может незаметно стать типом AC.
    test "неизвестная категория не даёт ничего", %{ruleset: ruleset} do
      unknown = build([:fighter], gear: Gear.new(worn: %{helmet: :full_plate}))

      assert Worn.base_ac(unknown, ruleset) == %{}
      assert Worn.dexterity_cap(unknown, ruleset) == nil
    end
  end

  describe "«надето» — это состояние блока «Вещи»" do
    # Одежда даёт 0 AC и всё-таки является ответом: она — то, чем игрок говорит
    # «я без доспеха», и на этом висят бонусы монаха. Значит блок не должен
    # считать себя пустым.
    test "выбранный предмет считается заполненным блоком даже с нулевой базой" do
      refute Gear.any?(Gear.new())
      assert Gear.any?(Gear.new(worn: %{armor: :none}))
    end

    # «Снял» и «не выбирал» — одно состояние: иначе у одного билда было бы два
    # разных кода ссылки.
    test "снятое не оставляет за собой ключа" do
      gear = Gear.new() |> Gear.put_worn(:shield, :tower) |> Gear.put_worn(:shield, nil)

      assert gear.worn == %{}
      assert gear == Gear.new()
    end
  end
end
