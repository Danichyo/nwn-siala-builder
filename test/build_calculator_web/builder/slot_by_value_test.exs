defmodule BuildCalculatorWeb.Builder.SlotByValueTest do
  @moduledoc """
  Задача 4.59: импорт кладёт фит в слот, который берёт ПАРУ, и называет причину
  ядра, когда слота нет.

  Часть 1 — слот по значению. `Feats.best_slot/4` выбирал самый узкий слот по
  фиту (бонусный раньше общего), а бонусный слот класса бывает уже по значению
  (`FeatSlots.choice_refusals/4`: `bonus_for_only`, `bonus_for_except`). Носитель —
  эльф, волшебник 1 → воин 9 → Тайный лучник 14: 24-й уровень даёт общий
  эпический слот и бонусный слот лучника, а бонусный слот лучника берёт Epic
  weapon focus только с луком (`vanilla/feat_bonus_slot_values.json`,
  `cls_feat_archer.2da`). Оба импорта клали `Epic weapon focus (longsword)` в
  бонусный слот лучника, ядро называло пик нелегальным, общий слот оставался
  пустым. В корпусе ECB и в логах таких случаев 0 — контроль синтетический.

  Части 2 и 3 — причина. Окно лога спрашивало у ядра три причины из четырёх
  (без пула, `Rules.feat_pool_refusals/2`), импорт текста — ни одной: одна фраза
  «некуда положить» на выключенный фит, классовое умение и занятый слот. Теперь
  обоим отвечает `Feats.no_slot_reason/5` (с задачи 4.40 — `unplaced_reason/5`:
  уровень вовсе без слотов фитов говорит своей фразой, `unplaced_reason_test.exs`).

  Сценарии собираются по одному левелапу (`Rules.validate_level_up/3`), как
  у игрока; текст для импорта — наш собственный экспорт того же билда, лог —
  уровни в форме шардовой печати `.билд`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{Export, Feats, GameLogImport, Import}

  @bonus {:class_bonus, :arcane_archer}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp level_up!(ruleset, steps, fields) do
    Enum.reduce(steps, Build.new(fields), fn {class, picks}, build ->
      level = Build.character_level(build) + 1
      assert Rules.validate_level_up(build, class, ruleset) == :ok
      build = Build.add_level(build, class)

      Enum.reduce(picks, build, fn {slot, feat, choice}, build ->
        pick = %{feat: feat, at: level, slot: slot, choice: choice}
        assert Rules.validate_feat_pick(build, pick, ruleset) == :ok
        Build.put_feat(build, level, slot, feat, choice)
      end)
    end)
  end

  # На ванили фокус на лук и длинный меч даёт воинское владение; у Сиалы
  # владения свои — фиты «Системы оружия», их берёт бонусный слот воина.
  defp archer_head(%{version: "siala_41"}) do
    [
      {:wizard, [{:general, :point_blank_shot, nil}]},
      {:fighter, [{{:class_bonus, :fighter}, :siala_ranged_proficiency, nil}]},
      {:fighter,
       [
         {:general, :weapon_focus, :longbow},
         {{:class_bonus, :fighter}, :siala_blade_proficiency, nil}
       ]},
      {:fighter, []},
      {:fighter, [{{:class_bonus, :fighter}, :weapon_focus, :longsword}]}
    ]
  end

  defp archer_head(_vanilla) do
    [
      {:wizard, [{:general, :point_blank_shot, nil}]},
      {:fighter, [{{:class_bonus, :fighter}, :weapon_focus, :longbow}]},
      {:fighter, [{:general, :weapon_focus, :longsword}]}
    ]
  end

  defp archer(ruleset, archer_levels \\ 14) do
    head = archer_head(ruleset)

    steps =
      head ++
        List.duplicate({:fighter, []}, 10 - length(head)) ++
        List.duplicate({:arcane_archer, []}, archer_levels)

    level_up!(ruleset, steps,
      ruleset_version: ruleset.version,
      race: :elf,
      alignment: :chaotic_good,
      base_abilities: %{str: 14, dex: 18, con: 12, int: 14, wis: 8, cha: 8}
    )
  end

  defp ecb(build, ruleset), do: Export.text(build, ruleset, Rules.compute(build, ruleset))

  @log_class %{wizard: "WIZARD", fighter: "FIGHTER", arcane_archer: "ARCANE ARCHER"}

  # Уровни в форме шардовой печати `.билд` (`test/fixtures/game_logs/`): номер,
  # класс, фиты слотов строкой `FEATS:`.
  defp log(build, ruleset) do
    levels =
      for {class, level} <- Enum.with_index(build.levels, 1) do
        feats =
          for {_slot, pick} <- Enum.sort(Map.get(build.feats, level, %{})) do
            case pick do
              {feat, choice} -> "#{ruleset.feats[feat].name} (#{choice})"
              feat -> ruleset.feats[feat].name
            end
          end

        "------------------------------------------------\n" <>
          "LEVEL #{level}: #{Map.fetch!(@log_class, class)}\n" <>
          if(feats == [], do: "", else: "  FEATS: #{Enum.join(feats, ", ")}\n")
      end

    "------------------------------------------------\n    CHARACTER BUILD: Test\n" <>
      "------------------------------------------------\n\nRACE: Elf\n\n" <> Enum.join(levels)
  end

  defp longsword_in(build, slot),
    do: Build.put_feat(build, 24, slot, :epic_weapon_focus, :longsword)

  describe "часть 1: слот берёт пару" do
    for version <- [:vanilla, :siala] do
      test "#{version}: носитель — на 24-м общий и бонусный слот лучника", ctx do
        ruleset = ctx[unquote(version)]
        build = archer(ruleset)

        assert Enum.map(Rules.FeatSlots.at(build, ruleset, 24), & &1.id) == [:general, @bonus]
        assert Rules.illegal_feats(longsword_in(build, :general), ruleset) == []

        assert Rules.illegal_feats(longsword_in(build, @bonus), ruleset) == [
                 {24, @bonus, :epic_weapon_focus, {:not_in_class_bonus_slot, :arcane_archer}}
               ]
      end

      test "#{version}: best_slot/5 — длинный меч в общий, лук в бонусный, без значения как раньше",
           ctx do
        ruleset = ctx[unquote(version)]
        build = archer(ruleset)

        assert Feats.best_slot(ruleset, build, 24, :epic_weapon_focus, :longsword).id == :general
        assert Feats.best_slot(ruleset, build, 24, :epic_weapon_focus, :longbow).id == @bonus
        assert Feats.best_slot(ruleset, build, 24, :epic_weapon_focus).id == @bonus
      end

      test "#{version}: импорт текста кладёт Epic weapon focus (longsword) в общий слот", ctx do
        ruleset = ctx[unquote(version)]
        build = longsword_in(archer(ruleset), :general)

        result = Import.parse(ecb(build, ruleset), ruleset)

        assert result.build.feats[24] == %{general: {:epic_weapon_focus, :longsword}}
        assert Rules.illegal_feats(result.build, ruleset) == []
        refute Enum.any?(result.issues, &match?({:feat_no_slot, _, :epic_weapon_focus, _}, &1))
      end

      test "#{version}: импорт текста — лук по-прежнему в бонусный слот лучника", ctx do
        ruleset = ctx[unquote(version)]
        build = Build.put_feat(archer(ruleset), 24, @bonus, :epic_weapon_focus, :longbow)

        result = Import.parse(ecb(build, ruleset), ruleset)

        assert result.build.feats[24] == %{@bonus => {:epic_weapon_focus, :longbow}}
        assert Rules.illegal_feats(result.build, ruleset) == []
      end

      test "#{version}: лог .билд кладёт Epic weapon focus (longsword) в общий слот", ctx do
        ruleset = ctx[unquote(version)]
        build = longsword_in(archer(ruleset), :general)

        result = GameLogImport.parse(log(build, ruleset), ruleset)

        assert result.build.feats[24] == %{general: {:epic_weapon_focus, :longsword}}
        assert Rules.illegal_feats(result.build, ruleset) == []
        refute Enum.any?(result.issues, &match?({:feat_not_placed, _, _, _}, &1))
      end

      # Оба слота уровня заняты бы одной парой каждый: длинный меч берёт только
      # общий, Epic prowess — оба. Как бы ни стояли в тексте, лягут оба.
      test "#{version}: два пика на уровне — каждый в свой слот, в любом порядке", ctx do
        ruleset = ctx[unquote(version)]
        build = archer(ruleset)

        legal =
          build
          |> longsword_in(:general)
          |> Build.put_feat(24, @bonus, :epic_prowess, nil)

        for parse <- [
              &Import.parse(ecb(&1, ruleset), ruleset),
              &GameLogImport.parse(log(&1, ruleset), ruleset)
            ] do
          result = parse.(legal)

          assert result.build.feats[24] == %{
                   :general => {:epic_weapon_focus, :longsword},
                   @bonus => :epic_prowess
                 }
        end
      end
    end
  end

  describe "части 2 и 3: причина — ядра" do
    # Тайный лучник 18 на 28-м уровне: бонусный слот лучника, общего нет
    # (общие эпические — 21, 24, 27, 30). Пару берёт только общий слот.
    for version <- [:vanilla, :siala] do
      test "#{version}: уровень с одним бонусным слотом лучника — значение, которого он не берёт",
           ctx do
        ruleset = ctx[unquote(version)]
        build = archer(ruleset, 18)

        assert Enum.map(Rules.FeatSlots.at(build, ruleset, 28), & &1.id) == [@bonus]

        placed = Build.put_feat(build, 28, @bonus, :epic_weapon_focus, :longsword)
        reason = {:not_in_class_bonus_slot, :arcane_archer}

        text = Import.parse(ecb(placed, ruleset), ruleset)
        assert {:feat_no_slot, 28, :epic_weapon_focus, reason} in text.issues

        logged = GameLogImport.parse(log(placed, ruleset), ruleset)
        assert {:feat_not_placed, 28, :epic_weapon_focus, reason} in logged.issues
      end
    end

    defp ladder(lines),
      do: "Human, Lawful Good\nLEVELING GUIDE\n" <> Enum.join(lines, "\n") <> "\n"

    defp no_slot(result, level) do
      for {:feat_no_slot, ^level, feat, reason} <- result.issues, do: {feat, reason}
    end

    test "импорт текста: каждая причина своей фразой, «нет свободного слота» — прежней", %{
      vanilla: vanilla,
      siala: siala
    } do
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")

      wizard =
        ladder(for l <- 1..5, do: "0#{l}: Wizard(#{l})#{if l in [2, 5], do: ": Power Attack"}")

      for ruleset <- [vanilla, siala] do
        result = Import.parse(wizard, ruleset)

        # Волшебник 2 слотов фитов не получает вовсе — с задачи 4.40 причина так
        # и говорит (`Feats.unplaced_reason/5`), до неё была «нет свободного слота».
        none = {:no_feat_slot_at_level, :power_attack}
        assert no_slot(result, 2) == [{:power_attack, none}]

        assert Import.issue_text({:feat_no_slot, 2, :power_attack, none}, ruleset) ==
                 "уровень 2: Power attack некуда положить — этот уровень не даёт слотов фитов"

        # «Нет свободного слота» (занятый слот) — прежняя фраза байт в байт.
        assert Import.issue_text(
                 {:feat_no_slot, 2, :power_attack, {:no_free_slot, :power_attack}},
                 ruleset
               ) ==
                 "уровень 2: Power attack некуда положить — подходящего свободного слота на этом уровне нет"

        # Волшебник 5 — один бонусный слот, и Power attack нет в его списке.
        reason = {:not_in_slot_pool, {:class_bonus, :wizard}}
        assert no_slot(result, 5) == [{:power_attack, reason}]

        assert Import.issue_text({:feat_no_slot, 5, :power_attack, reason}, ruleset) ==
                 "уровень 5: Power attack некуда положить — нет в списке бонусных фитов Wizard"
      end

      # Вор 1: Evasion класс выдаёт на 2-м, на 1-м это просто классовое умение,
      # которое слотом не берётся; Extra turning вору не выбрать вовсе.
      rogue = ladder(["01: Rogue(1): Extra Turning, Evasion"])

      for ruleset <- [vanilla, siala] do
        result = Import.parse(rogue, ruleset)

        assert Enum.sort(no_slot(result, 1)) == [
                 {:evasion, {:not_slottable, "class"}},
                 {:extra_turning, {:forbidden_by_class, :rogue}}
               ]

        assert Import.issue_text({:feat_no_slot, 1, :evasion, {:not_slottable, "class"}}, ruleset) ==
                 "уровень 1: Evasion некуда положить — выдаётся классом, слотом не берётся"

        assert Import.issue_text(
                 {:feat_no_slot, 1, :extra_turning, {:forbidden_by_class, :rogue}},
                 ruleset
               ) ==
                 "уровень 1: Extra turning некуда положить — на уровне Rogue этот фит не выбрать"
      end

      # Сиала выключила Devastating critical; у ванили он есть, но эпический —
      # на 1-м уровне его не берёт ни один слот, и ядро говорит почему.
      critical = ladder(["01: Fighter(1): Devastating Critical (Longsword)"])

      assert no_slot(Import.parse(critical, siala), 1) == [
               {:devastating_critical, {:feat_disabled, :devastating_critical}}
             ]

      assert Import.issue_text(
               {:feat_no_slot, 1, :devastating_critical, {:feat_disabled, :devastating_critical}},
               siala
             ) == "уровень 1: Devastating critical некуда положить — на Сиале отключён"

      assert no_slot(Import.parse(critical, vanilla), 1) == [
               {:devastating_critical, {:requires_character_level, 21}}
             ]
    end

    # `hela.log`, РДД 9: `Hit Die Increase` печатается трижды, класс выдаёт
    # его на одном уровне из трёх, и одна печать идёт в слоты. Слотом он
    # не берётся вовсе — пул ни одного слота его не держит.
    test "лог .билд: hela, РДД 9 — выдаётся классом, слотом не берётся", %{siala: siala} do
      Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
      text = File.read!(Path.expand("../../fixtures/game_logs/hela.log", __DIR__))
      issue = {:feat_not_placed, 9, :hit_die_increase, {:not_slottable, "class"}}

      assert issue in GameLogImport.parse(text, siala).issues

      assert GameLogImport.issue_text(issue, siala) ==
               "уровень 9: Hit die increase не перенесён — выдаётся классом, слотом не берётся"
    end
  end

  describe "no_slot_reason/5: слоты уровня" do
    # Человек воин 1: общий, расовый и бонусный воина. Фит, который берёт
    # только бонусный список вора, не берёт ни один из трёх; общий и расовый
    # отказывают одним списком — общих фитов, бонусный — своим. Разные причины
    # у разных слотов — одна фраза про слот не годится.
    test "разные отказы у разных слотов — «нет свободного слота»", %{vanilla: vanilla} do
      build = level_up!(vanilla, [{:fighter, []}], race: :human, alignment: :lawful_good)

      assert Enum.map(Rules.FeatSlots.at(build, vanilla, 1), & &1.id) == [
               :general,
               :racial,
               {:class_bonus, :fighter}
             ]

      assert Feats.no_slot_reason(vanilla, build, 1, :opportunist, nil) ==
               {:no_free_slot, :opportunist}
    end

    # Человек волшебник 1: общий и расовый — оба из списка общих фитов, одна
    # причина, хотя id слотов разные.
    test "общий и расовый слот — одна причина", %{vanilla: vanilla} do
      build = level_up!(vanilla, [{:wizard, []}], race: :human, alignment: :lawful_good)

      assert Enum.map(Rules.FeatSlots.at(build, vanilla, 1), & &1.id) == [:general, :racial]

      assert Feats.no_slot_reason(vanilla, build, 1, :opportunist, nil) ==
               {:not_in_slot_pool, :general}
    end

    test "занятый слот, который взял бы, — «нет свободного слота»", %{vanilla: vanilla} do
      build =
        level_up!(vanilla, [{:wizard, [{:general, :iron_will, nil}, {:racial, :alertness, nil}]}],
          race: :human,
          alignment: :lawful_good
        )

      assert Feats.no_slot_reason(vanilla, build, 1, :toughness, nil) ==
               {:no_free_slot, :toughness}
    end
  end
end
