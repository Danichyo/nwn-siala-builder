defmodule BuildCalculator.Rules.WeaponSpecializationClubTest do
  @moduledoc """
  Задача 4.43: Weapon specialization (club) на Сиале берётся без Fighter 4.

  Источники:

    * хак Сиалы, `priv/hak/2da/feat.2da`, строка 47 (`WeapSpeClub`) — без
      `MinLevel` / `MinLevelClass`; у остальных 39 строк семейства с порогом —
      `MinLevel 4`, `MinLevelClass 4`, как у базовой игры
      (`priv/base_2da/feat.2da`; сторож — `feat_requirements_hak_test.exs`);
    * замер Dan 27.09.2026, `GAME_CHECKS.md` `BB1`: «Дубина предлагается,
      рукопашный — нет» — варвар 4 → воин 1 с Weapon Focus (club) и Weapon
      Focus (unarmed strike), бонусный слот воина;
    * ваниль: Fandom «Weapon specialization» (revid 41492), Notes — «Four
      fighter levels are required to take this feat», и базовый `feat.2da:47`
      `MinLevel 4` (запись `vanilla/feat_requirements.json`, задача 4.25).

  🔴 Персонаж собирается так, как его собирает игрок: КАЖДЫЙ уровень — через
  `Rules.validate_level_up/3`, каждый фит уровня — через
  `Rules.validate_feat_pick/3` до того, как лечь в слот, и слот обязан быть
  у уровня и принимать фит (`FeatSlots`). `Build.new(levels: …)` валидацию
  не проходит вовсе (CLAUDE.md §3) — невозможный билд был бы измерен как
  законный.

  Обе стороны вопроса на ОБОИХ ruleset'ах: проверка пика (`validate_feat_pick/3`,
  `illegal_feats/2`) и список значений, который отдаёт ядро
  (`feat_choice_candidates/3` плюс вердикт по каждому значению, собранный тем
  же кодом, что рисует экран, — `Builder.Feats.choice_options/5`).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatSlots}
  alias BuildCalculatorWeb.Builder.Feats

  @fighter_bonus {:class_bonus, :fighter}
  @fighter_4 {:requires_class_level, :fighter, 4}

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  # Один левелап, как в игре: класс, потом фиты этого уровня — каждый в слот,
  # который у уровня есть и фит принимает, и каждый законен в момент выбора.
  defp level_up(%Build{} = build, ruleset, class, picks \\ []) do
    assert :ok = Rules.validate_level_up(build, class, ruleset),
           "#{ruleset.version}: #{class} на #{Build.character_level(build) + 1}-м"

    build = Build.add_level(build, class)
    level = Build.character_level(build)

    Enum.reduce(picks, build, fn {slot_id, feat, choice}, acc ->
      slot = Enum.find(FeatSlots.at(acc, ruleset, level), &(&1.id == slot_id))

      assert slot, "#{ruleset.version}: у #{level}-го уровня нет слота #{inspect(slot_id)}"
      assert FeatSlots.accepts?(ruleset, slot, feat)

      pick = %{feat: feat, choice: choice, at: level, slot: slot_id}

      assert :ok = Rules.validate_feat_pick(acc, pick, ruleset),
             "#{ruleset.version}: #{feat} (#{choice}) на #{level}-м"

      Build.put_feat(acc, level, slot_id, feat, choice)
    end)
  end

  defp fresh(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      alignment: :chaotic_neutral,
      base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}
    )
  end

  # Персонаж замера BB1: человек, варвар 4 → воин 1. Weapon Focus (club)
  # и (unarmed strike) — общий и расовый слоты 1-го уровня. Ни дубина, ни
  # рукопашный удар владения не требуют ни на одном ruleset'е (Сиала — замер
  # Dan 16.08.2026; ваниль — дубину берёт Simple, который варвару выдан).
  defp bb1(ruleset, fighter_levels \\ 1) do
    ruleset
    |> fresh()
    |> level_up(ruleset, :barbarian, [
      {:general, :weapon_focus, :club},
      {:racial, :weapon_focus, :unarmed_strike}
    ])
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :barbarian)
    |> then(fn build ->
      Enum.reduce(1..fighter_levels//1, build, fn _, acc -> level_up(acc, ruleset, :fighter) end)
    end)
  end

  # Контроль кейса BB1 — длинный меч, с настоящим Weapon Focus (longsword),
  # чтобы отказ был ровно один и про уровни воина. На Сиале длинный меч просит
  # её клинковое владение (замер 3.99), на ванили его даёт варвару класс.
  defp longsword_control(%{version: "siala_41"} = ruleset) do
    ruleset
    |> fresh()
    |> level_up(ruleset, :barbarian, [
      {:general, :siala_blade_proficiency, nil},
      {:racial, :weapon_focus, :longsword}
    ])
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :fighter)
  end

  defp longsword_control(%{version: "vanilla"} = ruleset) do
    ruleset
    |> fresh()
    |> level_up(ruleset, :barbarian, [{:general, :weapon_focus, :longsword}])
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :barbarian)
    |> level_up(ruleset, :fighter)
  end

  # Вопрос бонусного слота воина на 5-м уровне про одно значение.
  defp ws(build, ruleset, choice) do
    Rules.validate_feat_pick(
      build,
      %{feat: :weapon_specialization, choice: choice, at: 5, slot: @fighter_bonus},
      ruleset
    )
  end

  # Что видит игрок на втором шаге выбора: допустимые значения и заблокированные
  # с причиной — по тем значениям, о которых спрашивает тест.
  defp offered(build, ruleset, values) do
    options = Feats.choice_options(ruleset, build, 5, :weapon_specialization, @fighter_bonus)
    pick = fn list -> for o <- list, o.value in values, into: %{}, do: {o.value, o.reasons} end

    %{allowed: options.allowed |> pick.() |> Map.keys(), blocked: pick.(options.blocked)}
  end

  describe "сценарий BB1 — проверка пика" do
    test "Сиала: дубина в бонусном слоте воина проходит, рукопашный и длинный меч — нет", %{
      siala: siala
    } do
      build = bb1(siala)

      assert Build.class_levels(build) == %{barbarian: 4, fighter: 1}
      assert ws(build, siala, :club) == :ok
      assert ws(build, siala, :unarmed_strike) == {:error, [@fighter_4]}
      assert ws(longsword_control(siala), siala, :longsword) == {:error, [@fighter_4]}
    end

    # 🔴 Ваниль не сдвигается: там дубина требует воина 4, как все сорок строк
    # базового `feat.2da`.
    test "ваниль: дубина — отказ по Fighter 4, как рукопашный и длинный меч", %{vanilla: vanilla} do
      build = bb1(vanilla)

      assert ws(build, vanilla, :club) == {:error, [@fighter_4]}
      assert ws(build, vanilla, :unarmed_strike) == {:error, [@fighter_4]}
      assert ws(longsword_control(vanilla), vanilla, :longsword) == {:error, [@fighter_4]}
    end

    # Граница с другой стороны: воин 4 — порог семейства пройден, и рукопашный
    # проходит на обоих ruleset'ах; дубина на Сиале проходила и раньше.
    test "воин 4 снимает отказ у всех значений на обоих ruleset'ах", %{
      vanilla: vanilla,
      siala: siala
    } do
      for ruleset <- [vanilla, siala] do
        build = bb1(ruleset, 4)
        pick = &%{feat: :weapon_specialization, choice: &1, at: 8, slot: @fighter_bonus}

        assert Rules.validate_feat_pick(build, pick.(:club), ruleset) == :ok
        assert Rules.validate_feat_pick(build, pick.(:unarmed_strike), ruleset) == :ok
      end
    end

    # Строка фита на первом шаге выбора — без значения. На Сиале она открыта:
    # законное значение у персонажа есть. На ванили — закрыта прежней причиной.
    test "строка фита без значения: Сиала открыта, ваниль — Fighter 4", %{
      vanilla: vanilla,
      siala: siala
    } do
      assert Rules.validate_feat(bb1(siala), %{feat: :weapon_specialization, at: 5}, siala) == :ok

      assert Rules.validate_feat(bb1(vanilla), %{feat: :weapon_specialization, at: 5}, vanilla) ==
               {:error, [@fighter_4]}
    end

    # Сыгранный билд: взятый на воине 1 Weapon specialization (club). Сиала
    # его не называет, ваниль называет уровнем класса — на той строке, где он
    # стоит.
    test "взятая дубина на воине 1: Сиала легальна, ваниль называет порог", %{
      vanilla: vanilla,
      siala: siala
    } do
      taken = fn ruleset ->
        Build.put_feat(bb1(ruleset), 5, @fighter_bonus, :weapon_specialization, :club)
      end

      assert Rules.illegal_feats(taken.(siala), siala) == []

      assert Rules.illegal_feats(taken.(vanilla), vanilla) ==
               [{5, @fighter_bonus, :weapon_specialization, @fighter_4}]
    end
  end

  describe "сценарий BB1 — список значений" do
    # Кандидаты ядра — значения, у которых есть Weapon Focus (`same_choice_as`);
    # порог по уровню класса их не сужает, он даёт причину на втором шаге.
    test "ядро предлагает оба значения на обоих ruleset'ах", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        assert Rules.feat_choice_candidates(
                 bb1(ruleset),
                 %{feat: :weapon_specialization, at: 5, slot: @fighter_bonus},
                 ruleset
               ) == {:ok, [:club, :unarmed_strike]}
      end
    end

    test "Сиала: дубина доступна, рукопашный и длинный меч заблокированы прежней причиной", %{
      siala: siala
    } do
      assert offered(bb1(siala), siala, [:club, :unarmed_strike]) ==
               %{allowed: [:club], blocked: %{unarmed_strike: [@fighter_4]}}

      assert offered(longsword_control(siala), siala, [:longsword]) ==
               %{allowed: [], blocked: %{longsword: [@fighter_4]}}
    end

    test "ваниль: дубина заблокирована тем же Fighter 4", %{vanilla: vanilla} do
      assert offered(bb1(vanilla), vanilla, [:club, :unarmed_strike]) ==
               %{allowed: [], blocked: %{club: [@fighter_4], unarmed_strike: [@fighter_4]}}

      assert offered(longsword_control(vanilla), vanilla, [:longsword]) ==
               %{allowed: [], blocked: %{longsword: [@fighter_4]}}
    end
  end

  # 🔴 Положительный контроль на саму запись: сними её из слоя Сиалы — и Сиала
  # снова строже хака, ровно как до задачи (ложный отказ BB1).
  describe "без записи слоя Сиалы" do
    setup do
      root = BuildCalculator.TmpDir.unique_path!()
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    defp edit_shard_record(root, fun) do
      path = Path.join(root, "siala_41/feats.json")
      data = path |> File.read!() |> Jason.decode!()

      feats =
        Enum.map(data["feats"], fn entry ->
          if entry["id"] == "weapon_specialization", do: fun.(entry), else: entry
        end)

      File.write!(path, Jason.encode!(%{data | "feats" => feats}))
    end

    test "Сиала снова отказывает дубине по Fighter 4", %{root: root} do
      edit_shard_record(root, &Map.put(&1, "changes", []))
      siala = Loader.load!(root)["siala_41"]

      refute Map.has_key?(siala.feats[:weapon_specialization].prereqs, "class_levels_by_choice")
      assert ws(bb1(siala), siala, :club) == {:error, [@fighter_4]}
    end

    # Значение, которого нет в справочнике оружия, не совпало бы ни с одним
    # пиком — и запись уверяла бы, что порог снят. Сборка падает.
    test "опечатка в значении роняет сборку", %{root: root} do
      edit_shard_record(root, fn entry ->
        update_in(entry, ["changes", Access.at(0), "value", "choice"], fn _ -> "clubs" end)
      end)

      assert_raise RuntimeError,
                   ~r/weapon_specialization: class_levels_by_choice names "clubs"/,
                   fn ->
                     Loader.load!(root)
                   end
    end
  end
end
