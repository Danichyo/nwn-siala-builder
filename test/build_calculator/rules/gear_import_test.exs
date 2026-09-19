defmodule BuildCalculator.Rules.GearImportTest do
  @moduledoc """
  Свод надетого в блок «Вещи» — задачи 3.187, 3.199, 3.204, 3.206, 3.213.

  Вход — то, что `BuildCalculator.GameLog.parse/2` читает из четырёх логов
  `.билд+` (`test/fixtures/game_logs_plus/`, там же опись и слово Dan
  дословно), плюс синтетика там, где четыре лога нужной формы не дают.

  🔴 **Разбор текста здесь не проверяется** — он под своим тестом
  (`game_log_equipment_test.exs`, оракул — независимое зеркало файла). Этот
  файл проверяет СВОД: какие числа сложились, какие спорили и проиграли, какие
  не сложились и почему. Набранных руками наборов предметов больше нет: они
  жили ровно пока рядом существовало два поколения печати, и ушли вместе
  с первым (18.09.2026, слово Dan: «старые версии можно не хранить»).

  🔴 **Инвариант, который держит всё остальное честным:** сумма длин трёх
  вёдер равна числу строк свойств на входе — на всех четырёх логах и на каждой
  синтетике. Нераспознанное обязано быть НАЗВАНО, а не пропущено.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, GameLog}
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, GearFeats, GearImport}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp log(name, ruleset) do
    [File.cwd!(), "test/fixtures/game_logs_plus", name <> ".log"]
    |> Path.join()
    |> File.read!()
    |> GameLog.parse(ruleset)
  end

  defp sum(name, ruleset) do
    parsed = log(name, ruleset)
    GearImport.sum(parsed.equipment, ruleset, parsed.equipment_counts)
  end

  defp bucket_total(report),
    do: length(report.applied) + length(report.not_ours) + length(report.unresolved)

  defp item(slot, name, properties, extras \\ %{}),
    do: Map.merge(%{slot: slot, name: name, properties: properties}, extras)

  defp ac(value, raw), do: %{kind: :ac_bonus, value: value, raw: raw}
  defp attack(value, raw), do: %{kind: :attack_bonus, value: value, raw: raw}
  defp enhancement(value, raw), do: %{kind: :enhancement_bonus, value: value, raw: raw}
  defp feat(param, raw), do: %{kind: :bonus_feat, param: param, raw: raw}
  defp piece(set_id, raw), do: %{kind: :mini_set, param: set_id, raw: raw}

  # ---------------------------------------------------------- инвариант --

  describe "инвариант: ни одна строка не теряется молча" do
    for {name, lines} <- [{"hnyupius", 92}, {"brunna", 40}, {"moxie", 88}, {"bor", 58}] do
      test "#{name}: сумма по трём вёдрам равна #{lines}", %{ruleset: ruleset} do
        parsed = log(unquote(name), ruleset)
        {_gear, report} = GearImport.sum(parsed.equipment, ruleset, parsed.equipment_counts)

        assert GearImport.property_count(parsed.equipment) == unquote(lines)
        assert bucket_total(report) == unquote(lines)
      end
    end

    test "каждая строка лога встречается в отчёте ровно один раз", %{ruleset: ruleset} do
      parsed = log("hnyupius", ruleset)
      {_gear, report} = GearImport.sum(parsed.equipment, ruleset, parsed.equipment_counts)

      seen =
        for bucket <- [:applied, :not_ours, :unresolved],
            entry <- Map.fetch!(report, bucket),
            do: {entry.slot, entry.raw}

      assert Enum.sort(seen) == Enum.sort(Enum.uniq(seen))

      expected =
        for item <- parsed.equipment, property <- item.properties, do: {item.slot, property.raw}

      assert Enum.sort(seen) == Enum.sort(expected)
    end
  end

  # ------------------------------------------- имя свойства (задача 3.221) --

  # 🔴 СТОРОЖ НА ПРАВКУ ЧУЖОЙ ПЕЧАТИ. Урок 3.213: сервер снял параметр у `AC
  # Bonus`, строка перестала совпадать с именем таблицы и уехала в `not_ours`
  # — «не наша механика», ни одной оговорки, AC на проде 38 вместо 58, и так
  # до починки. Инвариант выше этого не ловит по построению: строка лежала
  # в ведре, просто не в том.
  #
  # Сторож ставится на НОЛЬ, и это сильнее списка «эти имена обязаны быть
  # нашими»: неузнанных имён на четырёх логах нет ни одного, значит любое
  # новое поколение печати, разошедшееся с нашей таблицей, поднимет счёт
  # с нуля — и напечатает сами строки.
  describe "имя свойства, которого мы не прочитали (задача 3.221)" do
    for name <- ~w(hnyupius brunna moxie bor) do
      test "#{name}: неузнанных имён свойств нет ни одного", %{ruleset: ruleset} do
        {_gear, report} = sum(unquote(name), ruleset)

        unknown =
          for entry <- report.unresolved,
              match?({:property_name_unknown, _raw}, entry.reason),
              do: "#{entry.slot} #{entry.item}: #{entry.raw}"

        assert unknown == [],
               """
               Лог #{unquote(name)}.log несёт строки, имя свойства которых не читает
               ни одна ветка `GameLog.classify_named_property/4` и ни одна запись
               `@equip_other_names`. Это ровно форма поломки 3.213 — правка печати
               на сервере. Строки:

               #{Enum.join(unknown, "\n")}
               """
      end
    end

    # Положительный контроль: выдуманное имя ДОЛЖНО производить эту причину —
    # иначе сторож выше зеленел бы и на сломанном коде.
    test "выдуманное имя ложится в unresolved, а не в «не наше»", %{ruleset: ruleset} do
      raw = "[3] Fancy New Property (65535) 4"
      items = [item(:chest, "нагрудник", [%{kind: :other, raw: raw}])]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert report.not_ours == []
      assert [%{reason: {:property_name_unknown, ^raw}}] = report.unresolved
    end

    # ...а узнанное имя остаётся утверждением «не наша механика» и ведром
    # `not_ours`: это и есть то, что правка НЕ должна была сдвинуть.
    test "узнанное имя остаётся в not_ours", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{kind: :other, param: :cast_spell, raw: "[1] Cast Spell (Unique Power) 13"}
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert report.unresolved == []
      assert [%{reason: {:property_not_modelled, :cast_spell}}] = report.not_ours
    end

    # 🔴 Живая форма прошлого поколения — ровно та строка, на которой сгорела
    # 3.213. Сегодня её читает регулярка `@equip_ac_bonus` (обе формы), то есть
    # в этот список она не попадает вовсе; тест держит ЭТО, чтобы починка 3.213
    # не отвалилась молча вместе со старыми сохранёнными логами игроков.
    test "«AC Bonus (0) 5» прежнего поколения по-прежнему читается как AC", %{ruleset: ruleset} do
      parsed =
        GameLog.parse(
          """
          === Equipped: Тест ===
          [HEAD] Шлем
            [1] AC Bonus (0) 5
          """,
          ruleset
        )

      {gear, report} = GearImport.sum(parsed.equipment, ruleset, parsed.equipment_counts)

      assert gear.ac == %{deflection: 5}
      assert report.unresolved == []
      assert report.not_ours == []
    end
  end

  # ------------------------------------------------------------ Хнюпиус --

  describe "Хнюпиус: суммы до потолков" do
    # Телосложение: 2 (нагрудник) + 3 (сапоги) + 4 (накидка) + 2 (кольцо) +
    # 1 (амулет) + 3 (пояс) = 15, то есть на ТРИ больше потолка +12. Клипает
    # ядро ниже по конвейеру (`Rules.Gear.ability_bonuses/2`), а свод отдаёт
    # сумму как есть — ровно ради «видеть, чего набрано сверх капов» (Dan).
    test "характеристики складываются, потолок здесь не применяется", %{ruleset: ruleset} do
      {gear, _report} = sum("hnyupius", ruleset)

      assert gear.abilities == %{con: 15, str: 13, dex: 6, wis: 10}

      {capped, capped?} = Rules.Gear.ability_bonuses(gear, ruleset)
      assert capped.con == 12
      assert capped?
    end

    test "навыки складываются по предметам", %{ruleset: ruleset} do
      {gear, _report} = sum("hnyupius", ruleset)

      assert gear.skills == %{
               discipline: 19,
               listen: 23,
               spot: 22,
               concentration: 10,
               heal_skill: 16
             }
    end

    # Universal 5 + 3 + 2 + 3 + 3 = 16; Стойкость 3 + 4 + 5 = 12; Воля 3.
    test "спасы: universal отдельно, раздельные отдельно", %{ruleset: ruleset} do
      {gear, _report} = sum("hnyupius", ruleset)

      assert gear.saves == 16
      assert gear.saves_specific == %{fort: 12, will: 3}
    end

    # 🔴 Ради чего вся правка модели: Стойкость этого персонажа получает
    # с вещей 28, а потолок +20 — один на сейв и на всё вещевое вместе.
    test "28 до потолка, 20 после — и это ОДИН клип", %{ruleset: ruleset} do
      {gear, _report} = sum("hnyupius", ruleset)

      assert Rules.Gear.save_bonus(gear, :fort) == 28
      assert Rules.Gear.save_bonus(gear, :ref) == 16
      assert Rules.Gear.save_bonus(gear, :will) == 19

      stats = Rules.compute(Build.new(levels: List.duplicate(:fighter, 20), gear: gear), ruleset)

      assert stats.save_bonus.fort == 20
      assert stats.save_bonus.ref == 16
      assert stats.save_bonus.will == 19
      assert :fort_save in stats.capped
      refute :ref_save in stats.capped
    end
  end

  describe "Хнюпиус: AC по слотам" do
    # Тип берётся от слота (`fandom:Armor class`, revid 71718): шлем →
    # отклонение, нагрудник → броня, сапоги → уклонение, амулет → природный,
    # башенный щит второй руки → щитовой (по базовому типу, задача 3.206).
    test "пять типов названы, ни одного неизвестного", %{ruleset: ruleset} do
      {gear, report} = sum("hnyupius", ruleset)

      assert gear.ac == %{deflection: 5, armor: 6, dodge: 4, natural: 5, shield: 5}
      refute Enum.any?(report.unresolved, &match?({:ac_type_unknown, _, _}, &1.reason))
    end
  end

  describe "Хнюпиус: фиты с вещей" do
    # 🔴 Задача 3.204. Ступень (`rank`) и есть номер взятия: `II` и `III`
    # с сапог — два взятия, `II` с пояса — тот же фит, а не третье. Цену назвала
    # сама игра: она печатает 1503 HP, модель печатала 1437.
    test "две ступени — два взятия, одинаковая ступень со второго предмета — нет",
         %{ruleset: ruleset} do
      {gear, report} = sum("hnyupius", ruleset)

      assert gear.feats == [:blind_fight, :cleave, :epic_toughness, :epic_toughness]

      # Ни одной строки в «не сложить»: выражать стало чем.
      assert for(
               entry <- report.unresolved,
               match?({:feat_repeat_not_expressible, _}, entry.reason),
               do: entry.raw
             ) == []

      # Повтор ТОЙ ЖЕ ступени прочитан и назван: «легла, но не прибавила» —
      # то же ведро и та же пометка, что у неповторяемого фита с двух предметов.
      assert for(
               entry <- report.applied,
               entry.kind == :bonus_feat,
               do: {entry.raw, entry.counted?, entry.note}
             ) == [
               {"[3] Bonus Feat (Epic Toughness II)", true, nil},
               {"[4] Bonus Feat (Epic Toughness III)", true, nil},
               {"[2] Bonus Feat (Cleave)", true, nil},
               {"[5] Bonus Feat (Blind-Fight)", true, nil},
               {"[2] Bonus Feat (Epic Toughness II)", false, :already_declared}
             ]
    end

    # 🔴 **ПОЛОВИНА ЗАДАЧИ 3.29 ЗАКРЫТА 18.09.2026 (задача 3.210), и этот кейс
    # проверял ОБРАТНОЕ.** Стояло «повторяемый фит С ВЫБОРОМ: второе взятие
    # по-прежнему не выразить», с доводом «повторяется ПАРА, а какую копию
    # одалживает предмет, лог не говорит». Довод снялся словом Dan («подтверждаю
    # твое предложение» — считать `Epic energy resistance` как `Epic toughness`
    # в 3.204: римская ступень и есть номер взятия): у этого фита источник
    # РАЗРЕШАЕТ повторить то же значение (`repeatable.distinct?: false`), так что
    # разные ступени с двух предметов — два взятия пары, ровно как у
    # `Epic toughness` ниже.
    #
    # ⚠️ Правило — В ДАННЫХ (`overrides.json` → `gear.feats.takes.applies_to`),
    # и накрывает оно ровно этот фит: у остальных четырнадцати фитов с доменом
    # `distinct?: true`, то есть повтор пары запрещён источником, и для них
    # утверждение прежнего кейса остаётся верным (см. следующий кейс).
    test "повторяемый фит С ВЫБОРОМ и разрешённым повтором значения: ступени — взятия",
         %{ruleset: ruleset} do
      items = [
        item(:neck, "Амулет", [
          %{
            kind: :bonus_feat,
            param: {:epic_energy_resistance, :fire},
            rank: "i",
            raw: "[1] Bonus Feat (Epic Energy Resistance (Fire) I)"
          }
        ]),
        item(:belt, "Пояс", [
          %{
            kind: :bonus_feat,
            param: {:epic_energy_resistance, :fire},
            rank: "ii",
            raw: "[1] Bonus Feat (Epic Energy Resistance (Fire) II)"
          }
        ])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      # ДВЕ записи одной пары — два взятия, и каждая строка «легла»
      assert gear.feats == [
               {:epic_energy_resistance, :fire},
               {:epic_energy_resistance, :fire}
             ]

      assert report.unresolved == []
      assert length(report.applied) == 2
      assert Enum.all?(report.applied, & &1.counted?)

      # и это ровно два взятия ПАРЫ, а не два взятия имени
      assert GearFeats.takes(gear, ruleset, :epic_energy_resistance, :fire) == 2
      assert GearFeats.takes(gear, ruleset, :epic_energy_resistance, :cold) == 0
    end

    # 🔴 Отрицательный контроль к кейсу выше, и он главный: та же форма записи
    # у фита, которому источник повтор значения ЗАПРЕЩАЕТ (`distinct?: true`),
    # по-прежнему невыразима. Иначе «расширили ровно на один фит» держалось бы
    # на слове, а не на данных.
    test "повторяемый фит с ЗАПРЕЩЁННЫМ повтором значения: второе взятие не выразить",
         %{ruleset: ruleset} do
      props =
        for rank <- ~w(i ii) do
          %{
            kind: :bonus_feat,
            param: {:skill_focus, :discipline},
            rank: rank,
            raw: "[1] Bonus Feat (Skill Focus (Discipline) #{String.upcase(rank)})"
          }
        end

      {gear, report} = GearImport.sum([item(:neck, "Амулет", props)], ruleset)

      assert gear.feats == [{:skill_focus, :discipline}]

      assert [%{reason: {:feat_repeat_not_expressible, :skill_focus}}] = report.unresolved
    end

    # Положительный контроль к строке про пояс: ТРИ разные ступени — три
    # взятия. Без него «одинаковая ступень не считается» зеленело бы и на
    # модели, которая считает одно взятие всегда.
    test "три разные ступени — три взятия", %{ruleset: ruleset} do
      props =
        for rank <- ~w(i ii iii) do
          %{
            kind: :bonus_feat,
            param: :epic_toughness,
            rank: rank,
            raw: "[1] Bonus Feat (Epic Toughness #{String.upcase(rank)})"
          }
        end

      {gear, report} =
        GearImport.sum([item(:boots, "Сапоги", props)], ruleset)

      assert gear.feats == List.duplicate(:epic_toughness, 3)
      assert report.unresolved == []
      assert Enum.all?(report.applied, & &1.counted?)
    end

    # ⚠️ И вторая половина того же: повторяемый фит БЕЗ ступени, объявленный
    # дважды. Различить «та же копия» и «другая» нечем — игра свои копии
    # нумерует, — поэтому строка уходит туда же, а не считается вторым взятием
    # молча.
    test "повторяемый фит без ступени: два одинаковых объявления не складываются",
         %{ruleset: ruleset} do
      items =
        for n <- 1..2,
            do:
              item(:belt, "Пояс #{n}", [
                feat(:epic_toughness, "[#{n}] Bonus Feat (Epic Toughness)")
              ])

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.feats == [:epic_toughness]
      assert [%{reason: {:feat_repeat_not_expressible, :epic_toughness}}] = report.unresolved
    end

    test "имя, которого словарь не узнал, названо, а не потеряно", %{ruleset: ruleset} do
      {_gear, report} = sum("hnyupius", ruleset)

      assert [%{raw: "[5] Bonus Feat (Sneak Attack (+4d6))", reason: reason}] =
               for(
                 entry <- report.unresolved,
                 match?({:feat_unknown, _}, entry.reason),
                 do: entry
               )

      assert reason == {:feat_unknown, {:unresolved, "Sneak Attack (+4d6)"}}
    end
  end

  describe "Хнюпиус: три из четырёх просьб к серверу закрыты" do
    test "полуторный меч в руке с усилением 6, башенный щит надет", %{ruleset: ruleset} do
      {gear, report} = sum("hnyupius", ruleset)

      assert gear.weapon == :bastard_sword
      assert gear.weapon_attack == 6
      assert gear.off_hand_weapon == nil
      assert gear.worn == %{armor: :full_plate, shield: :tower}

      assert report.weapons.main.wields == {:weapon, :bastard_sword}
      assert report.weapons.main.base_type == "Bastard Sword"
      assert report.weapons.off.wields == {:worn, :shield, :tower}

      # Строка усиления ЛЕГЛА — она в «применено», а не в «не сложить».
      assert [%{landed: {:weapon_attack, :main, 6}, counted?: true}] =
               for(entry <- report.applied, entry.kind == :enhancement_bonus, do: entry)
    end

    test "семь кусков → три набора [3, 2, 2], шапка сошлась", %{ruleset: ruleset} do
      {gear, report} = sum("hnyupius", ruleset)

      assert gear.mini_sets == [3, 2, 2]
      assert report.counts.groups == [3, 2, 2]
      assert report.counts.mini_set_pieces == 7
      assert report.counts.notes == []

      pieces = for entry <- report.applied, entry.kind == :mini_set, do: entry
      assert length(pieces) == 7
      assert Enum.all?(pieces, & &1.counted?)

      assert Enum.map(pieces, & &1.landed) ==
               Enum.map([22, 73, 73, 22, 73, 59, 59], &{:mini_set, &1})
    end

    # `CRAFT ITEMS: 7` при семи кусках и нуле пометок — это `Ctotal`, а не
    # «семь крафтовых»: иначе `Ctotal` 14 и обрыв, а игра печатает 1503.
    test "CRAFT ITEMS 7 − MINI SET PIECES 7 = 0 крафтовых", %{ruleset: ruleset} do
      {gear, report} = sum("hnyupius", ruleset)

      assert gear.named_items == 0
      assert report.counts.craft_items == 7
      assert report.counts.craft_marked == []
      assert report.counts.named_items == 0
    end

    test "Quality — не наша механика, а не «пометки крафта нет»", %{ruleset: ruleset} do
      {_gear, report} = sum("hnyupius", ruleset)

      assert [
               %{raw: "[4] Quality (65535) 10", reason: {:property_not_modelled, :quality}},
               %{raw: "[7] Quality (65535) 8", reason: {:property_not_modelled, :quality}}
             ] = for(entry <- report.not_ours, entry.kind == :quality, do: entry)

      refute Enum.any?(report.unresolved, &match?({:named_item_flag_missing, _}, &1.reason))
    end

    # Получатель есть, а ввода не будет: решение Dan 18.08.2026 (CLAUDE.md §6),
    # и SR к тому же не складывается, а конкурирует.
    test "сопротивление заклинаниям — решение, а не пробел", %{ruleset: ruleset} do
      {_gear, report} = sum("hnyupius", ruleset)

      assert [%{raw: "[13] Spell Resistance (0) 15"}] =
               for(
                 entry <- report.not_ours,
                 entry.reason == {:decided_not_modelled, :spell_resistance},
                 do: entry
               )
    end

    # Единственное, что осталось «не сложить», — фит, чей аргумент число урона.
    test "в unresolved — одна строка, и она про Sneak Attack", %{ruleset: ruleset} do
      {_gear, report} = sum("hnyupius", ruleset)

      assert [%{reason: {:feat_unknown, {:unresolved, "Sneak Attack (+4d6)"}}}] =
               report.unresolved
    end
  end

  # ------------------------------------------------ база доспеха (3.213) --

  describe "база доспеха из [BaseAC:n]" do
    # 🔴 Число, а не имя: «Нагрудник Призрака» с базой 8 — это ЛАТЫ, а не
    # `chainmail` («Chainmail, Breastplate», база 5), и подстановка по переводу
    # имени отняла бы три очка AC. Строка ищется по `base_ac` категории `armor`.
    for {name, base, id} <- [
          {"hnyupius", 8, :full_plate},
          {"bor", 7, :half_plate},
          {"brunna", 0, :none},
          {"moxie", 0, :none}
        ] do
      test "#{name}: база #{base} → #{id}", %{ruleset: ruleset} do
        {gear, report} = sum(unquote(name), ruleset)

        assert gear.worn[:armor] == unquote(id)

        assert report.worn.chest.base_ac == unquote(base)
        assert report.worn.chest.wears == {:worn, :armor, unquote(id)}
        assert report.worn.chest.reason == nil
      end
    end

    # ⚠️ Ноль — законная база («роба, одежда»), и она ДОЛЖНА лечь: AC-бонусы
    # монаха гасит надетый предмет с НЕНУЛЕВОЙ базой (слово Dan 19.08.2026),
    # и роба Мокси — живой контроль того, что нулевая их не гасит.
    test "роба с базой 0 не добавляет ни очка к AC", %{ruleset: ruleset} do
      {gear, _report} = sum("moxie", ruleset)

      assert gear.worn == %{armor: :none}
      assert Rules.Worn.base_ac(Build.new(levels: [:monk], gear: gear), ruleset) == %{armor: 0}
    end

    # ⚠️ «Доспех надет, базы не знаем» и «доспеха нет» — РАЗНЫЕ ответы, и до
    # третьего поколения печати они выглядели одинаково. Форма прежних логов.
    test "предмет без [BaseAC] — доспех не надет, и об этом сказано", %{ruleset: ruleset} do
      items = [item(:chest, "Нагрудник Призрака", [ac(6, "[6] AC Bonus 6")])]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.worn == %{}
      assert gear.ac == %{armor: 6}

      assert report.worn.chest == %{
               slot: :chest,
               name: "Нагрудник Призрака",
               base_ac: nil,
               wears: nil,
               reason: {:armor_base_not_printed, :chest}
             }

      # ⚠️ И строк в вёдра это не добавило: база печатается у ИМЕНИ предмета,
      # а не отдельной строкой свойства.
      assert bucket_total(report) == GearImport.property_count(items)
    end

    test "база, которой нет ни у одной записи справочника, названа", %{ruleset: ruleset} do
      items = [item(:chest, "Нечто", [], %{base_ac: 99})]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.worn == %{}
      assert report.worn.chest.reason == {:armor_base_unresolved, 99}
    end

    # Пустой слот — это ОТВЕТ, а не отсутствие ответа (тот же приём, что
    # у ключей рук в `report.weapons`).
    test "доспеха нет вовсе — ключ есть, значение nil", %{ruleset: ruleset} do
      {_gear, report} = GearImport.sum([], ruleset)

      assert report.worn == %{chest: nil}
    end

    # ⚠️ Снапшот, который не говорит, какую категорию называет `[BaseAC:n]`:
    # число прочитано и обязано быть названо, а не выброшено. Синтетика держит
    # форму живой — на поставляемых данных правило есть у обоих ruleset'ов.
    test "правила в снапшоте нет — число названо, а не выброшено", %{ruleset: ruleset} do
      ruleset =
        update_in(ruleset.gear.item_slot_ac_types, fn rows ->
          for row <- rows, do: %{row | worn_category_by_base_ac: nil}
        end)

      items = [item(:chest, "Нагрудник Призрака", [], %{base_ac: 8})]
      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.worn == %{}

      assert report.worn == %{
               chest: %{
                 slot: :chest,
                 name: "Нагрудник Призрака",
                 base_ac: 8,
                 wears: nil,
                 reason: {:armor_base_rule_missing, :chest}
               }
             }
    end

    # Щит приходит из ВТОРОЙ РУКИ по базовому типу, доспех — из числа своего
    # слота: две категории из двух разных мест лога, и они не спорят.
    test "доспех и щит ложатся вместе", %{ruleset: ruleset} do
      {gear, _report} = sum("bor", ruleset)

      assert gear.worn == %{armor: :half_plate, shield: :tower}
    end
  end

  # ------------------------------------------------- тип AC в ARMS (3.213) --

  describe "тип AC в ARMS — по напечатанному базовому типу" do
    # 🔴 Ни у одной вещи в `ARMS` на четырёх логах 18.09.2026 НЕТ строки
    # `AC Bonus` — правило проверяется только синтетикой, живого носителя у него
    # пока нет. Базовые типы при этом настоящие: `(Bracer) [BaseItem:78]`
    # у Хнюпиуса и Бора, `(Gauntlet) [BaseItem:36]` у Брунны и Мокси.
    test "живого носителя правила в четырёх логах нет — это не пропуск, а факт",
         %{ruleset: ruleset} do
      for name <- ~w(hnyupius brunna moxie bor) do
        arms = Enum.find(log(name, ruleset).equipment, &(&1.slot == :arms))

        assert arms.base_type in ["Bracer", "Gauntlet"], name
        refute Enum.any?(arms.properties, &(&1.kind == :ac_bonus)), name
      end
    end

    for {type, ac_type} <- [{"Bracer", :armor}, {"Gauntlet", :deflection}] do
      test "#{type} → #{ac_type}", %{ruleset: ruleset} do
        items = [item(:arms, "Нечто", [ac(3, "[1] AC Bonus 3")], %{base_type: unquote(type)})]

        {gear, report} = GearImport.sum(items, ruleset)

        assert gear.ac == %{unquote(ac_type) => 3}
        assert report.unresolved == []
      end
    end

    # Регистр и пробелы печати не решают, узнали мы тип или нет — тот же
    # порог, что у имени оружия.
    test "имя типа сверяется без учёта регистра", %{ruleset: ruleset} do
      items = [item(:arms, "Нечто", [ac(3, "[1] AC Bonus 3")], %{base_type: "  bracer "})]
      {gear, _report} = GearImport.sum(items, ruleset)

      assert gear.ac == %{armor: 3}
    end

    # 🔴 Базовый тип, которого в записях нет, ответа НЕ ДАЁТ: догадка тут
    # означала бы выдуманный тип AC, а альтернативы печатаются игроку.
    test "неизвестный базовый тип — unresolved с альтернативами, а не догадка",
         %{ruleset: ruleset} do
      items = [item(:arms, "Нечто", [ac(3, "[1] AC Bonus 3")], %{base_type: "Vambrace"})]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.ac == %{}
      assert [%{reason: {:ac_type_unknown, :arms, [:armor, :deflection]}}] = report.unresolved
    end

    # Форма прежних поколений: базового типа у `ARMS` лог не печатал вовсе.
    test "тип не напечатан — тот же отказ, что и раньше", %{ruleset: ruleset} do
      items = [item(:arms, "Наручи", [ac(3, "[1] AC Bonus (0) 3")])]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.ac == %{}
      assert [%{reason: {:ac_type_unknown, :arms, [:armor, :deflection]}}] = report.unresolved
    end

    # ⚠️ Две записи слота отвечают на РАЗНЫЕ вопросы и не мешают друг другу:
    # у `arms` заполнена только «по напечатанному типу», у `left_hand` — только
    # «по категории надетого». Порядок веток `ac_type/2` сегодня ничего
    # не решает, и это проверено, а не обещано.
    test "у left_hand тип по-прежнему решает категория надетого", %{ruleset: ruleset} do
      items = [
        item(:left_hand, "Щит", [ac(5, "[1] AC Bonus 5")], %{base_type: "Tower Shield"}),
        item(:right_hand, "Меч", [], %{base_type: "Longsword"})
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.ac == %{shield: 5}
      assert report.unresolved == []
    end
  end

  # ---------------------------------------------------------------- Бор --

  describe "Бор: шапка без строк кусков" do
    test "боевой молот +5, башенный щит с бонусом 6, латы в половину", %{ruleset: ruleset} do
      {gear, report} = sum("bor", ruleset)

      assert gear.weapon == :warhammer
      assert gear.weapon_attack == 5
      assert gear.worn == %{armor: :half_plate, shield: :tower}
      assert gear.ac.shield == 6
      assert report.unresolved == []
    end

    # Четыре куска по шапке и НИ ОДНОЙ строки `Use Item (Mini Set)` в предметах
    # (свойство печатается не на каждом экземпляре): групп не восстановить,
    # ложится одна группа размером в шапку — для `Nmini` это то же число, — и об
    # этом сказано вслух, а не молча.
    test "MINI SET PIECES 4 без [SetID] — одна группа [4] и оговорка", %{ruleset: ruleset} do
      {gear, report} = sum("bor", ruleset)

      assert gear.mini_sets == [4]
      assert report.counts.groups == []
      assert report.counts.notes == [{:mini_set_groups_unverified, 4, []}]
      assert gear.named_items == 0
    end
  end

  # ------------------------------------------------------- Брунна и Мокси --

  describe "Брунна и Мокси: крафт по шапке и по пометкам сходится" do
    test "Брунна: шесть крафтовых, посох в руке без числа", %{ruleset: ruleset} do
      {gear, report} = sum("brunna", ruleset)

      assert gear.named_items == 6
      assert length(report.counts.craft_marked) == 6
      assert report.counts.notes == []
      assert gear.mini_sets == []
      assert gear.weapon == :magic_staff
      assert gear.weapon_attack == 0
      assert report.weapons.main.attack == nil
      assert report.unresolved == []

      assert gear.abilities == %{con: 8, int: 13, str: 12}
      assert gear.saves == 4
      assert gear.saves_specific == %{fort: 15}
      assert gear.ac == %{deflection: 5}
      assert gear.feats == []
    end

    test "Брунна: шесть слотов заклинаний — не наш получатель", %{ruleset: ruleset} do
      {_gear, report} = sum("brunna", ruleset)

      slots =
        for entry <- report.not_ours,
            entry.reason == {:property_not_modelled, :bonus_spell_slot_of_level},
            do: entry.raw

      assert length(slots) == 6
    end

    test "Мокси: три крафтовые, двуручный меч в руке, роба без базы", %{ruleset: ruleset} do
      {gear, report} = sum("moxie", ruleset)

      assert gear.named_items == 3
      assert report.counts.craft_marked == ["Перчатки Мокси", "Кольцо Мокси", "Пояс Мокси"]
      assert gear.weapon == :greatsword
      assert gear.worn == %{armor: :none}

      # `Quality` на трёх её крафтовых — не наше; крафт посчитан шапкой.
      assert Enum.count(report.not_ours, &(&1.kind == :quality)) == 3
    end
  end

  # ---------------------------------------------------------- правила свода --

  describe "AC одного типа" do
    # 🔴 Слово Dan 11.09.2026: «AC берется максимальное за исключением dodge,
    # там сумма до капа +20». Оба конца правила читаются из данных
    # (`gear.ac_types.same_type.gear_vs_gear` и `cumulative_types`).
    test "одного типа берётся большее, уклонение складывается", %{ruleset: ruleset} do
      items = [
        item(:head, "шлем", [ac(5, "[1] AC Bonus 5")]),
        item(:cloak, "плащ", [ac(7, "[1] AC Bonus 7")]),
        item(:boots, "сапоги", [ac(4, "[1] AC Bonus 4")]),
        item(:belt, "пояс", [ac(2, "[1] AC Bonus 2")])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.ac == %{deflection: 7, dodge: 4}

      counted = for entry <- report.applied, entry.counted?, do: {entry.item, entry.landed}
      assert counted == [{"плащ", {:ac, :deflection, 7}}, {"сапоги", {:ac, :dodge, 4}}]

      # ⚠️ Проигравшие остаются в `applied` — они прочитаны и поняты, просто
      # их число в итог не вошло, и причина названа.
      lost = for entry <- report.applied, not entry.counted?, do: {entry.item, entry.note}

      assert lost == [
               {"шлем", :superseded_by_larger_same_type},
               {"пояс", :superseded_by_larger_same_type}
             ]
    end

    test "два уклонения складываются, а не спорят", %{ruleset: ruleset} do
      items = [
        item(:boots, "сапоги", [ac(4, "[1] AC Bonus 4"), ac(3, "[2] AC Bonus 3")])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.ac == %{dodge: 7}
      assert Enum.all?(report.applied, & &1.counted?)
    end
  end

  describe "фиты и мелочи" do
    # Два предмета, одолживших ОДИН неповторяемый фит (у Мокси это `Extend
    # spell` с плаща и с кольца), — в игре это один фит, и модель права.
    # Поэтому строка «легла», но ничего не прибавила, и об этом сказано.
    test "неповторяемый фит со второго предмета ничего не прибавляет", %{ruleset: ruleset} do
      items = [
        item(:cloak, "плащ", [feat(:extend_spell, "[2] Bonus Feat (Extend Spell)")]),
        item(:right_ring, "кольцо", [feat(:extend_spell, "[3] Bonus Feat (Extend Spell)")])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.feats == [:extend_spell]
      assert [%{counted?: true}, %{counted?: false, note: :already_declared}] = report.applied
      assert report.unresolved == []
    end

    test "фит с выбором доезжает парой", %{ruleset: ruleset} do
      items = [
        item(:right_hand, "меч", [
          feat({:epic_spell_focus, :evocation}, "[2] Bonus Feat (Epic Spell Focus (Evocation))")
        ])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.feats == [{:epic_spell_focus, :evocation}]
      assert [%{landed: {:feat, :epic_spell_focus, :evocation}}] = report.applied
    end

    # Проверка против ruleset'а, а не против «вызывающий же разобрал»: билд
    # открывается тем ruleset'ом, в котором собран.
    test "фита нет в ruleset'е — строка названа, а не объявлена надетой", %{ruleset: ruleset} do
      items = [item(:belt, "пояс", [feat(:no_such_feat, "[1] Bonus Feat (No Such Feat)")])]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.feats == []
      assert [%{reason: {:feat_unknown, :no_such_feat}}] = report.unresolved
    end

    test "строка без числа не становится нулём молча", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{kind: :ability_bonus, param: :con, raw: "[1] Ability Bonus (Constitution)"}
        ])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.abilities == %{}
      assert [%{reason: {:value_missing, :ability_bonus}}] = report.unresolved
    end

    test "слот, которого нет в таблице, назван", %{ruleset: ruleset} do
      items = [item(:tail, "хвост", [ac(3, "[1] AC Bonus 3")])]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.ac == %{}
      assert [%{reason: {:slot_unknown, :tail}}] = report.unresolved
    end

    test "пустой список — пустой блок «Вещи»", %{ruleset: ruleset} do
      {gear, report} = GearImport.sum([], ruleset)

      refute Rules.Gear.any?(gear)

      assert report == %{
               applied: [],
               not_ours: [],
               unresolved: [],
               # Ключ есть у обеих рук всегда: «в этой руке ничего» — ответ,
               # а отсутствие ключа было бы отсутствием ответа (3.199).
               weapons: %{main: nil, off: nil},
               # То же у доспеха (3.213): слот, который лог читает, назван
               # даже когда в нём ничего не надето.
               worn: %{chest: nil},
               # Шапки нет — обе суммы `nil`, а не ноль: «сервер не печатал»
               # и «сервер насчитал ноль» — разные ответы (3.206).
               counts: %{
                 mini_set_pieces: nil,
                 craft_items: nil,
                 groups: [],
                 craft_marked: [],
                 named_items: 0,
                 notes: []
               }
             }
    end
  end

  # ------------------------------------------------- оружие в руках (3.199) --
  #
  # 🔴 Решение Dan 12.09.2026 дословно: «нам просто надо взять максимальное
  # из них, enchantment bonus дает еще урон, а урон мы вообще не учитываем,
  # так что для конструктора данные 2 типа считай равны и надо взять большее».
  # Правило лежит в данных (`gear.weapon.import_rule`), ядро его читает.
  describe "оружие в руках: одно число на руку" do
    test "Бор: бонус атаки 5 — тот же ответ другим свойством", %{ruleset: ruleset} do
      {_gear, report} = sum("bor", ruleset)

      assert report.weapons.main.name == "Ург Шак"
      assert report.weapons.main.attack == 5
      assert report.weapons.main.from == [:attack_bonus]
      assert report.weapons.main.wields == {:weapon, :warhammer}
    end

    # Посох Брунны и Меч Света Сагры у Мокси не несут ни одного числа атаки:
    # `attack: nil`, а не ноль. «Строки нет» и «в строке ноль» — разные
    # утверждения, и тот же порог держит `number/1` у всех прочих свойств.
    test "предмет без чисел: имя названо, числа нет", %{ruleset: ruleset} do
      {_gear, report} = sum("brunna", ruleset)

      assert report.weapons.main.name == "Посох Волшебства"
      assert report.weapons.main.attack == nil
      assert report.weapons.off == nil
    end

    # 🔴 Ради чего задача: у предмета оба числа сразу. Живой такой пары
    # в четырёх логах нет — есть по одному числу у Хнюпиуса и у Бора, — поэтому
    # проверка синтетическая, и это не подгонка: правило обязано существовать
    # ДО того, как такой предмет придёт.
    test "два числа: большее легло, меньшее прочитано и не вошло", %{ruleset: ruleset} do
      items = [
        item(
          :right_hand,
          "Меч",
          [attack(5, "[1] Attack Bonus (0) 5"), enhancement(6, "[2] Enhancement Bonus (0) 6")],
          %{base_type: "Longsword"}
        )
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.weapon_attack == 6
      assert report.weapons.main.from == [:attack_bonus, :enhancement_bonus]

      assert [
               %{
                 raw: "[1] Attack Bonus (0) 5",
                 counted?: false,
                 note: :superseded_by_larger_same_type
               },
               %{raw: "[2] Enhancement Bonus (0) 6", counted?: true}
             ] =
               for(
                 entry <- report.applied,
                 entry.kind in [:attack_bonus, :enhancement_bonus],
                 do: entry
               )

      assert bucket_total(report) == GearImport.property_count(items)
    end

    test "оба числа равны: сумма была бы вдвое больше правды", %{ruleset: ruleset} do
      items = [
        item(
          :right_hand,
          "Меч",
          [attack(5, "[1] Attack Bonus (0) 5"), enhancement(5, "[2] Enhancement Bonus (0) 5")],
          %{base_type: "Longsword"}
        )
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert report.weapons.main.attack == 5
    end

    test "число второй руки ложится во вторую руку", %{ruleset: ruleset} do
      items = [
        item(:right_hand, "меч", [attack(5, "[1] Attack Bonus (0) 5")], %{base_type: "Longsword"}),
        item(:left_hand, "кинжал", [enhancement(3, "[1] Enhancement Bonus (0) 3")], %{
          base_type: "Dagger"
        })
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.weapon_attack == 5
      assert gear.off_hand_weapon == :dagger
      assert gear.off_hand_weapon_attack == 3
      assert report.weapons.off.wields == {:weapon, :dagger}
    end

    test "строка без числа не становится нулём и в сводке", %{ruleset: ruleset} do
      items = [
        item(:right_hand, "меч", [%{kind: :attack_bonus, raw: "[1] Attack Bonus (0)"}], %{
          base_type: "Longsword"
        })
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert report.weapons.main.attack == nil
      assert report.weapons.main.from == []
    end

    # ⚠️ Снапшот без правила: сводить два числа нечем, и модель об этом
    # МОЛЧИТ ЧИСЛОМ — `attack: nil` при непустом `from`. Синтетика держит
    # форму живой: на поставляемых данных правило есть всегда, и без этой
    # проверки ветка «правила нет» перестала бы что-либо проверять.
    test "правила в ruleset'е нет: два числа не сводятся, одно проходит",
         %{ruleset: ruleset} do
      ruleset = put_in(ruleset.gear.weapon_import_rule, nil)

      two = [
        item(
          :right_hand,
          "Меч",
          [attack(5, "[1] Attack Bonus (0) 5"), enhancement(6, "[2] Enhancement Bonus (0) 6")],
          %{base_type: "Longsword"}
        )
      ]

      {gear, report} = GearImport.sum(two, ruleset)

      assert gear.weapon == :longsword
      assert gear.weapon_attack == 0
      assert report.weapons.main.attack == nil
      assert report.weapons.main.from == [:attack_bonus, :enhancement_bonus]

      assert Enum.map(report.unresolved, & &1.reason) == [
               {:weapon_numbers_not_reconciled, [:attack_bonus, :enhancement_bonus]},
               {:weapon_numbers_not_reconciled, [:attack_bonus, :enhancement_bonus]}
             ]

      # Одно число сводить не надо вовсе — правило там не спрашивается.
      one = [
        item(:right_hand, "меч", [attack(5, "[1] Attack Bonus (0) 5")], %{
          base_type: "Longsword"
        })
      ]

      {_gear, report} = GearImport.sum(one, ruleset)
      assert report.weapons.main.attack == 5
    end
  end

  describe "базовый тип, который не лёг" do
    test "тип напечатан, а справочник его не знает — названо, в руку не ложится",
         %{ruleset: ruleset} do
      items = [
        item(:right_hand, "Нечто", [attack(5, "[1] Attack Bonus (0) 5")], %{
          base_type: "Vorpal Blade",
          base_item: 999
        })
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.weapon == nil
      assert gear.weapon_attack == 0
      assert [%{reason: {:base_type_unresolved, "Vorpal Blade"}}] = report.unresolved
      assert report.weapons.main.wields == nil
      assert report.weapons.main.base_type == "Vorpal Blade"

      # Число всё равно сведено — игрок впишет его руками.
      assert report.weapons.main.attack == 5
    end

    test "щит в ГЛАВНОЙ руке — опознан, но не оружие для неё", %{ruleset: ruleset} do
      items = [
        item(:right_hand, "Щит", [attack(2, "[1] Attack Bonus (0) 2")], %{
          base_type: "Tower Shield"
        })
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.weapon == nil
      assert gear.worn == %{}
      assert [%{reason: {:base_type_not_a_weapon, "Tower Shield"}}] = report.unresolved
    end

    # Форма первого поколения: типа не напечатано вовсе, число названо, чтобы
    # игрок вписал его сам.
    test "тип не напечатан — число названо, оружие не надето", %{ruleset: ruleset} do
      items = [
        item(:right_hand, "Меч Драконов", [enhancement(6, "[11] Enhancement Bonus (0) 6")])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.weapon == nil
      assert [%{reason: {:weapon_base_type_unknown, :enhancement_bonus}}] = report.unresolved
      assert report.weapons.main.attack == 6
      assert report.weapons.main.base_type == nil
    end

    # Регистр и пробелы имени — не повод не узнать: лог печатает `Bastard
    # Sword`, справочник — `Bastard sword`.
    test "имя типа сверяется без учёта регистра", %{ruleset: ruleset} do
      items = [item(:right_hand, "Меч", [], %{base_type: "bastard   SWORD"})]
      {gear, _report} = GearImport.sum(items, ruleset)

      assert gear.weapon == :bastard_sword
    end

    test "оружие во ВТОРОЙ руке — вторая рука, и AC второй руки — отклонение",
         %{ruleset: ruleset} do
      items = [
        item(:right_hand, "Меч", [], %{base_type: "Longsword"}),
        item(
          :left_hand,
          "Кинжал",
          [attack(3, "[1] Attack Bonus (0) 3"), ac(2, "[2] AC Bonus 2")],
          %{base_type: "Dagger"}
        )
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.weapon == :longsword
      assert gear.off_hand_weapon == :dagger
      assert gear.off_hand_weapon_attack == 3
      assert gear.ac == %{deflection: 2}
      assert report.unresolved == []
    end
  end

  # ------------------------------------------------------ шапка и предметы --

  describe "шапка против предметов" do
    test "пометок [CRAFT] больше, чем даёт шапка, — верх берёт шапка, разница названа",
         %{ruleset: ruleset} do
      items = [
        item(:boots, "Сапоги", [], %{craft?: true}),
        item(:belt, "Пояс", [], %{craft?: true})
      ]

      {gear, report} = GearImport.sum(items, ruleset, %{mini_set_pieces: 0, craft_items: 1})

      assert gear.named_items == 1
      assert report.counts.notes == [{:craft_marks_disagree, 1, 2}]
    end

    test "шапка называет крафта меньше, чем кусков, — ноль и оговорка", %{ruleset: ruleset} do
      {gear, report} = GearImport.sum([], ruleset, %{mini_set_pieces: 4, craft_items: 2})

      assert gear.named_items == 0

      # Сначала оговорки про куски, потом про крафт — в том порядке, в каком
      # считается: крафт вычитает уже посчитанные куски.
      assert report.counts.notes == [
               {:mini_set_groups_unverified, 4, []},
               {:craft_items_below_pieces, 2, 4}
             ]
    end

    test "без шапки крафт считается по пометкам", %{ruleset: ruleset} do
      items = [item(:boots, "Сапоги", [], %{craft?: true}), item(:belt, "Пояс", [])]
      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.named_items == 1
      assert report.counts.craft_items == nil
      assert report.counts.craft_marked == ["Сапоги"]
    end

    test "группы по [SetID] сошлись с шапкой — ложатся группы", %{ruleset: ruleset} do
      items = [
        item(:head, "а", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")]),
        item(:belt, "б", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")]),
        item(:neck, "в", [piece(9, "[1] Use Item (Mini Set) [SetID:9]")])
      ]

      {gear, report} = GearImport.sum(items, ruleset, %{mini_set_pieces: 2, craft_items: 2})

      # Одиночка (набор 9) не считается — прочитана, не вошла, названа. Шапка
      # её и не несёт: замер Dan 13.09.2026 — один надетый кусок печатает
      # `MINI SET PIECES: 0` (кейс `AT2`), то есть шапка это `Nmini`.
      assert gear.mini_sets == [2]
      assert report.counts.notes == []

      assert [%{counted?: false, note: :lone_piece, landed: {:mini_set, 9}}] =
               for(entry <- report.applied, entry.landed == {:mini_set, 9}, do: entry)
    end

    test "группы по [SetID] не сошлись с шапкой — одна группа размером в шапку",
         %{ruleset: ruleset} do
      items = [
        item(:head, "а", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")]),
        item(:belt, "б", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")])
      ]

      {gear, report} = GearImport.sum(items, ruleset, %{mini_set_pieces: 4, craft_items: 4})

      assert gear.mini_sets == [4]
      assert report.counts.groups == [2]
      assert report.counts.notes == [{:mini_set_groups_unverified, 4, [2]}]
    end

    test "шапка ноль при группах по [SetID] — пусто и оговорка", %{ruleset: ruleset} do
      items = [
        item(:head, "а", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")]),
        item(:belt, "б", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")])
      ]

      {gear, report} = GearImport.sum(items, ruleset, %{mini_set_pieces: 0, craft_items: 0})

      assert gear.mini_sets == []
      assert report.counts.notes == [{:mini_set_groups_unverified, 0, [2]}]
    end

    test "без шапки группы по [SetID] ложатся сами", %{ruleset: ruleset} do
      items = [
        item(:head, "а", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")]),
        item(:belt, "б", [piece(5, "[1] Use Item (Mini Set) [SetID:5]")])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.mini_sets == [2]
      assert report.counts.mini_set_pieces == nil
    end

    # Форма первого поколения: кусок без номера рядом с шапкой — строка
    # не сложена, а `mini_sets` заполнен шапкой.
    test "кусок без [SetID] при шапке — строка не сложена, число из шапки", %{ruleset: ruleset} do
      items = [item(:head, "а", [%{kind: :mini_set, raw: "[1] Use Item (Mini Set)"}])]
      {gear, report} = GearImport.sum(items, ruleset, %{mini_set_pieces: 2, craft_items: 2})

      assert gear.mini_sets == [2]
      assert [%{reason: {:mini_set_group_unknown, nil}}] = report.unresolved
    end

    # Форма первого поколения целиком: ни шапки, ни номеров, ни пометок — куски
    # не считаются вовсе, и `Quality` читается как «пометки крафта нет».
    test "ни шапки, ни номеров: куски названы, крафт не посчитан", %{ruleset: ruleset} do
      items = [
        item(:head, "а", [%{kind: :mini_set, raw: "[1] Use Item (Mini Set)"}]),
        item(:arms, "б", [%{kind: :quality, value: 15, raw: "[4] Quality (65535) 15"}])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.mini_sets == []
      assert gear.named_items == 0

      assert Enum.map(report.unresolved, & &1.reason) == [
               {:mini_set_group_unknown, nil},
               {:named_item_flag_missing, :quality}
             ]
    end
  end

  # -------------------------------------------------------- оба ruleset'а --

  describe "поглощение стихий: вещь против вещи (задача 3.210)" do
    defp resist(type, value, raw),
      do: %{kind: :damage_resistance, param: type, value: value, raw: raw}

    # 🔴 Правило из данных (`resistance_stacking.gear_vs_gear`): «only the
    # highest resistance granted by a spell or (equipped) item is used»
    # (`fandom:Damage resistance`, revid 68743). Значит между предметами
    # **максимум**, а не сумма.
    test "две вещи на одну стихию — максимум, проигравшая названа", %{ruleset: ruleset} do
      items = [
        item(:neck, "Амулет", [resist(:fire, 10, "[1] Damage Resistance (Fire) 10")]),
        item(:cloak, "Плащ", [resist(:fire, 15, "[1] Damage Resistance (Fire) 15")])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.resistances == %{fire: 15}

      rows = for entry <- report.applied, entry.kind == :damage_resistance, do: entry
      assert length(rows) == 2

      # прочитаны обе, в итог вошла одна — и проигравшая объяснена тем же
      # словом, что у AC одного типа
      assert Enum.count(rows, & &1.counted?) == 1

      assert %{counted?: false, note: :superseded_by_larger_same_type} =
               Enum.find(rows, &(not &1.counted?))

      assert bucket_total(report) == GearImport.property_count(items)
    end

    test "разные стихии не спорят вовсе", %{ruleset: ruleset} do
      items = [
        item(:neck, "Амулет", [
          resist(:fire, 10, "[1] Damage Resistance (Fire) 10"),
          resist(:cold, 15, "[2] Damage Resistance (Cold) 15")
        ])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.resistances == %{fire: 10, cold: 15}
      assert Enum.all?(report.applied, & &1.counted?)
    end

    # ⚠️ Ноль — законное число, и он проходит насквозь; в билд, однако, не
    # ложится: «вписал и стёр» и «не вписывал» у всех полей `Rules.Gear`
    # один ответ.
    test "нулевая строка прочитана, а в билд не легла", %{ruleset: ruleset} do
      items = [item(:neck, "Амулет", [resist(:fire, 0, "[1] Damage Resistance (Fire) 0")])]

      {gear, report} = GearImport.sum(items, ruleset)

      assert gear.resistances == %{}
      assert [%{counted?: true, landed: {:resistance, :fire, 0}}] = report.applied
    end

    # Строка без числа — это «лог напечатал свойство и не назвал величину»,
    # и молчаливым нулём она становиться не должна.
    test "строка без числа — в «не сложить»", %{ruleset: ruleset} do
      items = [
        item(:neck, "Амулет", [
          %{kind: :damage_resistance, param: :fire, raw: "[1] Damage Resistance (Fire)"}
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: {:value_missing, :damage_resistance}}] = report.unresolved
    end
  end

  describe "ванильный ruleset" do
    # У ванили системы мини-сетов нет вовсе: кусок с номером — не её механика,
    # шапка не заполняет ничего. Оружие, щит и доспех при этом ложатся так же:
    # таблица слотов и `gear.worn` лежат в общей секции.
    test "куски и крафт — не наша механика, оружие, щит и доспех ложатся",
         %{vanilla: vanilla} do
      {gear, report} = sum("hnyupius", vanilla)

      assert gear.mini_sets == []
      assert gear.named_items == 0
      assert gear.weapon == :bastard_sword
      assert gear.worn == %{armor: :full_plate, shield: :tower}
      assert Enum.count(report.not_ours, &(&1.kind == :mini_set)) == 7
      assert bucket_total(report) == 92
    end

    test "AC, спасы и база доспеха Хнюпиуса совпадают на ванили",
         %{ruleset: ruleset, vanilla: vanilla} do
      {siala_gear, _} = sum("hnyupius", ruleset)
      {vanilla_gear, _} = sum("hnyupius", vanilla)

      assert vanilla_gear.ac == siala_gear.ac
      assert vanilla_gear.saves == siala_gear.saves
      assert vanilla_gear.saves_specific == siala_gear.saves_specific
      assert vanilla_gear.worn == siala_gear.worn
    end
  end

  # ----------------------------------------------- сторожа загрузчика --

  describe "правила свода — из данных, не из кода" do
    setup do
      root = BuildCalculator.TmpDir.unique_path!()
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      %{root: root, path: Path.join([root, "siala_41", "overrides.json"])}
    end

    defp patch!(path, fun) do
      overrides = path |> File.read!() |> Jason.decode!()
      File.write!(path, Jason.encode!(fun.(overrides)))
    end

    defp patch_slots!(path, fun) do
      patch!(path, fn overrides ->
        update_in(overrides["gear"]["item_slot_ac_types"]["slots"], fn slots ->
          for slot <- slots, do: fun.(slot)
        end)
      end)
    end

    # 🔴 Сторож: режим, которого ядро не умеет, роняет СБОРКУ. «sum» здесь
    # подняло бы бонус атаки каждому импортированному билду с таким предметом,
    # и заметить это можно было бы только сверкой с игрой.
    test "неизвестный режим свода чисел оружия роняет сборку", %{root: root, path: path} do
      patch!(path, &put_in(&1["gear"]["weapon"]["import_rule"]["value"], "sum"))

      assert_raise RuntimeError, ~r/gear.weapon.import_rule is "sum"/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    # ⚠️ Половинный список рук — всегда ошибка: число второй руки исчезло бы
    # молча, и отличить это от пустой руки было бы нечем.
    test "названная половина рук роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "left_hand", do: Map.delete(slot, "hand"), else: slot
      end)

      assert_raise RuntimeError, ~r/names hands \[:main\]/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    test "рука, которой у модели нет, роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "left_hand", do: Map.put(slot, "hand", "third"), else: slot
      end)

      assert_raise RuntimeError, ~r/gear.item_slot_ac_types names hands/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    # 🔴 Сторожа базы доспеха (3.213). Первый — про указатель в пустоту: число
    # `[BaseAC:n]` указывало бы на категорию, которой нет, и доспех молча
    # оставался бы ненадетым.
    test "категория, которой gear.worn не объявляет, роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "chest",
          do: Map.put(slot, "worn_category_by_base_ac", "plate"),
          else: slot
      end)

      assert_raise RuntimeError, ~r/gear.worn does not declare/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    # 🔴 И второй, ради которого ключ вообще проверяется: две строки с ОДНОЙ
    # базой сделали бы выбор между ними нашей выдумкой. Девять доспехов несут
    # 0…8 без повторов — и это инвариант, а не наблюдение.
    test "повторённый base_ac внутри категории роняет сборку", %{root: root, path: path} do
      patch!(path, fn overrides ->
        update_in(overrides["gear"]["worn"]["categories"], fn categories ->
          for category <- categories do
            if category["id"] == "armor" do
              update_in(category["items"], fn items ->
                for item <- items do
                  if item["id"] == "half_plate", do: Map.put(item, "base_ac", 8), else: item
                end
              end)
            else
              category
            end
          end
        end)
      end)

      assert_raise RuntimeError, ~r/repeats base_ac/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    # Сторожа записи «напечатанный базовый тип → тип AC» (3.213).
    test "тип AC, которого игрок не вводит, роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "arms",
          do:
            put_in(slot, ["ac_type_by_base_type"], [
              %{"base_type" => "Bracer", "ac_type" => "luck"}
            ]),
          else: slot
      end)

      assert_raise RuntimeError, ~r/not one the player can enter/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    # 🔴 Ответ, которого нет среди альтернатив слота: игроку печатают одно,
    # а число уходит в другое.
    test "тип вне альтернатив слота роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "arms",
          do:
            put_in(slot, ["ac_type_by_base_type"], [
              %{"base_type" => "Bracer", "ac_type" => "natural"}
            ]),
          else: slot
      end)

      assert_raise RuntimeError, ~r/the player is told one answer/i, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    test "повторённое имя базового типа роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "arms",
          do:
            put_in(slot, ["ac_type_by_base_type"], [
              %{"base_type" => "Bracer", "ac_type" => "armor"},
              %{"base_type" => "bracer", "ac_type" => "deflection"}
            ]),
          else: slot
      end)

      assert_raise RuntimeError, ~r/maps the same base type twice/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    test "безымянный базовый тип роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "arms",
          do:
            put_in(slot, ["ac_type_by_base_type"], [%{"base_type" => " ", "ac_type" => "armor"}]),
          else: slot
      end)

      assert_raise RuntimeError, ~r/a nameless base type/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    test "запись у слота с собственным типом роняет сборку", %{root: root, path: path} do
      patch_slots!(path, fn slot ->
        if slot["id"] == "head",
          do:
            put_in(slot, ["ac_type_by_base_type"], [
              %{"base_type" => "Helmet", "ac_type" => "deflection"}
            ]),
          else: slot
      end)

      assert_raise RuntimeError, ~r/AND ac_type_by_base_type/, fn ->
        BuildCalculator.Data.Loader.load!(root)
      end
    end

    # Руки называет таблица слотов, и `Rules.Gear.hands/0` — тот же список,
    # которым ядро ходит по рукам везде: ключи сводки обязаны совпадать с ним,
    # а не быть третьим именованием рук в проекте.
    test "ключи сводки — это руки модели", %{ruleset: ruleset} do
      {_gear, report} = GearImport.sum([], ruleset)

      assert Enum.sort(Map.keys(report.weapons)) == Enum.sort(Rules.Gear.hands())
    end
  end
end
