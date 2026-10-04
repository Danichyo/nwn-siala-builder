defmodule BuildCalculatorWeb.Builder.LadderIssueReportTest do
  @moduledoc """
  Задача 4.40, заход 2 — переводчик причин веб-слоя:

    * `Labels.ladder_issue_report/2` — тот же прогон, что `ladder_issue_entries/2`,
      плюс причины фитов по слоту (пункт 1); причины уровня сгруппированы по
      одной фразе (пункт 17);
    * `Labels.drop_slot_beside_level_refusal/1` — «нужен общий слот» не рядом
      с «только на уровне …» (пункт 14);
    * `Labels.class_step_rank/1` и `Feats.granted_display/3` — ступень, которую
      список выдач не называет (пункт 6).

  Билды — по одному левелапу с проверкой ядра (CLAUDE.md §3); «старая ссылка» —
  законный билд, у которого одно решение сменено так, как его меняет правка
  или приносит ссылка, собранная до обновления правил.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Spells}
  alias BuildCalculatorWeb.Builder.{Feats, Labels}

  setup_all do
    %{siala: Data.ruleset!("siala_41")}
  end

  setup do
    Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
    :ok
  end

  defp ladder(build, classes, ruleset) do
    Enum.reduce(classes, build, fn class, acc ->
      assert Rules.validate_level_up(acc, class, ruleset) == :ok
      Build.add_level(acc, class)
    end)
  end

  # Колдун 3, каждое заклинание — первым ещё не известным из списка класса,
  # как кладёт `pick_spell`; затем 1-й уровень сменён на воина — ссылка,
  # собранная до 4.63, или открытая на экране просмотра.
  defp sorcerer_to_fighter(ruleset) do
    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        base_abilities: %{str: 10, dex: 14, con: 14, int: 10, wis: 10, cha: 18}
      )
      |> ladder(List.duplicate(:sorcerer, 3), ruleset)

    filled =
      Enum.reduce(1..3, build, fn level, acc ->
        Enum.reduce(Spells.slots_at(acc, ruleset, level), acc, fn slot, acc ->
          known = for {_l, at} <- acc.spells, {_s, sp} <- at, into: MapSet.new(), do: sp

          spell =
            ruleset
            |> Spells.list_for(:sorcerer)
            |> Enum.find(&(&1.circle == slot.circle and not MapSet.member?(known, &1.id)))

          at = Map.put(Map.get(acc.spells, level, %{}), slot.id, spell.id)
          %{acc | spells: Map.put(acc.spells, level, at)}
        end)
      end)

    assert Rules.illegal_spells(filled, ruleset) == []
    {filled, Build.replace_level(filled, 1, :fighter)}
  end

  describe "ladder_issue_report/2 — одна причина уровня, одна строка (пункт 17)" do
    test "колдун 1 → воин: шесть заклинаний — две строки, по кругу", %{siala: siala} do
      {legal, stale} = sorcerer_to_fighter(siala)

      # Положительный контроль: законный билд — ни одной записи.
      assert Labels.ladder_issue_report(siala, legal) == %{entries: [], picks: %{}}

      names = fn circle ->
        for {{:circle, ^circle, _}, spell} <- Enum.sort(stale.spells[1]),
            do: Labels.spell_name(siala, spell)
      end

      level_1 = for {1, kind, text} <- Labels.ladder_issue_entries(siala, stale), do: {kind, text}

      assert level_1 == [
               {:spell,
                Enum.join(names.(0), ", ") <> ": этот уровень не даёт заклинаний 0 круга"},
               {:spell, Enum.join(names.(1), ", ") <> ": этот уровень не даёт заклинаний 1 круга"}
             ]

      assert length(names.(0)) == 4
      assert length(names.(1)) == 2

      # Сгруппированный ответ — и у лестницы, и у экрана просмотра.
      assert Labels.ladder_issues(siala, stale)[1] == Enum.map(level_1, &elem(&1, 1))
    end

    test "причины фита по слоту — без имени фита, тем же словом, что у лестницы", %{
      siala: siala
    } do
      build =
        Build.new(
          ruleset_version: siala.version,
          race: :human,
          alignment: :lawful_neutral,
          base_abilities: %{str: 16, dex: 13, con: 14, int: 10, wis: 10, cha: 10},
          feats: %{2 => %{{:class_bonus, :fighter} => :cleave}}
        )
        |> ladder([:fighter, :fighter], siala)

      %{entries: entries, picks: picks} = Labels.ladder_issue_report(siala, build)

      assert picks == %{{2, {:class_bonus, :fighter}} => ["нужен фит Power attack"]}
      assert {2, :feat, "Cleave: нужен фит Power attack"} in entries
    end
  end

  describe "drop_slot_beside_level_refusal/1 (пункт 14)" do
    test "бонусный слот уходит только рядом с запретом уровня" do
      slot = {:not_in_class_bonus_slot, :assassin}
      level = {:requires_leveling_as, [:bard]}
      ranks = {:requires_chosen_skill_ranks, :tumble, 20}

      assert Labels.drop_slot_beside_level_refusal([slot, ranks, level]) == [ranks, level]
      assert Labels.drop_slot_beside_level_refusal([slot, ranks]) == [slot, ranks]
      assert Labels.drop_slot_beside_level_refusal([level]) == [level]
      assert Labels.drop_slot_beside_level_refusal([]) == []
    end
  end

  describe "class_step_rank/1 и «Класс даёт сам» (пункт 6)" do
    test "три вида ступени — числа и аббревиатуры, без слов" do
      assert Labels.class_step_rank({:total, 6}) == "+6"
      assert Labels.class_step_rank({:gains, %{cha: 2, str: 4}}) == "(+4 STR, +2 CHA)"
      assert Labels.class_step_rank({:rank, "(+1 AB)"}) == "(+1 AB)"
    end

    # Воин 6 / Мастер оружия 10 / Воин 4 / Мастер оружия 21 — у Сиалы WM 31
    # на 41-м. Фиты требований — как в `prestige_epic_scales_test.exs`.
    test "Сиала: Мастер оружия 31 — Epic superior weapon focus (+1 AB), как на 28-м", %{
      siala: siala
    } do
      build =
        Build.new(
          ruleset_version: siala.version,
          race: :human,
          alignment: :lawful_neutral,
          base_abilities: %{str: 14, dex: 13, con: 12, int: 13, wis: 10, cha: 10},
          feats: %{
            1 => %{
              :general => :dodge,
              :racial => :expertise,
              {:class_bonus, :fighter} => :siala_blade_proficiency
            },
            2 => %{{:class_bonus, :fighter} => {:weapon_focus, :longsword}},
            3 => %{general: :mobility},
            4 => %{{:class_bonus, :fighter} => :spring_attack},
            6 => %{general: :whirlwind_attack},
            7 => %{{:class_bonus, :weapon_master} => {:weapon_of_choice, :longsword}}
          },
          skills: %{1 => %{intimidate: 4}}
        )
        |> ladder(
          List.duplicate(:fighter, 6) ++
            List.duplicate(:weapon_master, 10) ++
            List.duplicate(:fighter, 4) ++ List.duplicate(:weapon_master, 21),
          siala
        )

      assert Feats.granted_display(siala, build, 38) == ["Epic superior weapon focus (+1 AB)"]
      assert Feats.granted_display(siala, build, 41) == ["Epic superior weapon focus (+1 AB)"]
      assert Feats.granted_display(siala, build, 40) == []
    end
  end
end
