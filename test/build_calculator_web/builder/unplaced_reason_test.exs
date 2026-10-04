defmodule BuildCalculatorWeb.Builder.UnplacedReasonTest do
  @moduledoc """
  Задача 4.40, пункт 18: фит, который импорт не положил на уровень вовсе без
  слотов фитов, слышит «этот уровень не даёт слотов фитов», а не «нет
  подходящего свободного слота».

  До 4.40 обе фразы были одной: `Feats.no_slot_reason/5` (4.59) отвечала
  `{:no_free_slot, id}` и уровню, чей слот занят, и уровню, где слота нет
  (91 замечание корпуса ECB на ванили, 99 на Сиале — `tmp/4.40a/p18_census.exs`).
  Первое игрок чинит, перекладывая фиты, второе — только другим уровнем.
  Новая причина — `Feats.unplaced_reason/5`, её спрашивают оба импорта;
  `no_slot_reason/5` оставлена прежней для копий `BASE` стендов равносильности
  (они зовут `Builder.Feats` живым) — тест держит и это.

  Сценарии — по одному левелапу (`Rules.validate_level_up/3`), как у игрока.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Rules}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{Feats, GameLogImport, Import}

  @none {:no_feat_slot_at_level, :power_attack}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp wizard(ruleset, levels) do
    Enum.reduce(1..levels, Build.new(race: :human, alignment: :lawful_good), fn _, build ->
      assert Rules.validate_level_up(build, :wizard, ruleset) == :ok
      Build.add_level(build, :wizard)
    end)
  end

  defp ladder(lines),
    do: "Human, Lawful Good\nLEVELING GUIDE\n" <> Enum.join(lines, "\n") <> "\n"

  # Шардовая печать `.билд` (`test/fixtures/game_logs/`): номер, класс, `FEATS:`.
  defp log(levels) do
    body =
      for {feats, level} <- Enum.with_index(levels, 1) do
        "------------------------------------------------\n" <>
          "LEVEL #{level}: WIZARD\n" <>
          if(feats == [], do: "", else: "  FEATS: #{Enum.join(feats, ", ")}\n")
      end

    "------------------------------------------------\n    CHARACTER BUILD: Test\n" <>
      "------------------------------------------------\n\nRACE: Human\n\n" <> Enum.join(body)
  end

  describe "unplaced_reason/5" do
    for version <- [:vanilla, :siala] do
      test "#{version}: уровень без слотов фитов — своя причина; no_slot_reason/5 — прежняя",
           ctx do
        ruleset = ctx[unquote(version)]
        build = wizard(ruleset, 2)

        # Положительный контроль посылки: волшебник 2 слотов фитов не получает.
        assert Rules.FeatSlots.at(build, ruleset, 2) == []
        assert Rules.FeatSlots.at(build, ruleset, 1) != []

        assert Feats.unplaced_reason(ruleset, build, 2, :power_attack, nil) == @none

        # Для `BASE` стендов: прежняя функция говорит, как до 4.40.
        assert Feats.no_slot_reason(ruleset, build, 2, :power_attack, nil) ==
                 {:no_free_slot, :power_attack}
      end

      test "#{version}: занятый слот, который взял бы, — по-прежнему «нет свободного слота»",
           ctx do
        ruleset = ctx[unquote(version)]

        build =
          ruleset
          |> wizard(1)
          |> Build.put_feat(1, :general, :iron_will, nil)
          |> Build.put_feat(1, :racial, :alertness, nil)

        assert Feats.unplaced_reason(ruleset, build, 1, :power_attack, nil) ==
                 {:no_free_slot, :power_attack}
      end
    end

    # Порядок выбора фитов: выключенный фит — сначала «выключен», и на уровне
    # без слотов тоже.
    test "siala: выключенный фит на уровне без слотов — «на Сиале отключён»", %{siala: siala} do
      build = wizard(siala, 2)

      assert Feats.unplaced_reason(siala, build, 2, :devastating_critical, :longsword) ==
               {:feat_disabled, :devastating_critical}
    end

    # Уровня 0 нет (окно лога, 4.39) — и сказать «этот уровень не даёт слотов»
    # не о чем.
    test "уровень 0 — «нет свободного слота», как прежде", %{vanilla: vanilla} do
      assert Feats.unplaced_reason(vanilla, wizard(vanilla, 1), 0, :power_attack, nil) ==
               {:no_free_slot, :power_attack}
    end

    test "у причины есть подпись в обоих языках и она в реестре форм", %{vanilla: vanilla} do
      assert {:no_feat_slot_at_level, :cleave} in Feats.reason_forms()

      Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
      assert Feats.reason(@none, vanilla) == "этот уровень не даёт слотов фитов"

      Gettext.put_locale(BuildCalculatorWeb.Gettext, "en")
      assert Feats.reason(@none, vanilla) == "this level grants no feat slots"
    end
  end

  describe "оба окна" do
    for version <- [:vanilla, :siala] do
      test "#{version}: импорт текста — уровень без слотов и занятый слот разными фразами", ctx do
        ruleset = ctx[unquote(version)]
        Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")

        text =
          ladder([
            "01: Wizard(1): Iron Will, Alertness, Toughness",
            "02: Wizard(2): Power Attack"
          ])

        issues = Import.parse(text, ruleset).issues

        assert {:feat_no_slot, 2, :power_attack, @none} in issues
        assert {:feat_no_slot, 1, :toughness, {:no_free_slot, :toughness}} in issues

        assert Import.issue_text({:feat_no_slot, 2, :power_attack, @none}, ruleset) ==
                 "уровень 2: Power attack некуда положить — этот уровень не даёт слотов фитов"

        Gettext.put_locale(BuildCalculatorWeb.Gettext, "en")

        assert Import.issue_text({:feat_no_slot, 2, :power_attack, @none}, ruleset) ==
                 "level 2: nowhere to put Power attack — this level grants no feat slots"
      end

      test "#{version}: лог .билд — уровень без слотов и занятый слот разными фразами", ctx do
        ruleset = ctx[unquote(version)]
        Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")

        issues =
          GameLogImport.parse(
            log([["Iron Will", "Alertness", "Toughness"], ["Power Attack"]]),
            ruleset
          ).issues

        assert {:feat_not_placed, 2, :power_attack, @none} in issues
        assert {:feat_not_placed, 1, :toughness, {:no_free_slot, :toughness}} in issues

        assert GameLogImport.issue_text({:feat_not_placed, 2, :power_attack, @none}, ruleset) ==
                 "уровень 2: Power attack не перенесён — этот уровень не даёт слотов фитов"

        Gettext.put_locale(BuildCalculatorWeb.Gettext, "en")

        assert GameLogImport.issue_text({:feat_not_placed, 2, :power_attack, @none}, ruleset) ==
                 "level 2: Power attack not carried over — this level grants no feat slots"
      end
    end
  end
end
