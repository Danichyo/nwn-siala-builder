defmodule BuildCalculator.Rules.GearImportReasonExamplesTest do
  @moduledoc """
  Guards `Rules.GearImport.reason_examples/0` (task 3.213, part of the web
  agent's finding: the import dialog rendered `:ability_unknown`,
  `:skill_unknown` and `:save_unknown` through its `"Не распознано"`/
  `inspect/1` fallback, because nothing had ever walked the full
  `reason()`/`worn_reason()` union to notice three constructors had no
  Russian sentence at all — see `GameLogImportPanelReasonLabelsTest` for the
  web-layer half of that guard).

  This file keeps the catalogue honest from the other side: every entry
  `reason_examples/0` declares is reproduced here by a REAL call to
  `GearImport.sum/2,3` on a minimal synthetic item — the same technique
  `GearImportTest` already uses for the three `worn_reason/0` forms (задача
  3.213's own core commit), extended to the three `reason/0` forms that
  commit did not need to touch. Nothing in the catalogue is a shape invented
  for the list and never actually produced.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.GearImport

  setup_all do: %{ruleset: Data.ruleset!("siala_41")}

  defp item(slot, name, properties, extras \\ %{}),
    do: Map.merge(%{slot: slot, name: name, properties: properties}, extras)

  # 🔴 A form is the head **plus the subject beside it** where the head is one
  # the panel dispatches on twice — exactly `Rules.Vocabulary.form/1`'s
  # `@families` device, and for the same reason. Задача 3.210 brought the first
  # head with two subjects: `{:decided_not_modelled, :spell_resistance}` and
  # `{:decided_not_modelled, :physical}` are two mechanics the owner decided not
  # to count, each with its own Russian sentence
  # (`GameLogImportPanel.gear_reason_text/2` has a clause per subject). Keying
  # by the bare head would call the second one a duplicate of the first and push
  # the catalogue towards one sentence for both — which is how a subject loses
  # its wording and falls back to `inspect/1`, the very defect this file guards.
  @families ~w(decided_not_modelled property_not_modelled)a

  defp form(tuple) do
    head = elem(tuple, 0)

    if head in @families and tuple_size(tuple) >= 2,
      do: {head, elem(tuple, 1)},
      else: head
  end

  test "the catalogue has no duplicate forms" do
    forms = Enum.map(GearImport.reason_examples(), &form/1)
    assert Enum.uniq(forms) == forms
  end

  # ⚠️ The finding itself: `known/3` (`ability_bonus`, `skill_bonus`,
  # `saving_throw_specific`) reads `property.param` straight through when it
  # is not an atom — and `GameLog.equip_atom/2` hands it `{:unresolved, text}`
  # for anything it cannot resolve, never a bare atom (CLAUDE.md §9: no
  # `String.to_atom/1` on log text). So the realistic shape is a
  # two-element tuple carrying that pair, not a bare unresolved atom.
  describe "the three forms nothing had reached before this task" do
    test "ability_unknown: an unrecognised Ability Bonus parameter", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{kind: :ability_bonus, param: {:unresolved, "Some Ability"}, value: 3, raw: "[1] x"}
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: reason}] = report.unresolved
      assert reason in GearImport.reason_examples()
      assert reason == {:ability_unknown, {:unresolved, "Some Ability"}}
    end

    test "skill_unknown: an unrecognised Skill Bonus parameter", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{kind: :skill_bonus, param: {:unresolved, "Some Skill"}, value: 3, raw: "[1] x"}
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: reason}] = report.unresolved
      assert reason in GearImport.reason_examples()
      assert reason == {:skill_unknown, {:unresolved, "Some Skill"}}
    end

    test "save_unknown: an unrecognised specific-save parameter", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{
            kind: :saving_throw_specific,
            param: {:unresolved, "Some Save"},
            value: 3,
            raw: "[1] x"
          }
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: reason}] = report.unresolved
      assert reason in GearImport.reason_examples()
      assert reason == {:save_unknown, {:unresolved, "Some Save"}}
    end
  end

  # Задача 3.210. Обе формы приходят из ОДНОЙ строки лога — `Damage Resistance
  # (X) N`, — и вся разница в том, что за `X`: вид урона, который секция
  # не показывает решением владельца, или имя, которого не знает ни один
  # из двух словарей. ⚠️ Разница дорогая: первая фраза говорит «это не наш
  # вопрос», вторая — «наш, и мы не смогли», то есть попадает в список
  # доработок сервера.
  describe "две формы поглощения стихийного урона (задача 3.210)" do
    test "decided_not_modelled: физическое поглощение — решение владельца", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{
            kind: :damage_resistance,
            param: {:unresolved, "Bludgeoning"},
            value: 10,
            raw: "[1] Damage Resistance (Bludgeoning) 10"
          }
        ])
      ]

      {gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: reason}] = report.not_ours
      assert reason == {:decided_not_modelled, :physical}
      assert reason in GearImport.reason_examples()
      # и ни в одну стихию оно при этом не попало
      assert gear.resistances == %{}
    end

    test "resistance_unknown: имени не знает ни один словарь", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{
            kind: :damage_resistance,
            param: {:unresolved, "Some Damage Type"},
            value: 10,
            raw: "[1] Damage Resistance (Some Damage Type) 10"
          }
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: reason}] = report.unresolved
      assert reason == {:resistance_unknown, {:unresolved, "Some Damage Type"}}
      assert reason in GearImport.reason_examples()
    end

    # Положительный контроль к обоим: божественный урон — тоже исключённый,
    # но по ДРУГОЙ причине (не поглощается в самой игре), и фраза у него
    # другая — «не наша механика», как у `Cast Spell` и `Regeneration`.
    test "property_not_modelled: божественный урон не поглощается вовсе", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{
            kind: :damage_resistance,
            param: {:unresolved, "Divine"},
            value: 15,
            raw: "[1] Damage Resistance (Divine) 15"
          }
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: {:property_not_modelled, :divine}}] = report.not_ours
    end
  end

  # Задача 3.221. Две формы приходят из ОДНОЙ клаузы (`:other`), и различает
  # их ровно один вопрос: прочитал ли разбиратель текста ИМЯ свойства. Атом —
  # прочитал, и «не наша механика» есть наше утверждение; строка — не прочитал,
  # и утверждать про неё что бы то ни было нельзя (урок 3.213).
  describe "имя свойства: прочитано против непрочитанного (задача 3.221)" do
    test "property_not_modelled: имя прочитано, получателя у механики нет", %{ruleset: ruleset} do
      items = [
        item(:chest, "нагрудник", [
          %{kind: :other, param: :cast_spell, raw: "[1] Cast Spell (Unique Power) 13"}
        ])
      ]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: reason}] = report.not_ours
      assert reason == {:property_not_modelled, :cast_spell}
      assert reason in GearImport.reason_examples()
    end

    test "property_name_unknown: имени не знает ни одна ветка разбора", %{ruleset: ruleset} do
      raw = "[3] Fancy New Property (65535) 4"
      items = [item(:chest, "нагрудник", [%{kind: :other, raw: raw}])]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert [%{reason: reason}] = report.unresolved
      assert reason == {:property_name_unknown, raw}
      assert reason in GearImport.reason_examples()
    end
  end

  # `GearImportTest` (`описание "база доспеха из [BaseAC:n]"`) already proves
  # each of these reachable on its own; this repeats the call once more, next
  # to the other two forms, so a drift between the two files' shapes fails
  # here instead of only silently widening the web layer's blind spot.
  describe "the three worn_reason/0 forms task 3.213 added" do
    test "armor_base_not_printed: an older saved log, no [BaseAC] at all", %{ruleset: ruleset} do
      items = [item(:chest, "Нагрудник Призрака", [%{kind: :ac_bonus, value: 6, raw: "[1] x"}])]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert report.worn.chest.reason == {:armor_base_not_printed, :chest}
      assert report.worn.chest.reason in GearImport.reason_examples()
    end

    test "armor_base_unresolved: a printed base no armour row claims", %{ruleset: ruleset} do
      items = [item(:chest, "Нечто", [], %{base_ac: 99})]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert report.worn.chest.reason == {:armor_base_unresolved, 99}
      assert report.worn.chest.reason in GearImport.reason_examples()
    end

    test "armor_base_rule_missing: the snapshot names no category for the base", %{
      ruleset: ruleset
    } do
      ruleset =
        update_in(ruleset.gear.item_slot_ac_types, fn rows ->
          for row <- rows, do: %{row | worn_category_by_base_ac: nil}
        end)

      items = [item(:chest, "Нагрудник Призрака", [], %{base_ac: 8})]

      {_gear, report} = GearImport.sum(items, ruleset)

      assert report.worn.chest.reason == {:armor_base_rule_missing, :chest}
      assert report.worn.chest.reason in GearImport.reason_examples()
    end
  end
end
