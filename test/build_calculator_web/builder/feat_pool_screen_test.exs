defmodule BuildCalculatorWeb.Builder.FeatPoolScreenTest do
  @moduledoc """
  Какие фиты берутся слотом — экран и ядро отвечают одинаково (задача 4.55).

  До 4.55 выбор фитов (`Builder.Feats`) решал «берётся ли фит слотом» сам, по
  `type` Fandom: `type == "general"` или непустой `bonus_for`, иначе
  `{:not_slottable, type}`. Ядро (`Rules.FeatSlots`) читало тот же `type` шире,
  и на двух фитах ответы разошлись: `Extra turning` (`special`) и `Scribe scroll`
  (`item creation`) кандидатами в слот приходили от ядра, а экран их отбивал.
  Теперь экран спрашивает ядро (`Rules.feat_pool_refusals/2`).

  Здесь две вещи:

    * **сценарии по одному левелапу** (`Rules.validate_level_up/3` на каждом
      уровне) — клирик и паладин с `Extra turning`, волшебник и бард со `Scribe
      scroll`, Арфист с `Craft harper item`; на обоих ruleset'ах;
    * **перепись**: каждый фит, которому экран раньше отказывал
      `{:not_slottable, …}` (прежний предикат заморожен ниже), на уровне каждого
      класса в общем слоте 1-го и 21-го уровня — список слота на экране
      совпадает с `Rules.validate_feat_pick/3`. Не выборка.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.Feats

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp both(%{vanilla: vanilla, siala: siala}), do: [{"vanilla", vanilla}, {"siala_41", siala}]

  # Высокие характеристики — чтобы требования фитов не мешали вопросу о слоте.
  defp start(ruleset, alignment) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      alignment: alignment,
      base_abilities: %{str: 16, dex: 14, con: 14, int: 14, wis: 14, cha: 14}
    )
  end

  # Один левелап, как у игрока: ядро разрешает класс — уровень добавляется,
  # с навыками и фитами этого уровня (навыки раньше фитов — порядок экранов
  # мастера, замер BA1).
  defp level_up!(build, ruleset, class, opts \\ []) do
    assert Rules.validate_level_up(build, class, ruleset) == :ok,
           "#{class} на #{Build.character_level(build) + 1}-м: " <>
             inspect(Rules.validate_level_up(build, class, ruleset))

    build = Build.add_level(build, class)
    level = Build.character_level(build)

    build =
      case Keyword.get(opts, :skills) do
        nil -> build
        ranks -> %Build{build | skills: Map.put(build.skills, level, ranks)}
      end

    Enum.reduce(Keyword.get(opts, :feats, []), build, fn {slot, feat}, acc ->
      assert Rules.validate_feat_pick(acc, %{feat: feat, at: level, slot: slot}, ruleset) == :ok,
             "#{feat} в #{inspect(slot)} на #{level}-м"

      Build.put_feat(acc, level, slot, feat)
    end)
  end

  defp general_list(ruleset, build, level),
    do: Feats.lists(ruleset, build, level, slot: :general)

  defp offered?(ruleset, build, level, feat),
    do: feat in Enum.map(general_list(ruleset, build, level).available, & &1.feat.id)

  defp screen_reasons(ruleset, build, level, feat, query) do
    lists = Feats.lists(ruleset, build, level, query: query)

    case Enum.find(lists.blocked, &(&1.feat.id == feat)) do
      nil -> if Enum.any?(lists.available, &(&1.feat.id == feat)), do: [], else: :absent
      entry -> entry.reasons
    end
  end

  defp core(ruleset, build, level, feat),
    do: Rules.validate_feat_pick(build, %{feat: feat, at: level, slot: :general}, ruleset)

  # Прежний предикат экрана, замороженный как определение переписи: всё, чему
  # экран отказывал `{:not_slottable, type}` — то есть не выключенное, не
  # «нельзя при левелапе», без `type == "general"` и без `bonus_for`.
  defp formerly_refused(ruleset) do
    for {id, feat} <- ruleset.feats,
        not feat.disabled?,
        Rules.feat_level_up_refusals(id, ruleset) == [],
        not (feat.type == "general" or MapSet.size(feat.bonus_for) > 0),
        do: id
  end

  # Общий слот на уровне `class`: 1-й уровень (у престижа — синтетика: вопрос
  # о слоте законности билда не требует, и экран с ядром видят один билд)
  # и 21-й, эпический, после двадцати уровней воина.
  defp census_builds(ruleset, class) do
    %Build{} = base = start(ruleset, :true_neutral)

    [
      {1, %Build{base | levels: [class]}},
      {21, %Build{base | levels: List.duplicate(:fighter, 20) ++ [class]}}
    ]
  end

  describe "Extra turning — клирик и паладин (замер AG1)" do
    # `fandom:Extra turning`: «exclusive to clerics and paladins», «select it as
    # a general feat»; feat.2da:13 ALLCLASSESCANUSE 0, cls_feat_cler.2da и
    # cls_feat_pal.2da — List 0. AG1 (Dan 28.08.2026, Сиала): «клерику на 1
    # уровне extra turning был доступен, на 3 и далее уже был не доступен,
    # нельзя взять несколько раз».
    test "клирик 1 берёт его общим слотом, на 3-м второй раз — нет", ctx do
      for {name, ruleset} <- both(ctx) do
        cleric1 = ruleset |> start(:lawful_good) |> level_up!(ruleset, :cleric)

        assert core(ruleset, cleric1, 1, :extra_turning) == :ok, name
        assert offered?(ruleset, cleric1, 1, :extra_turning), name

        took =
          ruleset
          |> start(:lawful_good)
          |> level_up!(ruleset, :cleric, feats: [general: :extra_turning])
          |> level_up!(ruleset, :cleric)
          |> level_up!(ruleset, :cleric)

        assert {:error, [{:already_taken, :extra_turning}]} =
                 core(ruleset, took, 3, :extra_turning)

        refute offered?(ruleset, took, 3, :extra_turning), name

        assert screen_reasons(ruleset, took, 3, :extra_turning, "extra turning") ==
                 [{:already_taken, :extra_turning}]
      end
    end

    # Паладин получает `Turn undead` на 3-м уровне класса (`classes.json` →
    # paladin, `granted_feats`), поэтому его первый общий слот с требованием —
    # 3-й. До этого фит отбивает требование, а не слот.
    test "паладин 3 — тоже; паладин 1 — нет, и только по требованию", ctx do
      for {name, ruleset} <- both(ctx) do
        paladin1 = ruleset |> start(:lawful_good) |> level_up!(ruleset, :paladin)

        assert core(ruleset, paladin1, 1, :extra_turning) ==
                 {:error, [{:requires_feat, :turn_undead}]},
               name

        assert screen_reasons(ruleset, paladin1, 1, :extra_turning, "extra turning") ==
                 [{:requires_feat, :turn_undead}]

        paladin3 = paladin1 |> level_up!(ruleset, :paladin) |> level_up!(ruleset, :paladin)

        assert core(ruleset, paladin3, 3, :extra_turning) == :ok, name
        assert offered?(ruleset, paladin3, 3, :extra_turning), name
      end
    end

    # Граница: «exclusive» — про уровень, на котором тратится слот. Воин 1 —
    # уровень воина, и экран называет ровно это, а не «слотом не берётся».
    test "воин 1 — нет, и причина — уровень класса", ctx do
      for {name, ruleset} <- both(ctx) do
        fighter1 = ruleset |> start(:lawful_good) |> level_up!(ruleset, :fighter)

        assert {:error, reasons} = core(ruleset, fighter1, 1, :extra_turning)
        assert {:forbidden_by_class, :fighter} in reasons
        refute offered?(ruleset, fighter1, 1, :extra_turning), name

        assert screen_reasons(ruleset, fighter1, 1, :extra_turning, "extra turning") ==
                 [{:forbidden_by_class, :fighter}]
      end
    end
  end

  describe "Scribe scroll — волшебник и бард" do
    # `fandom:Scribe scroll`: «Wizards get this feat for free at first level»;
    # cls_feat_wiz.2da — List 3 (выдача), у барда — List 0 (общим слотом).
    test "волшебнику 1 — «класс выдаёт на этом уровне», а не «слотом не берётся»", ctx do
      for {name, ruleset} <- both(ctx) do
        wizard1 = ruleset |> start(:true_neutral) |> level_up!(ruleset, :wizard)

        assert core(ruleset, wizard1, 1, :scribe_scroll) ==
                 {:error, [{:already_taken, :scribe_scroll}]},
               name

        assert screen_reasons(ruleset, wizard1, 1, :scribe_scroll, "scribe") ==
                 [{:granted_here, :scribe_scroll}]
      end
    end

    test "бард 1 берёт его общим слотом", ctx do
      for {name, ruleset} <- both(ctx) do
        bard1 = ruleset |> start(:chaotic_good) |> level_up!(ruleset, :bard)

        assert core(ruleset, bard1, 1, :scribe_scroll) == :ok, name
        assert offered?(ruleset, bard1, 1, :scribe_scroll), name
      end
    end
  end

  describe "Craft harper item — Арфист" do
    # Ваниль: `fandom:Craft harper item` — `type=class`, выдача Арфисту 5.
    # Требования Арфиста ванили: Alertness, Iron will, Discipline 4, Lore 6,
    # Persuade 8, Search 4, не злой.
    test "ваниль: Арфист 1 на 6-м — «выдаётся классом, слотом не берётся»", %{vanilla: ruleset} do
      build =
        ruleset
        |> start(:neutral_good)
        |> level_up!(ruleset, :rogue,
          skills: %{persuade: 4, lore: 4, search: 4, discipline: 2},
          feats: [general: :alertness, racial: :iron_will]
        )
        |> level_up!(ruleset, :rogue, skills: %{persuade: 1, lore: 1})
        |> level_up!(ruleset, :rogue, skills: %{persuade: 1, lore: 1, discipline: 1})
        |> level_up!(ruleset, :rogue, skills: %{persuade: 1})
        |> level_up!(ruleset, :rogue, skills: %{persuade: 1, discipline: 1})
        |> level_up!(ruleset, :harper_scout)

      assert {:error, reasons} = core(ruleset, build, 6, :craft_harper_item)
      assert {:not_slottable, "class"} in reasons

      assert screen_reasons(ruleset, build, 6, :craft_harper_item, "harper item") ==
               [{:not_slottable, "class"}]
    end

    # Сиала: «Тип навыка: Создание предметов (Классовый)», выдача на Арфисте 1
    # (`feat_level_shift` 5 → 1); хак — List 3. Требования Арфиста Сиалы: Brew
    # potion, Discipline 10, Search 10, не злой. Brew potion на Сиале — Lore 4
    # и общий слот любого класса (замер H1).
    test "Сиала: на уровне Арфиста — выдача, на уровне вора — «выдаётся классом»", %{
      siala: ruleset
    } do
      rogue7 =
        ruleset
        |> start(:neutral_good)
        |> level_up!(ruleset, :rogue,
          skills: %{search: 4, lore: 4},
          feats: [general: :brew_potion]
        )
        |> then(fn b ->
          Enum.reduce(2..7, b, fn _, acc ->
            level_up!(acc, ruleset, :rogue, skills: %{search: 1})
          end)
        end)

      harper =
        rogue7
        |> level_up!(ruleset, :fighter, skills: %{discipline: 10})
        |> level_up!(ruleset, :harper_scout)

      assert {:error, reasons} = core(ruleset, harper, 9, :craft_harper_item)
      assert {:already_taken, :craft_harper_item} in reasons

      assert screen_reasons(ruleset, harper, 9, :craft_harper_item, "harper item") ==
               [{:granted_here, :craft_harper_item}]

      # 6-й — уровень вора с общим слотом. До 4.55 тип был `item creation`, и
      # сверка хака записывала: «общий слот формально принимает, отбивает
      # требование Арфист-скаут 1». С правкой ответ — сама суть: выдаётся.
      assert {:error, reasons} = core(ruleset, rogue7, 6, :craft_harper_item)
      assert {:not_slottable, "class"} in reasons

      assert screen_reasons(ruleset, rogue7, 6, :craft_harper_item, "harper item") ==
               [{:not_slottable, "class"}]

      assert Feats.reason({:not_slottable, "class"}, ruleset) ==
               "выдаётся классом, слотом не берётся"
    end
  end

  describe "перепись: экран = ядро" do
    test "у каждого фита, которому экран отказывал «слотом не берётся», ответы совпали", ctx do
      for {name, ruleset} <- both(ctx) do
        population = formerly_refused(ruleset)
        assert length(population) > 140, "#{name}: перепись подозрительно мала"

        offered_somewhere =
          for class <- Map.keys(ruleset.classes),
              {level, build} <- census_builds(ruleset, class),
              reduce: MapSet.new() do
            acc ->
              screen =
                for entry <- general_list(ruleset, build, level).available,
                    entry.feat.id in population,
                    into: MapSet.new(),
                    do: entry.feat.id

              core =
                for id <- population,
                    core(ruleset, build, level, id) == :ok,
                    into: MapSet.new(),
                    do: id

              assert screen == core, """
              #{name}, #{class} на #{level}-м: экран и ядро разошлись
              только экран: #{inspect(MapSet.difference(screen, core))}
              только ядро:  #{inspect(MapSet.difference(core, screen))}
              """

              MapSet.union(acc, screen)
          end

        # Положительный контроль: перепись не пуста — ровно два фита из прежде
        # отбитых теперь где-то предлагаются, и это фиты задачи.
        assert offered_somewhere == MapSet.new([:extra_turning, :scribe_scroll]), name
      end
    end
  end
end
