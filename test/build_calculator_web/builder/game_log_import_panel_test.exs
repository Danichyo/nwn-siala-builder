defmodule BuildCalculatorWeb.Builder.GameLogImportPanelReasonLabelsTest do
  @moduledoc """
  Guards `GameLogImportPanel`'s translator against the fallback silently
  eating a real form — задача 3.213, п. 4 постановки.

  Same idea as `BuildCalculator.Rules.VocabularyTest`, at the scale this
  module's own two small closed unions actually need: walk
  `BuildCalculator.Rules.GearImport.reason_examples/0` (itself guarded by
  `BuildCalculator.Rules.GearImportReasonExamplesTest` against being
  fiction — every entry there is reproduced by a real call) and require
  every one to render as a real Russian sentence, never the catch-all
  `"Не распознано"` and never `inspect/1` of the bare tuple.

  🔴 **What this catches, named once so it is not rediscovered by accident:**
  `:ability_unknown`, `:skill_unknown` and `:save_unknown` are real, reachable
  `reason/0` forms (`GearImport.known/3` produces them whenever a log names
  an ability, skill or save the ruleset does not recognise), and until this
  task nothing had ever walked the full union to notice `gear_reason_kind/1`
  and `gear_reason_text/2` had no clause for any of the three — the import
  dialog rendered them as `"Не распознано"` grouped with genuine mismatches,
  or as a raw `{:ability_unknown, …}` tuple, whichever ran first.

  ⚠️ **What this does NOT catch:** a fourth constructor added to
  `@type reason/0` or `@type worn_reason/0` in `Rules.GearImport` without a
  matching entry in `reason_examples/0`. That type is not introspected here
  (task 3.213 deliberately kept the new core surface to one small function,
  not a source scan) — the registry is only as complete as its own upkeep,
  same as `Vocabulary`'s before its two scans existed.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.GearImport
  alias BuildCalculatorWeb.Builder.GameLogImportPanel

  setup_all do: %{ruleset: Data.ruleset!("siala_41")}

  # `reason/0` и `worn_reason/0` не пересекаются по головам ни одной формой,
  # так что один проход различает их по голове, а не по типу-обёртке.
  @worn_reason_heads ~w(armor_base_not_printed armor_base_unresolved armor_base_rule_missing)a

  test "every declared example has real Russian wording, not the fallback", %{ruleset: ruleset} do
    for reason <- GearImport.reason_examples() do
      text = reason_text(reason, ruleset)

      refute text =~ ~r/^\{/,
             "#{inspect(reason)} rendered as a raw tuple, not a sentence: #{inspect(text)}"

      assert text =~ ~r/[а-яё]/iu,
             "#{inspect(reason)} rendered without a single Cyrillic letter: #{inspect(text)}"
    end
  end

  test "every reason/0 example is grouped under a real kind, not the catch-all", %{
    ruleset: _ruleset
  } do
    for reason <- GearImport.reason_examples(), elem(reason, 0) not in @worn_reason_heads do
      kind = GameLogImportPanel.gear_reason_kind(reason)

      refute kind == "Не распознано",
             "#{inspect(reason)} falls through gear_reason_kind/1 to the catch-all"
    end
  end

  defp reason_text(reason, ruleset) do
    if elem(reason, 0) in @worn_reason_heads do
      GameLogImportPanel.gear_worn_reason_text(reason)
    else
      GameLogImportPanel.gear_reason_text(reason, ruleset)
    end
  end
end
