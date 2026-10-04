defmodule BuildCalculator.Rules.FeatSlotPoolTest do
  @moduledoc """
  Задача 4.61: `Rules.validate_feat_pick/3` (и через него `Rules.illegal_feats/2`)
  спрашивает слот пика не только про значение, но и про его ПУЛ — и про то, даёт ли
  уровень такой слот вообще.

  Дыра, ради которой задача (находка 4.60, проверена координатором вызовом):
  Сиала перенесла `Brew potion` со списка бонусных фитов Волшебника на списки
  Друида и Арфиста (задача 4.49; источник — хак шарда, `cls_feat_wiz.2da` строка
  134, `cls_feat_druid.2da` строка 130, `cls_feat_harper.2da` строка 126, запись
  `siala_changes` фита в `priv/rules/siala_41/generated/feats.json`). Ссылка
  на волшебника 5 с Brew potion в его бонусном слоте, собранная до 4.49, —
  законный тогда билд — после неё читалась законной: `FeatSlots.accepts?/3`
  false, а `illegal_feats/2` пуст.

  Три ответа про слот, у каждого своя форма:

    * `{:not_in_slot_pool, slot_id}` — фит в каком-то пуле есть, но не в пуле
      этого слота (`FeatSlots.slot_refusals/3`);
    * `{:requires_character_level, n}` — пул слота фит держит, не хватает только
      эпичности персонажа (`n` = `ruleset.epic.starts_at`); рядом с тем же
      требованием из блока фита не повторяется;
    * `{:slot_not_granted, slot_id}` — уровень пика такого слота не даёт.

  Чего ответ НЕ повторяет — выключенный, невыбираемый, не берущийся ни одним
  слотом фит и запрет класса уровня: у них своя причина, сильнее и точнее
  (`describe "без дублей"` и сторож на всём справочнике ниже).

  🔴 Билды собраны по одному левелапу (`Rules.validate_level_up/3`), как их
  проходит игрок (CLAUDE.md §3), и каждый пик поставлен через
  `Rules.validate_feat_pick/3` — тот же вопрос, что задаёт конструктор. «Старая
  ссылка» — тот же ruleset с откатом ровно одной правки 4.49 в памяти
  (`before_4_49/1`), как в `builder_closed_feat_test.exs`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  # Brew potion до задачи 4.49 на Сиале: ванильный `bonus_for` — Волшебник
  # (`siala_changes` фита: `"from" => ["wizard"]`).
  defp before_4_49(siala), do: put_in(siala.feats[:brew_potion].bonus_for, MapSet.new([:wizard]))

  defp start(ruleset, race, alignment, abilities),
    do:
      Build.new(
        ruleset_version: ruleset.version,
        race: race,
        alignment: alignment,
        base_abilities: abilities
      )

  # Один левелап: класс проверен ядром до того, как взят, затем ранги этого
  # уровня, прибавка и пики — каждый пик тем вопросом, что задаёт конструктор.
  defp level_up(build, class, ruleset, opts) do
    level = Build.character_level(build) + 1

    assert Rules.validate_level_up(build, class, ruleset) == :ok,
           "#{class} на #{level}-м уровне отказан"

    build = Build.add_level(build, class)

    build =
      case Keyword.get(opts, :skills) do
        nil -> build
        ranks -> %Build{build | skills: Map.put(build.skills, level, ranks)}
      end

    build =
      case Keyword.get(opts, :increase) do
        nil ->
          build

        ability ->
          %Build{build | ability_increases: Map.put(build.ability_increases, level, ability)}
      end

    Enum.reduce(Keyword.get(opts, :feats, []), build, fn {slot, feat}, acc ->
      pick = %{feat: feat, at: level, slot: slot}

      assert Rules.validate_feat_pick(acc, pick, ruleset) == :ok,
             "#{feat} в #{inspect(slot)} на #{level}-м: " <>
               inspect(Rules.validate_feat_pick(acc, pick, ruleset))

      Build.put_feat(acc, level, slot, feat)
    end)
  end

  # Лестница одного класса; `per_level` — опции по номеру уровня персонажа.
  defp ladder(build, class, count, ruleset, per_level \\ %{}) do
    from = Build.character_level(build) + 1

    Enum.reduce(from..(from + count - 1)//1, build, fn level, acc ->
      level_up(acc, class, ruleset, Map.get(per_level, level, []))
    end)
  end

  defp slot!(build, ruleset, level, id) do
    case Enum.find(FeatSlots.at(build, ruleset, level), &(&1.id == id)) do
      nil -> flunk("на #{level}-м уровне нет слота #{inspect(id)}")
      slot -> slot
    end
  end

  # ------------------------------------------------- Brew potion (находка 4.60) --

  @wizard_abilities %{str: 8, dex: 14, con: 14, int: 18, wis: 10, cha: 8}

  # Человек волшебник 5, Lore 4 на 1-м (навык классовый, потолок 1-го уровня 4) —
  # требование Brew potion на Сиале («Знание (Lore) 4.»), у ванили — заклинатель 3.
  defp wizard_5(ruleset, picks_at_5) do
    ruleset
    |> start(:human, :true_neutral, @wizard_abilities)
    |> ladder(:wizard, 5, ruleset, %{1 => [skills: %{lore: 4}], 5 => [feats: picks_at_5]})
  end

  describe "Сиала: Brew potion в бонусном слоте волшебника — ссылка до 4.49" do
    test "по правилам до 4.49 законна, сегодня ядро называет пул слота", %{siala: siala} do
      old = before_4_49(siala)
      build = wizard_5(old, [{{:class_bonus, :wizard}, :brew_potion}])

      assert Rules.illegal_feats(build, old) == []

      slot = slot!(build, siala, 5, {:class_bonus, :wizard})
      refute FeatSlots.accepts?(siala, slot, :brew_potion)

      assert Rules.validate_feat_pick(
               build,
               %{feat: :brew_potion, at: 5, slot: {:class_bonus, :wizard}},
               siala
             ) == {:error, [{:not_in_slot_pool, {:class_bonus, :wizard}}]}

      assert Rules.illegal_feats(build, siala) == [
               {5, {:class_bonus, :wizard}, :brew_potion,
                {:not_in_slot_pool, {:class_bonus, :wizard}}}
             ]
    end

    test "тот же фит в общем слоте волшебника — законен", %{siala: siala} do
      build =
        siala
        |> start(:human, :true_neutral, @wizard_abilities)
        |> ladder(:wizard, 3, siala, %{
          1 => [skills: %{lore: 4}],
          3 => [feats: [{:general, :brew_potion}]]
        })

      assert Rules.illegal_feats(build, siala) == []
      assert FeatSlots.slot_refusals(siala, slot!(build, siala, 3, :general), :brew_potion) == []
    end

    test "друид на эпическом бонусном уровне — законен (бонусный список Друида)", %{
      siala: siala
    } do
      # Бонусные уровни Друида только эпические — 24, 28 … (`epic_bonus_feat_levels`).
      build =
        siala
        |> start(:human, :true_neutral, %{str: 10, dex: 14, con: 14, int: 12, wis: 18, cha: 8})
        |> ladder(:druid, 24, siala, %{
          1 => [skills: %{lore: 4}],
          24 => [feats: [{{:class_bonus, :druid}, :brew_potion}]]
        })

      assert slot!(build, siala, 24, {:class_bonus, :druid}).epic?
      assert Rules.illegal_feats(build, siala) == []
    end

    test "41-й уровень (бонусный фит Волшебника 4.51) — пул тот же, отказ тот же", %{
      siala: siala
    } do
      build =
        siala
        |> start(:human, :true_neutral, @wizard_abilities)
        |> ladder(:wizard, 41, siala, %{1 => [skills: %{lore: 4}]})
        |> Build.put_feat(41, {:class_bonus, :wizard}, :brew_potion)

      assert slot!(build, siala, 41, {:class_bonus, :wizard}).epic?

      assert Rules.illegal_feats(build, siala) == [
               {41, {:class_bonus, :wizard}, :brew_potion,
                {:not_in_slot_pool, {:class_bonus, :wizard}}}
             ]
    end
  end

  describe "ваниль: бонусный список Brew potion — Волшебник (`vanilla/feats.json`)" do
    test "волшебник 5 с Brew potion в бонусном слоте — законен", %{vanilla: vanilla} do
      build = wizard_5(vanilla, [{{:class_bonus, :wizard}, :brew_potion}])

      assert Rules.illegal_feats(build, vanilla) == []
    end

    test "друид 24 с Brew potion в бонусном слоте — пул Друида его не держит", %{
      vanilla: vanilla
    } do
      build =
        vanilla
        |> start(:human, :true_neutral, %{str: 10, dex: 14, con: 14, int: 12, wis: 18, cha: 8})
        |> ladder(:druid, 24, vanilla, %{1 => [skills: %{lore: 4}]})
        |> Build.put_feat(24, {:class_bonus, :druid}, :brew_potion)

      assert Rules.illegal_feats(build, vanilla) == [
               {24, {:class_bonus, :druid}, :brew_potion,
                {:not_in_slot_pool, {:class_bonus, :druid}}}
             ]
    end
  end

  # ---------------------------------------------- общий слот, бонусный фит --

  describe "фит только бонусного списка в общем слоте — `{:not_in_slot_pool, :general}`" do
    # Opportunist — бонусный фит Вора на 10/13/16/19 (`fandom:Rogue`, `type: class`):
    # в общем списке его нет ни у ванили, ни у Сиалы.
    for version <- ["siala_41", "vanilla"] do
      @version version

      test "вор 12, #{version}: бонусный слот на 10-м берёт, общий на 12-м — нет", context do
        ruleset = if @version == "vanilla", do: context.vanilla, else: context.siala

        build =
          ruleset
          |> start(:human, :true_neutral, %{str: 12, dex: 16, con: 14, int: 12, wis: 10, cha: 10})
          |> ladder(:rogue, 12, ruleset)

        bonus = %{feat: :opportunist, at: 10, slot: {:class_bonus, :rogue}}
        assert Rules.validate_feat_pick(build, bonus, ruleset) == :ok

        refute FeatSlots.accepts?(ruleset, slot!(build, ruleset, 12, :general), :opportunist)

        general = %{feat: :opportunist, at: 12, slot: :general}

        assert Rules.validate_feat_pick(build, general, ruleset) ==
                 {:error, [{:not_in_slot_pool, :general}]}
      end
    end
  end

  # ----------------------------------------- эпический фит в доэпическом слоте --

  describe "эпический фит в слоте персонажа, который не эпик — граница 20/21" do
    # Improved ki strike 4 — эпический фит без `character_level` в своём блоке
    # (`fandom:Improved ki strike 4`: монах 16, WIS 21, Ki strike), один из
    # семнадцати (Сиала) / шестнадцати (ваниль). Монах 18: WIS 18 + 4 прибавки = 22.
    defp monk(ruleset, levels, per_level) do
      increases = Map.new([4, 8, 12, 16, 20], &{&1, [increase: :wis]})

      ruleset
      |> start(:human, :lawful_neutral, %{str: 12, dex: 14, con: 12, int: 10, wis: 18, cha: 8})
      |> ladder(
        :monk,
        levels,
        ruleset,
        Map.merge(increases, per_level, fn _l, a, b -> a ++ b end)
      )
    end

    for version <- ["siala_41", "vanilla"] do
      @version version

      test "#{version}: монах 18, общий слот — нужен 21-й уровень; монах 21 — законен", context do
        ruleset = if @version == "vanilla", do: context.vanilla, else: context.siala
        epic_at = ruleset.epic.starts_at

        build = Build.put_feat(monk(ruleset, 18, %{}), 18, :general, :improved_ki_strike_4)

        assert Rules.validate_feat_pick(
                 build,
                 %{feat: :improved_ki_strike_4, at: 18, slot: :general},
                 ruleset
               ) == {:error, [{:requires_character_level, epic_at}]}

        epic = monk(ruleset, 21, %{21 => [feats: [{:general, :improved_ki_strike_4}]]})
        assert Rules.illegal_feats(epic, ruleset) == []
      end

      test "#{version}: эпический фит с уровнем в своём блоке — требование одно, не два",
           context do
        ruleset = if @version == "vanilla", do: context.vanilla, else: context.siala
        epic_at = ruleset.epic.starts_at

        # Great strength: `character_level 21` в блоке фита (`fandom:Great Strength`).
        build = Build.put_feat(monk(ruleset, 18, %{}), 18, :general, :great_strength)

        {:error, reasons} =
          Rules.validate_feat_pick(
            build,
            %{feat: :great_strength, at: 18, slot: :general},
            ruleset
          )

        assert Enum.filter(reasons, &match?({:requires_character_level, _}, &1)) ==
                 [{:requires_character_level, epic_at}]

        refute Enum.any?(reasons, &match?({:not_in_slot_pool, _}, &1))
      end
    end
  end

  describe "требование уровня из блока фита выше эпического порога — одно, а не два" do
    # ⚠️ Синтетика: у всех эпических фитов обоих ruleset'ов, где уровень записан
    # в блоке, он ровно 21 (43 на Сиале, 44 у ванили) — с ответом слота он
    # совпадает байт в байт и сливается `Enum.uniq`. Правило «требование выше
    # гасит ответ слота» держит запись, которой в данных пока нет: Great
    # strength с `character_level 24`.
    test "Great strength с уровнем 24 на 18-м — только «нужен 24-й»", %{siala: siala} do
      ruleset = put_in(siala.feats[:great_strength].prereqs["character_level"], 24)

      build =
        ruleset
        |> start(:human, :true_neutral, %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8})
        |> ladder(:fighter, 18, ruleset)
        |> Build.put_feat(18, :general, :great_strength)

      {:error, reasons} =
        Rules.validate_feat_pick(build, %{feat: :great_strength, at: 18, slot: :general}, ruleset)

      assert Enum.filter(reasons, &match?({:requires_character_level, _}, &1)) ==
               [{:requires_character_level, 24}]
    end
  end

  # ------------------------------------------------------- слот, которого нет --

  describe "уровень не даёт такого слота — `{:slot_not_granted, slot_id}`" do
    for version <- ["siala_41", "vanilla"] do
      @version version

      test "#{version}: расовый пик человека после смены расы", context do
        ruleset = if @version == "vanilla", do: context.vanilla, else: context.siala

        human =
          ruleset
          |> start(:human, :true_neutral, @wizard_abilities)
          |> level_up(:wizard, ruleset, feats: [{:racial, :dodge}])

        assert Rules.illegal_feats(human, ruleset) == []

        # Так расовый пик оставлял конструктор до задачи 4.62 (`pick_race` его
        # не чистил); с 4.62 его снимает воронка правок
        # (`Builder.LostPicks.prune/2`), а ядро называет по-прежнему — сторож.
        elf = %Build{human | race: :elf}

        assert FeatSlots.at(elf, ruleset, 1) |> Enum.map(& &1.id) == [:general]
        assert :dodge in Build.feats_taken(elf, 1)

        assert Rules.illegal_feats(elf, ruleset) == [
                 {1, :racial, :dodge, {:slot_not_granted, :racial}}
               ]
      end

      test "#{version}: смена класса раньше по лестнице перенумеровала бонусный уровень",
           context do
        ruleset = if @version == "vanilla", do: context.vanilla, else: context.siala

        # Бонусные уровни Воина — 1, 2, 4, 6 … его классовых (`fandom:Fighter`).
        fighter =
          ruleset
          |> start(:human, :true_neutral, %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8})
          |> ladder(:fighter, 4, ruleset, %{
            1 => [feats: [{{:class_bonus, :fighter}, :blind_fight}]],
            2 => [feats: [{{:class_bonus, :fighter}, :dodge}]],
            4 => [feats: [{{:class_bonus, :fighter}, :mobility}]]
          })

        assert Rules.illegal_feats(fighter, ruleset) == []

        # Уровень 1 → волшебник, как его менял конструктор до задачи 4.62:
        # `replace_level` и чистка слотов ТОЛЬКО правленого уровня (`prune_slots/3`,
        # с 4.62 снят — воронка чистит все уровни, `Builder.LostPicks.prune/2`).
        edited = Build.replace_level(fighter, 1, :wizard)

        edited = %Build{
          edited
          | feats: Map.update!(edited.feats, 1, &Map.delete(&1, {:class_bonus, :fighter}))
        }

        # 4-й уровень персонажа — теперь 3-й уровень Воина, бонусного слота нет.
        refute Enum.any?(FeatSlots.at(edited, ruleset, 4), &(&1.id == {:class_bonus, :fighter}))

        assert Rules.illegal_feats(edited, ruleset) == [
                 {4, {:class_bonus, :fighter}, :mobility,
                  {:slot_not_granted, {:class_bonus, :fighter}}}
               ]
      end
    end

    test "слот не даётся — значение не спрашивается: ответ один", %{siala: siala} do
      # Epic skill focus (use magic device) — пара, которую бонусный слот Вора
      # отбивает по значению (`choice_refusals/4`). У слота, которого нет, ответ
      # один — сам слот, а не фраза про значение в отсутствующем слоте.
      build = start(siala, :human, :true_neutral, @wizard_abilities) |> ladder(:wizard, 2, siala)

      pick = %{
        feat: :epic_skill_focus,
        at: 2,
        slot: {:class_bonus, :rogue},
        choice: :use_magic_device
      }

      {:error, reasons} = Rules.validate_feat_pick(build, pick, siala)

      assert {:slot_not_granted, {:class_bonus, :rogue}} in reasons
      refute Enum.any?(reasons, &match?({:not_in_class_bonus_slot, _}, &1))
    end
  end

  # ------------------------------------------------------------- без дублей --

  describe "без дублей: причина сильнее уже есть — пула слота не называем" do
    test "Сиала: Mount actions (не выбирается), Craft harper item (ни в одном пуле)", %{
      siala: siala
    } do
      build = start(siala, :human, :true_neutral, @wizard_abilities) |> ladder(:wizard, 1, siala)

      for {feat, head} <- [
            mount_actions: :not_selectable_at_level_up,
            craft_harper_item: :not_slottable
          ] do
        {:error, reasons} =
          Rules.validate_feat_pick(build, %{feat: feat, at: 1, slot: :general}, siala)

        assert Enum.any?(reasons, &(elem(&1, 0) == head)), inspect({feat, reasons})
        refute Enum.any?(reasons, &match?({:not_in_slot_pool, _}, &1)), inspect({feat, reasons})
      end
    end

    test "Сиала: выключенный фит (Devastating critical) — только `feat_disabled`", %{siala: siala} do
      slot = %{
        id: {:class_bonus, :fighter},
        kind: :class_bonus,
        class: :fighter,
        taken_with: :fighter,
        epic?: true
      }

      assert FeatSlots.slot_refusals(siala, slot, :devastating_critical) == []
    end

    test "запрет класса уровня — только `forbidden_by_class`, в любом слоте уровня", %{
      vanilla: vanilla
    } do
      # Воин: Brew potion у ванили в `unavailable_feats` Воина (`fandom:Fighter`).
      build =
        vanilla
        |> start(:human, :true_neutral, %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8})
        |> ladder(:fighter, 1, vanilla)

      for slot <- [:general, :racial, {:class_bonus, :fighter}] do
        {:error, reasons} =
          Rules.validate_feat_pick(build, %{feat: :brew_potion, at: 1, slot: slot}, vanilla)

        assert {:forbidden_by_class, :fighter} in reasons
        refute Enum.any?(reasons, &match?({:not_in_slot_pool, _}, &1)), inspect({slot, reasons})
      end
    end
  end

  # ------------------------------------- сторож: весь справочник, все слоты --

  describe "сторож: слот, который фит не берёт, всегда назван — и только тогда" do
    # Каждый слот каждого уровня нескольких билдов × каждый фит справочника.
    # `accepts?/3` — правило слота, которым кладут фит конструктор и оба импорта.
    #
    #   * берёт → `slot_refusals/3` молчит: новая проверка не отбивает ничего, что
    #     конструктор мог поставить (Воин, Паладин, мультикласс на 4 класса);
    #   * не берёт → кто-то это называет: пул слота (`slot_refusals/3`) или одна
    #     из причин сильнее (выключен, не выбирается, ни в одном пуле, запрет класса).
    #
    # ⚠️ Пара `{accepted?, own}` связана ОДНИМ сопоставлением с кортежем, а не
    # двумя `x = …`: в заголовке `for` выражение `accepted? = false` — фильтр
    # (HANDOFF, «`x = выражение` в заголовке `for`»), и все пары, которые слот
    # НЕ берёт, молча выпадали бы — то есть ровно та половина, ради которой
    # сторож. Так он и был слеп в первой редакции: мутант с `slot_refusals/3`,
    # всегда отвечающим `[]`, его не ронял. Счёт ниже — положительный контроль.
    defp sweep(build, ruleset) do
      for level <- 1..Build.character_level(build),
          slot <- FeatSlots.at(build, ruleset, level),
          {id, feat} <- ruleset.feats,
          {accepted?, own} =
            {FeatSlots.accepts?(ruleset, slot, id), FeatSlots.slot_refusals(ruleset, slot, id)},
          not consistent?(ruleset, slot, id, feat, accepted?, own),
          do: {level, slot.id, id, accepted?, own}
    end

    # Сколько пар «слот × фит» сторож видел с непустым ответом самого слота —
    # чтобы пустой результат `sweep/2` не мог значить «ничего не проверено».
    defp named_by_slot(build, ruleset) do
      for level <- 1..Build.character_level(build),
          slot <- FeatSlots.at(build, ruleset, level),
          {id, _feat} <- ruleset.feats,
          FeatSlots.slot_refusals(ruleset, slot, id) != [],
          reduce: 0,
          do: (n -> n + 1)
    end

    defp consistent?(_ruleset, _slot, _id, _feat, true, own), do: own == []

    defp consistent?(ruleset, slot, id, feat, false, own) do
      own != [] or Map.get(feat, :disabled?, false) or
        Rules.feat_level_up_refusals(id, ruleset) != [] or
        Rules.feat_pool_refusals(id, ruleset) != [] or
        FeatSlots.class_refusals(ruleset, slot.taken_with, id) != []
    end

    @four [{:fighter, 6}, {:wizard, 5}, {:rogue, 10}, {:ranger, 20}]

    for version <- ["siala_41", "vanilla"] do
      @version version

      test "#{version}: Воин и Паладин на капе, мультикласс на предел классов", context do
        ruleset = if @version == "vanilla", do: context.vanilla, else: context.siala
        abilities = %{str: 16, dex: 14, con: 14, int: 12, wis: 12, cha: 12}
        cap = ruleset.level_cap

        multi =
          @four
          |> Enum.take(ruleset.max_classes)
          |> Enum.reduce(start(ruleset, :human, :neutral_good, abilities), fn {class, n}, acc ->
            ladder(acc, class, min(n, cap - Build.character_level(acc)), ruleset)
          end)

        assert map_size(Build.class_levels(multi)) == ruleset.max_classes

        builds = [
          start(ruleset, :human, :true_neutral, abilities) |> ladder(:fighter, cap, ruleset),
          start(ruleset, :human, :lawful_good, abilities) |> ladder(:paladin, cap, ruleset),
          multi
        ]

        for build <- builds do
          assert sweep(build, ruleset) == []
        end

        # Положительный контроль: сам слот называет отказ у сотен пар — у каждого
        # бонусного слота фиты чужих списков, у общего — бонусные фиты.
        assert Enum.all?(builds, &(named_by_slot(&1, ruleset) > 100))
      end
    end
  end
end
