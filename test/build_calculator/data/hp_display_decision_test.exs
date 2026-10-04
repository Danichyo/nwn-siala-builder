defmodule BuildCalculator.Data.HpDisplayDecisionTest do
  @moduledoc """
  HP ванили — максимум кости на каждом уровне РЕШЕНИЕМ ПОКАЗА, а не допущением
  (задача 4.20; решение Dan 02.10.2026: «HP ванили все равно предлагаю всегда
  показывать максимальное», `VANILLA.md` §5, вопрос 2).

  Две записи рядом в `vanilla/rules.json` → `character`, и у каждой своя роль:

    * `hit_points_roll` — правило ИГРЫ (задача 4.6): Fandom «Hit point»
      (rev 62785) и ruleset.2da `MIN_LEVEL_FOR_MAX_HP 3` — максимум на уровнях
      персонажа 1–3, дальше бросок. Остаётся источником;
    * `hit_points_shown` — решение ПОКАЗА: что печатать на месте броска.

  У Сиалы основание другое и сильнее: её правило игры само `always_max`
  (`siala_41/overrides.json`, слово Dan 01.08.2026), напечатанное число равно
  игровому, и решения ей не нужно (`Character.hp_maximum_basis/1` →
  `:game_rule` против ванильного `:display_decision`).

  🔴 Оговорку `{:assumed, :hp_uses_maximum_hit_die_rolls}` снимает ЗАПИСЬ,
  а не вычёркивание (CLAUDE.md §9, «ложное признание»), поэтому здесь
  положительный контроль: копия данных без записи решения возвращает оговорку —
  и ничего больше; ни одно число HP ни на одном ruleset'е не сдвигается.
  Форма гэпа живых носителей больше не имеет — её держит эта синтетика.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Data.Loader.{Character, Layers}
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  @gap {:assumed, :hp_uses_maximum_hit_die_rolls}

  @vanilla_rules "priv/rules/vanilla/rules.json"
  @siala_overrides "priv/rules/siala_41/overrides.json"

  setup_all do
    vanilla_ov = @vanilla_rules |> File.read!() |> Jason.decode!()
    siala_ov = Layers.merge(vanilla_ov, @siala_overrides |> File.read!() |> Jason.decode!())

    root = BuildCalculator.TmpDir.unique_path!("hp_shown_")
    File.cp_r!("priv/rules", root)

    File.write!(
      Path.join(root, "vanilla/rules.json"),
      Jason.encode!(without_decision(vanilla_ov))
    )

    without = Loader.load!(root)
    File.rm_rf!(root)

    %{
      vanilla_ov: vanilla_ov,
      siala_ov: siala_ov,
      vanilla: Data.ruleset!("vanilla"),
      siala: Data.ruleset!("siala_41"),
      without: without
    }
  end

  defp without_decision(ov), do: update_in(ov, ["character"], &Map.delete(&1, "hit_points_shown"))

  defp character(ov, key, entry), do: put_in(ov, ["character", key], entry)

  describe "ваниль: оговорки нет, и причина — запись решения" do
    test "в ruleset'е ванили оговорки нет", %{vanilla: vanilla} do
      refute @gap in vanilla.gaps
    end

    test "основание — решение показа, а правило игры осталось броском", %{vanilla_ov: ov} do
      assert Character.hp_maximum_basis(ov) == :display_decision

      assert %{"value" => "max_to_level_3_then_roll", "status" => "verified"} =
               ov["character"]["hit_points_roll"]

      assert %{
               "value" => "always_max",
               "status" => "verified",
               "quote" => "HP ванили все равно предлагаю всегда показывать максимальное",
               "source" => %{"kind" => "user", "who" => "Dan", "date" => "2026-10-02"}
             } = ov["character"]["hit_points_shown"]
    end

    # 🔴 Положительный контроль: без записи решения оговорка возвращается сама —
    # и это ЕДИНСТВЕННОЕ, что сдвигается: ruleset ванили без неё отличается
    # только списком оговорок, и ровно на эту одну.
    test "без записи решения оговорка возвращается, и больше ничего не сдвигается", %{
      vanilla: vanilla,
      vanilla_ov: ov,
      without: without
    } do
      assert Character.hp_maximum_basis(without_decision(ov)) == nil
      assert @gap in without["vanilla"].gaps
      assert without["vanilla"].gaps -- [@gap] == vanilla.gaps
      assert %{without["vanilla"] | gaps: vanilla.gaps} == vanilla
    end
  end

  describe "Сиала: основание — правило игры, решение ванили ей не нужно" do
    test "оговорки нет, основание :game_rule", %{siala: siala, siala_ov: ov} do
      refute @gap in siala.gaps
      assert Character.hp_maximum_basis(ov) == :game_rule
      assert %{"value" => "always_max"} = ov["character"]["hit_points_roll"]
    end

    # Сиала наследует запись решения по наложению слоёв, но не спрашивает её:
    # вырезанное из ванили решение её не трогает ни в одном поле.
    test "без ванильного решения Сиала та же, поле в поле", %{siala: siala, without: without} do
      assert without["siala_41"] == siala
    end
  end

  describe "hp_maximum_basis/1 — синтетика" do
    @roll %{"value" => "max_to_level_3_then_roll", "status" => "verified"}
    @max %{"value" => "always_max", "status" => "verified"}
    @decision %{
      "value" => "always_max",
      "quote" => "слово владельца",
      "source" => %{"kind" => "user", "who" => "Dan", "date" => "2026-10-02"},
      "status" => "verified"
    }

    defp ov(entries), do: %{"character" => Map.new(entries)}

    test "таблица оснований" do
      for {entries, expected} <- [
            {[], nil},
            {[{"hit_points_roll", @roll}], nil},
            {[{"hit_points_roll", @roll}, {"hit_points_shown", @decision}], :display_decision},
            {[{"hit_points_roll", @max}], :game_rule},
            # Правило игры сильнее решения: где игра даёт максимум сама, решать нечего.
            {[{"hit_points_roll", @max}, {"hit_points_shown", @decision}], :game_rule},
            # Решение — о том, что печатать на месте БРОСКА: без правила игры
            # (или с непроверенным) оно оговорку не снимает.
            {[{"hit_points_shown", @decision}], nil},
            {[
               {"hit_points_roll", %{@roll | "status" => "unclear"}},
               {"hit_points_shown", @decision}
             ], nil},
            # Непроверенное решение — не решение.
            {[
               {"hit_points_roll", @roll},
               {"hit_points_shown", %{@decision | "status" => "unclear"}}
             ], nil}
          ] do
        assert Character.hp_maximum_basis(ov(entries)) == expected, inspect(entries)
      end
    end

    test "неизвестное значение любой из двух записей роняет сборку" do
      assert_raise RuntimeError, ~r/hit_points_roll is "average"/, fn ->
        Character.hp_maximum_basis(ov([{"hit_points_roll", %{@roll | "value" => "average"}}]))
      end

      # Ядро считает только максимум: решение показывать другое утверждало бы
      # показ, которого нет.
      assert_raise RuntimeError, ~r/hit_points_shown is "average"/, fn ->
        Character.hp_maximum_basis(
          ov([
            {"hit_points_roll", @roll},
            {"hit_points_shown", %{@decision | "value" => "average"}}
          ])
        )
      end
    end

    test "проверенное решение без автора, даты или цитаты роняет сборку" do
      for broken <- [
            Map.delete(@decision, "quote"),
            %{@decision | "quote" => "  "},
            put_in(@decision, ["source", "who"], nil),
            update_in(@decision, ["source"], &Map.delete(&1, "date")),
            put_in(@decision, ["source", "kind"], "wiki"),
            Map.delete(@decision, "source")
          ] do
        assert_raise RuntimeError, ~r/without a quote/, fn ->
          Character.hp_maximum_basis(
            ov([{"hit_points_roll", @roll}, {"hit_points_shown", broken}])
          )
        end
      end
    end

    # ⚠️ Следствие наложения слоёв, названное в обеих записях: Сиала наследует
    # решение ванили. Пока её правило игры — максимум, решение не спрашивается;
    # стань оно броском — решение ванили сработает и у неё. Тест держит это
    # следствие на виду, чтобы правка правила Сиалы не прошла мимо него.
    test "Сиала с правилом-броском жила бы ванильным решением", %{siala_ov: siala_ov} do
      assert %{"quote" => "HP ванили" <> _} = siala_ov["character"]["hit_points_shown"]

      assert Character.hp_maximum_basis(character(siala_ov, "hit_points_roll", @roll)) ==
               :display_decision
    end
  end

  describe "числа HP не сдвинулись ни на одном ruleset'е" do
    # Ожидаемые числа сняты прогоном ДО правки (02.10.2026) и сходятся
    # с арифметикой данных, человек.
    #   * Хит-дайс: `vanilla/classes.json` (Fandom, страницы классов) — fighter
    #     d10, wizard d4, rogue d6, barbarian d12, cleric d8; максимум кости
    #     на каждом уровне (`Rules.Progression.hit_points/3`).
    #   * CON: мод. × уровень персонажа (`fandom:Hit point`).
    #   * Сиала: +20 «Дух Сиалы» (`siala_41/overrides.json` →
    #     `character.spirit_of_siala`, замер A1) и `Toughness` даром на 1-м уровне
    #     у воина и варвара (`auto_feat_at_level_1`), +1 за уровень персонажа.
    #
    # Воин 1, CON 10: ваниль 10; Сиала 10 + 20 + 1 = 31 (замер A1).
    # Волшебник 20, CON 10: ваниль 20 × 4 = 80; Сиала 80 + 20 = 100.
    # Воин 10 / вор 5 / волшебник 5, CON 14: 100 + 30 + 20 + 2 × 20 = 190;
    #   Сиала 190 + 20 + 20 (Toughness с воина 1-го уровня) = 230.
    # Воин 20 / волшебник 20, CON 12 (ваниль, 40): 200 + 80 + 40 = 320.
    # Варвар 4 / воин 4 / вор 4 / клирик 29, CON 16 (Сиала, 4 класса, 41):
    #   48 + 40 + 24 + 232 + 3 × 41 + 20 + 41 = 528.
    @cases [
      {"vanilla", [fighter: 1], 10, 10},
      {"siala_41", [fighter: 1], 10, 31},
      {"vanilla", [wizard: 20], 10, 80},
      {"siala_41", [wizard: 20], 10, 100},
      {"vanilla", [fighter: 10, rogue: 5, wizard: 5], 14, 190},
      {"siala_41", [fighter: 10, rogue: 5, wizard: 5], 14, 230},
      {"vanilla", [fighter: 20, wizard: 20], 12, 320},
      {"siala_41", [barbarian: 4, fighter: 4, rogue: 4, cleric: 29], 16, 528}
    ]

    defp build(version, classes, con) do
      Build.new(
        ruleset_version: version,
        race: :human,
        levels: Enum.flat_map(classes, fn {class, n} -> List.duplicate(class, n) end),
        base_abilities: %{str: 10, dex: 10, con: con, int: 10, wis: 10, cha: 10}
      )
    end

    test "та же таблица до и после, с решением и без", %{without: without} do
      for {version, classes, con, hp} <- @cases do
        b = build(version, classes, con)
        stats = Rules.compute(b, Data.ruleset!(version))
        bare = Rules.compute(b, without[version])

        assert {stats.hp, stats.hp_naked} == {hp, hp}, "#{version} #{inspect(classes)}"
        assert {bare.hp, bare.hp_naked} == {hp, hp}, "#{version} #{inspect(classes)} без решения"
      end
    end
  end
end
