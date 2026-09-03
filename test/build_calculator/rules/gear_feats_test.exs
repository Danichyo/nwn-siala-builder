defmodule BuildCalculator.Rules.GearFeatsTest do
  @moduledoc """
  Фит с вещи — задача 3.3.

  До неё калькулятор **отказывал билду, который на шарде собирается**: фита нет
  в лестнице, он лежит на надетом предмете, а требование читалось только по
  слотам и классовым выдачам. Мастер оружия и Чемпион Торма требуют
  `Weapon focus`, Арфист-скаут и Оборотень — `Alertness`, `Weapon
  specialization` — снова `Weapon focus`; всё это носится вещами не реже, чем
  берётся слотом.

  Решения, которые здесь закреплены (Dan, 02.08.2026, 09.08.2026 и 14.08.2026):

    * слота фит с вещи **не занимает** — ни одного слота больше и ни одного
      меньше;
    * требования **КЛАССА** он выполняет: «но вот КЛАСС можно взять: ВМ требует
      ряд фитов, и если expertise у нас есть на вещи, то брать его фитом при
      лвл апе не обязательно» (замер 14.08.2026, `GAME_CHECKS.md` H7);
    * пререквизиты других **ФИТОВ** он **НЕ** выполняет: «мы взяли expertise
      с вещи, improve expertise не появится в выборке доступных фитов
      (т.е. полный игнор фитов с вещи)». ⚠️ Здесь стояло «требования он
      выполняет — и фитовые, и классовые, потому что оба блока читает один
      интерпретатор» — интерпретатор по-прежнему один, но у ключа `feats`
      теперь два ответа, и какой из них дать, решает `requirement_of`;
    * сам фит при этом остаётся выбираемым: «а вот сам expertise там будет»;
    * его **эффект считается**: «да, пускай эффект фита с вещи учитывается
      в числах. Ведь если фит есть, допустим тафнес, то и HP будут увеличены»;
    * потолок **взятий** вещь не считает («брать эти фиты в билде также можно
      вплоть до 10 раз»), потолок **эффекта** — считает («как максимум для
      УЧЁТА там всё равно будет только 10 раз»);
    * значения (школа у `Spell focus`, оружие у `Weapon focus`) объявление
      не несёт, и билд об этом говорит.

  Источники ожидаемых чисел:

    * требования классов и фитов — `priv/rules/vanilla/classes.json`,
      `feats.json` (со страниц Fandom `Weapon master`, `Harper scout`,
      `Weapon specialization`);
    * `Toughness` +1 HP за уровень — `vanilla/feat_hp_bonuses.json`
      (`fandom:Toughness`, revid 41265);
    * `Alertness` +2 Listen/Spot — `vanilla/feat_skill_bonuses.json`;
    * `Armor skin` +2 natural AC — `vanilla/ac_bonuses.json`;
    * `Iron will` +2 Will — `vanilla/feat_save_bonuses.json`;
    * `Epic prowess` +1 к атаке — `vanilla/feat_attack_bonuses.json`;
    * `Great strength` +1 STR за взятие — `vanilla/feat_ability_bonuses.json`;
    * `Devastating critical` на Сиале отключён — `siala_41/generated/feats.json`;
    * `Riding Sprint` (`siala:Riding Sprint`, revid 17794) и `Smile of Death`
      (revid 20027) — «Умение нельзя выбрать при росте персонажа; Умение
      доступно персонажу только при наличии предмета».

  ⚠️ Ни одна проверка здесь **не опирается на то, под капом источник или над
  ним**. Сторона потолка читается из данных (`stat_caps.*.applies_to_sources`)
  и уже один раз переезжала; поэтому прибавки проверяются по сырым термам
  (`own_save_terms`, `own_attack_terms`), а итоговые числа — только на билдах,
  где потолок заведомо не задет.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, Build, FeatSlots, Gear, GearFeats}

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  @abilities %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}

  # `%Build{} =` не декорация: без него компилятор видит у `Build.new/1`
  # динамический тип и ругается на каждое обновление структуры ниже.
  defp build(levels, fields \\ []) do
    %Build{} =
      Build.new(
        [
          ruleset_version: "siala_41",
          race: :human,
          alignment: :true_neutral,
          base_abilities: @abilities,
          levels: levels
        ] ++ fields
      )
  end

  defp with_feats(%Build{gear: %Gear{} = gear} = build, feats) do
    %Build{build | gear: %Gear{gear | feats: feats}}
  end

  # Причины отказа классу, `[]` если класс легален. Ванильный ruleset добавляет
  # к списку `{:missing_data, :max_classes}` (лимита классов у него нет вовсе),
  # поэтому сравнивать список целиком там нельзя — проверяется вхождение.
  defp refusals(build, class, ruleset) do
    case Rules.validate_level_up(build, class, ruleset) do
      :ok -> []
      {:error, reasons} -> reasons
    end
  end

  describe "требования выполняются — и без объявления по-прежнему нет" do
    # Мастер оружия: шесть фитов в требованиях. Пять взяты слотами, шестой —
    # `Weapon focus` — приходит с вещи. Отрицательный контроль стоит рядом:
    # без объявления остаётся ровно один отказ, и он именно про этот фит.
    test "класс: Weapon Master и Weapon focus с вещи", %{ruleset: ruleset} do
      base =
        build(List.duplicate(:fighter, 6),
          skills: %{1 => %{intimidate: 4}},
          feats: %{
            1 => %{
              :general => :dodge,
              :racial => :expertise,
              {:class_bonus, :fighter} => :mobility
            },
            2 => %{{:class_bonus, :fighter} => :spring_attack},
            4 => %{{:class_bonus, :fighter} => :whirlwind_attack}
          }
        )

      assert Rules.validate_level_up(base, :weapon_master, ruleset) ==
               {:error, [{:requires_feat, :weapon_focus}]}

      assert Rules.validate_level_up(with_feats(base, [:weapon_focus]), :weapon_master, ruleset) ==
               :ok
    end

    # `Alertness` — второй фит, названный Dan как «носится вещью». На Сиале его
    # требует Оборотень.
    #
    # ⚠️ **Не** Арфист-скаут, хотя в ванили именно он требует `Alertness` и
    # `Iron will`: Сиала переписала его требования целиком на `Brew Potion` +
    # Дисциплина 10 + Поиск 10 (`siala:Арфист-скаут`, revid 19414). Проверка
    # закреплена здесь, чтобы следующий читатель не «починил» отсутствующее
    # требование по ванильной памяти.
    test "класс: Shifter требует Alertness", %{ruleset: ruleset} do
      base = build(List.duplicate(:druid, 5), base_abilities: %{@abilities | wis: 14})

      assert Rules.validate_level_up(base, :shifter, ruleset) ==
               {:error, [{:requires_feat, :alertness}]}

      assert Rules.validate_level_up(with_feats(base, [:alertness]), :shifter, ruleset) == :ok

      refute {:requires_feat, :alertness} in refusals(base, :harper_scout, ruleset)
    end

    # То же требование в ванильном ruleset'е, где оба фита ещё на месте: два
    # отказа, и объявление снимает их по одному.
    test "класс: Harper Scout в ванили требует Alertness и Iron will" do
      vanilla = Data.ruleset!("vanilla")

      base =
        build(List.duplicate(:rogue, 6),
          ruleset_version: "vanilla",
          skills: %{1 => %{discipline: 4, lore: 6, persuade: 8, search: 4}}
        )

      assert {:requires_feat, :alertness} in refusals(base, :harper_scout, vanilla)
      assert {:requires_feat, :iron_will} in refusals(base, :harper_scout, vanilla)

      one = refusals(with_feats(base, [:alertness]), :harper_scout, vanilla)
      refute {:requires_feat, :alertness} in one
      assert {:requires_feat, :iron_will} in one

      both = refusals(with_feats(base, [:alertness, :iron_will]), :harper_scout, vanilla)
      refute Enum.any?(both, &match?({:requires_feat, _}, &1))
    end

    # 🔴 ТРИ ОТВЕТА ОДНОГО ЗАМЕРА, И ОНИ РАЗНЫЕ — поэтому одним тестом.
    #
    # Замер Dan 14.08.2026 (`GAME_CHECKS.md` H7, `source: kind: user` — высший
    # ранг источника по CLAUDE.md §3), дословно:
    #
    #   «фит с вещи не позволит взять другой фит, требующий тот фит, который мы
    #    взяли с вещи. Пример, мы взяли expertise с вещи, improve expertise
    #    не появится в выборке доступных фитов. А вот сам expertise там будет
    #    (т.е. полный игнор фитов с вещи). Но вот КЛАСС можно взять: ВМ требует
    #    ряд фитов, и если expertise у нас есть на вещи, то брать его фитом при
    #    лвл апе не обязательно.»
    #
    # ⚠️ Порознь каждая строка зеленеет и при неверной модели: «класс можно» —
    # у старой (вещь везде считается), «фит нельзя» — у наивно строгой (вещь
    # нигде не считается), «сам фит можно» — у обеих. Врозь они не ловят ничего;
    # вместе не проходят ни у одной из трёх неверных моделей.
    #
    # Билд — тот самый, что прислал Dan: `Expertise` с брони и `Whirlwind
    # attack` с боевого посоха открывают Мастера оружия, а слоты потрачены
    # на остальные четыре фита требования.
    test "вещь открывает КЛАСС, не открывает ФИТ и не мешает взять сам фит", %{ruleset: ruleset} do
      base =
        build(List.duplicate(:fighter, 6),
          base_abilities: %{@abilities | int: 13},
          skills: %{1 => %{intimidate: 4}},
          feats: %{
            1 => %{
              :general => :dodge,
              :racial => :mobility,
              {:class_bonus, :fighter} => :weapon_focus
            },
            4 => %{{:class_bonus, :fighter} => :spring_attack}
          }
        )

      geared = with_feats(base, [:expertise, :whirlwind_attack])

      # 1. КЛАСС: два фита требования пришли с вещей — Мастер оружия открыт.
      assert Rules.validate_level_up(geared, :weapon_master, ruleset) == :ok

      # 2. ФИТ: `Improved expertise` требует `Expertise`, и вещь его не даёт.
      #    Причина — обычная `{:requires_feat, …}`, новой формы не заведено:
      #    нужен именно фит, и нужен постоянно.
      assert Rules.validate_feat(geared, :improved_expertise, ruleset) ==
               {:error, [{:requires_feat, :expertise}]}

      # 3. САМ фит остаётся выбираемым — вещь снимается, слот нет.
      assert Rules.validate_feat(geared, :expertise, ruleset) == :ok
    end

    # Отрицательные контроли к тесту выше — по одному на каждый способ
    # получить его три строки неверно.
    test "контроли: чем именно держатся три ответа", %{ruleset: ruleset} do
      base =
        build(List.duplicate(:fighter, 6),
          base_abilities: %{@abilities | int: 13},
          skills: %{1 => %{intimidate: 4}},
          feats: %{
            1 => %{
              :general => :dodge,
              :racial => :mobility,
              {:class_bonus, :fighter} => :weapon_focus
            },
            4 => %{{:class_bonus, :fighter} => :spring_attack}
          }
        )

      # Без вещей класс отказывает ровно теми двумя фитами, что на них лежат —
      # значит строка 1 держится на объявлении, а не на том, что требование
      # и так выполнено.
      assert Rules.validate_level_up(base, :weapon_master, ruleset) ==
               {:error, [{:requires_feat, :expertise}, {:requires_feat, :whirlwind_attack}]}

      # `Expertise` в СЛОТЕ открывает `Improved expertise` — значит строка 2
      # отказывает из-за источника фита, а не из-за INT, порванной цепочки
      # или запрета класса на уровне.
      slotted = Build.put_feat(base, 3, :general, :expertise)
      assert Rules.validate_feat(slotted, :improved_expertise, ruleset) == :ok

      # ⚠️ Сужение 14.08.2026 — про ВЕЩЬ, а не про «всё, что не слот».
      # Классовая выдача остаётся постоянным владением и пререквизит открывает:
      # один и тот же фит, два маршрута, противоположные ответы.
      #
      # Воин выдаёт лёгкий и средний доспех сам, и `Armor proficiency (heavy)`
      # ему доступен; волшебник, надевший оба, — нет.
      assert MapSet.member?(Build.feats_permanent(base, ruleset, 1), :armor_proficiency_medium)
      assert Rules.validate_feat(base, :armor_proficiency_heavy, ruleset) == :ok

      worn =
        with_feats(build(List.duplicate(:wizard, 6)), [
          :armor_proficiency_light,
          :armor_proficiency_medium
        ])

      assert Rules.validate_feat(worn, :armor_proficiency_heavy, ruleset) ==
               {:error,
                [
                  {:requires_feat, :armor_proficiency_light},
                  {:requires_feat, :armor_proficiency_medium}
                ]}
    end

    # Объявление не level-scoped: предмет надет независимо от того, про какой
    # уровень спрашивают. Дельта считается на усечённом билде, и там вещи
    # обязаны остаться теми же (`Build.truncate/2` их не трогает).
    #
    # ⚠️ Раньше это проверялось требованием ФИТА (`Weapon specialization`
    # при `Weapon focus` с вещи, `at: 4`). С 14.08.2026 такая проверка
    # утверждала бы неверное: фит с вещи пререквизит другого фита не выполняет.
    # Свойство то же, вопросы — те два, что вещь по-прежнему двигает:
    # множество владения и числа на усечённом билде.
    test "объявление не усекается вместе с лестницей", %{ruleset: ruleset} do
      base = build(List.duplicate(:wizard, 6))
      geared = with_feats(base, [:toughness])

      assert Build.truncate(geared, 1).gear.feats == [:toughness]

      for level <- [1, 4, 6] do
        cut = Build.truncate(geared, level)

        assert MapSet.member?(Build.feats_owned(cut, ruleset, level), :toughness)

        # `Toughness` — +1 HP за уровень персонажа, поэтому разность равна
        # уровню, на котором усекли.
        assert Rules.compute(cut, ruleset).hp ==
                 Rules.compute(Build.truncate(base, level), ruleset).hp + level
      end
    end
  end

  describe "слот не тратится" do
    test "слоты уровня и весь их набор не меняются от объявления", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21))
      declared = with_feats(base, [:toughness, :weapon_focus, :epic_prowess])

      for level <- [1, 4, 20, 21] do
        assert FeatSlots.at(base, ruleset, level) == FeatSlots.at(declared, ruleset, level)
      end

      assert Rules.compute(base, ruleset).feat_slots ==
               Rules.compute(declared, ruleset).feat_slots
    end

    test "объявленный фит не попадает ни в один слот билда", %{ruleset: ruleset} do
      declared = build(List.duplicate(:fighter, 6)) |> with_feats([:toughness])

      assert declared.feats == %{}
      assert Build.feats_taken(declared, 6) == MapSet.new()
      assert MapSet.member?(Build.feats_owned(declared, ruleset, 6), :toughness)
      refute :toughness in Build.feats_at(declared, 1)
    end
  end

  describe "эффект считается — и назван отдельным термом" do
    # Волшебник взят намеренно: `Toughness` ему никто не выдаёт, поэтому
    # видно ровно вклад объявления. У воина на Сиале фит уже классовый —
    # это отдельный тест ниже.
    test "HP: Toughness с вещи даёт +1 за уровень персонажа", %{ruleset: ruleset} do
      base = build(List.duplicate(:wizard, 10))

      before = Rules.compute(base, ruleset)
      after_ = Rules.compute(with_feats(base, [:toughness]), ruleset)

      # 40 из хит-дайсов + 20 от CON 14 + 20 от «Духа Сиалы» (задача, волна
      # 12) — плоский и присутствует уже в `before`, объявление его не
      # трогает ни в одну сторону.
      assert before.hp == 60 + 20
      assert after_.hp == 70 + 20
      assert before.hp_breakdown.by_feat == []
      assert before.hp_breakdown.innate == %{id: :spirit_of_siala, ru: "Дух Сиалы", amount: 20}

      assert after_.hp_breakdown.by_feat == [
               %{feat: :toughness, takes: 1, subtotal: 10, capped?: false}
             ]
    end

    test "навыки: Alertness с вещи даёт +2 к Spot и Listen", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 6), skills: %{1 => %{spot: 4, listen: 4}})

      before = Rules.compute(base, ruleset)
      after_ = Rules.compute(with_feats(base, [:alertness]), ruleset)

      assert before.skill_values[:spot].total == 4
      assert before.skill_values[:spot].feat_bonus_from == []
      assert after_.skill_values[:spot].total == 6
      assert after_.skill_values[:spot].feat_bonus == 2
      assert after_.skill_values[:spot].feat_bonus_from == [:alertness]
      assert after_.skill_values[:listen].total == 6
    end

    # ⚠️ И только в «шмоте». Снимешь предмет — фит уйдёт с ним, поэтому
    # «голым» его AC не считается; фит, взятый СЛОТОМ, стоит в обоих числах
    # (проверка ниже) — ровно для этого у AC и два числа.
    test "AC: Armor skin с вещи даёт +2 природных — в шмоте, не голым", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 6))

      before = Rules.compute(base, ruleset)
      after_ = Rules.compute(with_feats(base, [:armor_skin]), ruleset)

      assert {before.ac_naked, before.ac_geared} == {12, 12}
      assert {after_.ac_naked, after_.ac_geared} == {12, 14}

      assert after_.ac_own_terms_geared == [
               %{
                 id: :armor_skin,
                 source: {:feat, :armor_skin},
                 type: :natural,
                 ac: 2,
                 vs_typed: :sum
               }
             ]

      assert after_.ac_own_terms == []
    end

    test "тот же фит, взятый слотом, стоит в обоих числах", %{ruleset: ruleset} do
      slotted =
        build(List.duplicate(:fighter, 21), feats: %{21 => %{general: :armor_skin}})
        |> Rules.compute(ruleset)

      bare = Rules.compute(build(List.duplicate(:fighter, 21)), ruleset)

      assert slotted.ac_naked == bare.ac_naked + 2
      assert slotted.ac_geared == bare.ac_geared + 2
    end

    # ⚠️ Терм сырой, до потолка. Итоговый Will проверяется на билде без чисел
    # с вещей — там +2 заведомо ниже потолка +20, каким бы правилом он ни
    # клипался.
    test "сейвы: Iron will с вещи даёт +2 к Will и ничего к остальным", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 6))

      before = Rules.compute(base, ruleset)
      after_ = Rules.compute(with_feats(base, [:iron_will]), ruleset)

      assert before.own_save_terms == []

      assert after_.own_save_terms == [
               %{
                 id: :iron_will,
                 source: {:feat, :iron_will},
                 save: :will,
                 bonus: 2,
                 under_cap?: false,
                 counts_for_prereqs?: true
               }
             ]

      assert after_.will == before.will + 2
      assert after_.fort == before.fort
      assert after_.ref == before.ref
    end

    # 🔴 Правка 09.08.2026: сторона капа — свойство ЗАПИСИ разметки, а объявленный
    # с вещи фит приходит обычным термом `{:feat, id}`. Значит он обязан получить
    # сторону ТОЙ ЖЕ записи, что и взятый слотом, — и оба ложатся ПОВЕРХ капа
    # («У сейвов тоже фиты не входят в кап +20», Dan). Проверяется на вещах +20,
    # то есть ровно там, где старое поведение съедало прибавку целиком.
    test "объявленный Iron will ложится поверх капа так же, как взятый слотом", %{
      ruleset: ruleset
    } do
      geared = %Build{
        build(List.duplicate(:fighter, 6))
        | gear: Gear.new(saves: 20, feats: [:iron_will])
      }

      %Build{} =
        with_slot = build(List.duplicate(:fighter, 6), feats: %{1 => %{general: :iron_will}})

      slotted = %Build{with_slot | gear: Gear.new(saves: 20)}

      for {stats, whence} <- [
            {Rules.compute(geared, ruleset), "с вещи"},
            {Rules.compute(slotted, ruleset), "слотом"}
          ] do
        assert Enum.map(stats.own_save_terms, &{&1.id, &1.save, &1.bonus, &1.under_cap?}) ==
                 [{:iron_will, :will, 2, false}],
               "Iron will #{whence}: сторона капа не та"

        assert stats.save_bonus == %{fort: 20, ref: 20, will: 22},
               "Iron will #{whence}: прибавка съедена потолком"
      end
    end

    # ⚠️ Тоже сырой терм: `under_cap?` у него читается из данных, и проверять
    # тут надо не сторону потолка, а то, что терм вообще появился и назван.
    test "атака: Epic prowess с вещи даёт +1", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21))

      before = Rules.compute(base, ruleset)
      after_ = Rules.compute(with_feats(base, [:epic_prowess]), ruleset)

      assert before.own_attack_terms == []

      assert [%{id: :epic_prowess, source: {:feat, :epic_prowess}, bonus: 1}] =
               after_.own_attack_terms

      assert after_.own_attack_bonus == 1
      assert after_.attack_bonus == before.attack_bonus + 1
    end

    # `Great strength` считается «за взятие», а объявление слота не тратит,
    # то есть взятий ноль. Пол «владеешь — значит одно взятие» стоит в
    # `Rules.AbilityBonuses` ровно для таких случаев: без него фит был бы
    # у персонажа и не стоил бы ничего — тот самый молчаливый ноль.
    test "характеристики: Great strength с вещи даёт +1 STR, а не +0", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21))

      before = Rules.compute(base, ruleset)
      after_ = Rules.compute(with_feats(base, [:great_strength]), ruleset)

      assert before.abilities.str == 16
      assert after_.abilities.str == 17

      # Разбор характеристики — там же, где его берёт панель итогов: слагаемое
      # названо по фиту и стоит отдельно от `gear_typed`, то есть от числа,
      # которое игрок вписал руками.
      str = Abilities.breakdown(with_feats(base, [:great_strength]), ruleset)[:str]
      assert str.own_bonus == 1
      assert str.gear_typed == 0
      assert [%{id: :great_strength, bonus: 1, takes: 1}] = str.own_terms
    end

    test "без объявления ни одно число не меняется", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21), skills: %{1 => %{spot: 4}})

      # Положительный контроль рядом, и фит для него взят такой, которого этот
      # класс НЕ выдаёт сам: `Toughness` воину даётся даром (тест ниже), так что
      # на нём контроль был бы вакуумным.
      assert Rules.compute(base, ruleset) == Rules.compute(%Build{base | gear: %Gear{}}, ruleset)

      refute Rules.compute(base, ruleset) ==
               Rules.compute(with_feats(base, [:alertness]), ruleset)
    end
  end

  # ⚠️ Правка 09.08.2026 (волна 14). До неё объявление фита с вещи **запрещало
  # взять его же слотом**: `Build.feats_owned/3` — множество, и пик читался как
  # дубль. Это ложная нелегальность: предмет снимается, слот нет, а образец
  # правильного поведения в проекте уже был — фит, который класс выдаёт даром,
  # мы не запрещаем, а предупреждаем (CLAUDE.md §6). Числа замерены вызовами
  # ядра до правки: волшебник 5 с CON 14 без вещей брал `Toughness` (`:ok`),
  # а с `Toughness` на вещи получал `{:error, [already_taken: :toughness]}` —
  # то есть отказ появлялся ОТ вещи.
  describe "фит с вещи не запрещает взять его же слотом" do
    # ⚠️ Обе половины парного правила — одним тестом. «Слот потратить можно»
    # и «второй раз он ничего не даёт» по отдельности зеленеют и при неверной
    # модели (так уже наступали с dual wield рейнджера).
    test "неповторяемый: слот потратить можно, числа не меняются, и это сказано", %{
      ruleset: ruleset
    } do
      # Волшебник: `Toughness` ему не выдаёт ни класс, ни раса, поэтому виден
      # ровно вклад объявления.
      base = build(List.duplicate(:wizard, 5))
      geared = with_feats(base, [:toughness])

      # Половина первая: пик разрешён — и без вещи, и с вещью одинаково.
      assert Rules.validate_feat_pick(base, %{feat: :toughness, at: 1}, ruleset) == :ok
      assert Rules.validate_feat_pick(geared, %{feat: :toughness, at: 1}, ruleset) == :ok

      # Половина вторая: слот ничего не добавляет. 20 хит-дайсов (d4 × 5) +
      # 10 от CON 14 + 20 «Духа Сиалы» = 50, `Toughness` даёт +5 (по 1 за
      # уровень) — и даёт их РОВНО ОДИН РАЗ, каким бы путём фит ни пришёл.
      slotted = Build.put_feat(geared, 1, :general, :toughness)

      assert Rules.compute(base, ruleset).hp == 50
      assert Rules.compute(geared, ruleset).hp == 55
      assert Rules.compute(slotted, ruleset).hp == 55

      assert Rules.compute(slotted, ruleset).hp_breakdown.by_feat ==
               [%{feat: :toughness, takes: 1, subtotal: 5, capped?: false}]

      # Половина третья, без которой первые две — молчаливая ловушка: ядро
      # говорит, что слот потрачен впустую. Отрицательный контроль рядом.
      assert Rules.feat_pick_caveats(geared, :toughness, ruleset) ==
               [{:owned_from_gear, :toughness}]

      assert Rules.feat_pick_caveats(base, :toughness, ruleset) == []
    end

    # То же на 3-м уровне: правило не про первый уровень и не про расовый слот.
    test "и на уровне, где слот один — общий", %{ruleset: ruleset} do
      geared = with_feats(build(List.duplicate(:wizard, 5)), [:toughness])

      assert Rules.validate_feat_pick(geared, %{feat: :toughness, at: 3}, ruleset) == :ok
    end

    # ⚠️ Две половины одного контракта обязаны согласиться. До правки
    # `FeatSlots.accepts?/3` отвечал `true` (слот фит принимает), а
    # `validate_feat_pick/3` — отказом: разошлись. По контракту прав был
    # `accepts?/3`: он про ПУЛ слота и билда не видит вовсе (в аргументах его
    # нет), поэтому «уже взят» — не его вопрос и никогда им не был. Неверен был
    # второй.
    test "accepts?/3 и validate_feat_pick/3 говорят одно и то же", %{ruleset: ruleset} do
      geared = with_feats(build(List.duplicate(:wizard, 5)), [:toughness])

      for level <- [1, 3] do
        slots = FeatSlots.at(geared, ruleset, level)
        assert slots != []

        accepted? = Enum.any?(slots, &FeatSlots.accepts?(ruleset, &1, :toughness))

        allowed? =
          Rules.validate_feat_pick(geared, %{feat: :toughness, at: level}, ruleset) == :ok

        assert accepted? == allowed?,
               "уровень #{level}: слот принимает #{accepted?}, а пик разрешён #{allowed?}"
      end
    end

    # Классовая выдача — по-прежнему ОТКАЗ, и это не непоследовательность:
    # её нельзя потерять, значит слот действительно нельзя потратить осмысленно.
    # Ровно этим она отличается от вещи, и разница обязана быть под тестом,
    # иначе следующая правка «для единообразия» откроет и её.
    test "а фит, выданный классом, взять слотом по-прежнему нельзя", %{ruleset: ruleset} do
      fighter = build(List.duplicate(:fighter, 5))

      assert MapSet.member?(Build.granted_feats(fighter, ruleset, 5), :toughness)

      assert Rules.validate_feat_pick(fighter, %{feat: :toughness, at: 3}, ruleset) ==
               {:error, [{:already_taken, :toughness}]}
    end

    # Повторяемый: два источника СКЛАДЫВАЮТСЯ. «Это будет +2, сможем такое
    # сделать?» — Dan, 09.08.2026. Числа до правки: слот+вещь давали
    # `takes: 1, subtotal: 20`, то есть второе взятие исчезало.
    test "повторяемый: взятие с вещи и взятие слотом — два взятия", %{ruleset: ruleset} do
      base = build(List.duplicate(:wizard, 21))
      slotted = Build.put_feat(base, 21, :general, :epic_toughness)

      terms = fn b -> Rules.compute(b, ruleset).hp_breakdown.by_feat end
      hp = fn b -> Rules.compute(b, ruleset).hp end

      assert terms.(base) == []

      for one <- [slotted, with_feats(base, [:epic_toughness])] do
        assert terms.(one) == [%{feat: :epic_toughness, takes: 1, subtotal: 20, capped?: false}]
        assert hp.(one) == hp.(base) + 20
      end

      both = with_feats(slotted, [:epic_toughness])

      assert terms.(both) == [%{feat: :epic_toughness, takes: 2, subtotal: 40, capped?: false}]
      assert hp.(both) == hp.(base) + 40
    end

    # То же у характеристик: `Great strength` считается «за взятие».
    test "повторяемый: STR от Great strength складывается тем же счётом", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21))
      slotted = Build.put_feat(base, 21, :general, :great_strength)

      str = fn b -> Rules.compute(b, ruleset).abilities.str end

      assert str.(base) == 16
      assert str.(slotted) == 17
      assert str.(with_feats(base, [:great_strength])) == 17
      assert str.(with_feats(slotted, [:great_strength])) == 18
    end

    # ⚠️ Потолок ВЗЯТИЙ считает только СЛОТЫ — замер Dan 14.08.2026
    # (`GAME_CHECKS.md` H8): «брать эти фиты в билде также можно вплоть до
    # 10 раз (если фит уже взят с вещи его можно взять при левел апе этот же
    # фит)». `max_takes` у `Epic toughness` — 10 (Dan, 02.08.2026).
    #
    # ⚠️ Здесь стояло обратное — «потолок взятий считает и слоты, и вещь»,
    # с доводом «иначе через вещь его обходят». Довод был НАШИМ выводом,
    # единственным местом в H8, за которым не стояло ничьё слово, и замер его
    # опроверг. Обход закрывает не этот потолок, а потолок ЭФФЕКТА, который
    # Dan назвал тем же ответом: «как максимум для УЧЁТА там всё равно будет
    # только 10 раз» — последняя треть теста про него.
    test "потолок взятий считает слоты, потолок эффекта — оба источника", %{ruleset: ruleset} do
      # Уровни взяты произвольные: `validate_feat_pick` проверяет повторяемость
      # и требования, а не существование слота.
      picks = fn upto ->
        Enum.reduce(21..upto//1, build(List.duplicate(:wizard, 41)), fn level, acc ->
          Build.put_feat(acc, level, :general, :epic_toughness)
        end)
      end

      nine = picks.(29)
      assert Build.feat_takes(nine, :epic_toughness, 41) == 9
      assert Build.feat_takes_owned(nine, ruleset, :epic_toughness, 41) == 9

      geared = with_feats(nine, [:epic_toughness])
      assert Build.feat_takes_owned(geared, ruleset, :epic_toughness, 41) == 10

      # Десятое взятие слотом разрешено И без вещи, И с вещью: вещь в потолок
      # взятий не входит. Обе половины рядом — порознь каждая зеленела бы
      # и у прежней, неверной модели.
      assert Rules.validate_feat_pick(nine, %{feat: :epic_toughness, at: 41}, ruleset) == :ok
      assert Rules.validate_feat_pick(geared, %{feat: :epic_toughness, at: 41}, ruleset) == :ok

      # Одиннадцатое — отказ, и он приходит от десяти СЛОТОВ, а не от девяти
      # плюс вещь: тот же отказ обязан стоять и на билде без вещей.
      ten = picks.(30)
      assert Build.feat_takes(ten, :epic_toughness, 41) == 10

      for b <- [ten, with_feats(ten, [:epic_toughness])] do
        assert Rules.validate_feat_pick(b, %{feat: :epic_toughness, at: 41}, ruleset) ==
                 {:error, [{:max_takes, :epic_toughness, 10}]}
      end

      # 🔴 И потолок ЭФФЕКТА закрывает обход: одиннадцать взятий (десять слотов
      # плюс вещь) — это по-прежнему 200 HP, а не 220.
      hp_terms = fn b -> Rules.compute(b, ruleset).hp_breakdown.by_feat end

      assert hp_terms.(ten) ==
               [%{feat: :epic_toughness, takes: 10, subtotal: 200, capped?: false}]

      assert hp_terms.(with_feats(ten, [:epic_toughness])) ==
               [%{feat: :epic_toughness, takes: 11, subtotal: 200, capped?: true}]

      assert Rules.compute(ten, ruleset).hp ==
               Rules.compute(with_feats(ten, [:epic_toughness]), ruleset).hp
    end

    # 🔴 Решение Dan 14.08.2026, задача 3.29 — закрыта РЕШЕНИЕМ, а не моделью.
    # В игре это пронумерованные экземпляры, и один и тот же номер с вещи
    # и слотом не складывается; мы номеров не различаем сознательно: «при
    # подсчёте статов или ХП в Итогах мы можем их просто складывать… и ставим
    # кап на 10 штук, чтоб не получилось больше 10 эпик силы или больше 200 ХП,
    # учитывая СУММУ того, что взяли в билде, и того, что набрали с вещей».
    #
    # Тест выше пиннит эту же пару для HP; здесь — для характеристики, потому что
    # потолки у них разной природы: у HP режется ЭФФЕКТ (200), у характеристики —
    # ЧИСЛО взятий (10). Одно поведение, два механизма, и молча разъехаться они
    # могут independently.
    test "Great strength: слот и вещь складываются, кап 10 стоит на сумме", %{ruleset: ruleset} do
      picks = fn upto ->
        Enum.reduce(21..upto//1, build(List.duplicate(:fighter, 41)), fn level, acc ->
          Build.put_feat(acc, level, :general, :great_strength)
        end)
      end

      str = fn b -> Rules.compute(b, ruleset).abilities.str end

      # Складываются: четыре слотовых взятия плюс вещь дают пять, а не четыре.
      four = picks.(24)
      assert Build.feat_takes_owned(four, ruleset, :great_strength, 41) == 4

      assert Build.feat_takes_owned(
               with_feats(four, [:great_strength]),
               ruleset,
               :great_strength,
               41
             ) == 5

      assert str.(with_feats(four, [:great_strength])) == str.(four) + 1

      # Кап стоит на СУММЕ: десять слотовых уже дают потолок, и вещь сверх них
      # не прибавляет ничего — то есть через вещь одиннадцатую силу не набрать.
      ten = picks.(30)
      assert Build.feat_takes_owned(ten, ruleset, :great_strength, 41) == 10

      assert Build.feat_takes_owned(
               with_feats(ten, [:great_strength]),
               ruleset,
               :great_strength,
               41
             ) == 11

      assert str.(with_feats(ten, [:great_strength])) == str.(ten)

      # ⚠️ И место, где наша модель отличается от примера Dan («4 фитами и ещё
      # 2 с вещи»): ввод количества НЕ НЕСЁТ — блок «Вещи» это переключатель
      # «фит есть / нет», строка одна на фит. Объявить дважды нельзя, и объявленный
      # считается ОДНИМ взятием. Пиннится, потому что это и есть цена решения:
      # выражать «×N» стоило бы формы `Gear.feats`, кодировки билда в URL
      # и счётчика в интерфейсе (отложено до армори).
      twice = with_feats(four, [:great_strength, :great_strength])
      assert Build.feat_takes_owned(twice, ruleset, :great_strength, 41) == 5
      assert str.(twice) == str.(with_feats(four, [:great_strength]))
    end

    # У повторяемого оговорки нет — и это не забывчивость: второе взятие стоит
    # настоящих 20 HP (тест выше), поэтому «слот ничего не добавит» было бы
    # прямой ложью. Отрицательный и положительный контроль в одном тесте.
    test "оговорка только там, где слот действительно ничего не купит", %{ruleset: ruleset} do
      base = build(List.duplicate(:wizard, 21))

      assert Rules.feat_pick_caveats(
               with_feats(base, [:epic_toughness]),
               :epic_toughness,
               ruleset
             ) ==
               []

      assert Rules.feat_pick_caveats(with_feats(base, [:alertness]), :alertness, ruleset) ==
               [{:owned_from_gear, :alertness}]
    end
  end

  describe "двойного счёта нет" do
    # На Сиале воин выдаёт `Toughness` сам. Объявить его с вещи можно, но
    # владение — множество, поэтому HP не удваиваются.
    test "фит, который выдаёт класс, объявленный с вещи, считается один раз", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 6))

      assert MapSet.member?(Build.granted_feats(base, ruleset, 6), :toughness)

      assert Rules.compute(base, ruleset).hp ==
               Rules.compute(with_feats(base, [:toughness]), ruleset).hp
    end

    test "фит, взятый слотом и объявленный с вещи, считается один раз", %{ruleset: ruleset} do
      base = build(List.duplicate(:wizard, 10), feats: %{1 => %{general: :toughness}})

      assert Rules.compute(base, ruleset).hp ==
               Rules.compute(with_feats(base, [:toughness]), ruleset).hp
    end

    # AC — единственный получатель, у которого пересечение с введённым числом
    # видно данными: у прибавки есть тип. И с задачи 3.91 пересечения нет:
    # фит с вещи даёт +2 природного, вписано тоже 2 — в число идут ОБА,
    # «АЦ с фитов всегда стакаются все» (Dan, 25.08.2026).
    #
    # ⚠️ ИСТОРИЯ этой строки — сама по себе урок, её переписывали дважды.
    # Сперва `+4` с оговоркой `{:not_modelled, :ac_same_type_stacking}`
    # («складываем, а игра, кажется, нет»); потом задача 3.39 сделала из
    # оговорки правило и число стало `+2`; теперь снова `+4`, но уже без
    # оговорки — не потому, что вернулись к началу, а потому что владелец
    # назвал правило прямо. Разница между первой и третьей редакцией не в
    # числе, а в том, что за третьей стоит ответ, а за первой стояла догадка.
    test "AC одного типа с введённым числом складывается", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 6))
      gear = Gear.new(feats: [:armor_skin], ac: %{natural: 2})
      stats = Rules.compute(%Build{base | gear: gear}, ruleset)

      assert stats.ac_geared == Rules.compute(base, ruleset).ac_geared + 4

      # Вписанное доехало целиком, и терять из него нечего — значит и говорить
      # не о чем: ни «перебито», ни «базу не отделить».
      assert stats.ac_by_type[:natural] == 2
      assert stats.ac_superseded_types == []
      refute {:not_modelled, {:ac_gear_base, :natural}} in stats.gaps
    end
  end

  describe "объявить можно не всё" do
    test "неизвестный фит и отключённый шардом отказываются", %{ruleset: ruleset} do
      assert Rules.validate_gear_feat(:not_a_feat, ruleset) ==
               {:error, [{:unknown_feat, :not_a_feat}]}

      assert Rules.validate_gear_feat(:devastating_critical, ruleset) ==
               {:error, [{:feat_disabled, :devastating_critical}]}

      assert Rules.validate_gear_feat(:alertness, ruleset) == :ok
    end

    # Ссылка, написанная до того, как шард отключил фит, не должна читаться
    # как законная: объявление сохраняется, но требований не выполняет
    # и называется в `illegal_gear_feats/2`.
    test "отключённый фит не выполняет требований и назван нелегальным", %{ruleset: ruleset} do
      declared = build(List.duplicate(:fighter, 6)) |> with_feats([:devastating_critical])

      refute MapSet.member?(Build.feats_owned(declared, ruleset, 6), :devastating_critical)

      assert Rules.illegal_gear_feats(declared, ruleset) == [
               {:devastating_critical, {:feat_disabled, :devastating_critical}}
             ]

      assert Rules.illegal_gear_feats(build([:fighter]), ruleset) == []
    end

    # Требования САМОГО фита не проверяются: предмет даёт то, что даёт.
    # `Epic prowess` требует 21-го уровня, и надетым он работает на первом.
    test "свои требования у объявленного фита не проверяются", %{ruleset: ruleset} do
      first = build([:fighter]) |> with_feats([:epic_prowess])

      assert Rules.validate_gear_feat(:epic_prowess, ruleset) == :ok
      assert Rules.compute(first, ruleset).own_attack_bonus == 1

      # Слотом на 1-м уровне его при этом по-прежнему не взять.
      assert {:error, reasons} = Rules.validate_feat(build([:fighter]), :epic_prowess, ruleset)
      assert {:requires_character_level, 21} in reasons
    end
  end

  describe "оговорка про значение" do
    test "у фита с параметром объявление говорит, что значения не знает", %{ruleset: ruleset} do
      stats =
        build(List.duplicate(:fighter, 6))
        |> with_feats([:weapon_focus])
        |> Rules.compute(ruleset)

      assert {:not_modelled, {:gear_feat_choice, :weapon_focus}} in stats.gaps
    end

    test "у фита без параметра оговорки нет", %{ruleset: ruleset} do
      stats =
        build(List.duplicate(:fighter, 6))
        |> with_feats([:alertness])
        |> Rules.compute(ruleset)

      refute Enum.any?(stats.gaps, &match?({:not_modelled, {:gear_feat_choice, _}}, &1))
    end

    # Обратная сторона оговорки, названная в `Rules.GearFeats`: требование
    # «в той же школе» объявлением не выполняется.
    #
    # ⚠️ Здесь стояло «и в этом нет ошибки — значения просто нет». С задачи 3.97
    # значение бывает, и ответ от этого не сдвинулся ни на букву: дело не
    # в отсутствии значения, а в замере H7 — фит с вещи не открывает
    # пререквизит другого фита ВООБЩЕ. Обе половины под одним тестом, потому
    # что поодиночке каждая зеленела бы и при неверной модели.
    test "same_choice_as объявлением не выполняется", %{ruleset: ruleset} do
      declared =
        build(List.duplicate(:wizard, 10), feats: %{})
        |> with_feats([:spell_focus])

      # Голое требование `feats: [spell_focus]` выполнено...
      assert MapSet.member?(Build.feats_owned(declared, ruleset, 10), :spell_focus)

      # ...а школу предложить нечем, и причина называет требуемый фит.
      assert {:empty, [{:choice_requires, :greater_spell_focus, [:spell_focus], _domain}]} =
               Rules.feat_choice_candidates(declared, :greater_spell_focus, ruleset)

      # ⚠️ И с НАЗВАННОЙ школой ответ тот же — граница H7 стоит на месте.
      named =
        build(List.duplicate(:wizard, 10), feats: %{})
        |> with_feats([{:spell_focus, :evocation}])

      assert {:empty, [{:choice_requires, :greater_spell_focus, [:spell_focus], _domain}]} =
               Rules.feat_choice_candidates(named, :greater_spell_focus, ruleset)

      assert Rules.validate_feat(named, :greater_spell_focus, ruleset) ==
               {:error, [{:requires_feat, :spell_focus}]}

      # Положительный контроль: та же школа СЛОТОМ открывает фит. Без него
      # проверка выше зеленела бы и на модели, которая ломает `same_choice_as`
      # всем подряд.
      picked =
        build(List.duplicate(:wizard, 10), feats: %{1 => %{general: {:spell_focus, :evocation}}})

      assert Rules.validate_feat(picked, :greater_spell_focus, ruleset) == :ok
    end
  end

  # --------------------------------------------------------------------------
  # У оговорки про значение есть получатель — задача 3.98
  # --------------------------------------------------------------------------
  #
  # Оговорка «вещь не сказала, с каким значением взят фит» верна ровно тогда,
  # когда неназванное значение стоит числа, которое мы печатаем (CLAUDE.md §9,
  # решение Dan 10.08.2026: гэп — дырка в нашем ОТВЕТЕ, а не в наших знаниях).
  # До правки её получал ЛЮБОЙ фит с доменом: десять из пятнадцати на
  # `siala_41` признавались в незнании школы, которая двигает ДЦ чужого
  # спасброска, оружия, которое двигает крит-диапазон, и стихии, которая
  # двигает сопротивления, — то есть трёх механик, которых калькулятор
  # не считает и не собирался.
  #
  # 🔴 Расхождение было ВИДНО НА ОДНОМ ЭКРАНЕ: тот же фит, взятый слотом,
  # замолчал с задачи 3.93 — того же дня, коммитом раньше. Спрашивается тот же
  # механизм и тот же словарь — `GapReceivers.feat_effect_ours?/2`.

  describe "оговорка про значение спрашивает получателя" do
    # ⚠️ Фикстура СИНТЕТИЧЕСКАЯ, и это не вкус: живой носитель завтра получает
    # правку данных, и контроль молча перестаёт что-либо проверять — так за
    # неделю сгорело пять контролей подряд (уроки задач 3.93 и 3.85).
    defp choice_fixture(ruleset, label) do
      feats =
        Map.put(ruleset.feats, :fixture_choice_feat, %{
          id: :fixture_choice_feat,
          repeatable: %{choice: :fixture_domain}
        })

      receivers =
        case label do
          nil -> Map.delete(ruleset.feat_effect_receivers, :fixture_choice_feat)
          map -> Map.put(ruleset.feat_effect_receivers, :fixture_choice_feat, map)
        end

      ruleset |> Map.put(:feats, feats) |> Map.put(:feat_effect_receivers, receivers)
    end

    defp fixture_gaps(ruleset) do
      GearFeats.gaps(%Gear{feats: [:fixture_choice_feat]}, ruleset)
    end

    test "метки нет — оговорка остаётся", %{ruleset: ruleset} do
      assert fixture_gaps(choice_fixture(ruleset, nil)) ==
               [{:not_modelled, {:gear_feat_choice, :fixture_choice_feat}}]
    end

    test "метка пуста — оговорка остаётся", %{ruleset: ruleset} do
      assert fixture_gaps(choice_fixture(ruleset, %{"affects" => []})) ==
               [{:not_modelled, {:gear_feat_choice, :fixture_choice_feat}}]
    end

    test "получатель наш — оговорка остаётся", %{ruleset: ruleset} do
      assert fixture_gaps(choice_fixture(ruleset, %{"affects" => ["hp"]})) ==
               [{:not_modelled, {:gear_feat_choice, :fixture_choice_feat}}]
    end

    test "получатель не наш — оговорки нет", %{ruleset: ruleset} do
      assert fixture_gaps(choice_fixture(ruleset, %{"affects" => ["damage"]})) == []
    end

    # Правило `ours?/2` целиком: хватает ОДНОГО нашего получателя из скольких
    # угодно, и направление ошибки — в сторону показа.
    test "одного нашего получателя из двух хватает", %{ruleset: ruleset} do
      assert fixture_gaps(choice_fixture(ruleset, %{"affects" => ["damage", "hp"]})) ==
               [{:not_modelled, {:gear_feat_choice, :fixture_choice_feat}}]
    end

    # Решение владельца (`not_a_gap`, задача 3.95) едет тем же вызовом —
    # своей ветки ему не нужно. Получатель при этом остаётся НАШИМ: метка
    # называет механику, а не видимость.
    test "решение владельца not_a_gap гасит оговорку при нашем получателе", %{ruleset: ruleset} do
      decided =
        choice_fixture(ruleset, %{
          "affects" => ["hp"],
          "not_a_gap" => %{"who" => "фикстура", "status" => "verified"}
        })

      assert fixture_gaps(decided) == []
    end

    # Ruleset без словаря получателей не фильтрует ничего — `vanilla` живёт
    # именно так, и молчать он не имеет права.
    test "без словаря получателей не фильтруется ничего", %{ruleset: ruleset} do
      empty =
        ruleset
        |> choice_fixture(%{"affects" => ["damage"]})
        |> Map.put(:gap_receivers, %{our: MapSet.new(), not_our: MapSet.new()})

      assert fixture_gaps(empty) ==
               [{:not_modelled, {:gear_feat_choice, :fixture_choice_feat}}]
    end

    # Живая перепись, и она же — ответ на «сколько осталось». Пять из
    # пятнадцати, и все пять стоят числа:
    #
    #   * `Skill focus` +3 и `Epic skill focus` +10 — строка навыка
    #     (`vanilla/feat_skill_bonuses.json`, задача 3.92);
    #   * `Weapon focus` +1 и `Epic weapon focus` +2 — бросок атаки
    #     (`vanilla/feat_attack_bonuses.json`, задача 3.5 часть B);
    #   * `Weapon of choice` — вся колонка «AB bonus» Мастера оружия, потому
    #     что именно он назначает оружие, которым она считается.
    test "на живых данных остаются ровно пять", %{ruleset: ruleset} do
      surviving =
        for {id, _feat} <- ruleset.feats,
            not is_nil(Rules.FeatChoices.domain(id, ruleset)),
            GearFeats.gaps(%Gear{feats: [id]}, ruleset) != [],
            do: id

      assert Enum.sort(surviving) == [
               :epic_skill_focus,
               :epic_weapon_focus,
               :skill_focus,
               :weapon_focus,
               :weapon_of_choice
             ]
    end

    # 🔴 И вот почему `Weapon of choice` остался, хотя его собственная страница
    # говорит «This feat has no direct effect on game play»: он НАЗНАЧАЕТ
    # оружие, которым считается колонка класса, и без названного оружия
    # колонка не считается вовсе. Семь очков атаки у Мастера оружия 28.
    #
    # ⚠️ Это ровно тот случай, ради которого метка получателя у него НЕ
    # заведена: запись `affects: ["critical_hit"]` выглядела бы правдоподобно
    # (крит-диапазон он и правда назначает) и погасила бы оговорку про число,
    # которое игрок видит первым.
    test "Weapon of choice без названного оружия стоит семи очков атаки", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 13) ++ List.duplicate(:weapon_master, 28)

      with_gear = fn feats ->
        %Build{build(levels) | gear: %Gear{feats: feats, weapon: :longsword}}
      end

      bare = with_gear.([:siala_blade_proficiency, :weapon_of_choice])
      named = with_gear.([:siala_blade_proficiency, {:weapon_of_choice, :longsword}])

      assert Rules.compute(named, ruleset).attack_bonus ==
               Rules.compute(bare, ruleset).attack_bonus + 7

      assert {:not_modelled, {:gear_feat_choice, :weapon_of_choice}} in Rules.compute(
               bare,
               ruleset
             ).gaps

      refute {:not_modelled, {:gear_feat_choice, :weapon_of_choice}} in Rules.compute(
               named,
               ruleset
             ).gaps
    end

    # Ваниль словаря получателей не имеет вовсе (`VANILLA_SPLIT` §7.7.5),
    # поэтому фильтрует там только решение владельца — и ровно одна запись
    # его несёт.
    test "на ванили гасится ровно одна запись, и решением, а не меткой" do
      vanilla = Data.ruleset!("vanilla")
      assert MapSet.size(Rules.GapReceivers.our(vanilla)) == 0

      silent =
        for {id, _feat} <- vanilla.feats,
            not is_nil(Rules.FeatChoices.domain(id, vanilla)),
            GearFeats.gaps(%Gear{feats: [id]}, vanilla) == [],
            do: id

      assert silent == [:favored_enemy]
      assert is_map(vanilla.feat_effect_receivers[:favored_enemy]["not_a_gap"])
    end
  end

  # --------------------------------------------------------------------------
  # Оговорки про сам фит: объявление молчало там, где слот говорил (14.08.2026)
  # --------------------------------------------------------------------------
  #
  # Правило одной строкой: **оговорка про то, ЧТО фит делает, следует за фитом;
  # оговорка про то, КАК его получают, следует за слотом.** Эффект фита с вещи
  # считается («если фит есть, допустим тафнес, то и HP будут увеличены», Dan
  # 09.08.2026) — значит утверждение «а вот этого мы не посчитали» объявившему
  # нужно ровно так же, как взявшему. Требования же у объявленного фита не
  # проверяются вовсе, и предупреждать о непроверенном требовании — значит
  # предупреждать о том, чего не происходит.

  describe "прибавка, которую не считает ни один файл разметки" do
    # `Favored enemy` — повторяемый, и его прибавка (+1 к трём навыкам против
    # избранного врага) ни одним файлом разметки не посчитана. До правки
    # оговорку получал только взявший слотом: `FeatChoices.gaps/3` ходила
    # по `feats_taken/2`.
    #
    # ⚠️ Пример менялся дважды. 25.08.2026 (3.93) выбыл `Self concealment` —
    # его эффект маскировка, механика вне нашего ответа. В тот же день (3.95)
    # оговорку потерял и `Favored enemy`, уже по другой причине: прибавка
    # падает в наше число, но узка по условию, а описание фита называет и то,
    # и другое лучше нас.
    #
    # 🔴 После 3.95 живых носителей этой оговорки не осталось ни одного, и
    # ruleset тут — с СОЗНАТЕЛЬНО снятым решением по одному фиту. Проверяемое
    # свойство от этого не пострадало ни на букву: оно про МАРШРУТ (объявление
    # против слота), а не про конкретный фит. Первая строка не даёт контролю
    # выродиться в пустой: снимаемое решение обязано существовать.
    test "объявление говорит то же, что и слот", %{ruleset: ruleset} do
      assert Map.has_key?(ruleset.feat_effect_receivers, :favored_enemy)
      talkative = Map.update!(ruleset, :feat_effect_receivers, &Map.delete(&1, :favored_enemy))

      worn =
        build(List.duplicate(:fighter, 10))
        |> with_feats([:favored_enemy])
        |> Rules.compute(talkative)

      picked =
        build(List.duplicate(:fighter, 10), feats: %{1 => %{general: :favored_enemy}})
        |> Rules.compute(talkative)

      assert {:not_modelled, {:feat_bonus, :favored_enemy}} in worn.gaps
      assert {:not_modelled, {:feat_bonus, :favored_enemy}} in picked.gaps

      # И оба маршрута молчат ОДИНАКОВО на живых данных — оговорка снята
      # у фита, а не у одного из двух путей.
      for rs_stats <- [
            build(List.duplicate(:fighter, 10)) |> with_feats([:favored_enemy]),
            build(List.duplicate(:fighter, 10), feats: %{1 => %{general: :favored_enemy}})
          ] do
        refute {:not_modelled, {:feat_bonus, :favored_enemy}} in Rules.compute(rs_stats, ruleset).gaps
      end
    end

    # Отрицательный контроль, и он же — та самая ошибка, которой оговорка
    # обязана избегать: у `Epic toughness` прибавка посчитана и НАЗВАНА термом
    # в разборе HP, поэтому «в статы не считаем» спорило бы с числом на экране.
    test "у посчитанной прибавки оговорки нет ни на одном пути", %{ruleset: ruleset} do
      worn =
        build(List.duplicate(:fighter, 21))
        |> with_feats([:epic_toughness])
        |> Rules.compute(ruleset)

      refute {:not_modelled, {:feat_bonus, :epic_toughness}} in worn.gaps
    end

    # ⚠️ Ruleset со снятым решением по одному фиту — по той же причине, что
    # в тесте выше (задача 3.95): без него вопрос «сколько раз про один факт»
    # проверялся бы на нуле, где один и два неразличимы.
    test "фит, взятый и слотом и вещью, говорит своё один раз", %{ruleset: ruleset} do
      assert Map.has_key?(ruleset.feat_effect_receivers, :favored_enemy)
      talkative = Map.update!(ruleset, :feat_effect_receivers, &Map.delete(&1, :favored_enemy))

      stats =
        build(List.duplicate(:fighter, 10), feats: %{1 => %{general: :favored_enemy}})
        |> with_feats([:favored_enemy])
        |> Rules.compute(talkative)

      assert Enum.count(stats.gaps, &(&1 == {:not_modelled, {:feat_bonus, :favored_enemy}})) ==
               1
    end

    # ⚠️ И третий вид ответа, заведённый задачей 3.93: фит, чей эффект вообще
    # не падает ни в одно наше число, молчит НА ОБОИХ маршрутах. Без этой
    # строки правка выглядела бы как «оговорка исчезла у объявления», а она
    # исчезла у фита — и одинаково.
    test "у фита, чью механику мы не считаем вовсе, оговорки нет ни на одном пути", %{
      ruleset: ruleset
    } do
      worn =
        build(List.duplicate(:fighter, 10))
        |> with_feats([:self_concealment])
        |> Rules.compute(ruleset)

      picked =
        build(List.duplicate(:fighter, 10), feats: %{1 => %{general: :self_concealment}})
        |> Rules.compute(ruleset)

      refute {:not_modelled, {:feat_bonus, :self_concealment}} in worn.gaps
      refute {:not_modelled, {:feat_bonus, :self_concealment}} in picked.gaps
    end
  end

  # Синтетический факт вместо правки `priv/` — вопрос «как код читает метку»
  # решается формой факта, а не составом файла шарда (тот же приём, что
  # в `gap_receivers_test.exs`).
  defp with_fact(ruleset, feat_id, affects) do
    put_in(ruleset, [:feats, feat_id, :siala_unapplied], [
      %{"what" => "siala_note", "affects" => affects}
    ])
  end

  defp feat_change_gaps(stats, feat_id) do
    for {:not_modelled, {:feat_change, ^feat_id, what}} <- stats.gaps, do: what
  end

  describe "неприменённые правки шарда у объявленного фита" do
    # ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: получатель наш и не про доступность — объявившему
    # говорим то же, что взявшему слотом. Сегодня на реальных данных такого
    # факта у фитов нет ни одного (все 21 — про урон, длительность, иммунитеты
    # и умения без числа), поэтому механизм проверяется синтетикой.
    #
    # ⚠️ Здесь стояло «кроме одного про доступность» — это устарело 17.08.2026
    # вместе с гэпом `Improved evasion` (тест ниже): фактов с `feat_availability`
    # на слое фитов не осталось вовсе, и синтетика — единственное покрытие
    # обоих контролей, а не подстраховка к живому примеру.
    test "факт про НАШЕ число доезжает обоими путями", %{ruleset: ruleset} do
      ruleset = with_fact(ruleset, :alertness, ["hp"])

      worn =
        build(List.duplicate(:fighter, 10))
        |> with_feats([:alertness])
        |> Rules.compute(ruleset)

      picked =
        build(List.duplicate(:fighter, 10), feats: %{1 => %{general: :alertness}})
        |> Rules.compute(ruleset)

      assert feat_change_gaps(worn, :alertness) == ["siala_note"]
      assert feat_change_gaps(picked, :alertness) == ["siala_note"]
    end

    # ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ, и это не «просто не наш получатель»: `feat_availability`
    # как раз НАШ. Он про то, ПРЕДЛОЖИТ ли конструктор фит в слоте — а фит с вещи
    # никто не предлагает, его пререквизиты не проверяются вовсе. Молчание здесь
    # и есть правильный ответ.
    test "факт про доступность фита объявившему не говорится", %{ruleset: ruleset} do
      ruleset = with_fact(ruleset, :alertness, ["feat_availability"])

      worn =
        build(List.duplicate(:fighter, 10))
        |> with_feats([:alertness])
        |> Rules.compute(ruleset)

      picked =
        build(List.duplicate(:fighter, 10), feats: %{1 => %{general: :alertness}})
        |> Rules.compute(ruleset)

      assert feat_change_gaps(worn, :alertness) == []
      assert feat_change_gaps(picked, :alertness) == ["siala_note"]
    end

    # ⚠️ Здесь стоял тест «Improved evasion: слот говорит, вещь молчит» — тот же
    # контраст на РЕАЛЬНЫХ данных, потому что этот фит был единственным, чей
    # факт переживал фильтр получателей. **17.08.2026 он перестал им быть**
    # (решение Dan: «правила железные и измеряны», после замера H9), и живого
    # примера у механизма больше нет ни одного.
    #
    # Тест не удалён, а перевёрнут в тишину, и это не формальность: он ловит
    # возврат гэпа с той стороны, с которой его никто не ждёт — со стороны
    # БИЛДА. `ruleset.gaps` считает факт один раз на корпус, а здесь два билда,
    # и молчать обязаны оба.
    test "Improved evasion молчит обоими путями — и слотом, и с вещи",
         %{ruleset: ruleset} do
      worn =
        build(List.duplicate(:rogue, 10))
        |> with_feats([:improved_evasion])
        |> Rules.compute(ruleset)

      picked =
        build(List.duplicate(:rogue, 36),
          feats: %{36 => %{{:class_bonus, :rogue} => :improved_evasion}}
        )
        |> Rules.compute(ruleset)

      assert feat_change_gaps(worn, :improved_evasion) == []
      assert feat_change_gaps(picked, :improved_evasion) == []
    end

    # ⚠️ Обратная сторона того же правила, названная отдельно, чтобы её не
    # «починили»: требования у объявленного фита не проверяются, значит и
    # оговорка «часть требования схемой не выражается» ему не адресована.
    # ⚠️ Фит ИЩЕТСЯ, а не назван: до задачи 3.99 здесь стоял `weapon_focus`,
    # и он перестал нести оговорку — требование стало проверяемым. Какие фиты
    # несут оговорку, решают данные, и список id в тесте протухает молча.
    test "непроверяемое требование объявившему не говорится", %{ruleset: ruleset} do
      feat =
        ruleset.feats
        |> Map.keys()
        |> Enum.sort()
        |> Enum.find(fn id ->
          Rules.feat_caveats(id, ruleset) != [] and not ruleset.feats[id].disabled?
        end)

      refute is_nil(feat), "в ruleset'е не осталось фита с оговоркой — тест проверять нечем"

      worn =
        build(List.duplicate(:fighter, 30))
        |> with_feats([feat])
        |> Rules.compute(ruleset)

      picked =
        build(List.duplicate(:fighter, 30), feats: %{21 => %{general: feat}})
        |> Rules.compute(ruleset)

      refute Enum.any?(worn.gaps, &match?({:not_modelled, {:feat_qualifier, ^feat, _}}, &1))
      assert Enum.any?(picked.gaps, &match?({:not_modelled, {:feat_qualifier, ^feat, _}}, &1))
    end
  end

  # ⚠️ Волна 14 (09.08.2026) сделала это правилом из данных. Раньше отказ был
  # верен СЛУЧАЙНО: у обоих фитов `type: "special"`, а у сиального фита слот
  # читается по блоку «Возможность взятия фита», которого на их страницах нет —
  # то есть совпало «страница не сказала» с «нельзя». Замерено до правки:
  # `FeatSlots.accepts?/3` отвечал `false` на всех слотах, а
  # `validate_feat_pick/3` — `:ok`, и в списке фитов причиной стояло
  # `{:not_slottable, "special"}`, то есть «выдаётся классом или расой», чего
  # страница не говорит вовсе.
  describe "фиты, которые ИНАЧЕ как с вещи не берутся" do
    @unpickable [:riding_sprint, :smile_of_death]

    test "ни один слот их не принимает", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21))

      for feat <- @unpickable, level <- [1, 21] do
        slots = FeatSlots.at(base, ruleset, level)
        assert slots != []
        refute Enum.any?(slots, &FeatSlots.accepts?(ruleset, &1, feat))
      end

      # Положительный контроль: тот же слот на том же билде принимает фит,
      # который брать МОЖНО, — иначе `refute` выше зеленел бы и на сломанном
      # вызове.
      assert Enum.any?(
               FeatSlots.at(base, ruleset, 21),
               &FeatSlots.accepts?(ruleset, &1, :epic_toughness)
             )
    end

    # Причина названа, и она третья по счёту — не `feat_disabled` (фит работает)
    # и не `forbidden_by_class` (виноват не класс). Спрашивается у ядра в обеих
    # точках: и «может ли персонаж», и «можно ли положить в слот».
    test "отказ называет себя, а не молчит и не врёт", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21))

      for feat <- @unpickable, level <- [3, 21] do
        expected = {:error, [{:not_selectable_at_level_up, feat}]}

        assert Rules.validate_feat(base, %{feat: feat, at: level}, ruleset) == expected
        assert Rules.validate_feat_pick(base, %{feat: feat, at: level}, ruleset) == expected

        assert Rules.feat_level_up_refusals(feat, ruleset) == [
                 {:not_selectable_at_level_up, feat}
               ]
      end

      # Отрицательный контроль: обычный фит этой причины не получает.
      assert Rules.feat_level_up_refusals(:power_attack, ruleset) == []
    end

    # ⚠️ Главное, ради чего завели данные: правило НЕ держится на типе фита.
    # Ruleset правится в памяти — `type` становится "general", как у пяти
    # сиальских владений оружием, которые блок «Возможность взятия фита» несут
    # и берутся нормально. До волны 14 такой фит стал бы выбираемым молча.
    test "правило лежит в данных, а не в типе фита", %{ruleset: ruleset} do
      base = build(List.duplicate(:fighter, 21))
      slot = %{id: :general, kind: :epic_general, class: nil, taken_with: :fighter, epic?: true}

      for feat <- @unpickable do
        retyped = put_in(ruleset.feats[feat].type, "general")

        # Тип действительно поменялся — сторож против опечатки в самом тесте.
        assert retyped.feats[feat].type == "general"
        assert retyped.feats[feat].level_up_selectable? == false

        refute FeatSlots.accepts?(retyped, slot, feat)

        assert Rules.validate_feat(base, %{feat: feat, at: 21}, retyped) ==
                 {:error, [{:not_selectable_at_level_up, feat}]}
      end

      # И обратная порча: снять флаг в данных — фит становится выбираемым.
      # Без этой половины тест зеленел бы и на «отказываем всегда и всем».
      freed = put_in(ruleset.feats[:riding_sprint].level_up_selectable?, true)
      freed = put_in(freed.feats[:riding_sprint].type, "general")

      assert FeatSlots.accepts?(freed, slot, :riding_sprint)
      assert Rules.validate_feat(base, %{feat: :riding_sprint, at: 21}, freed) == :ok
    end

    # Уже сохранённая ссылка с таким фитом в слоте перестаёт читаться как
    # законная — тот же контракт «проиграть то, что уже в билде», что у
    # `illegal_feats/2` вообще.
    test "билд, у которого фит лежит в слоте, назван нелегальным", %{ruleset: ruleset} do
      bad =
        build(List.duplicate(:fighter, 3))
        |> Build.put_feat(1, :general, :riding_sprint)

      assert Rules.illegal_feats(bad, ruleset) ==
               [{1, :general, :riding_sprint, {:not_selectable_at_level_up, :riding_sprint}}]

      assert Rules.illegal_feats(build(List.duplicate(:fighter, 3)), ruleset) == []
    end

    test "через вещь персонаж их получает", %{ruleset: ruleset} do
      declared = build(List.duplicate(:fighter, 6)) |> with_feats([:riding_sprint])

      assert Rules.validate_gear_feat(:riding_sprint, ruleset) == :ok
      assert MapSet.member?(Build.feats_owned(declared, ruleset, 6), :riding_sprint)
    end

    # ⚠️ И запрет на выбор НЕ должен протечь в объявление: это единственный
    # путь такого фита в билд, и закрыть его значило бы сделать фит
    # недостижимым вовсе.
    test "запрет не задевает объявление с вещи", %{ruleset: ruleset} do
      for feat <- @unpickable do
        assert Rules.validate_gear_feat(feat, ruleset) == :ok
      end

      # Отрицательный контроль: выключенный шардом фит объявить всё равно нельзя,
      # то есть проверка объявления не превратилась в «разрешено всё».
      assert Rules.validate_gear_feat(:devastating_critical, ruleset) ==
               {:error, [{:feat_disabled, :devastating_critical}]}
    end

    # Сплошной поиск по всем 66 страницам категории «Фиты» в кэше Сиалы
    # (09.08.2026) нашёл фразу «нельзя выбрать при росте персонажа» ровно
    # у этих двух. Сторож на случай, если разметку заведут третьему фиту
    # и забудут про тесты, — и на случай, если её у кого-то снимут.
    test "во всём ruleset'е таких фитов ровно два", %{ruleset: ruleset} do
      unpickable =
        for {id, feat} <- ruleset.feats, feat.level_up_selectable? == false, do: id

      assert Enum.sort(unpickable) == @unpickable
    end
  end

  # --------------------------------------------------------------------------
  # Значение у объявления — задача 3.97 (решение Dan, 25.08.2026)
  # --------------------------------------------------------------------------
  #
  # «Подобный фит не может существовать без привязки к конкретному выбору.
  # skill_focus всегда привязывается к одному из навыков и дает 3 к данному
  # конкретному навыку, а weapon focus привязывается к конкретному оружию
  # и дает с ним +1 АБ.»
  #
  # ⚠️ Это ПЕРЕСМОТР решения «объявление параметра не несёт», и посылка под ним
  # снялась дважды: задача 3.5 дала домену `weapon` словарь и оружие в руках,
  # задача 3.92 научила ядро считать +3 и +10 у фокусов на навык. До 3.92
  # терять было нечего — прибавка не считалась ни по одному маршруту.
  #
  # Источники чисел:
  #   * `Skill focus` +3 — `vanilla/feat_skill_bonuses.json`
  #     (`fandom:Skill focus`, revid 72101);
  #   * `Epic skill focus` +10 — там же (`fandom:Epic skill focus`, revid 72105);
  #   * `Weapon focus` +1 к атаке — `vanilla/feat_attack_bonuses.json`
  #     (`fandom:Weapon focus`, revid 70066).

  describe "значение у объявления считается" do
    # 44 ранга Discipline у воина 41 (классовый, потолок «уровень + 3»), STR 10,
    # то есть модификатор ноль: в числе не спрятано ничего, кроме рангов и
    # прибавок фитов.
    defp discipline_build(feats) do
      ranks =
        for level <- 1..41, into: %{} do
          {level, if(level == 1, do: %{discipline: 4}, else: %{discipline: 1})}
        end

      List.duplicate(:fighter, 41)
      |> build(skills: ranks, base_abilities: %{@abilities | str: 10})
      |> with_feats(feats)
    end

    defp skill_row(build, ruleset, skill) do
      build |> Rules.compute(ruleset) |> Map.fetch!(:skill_values) |> Map.get(skill)
    end

    defp choice_gaps(build, ruleset) do
      build
      |> Rules.compute(ruleset)
      |> Map.fetch!(:gaps)
      |> Enum.filter(&match?({:not_modelled, {:gear_feat_choice, _}}, &1))
    end

    test "Skill focus и Epic skill focus с вещи дают +3 и +10", %{ruleset: ruleset} do
      named =
        discipline_build([{:skill_focus, :discipline}, {:epic_skill_focus, :discipline}])

      assert %{ranks: 44, feat_bonus: 13, total: 57} = skill_row(named, ruleset, :discipline)

      # И оговорка снята — не вычёркиванием, а тем, что игрок навык назвал.
      assert choice_gaps(named, ruleset) == []
    end

    # Отрицательный контроль, и он же — вся обратная совместимость: ссылка,
    # выпущенная до задачи 3.97, несёт голые id, считается ровно как считалась
    # и по-прежнему говорит, чего не знает.
    test "то же объявление без значения не даёт ничего и говорит об этом", %{ruleset: ruleset} do
      bare = discipline_build([:skill_focus, :epic_skill_focus])

      assert %{ranks: 44, feat_bonus: 0, total: 44} = skill_row(bare, ruleset, :discipline)

      assert choice_gaps(bare, ruleset) == [
               {:not_modelled, {:gear_feat_choice, :epic_skill_focus}},
               {:not_modelled, {:gear_feat_choice, :skill_focus}}
             ]
    end

    # Решение Dan: «разные значения — разные записи». Два предмета с одним
    # фитом на разные навыки — две прибавки, а не одна.
    test "два Skill focus на разные навыки дают обе прибавки", %{ruleset: ruleset} do
      ranks =
        for level <- 1..41, into: %{} do
          {level, if(level == 1, do: %{discipline: 4, spot: 2}, else: %{discipline: 1})}
        end

      two =
        List.duplicate(:fighter, 41)
        |> build(skills: ranks, base_abilities: %{@abilities | str: 10, wis: 10})
        |> with_feats([{:skill_focus, :discipline}, {:skill_focus, :spot}])

      assert %{feat_bonus: 3, total: 47} = skill_row(two, ruleset, :discipline)
      assert %{feat_bonus: 3, total: 5} = skill_row(two, ruleset, :spot)
    end

    # Оружие в руках — то же правило с другой стороны: `Weapon focus` считается
    # только тем оружием, которое он назвал. Владение объявлено с вещи же,
    # иначе клинок в руке отбивается (`Rules.GearWeapon`) и записи не с чем
    # сравнивать.
    test "Weapon focus с вещи считается названным оружием", %{ruleset: ruleset} do
      with_weapon = fn feats ->
        gear = %Gear{feats: feats, weapon: :longsword}
        %Build{build(List.duplicate(:fighter, 41)) | gear: gear}
      end

      naked = Rules.compute(with_weapon.([:siala_blade_proficiency]), ruleset)

      named =
        Rules.compute(
          with_weapon.([:siala_blade_proficiency, {:weapon_focus, :longsword}]),
          ruleset
        )

      assert named.attack_bonus == naked.attack_bonus + 1

      # Обе оговорки ушли, и вторая — не наша: `{:attack_bonus_weapon, …}`
      # говорит «оружие в руках не назвали», а его назвали.
      assert Enum.filter(named.gaps, &match?({:not_modelled, {:gear_feat_choice, _}}, &1)) == []

      assert Enum.filter(named.gaps, &match?({:not_modelled, {:attack_bonus_weapon, _}}, &1)) ==
               []
    end

    test "Weapon focus на ДРУГОЕ оружие атаку не поднимает", %{ruleset: ruleset} do
      gear = %Gear{
        feats: [:siala_blade_proficiency, {:weapon_focus, :scimitar}],
        weapon: :longsword
      }

      other = %Build{build(List.duplicate(:fighter, 41)) | gear: gear}

      naked = %Build{
        build(List.duplicate(:fighter, 41))
        | gear: %Gear{feats: [:siala_blade_proficiency], weapon: :longsword}
      }

      assert Rules.compute(other, ruleset).attack_bonus ==
               Rules.compute(naked, ruleset).attack_bonus
    end

    # Маршруты сошлись: до правки объявление говорило «значения не знаем» там,
    # где слот молчал, — при одинаковом знании о персонаже.
    #
    # ⚠️ Здесь СТОЯЛО обратное — что голое объявление этих трёх фитов оговорку
    # даёт, — и тест был зелёным ровно потому, что расхождение и было. 3.97
    # свела маршруты у объявления СО ЗНАЧЕНИЕМ, 3.98 — у голого.
    test "у объявления со значением тех же оговорок, что у слота, нет", %{ruleset: ruleset} do
      for {id, value} <- [
            {:spell_focus, :evocation},
            {:arcane_defense, :evocation},
            {:favored_enemy, :goblinoid}
          ] do
        bare = build(List.duplicate(:fighter, 6)) |> with_feats([id])
        named = build(List.duplicate(:fighter, 6)) |> with_feats([{id, value}])

        assert choice_gaps(bare, ruleset) == []
        assert choice_gaps(named, ruleset) == []
      end
    end

    # ⚠️ Граница `feats_owned/3` ↔ `feats_permanent/3` на уровне ЗНАЧЕНИЙ —
    # ровно та же и по тому же замеру (H7). Проверяется обеими сторонами:
    # эффект видит вещь, требование другого фита — нет.
    test "feat_choices_owned видит вещь, feat_choices_permanent — нет", %{ruleset: ruleset} do
      declared =
        build(List.duplicate(:wizard, 10), feats: %{})
        |> with_feats([{:spell_focus, :evocation}])

      assert Build.feat_choices_owned(declared, ruleset, :spell_focus, 10) == [:evocation]
      assert Build.feat_choices_permanent(declared, ruleset, :spell_focus, 10) == []
    end
  end

  describe "хранение объявлений" do
    test "toggle_feat добавляет и снимает" do
      gear = Gear.toggle_feat(%Gear{}, :toughness)
      assert gear.feats == [:toughness]

      # Тот же фит вторым кликом снимается, а не удваивается.
      assert Gear.toggle_feat(gear, :toughness).feats == []
    end

    # Уникальность по ПАРЕ, а не по id (решение Dan, 25.08.2026): два предмета
    # с одним фитом на разные значения — две записи, и снимается ровно та,
    # по которой кликнули.
    test "toggle_feat со значением работает парой" do
      gear =
        %Gear{}
        |> Gear.toggle_feat(:skill_focus, :discipline)
        |> Gear.toggle_feat(:skill_focus, :spot)

      assert gear.feats == [skill_focus: :discipline, skill_focus: :spot]

      assert Gear.toggle_feat(gear, :skill_focus, :spot).feats == [skill_focus: :discipline]

      # ⚠️ Голый id — ТРЕТЬЕ состояние, а не «любая запись этого фита»: клик
      # по нему не снимает пару и не прячется за ней.
      assert Gear.toggle_feat(gear, :skill_focus).feats ==
               [:skill_focus, {:skill_focus, :discipline}, {:skill_focus, :spot}]
    end

    test "порядок кликов не влияет и на пары" do
      one =
        %Gear{} |> Gear.toggle_feat(:weapon_focus, :longsword) |> Gear.toggle_feat(:alertness)

      other =
        %Gear{} |> Gear.toggle_feat(:alertness) |> Gear.toggle_feat(:weapon_focus, :longsword)

      assert one.feats == other.feats
      assert one.feats == [:alertness, {:weapon_focus, :longsword}]
    end

    # ⚠️ Порядок кликов билд не хранит, а код в ссылке обязан быть у одного
    # билда одним — и декодер возвращает список отсортированным, так что
    # `decode(encode(b)) == b` держится только на этом. Проверяется именно
    # независимость от порядка: сравнение с литералом зеленело бы и на
    # реализации, которая просто дописывает в начало.
    test "два порядка кликов дают один и тот же список" do
      one = %Gear{} |> Gear.toggle_feat(:alertness) |> Gear.toggle_feat(:toughness)
      other = %Gear{} |> Gear.toggle_feat(:toughness) |> Gear.toggle_feat(:alertness)

      assert one.feats == other.feats
      assert one.feats == [:alertness, :toughness]
    end

    test "объявление считается заполненным блоком «Вещи»" do
      refute Gear.any?(%Gear{})
      assert Gear.any?(%Gear{feats: [:toughness]})
    end
  end
end
