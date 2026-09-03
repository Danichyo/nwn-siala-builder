defmodule BuildCalculatorWeb.Builder.ImportPanel do
  @moduledoc """
  The "here's what we read" report shown by the constructor's import dialog.

  Split out of `BuildCalculatorWeb.BuilderLive` (задача 3.46, заход 4, marker
  "the import"): this is the socket-facing half of importing a pasted build —
  turning an `BuildCalculatorWeb.Builder.Import` result into the form, the
  summary rows and the grouped issue list the dialog shows. The other half,
  actually parsing the community text block, stays in `Builder.Import` — that
  module is named for the parse, this one for the report built on top of it.
  """

  alias BuildCalculator.Rules
  alias BuildCalculatorWeb.Builder.Import
  alias BuildCalculatorWeb.Builder.Labels

  import Phoenix.Component, only: [to_form: 2]

  # ------------------------------------------------------------- the import --

  def import_text(%{"import" => %{"text" => text}}) when is_binary(text), do: text
  def import_text(_params), do: ""

  def import_form(text), do: to_form(%{"text" => text}, as: :import)

  # The build is computed here and not on accept, because the whole point of the
  # second step is to show our numbers beside the source's before anything is
  # applied — a wild disagreement usually means the block was posted with gear on.
  def import_report(result, text, ruleset) do
    stats = Rules.compute(result.build, ruleset)

    %{
      text: text,
      result: result,
      summary: import_summary(result, ruleset),
      rows: Import.comparison(result, stats),
      groups: import_groups(result.issues, ruleset),
      issue_count: length(result.issues),
      apply?: result.read.anything?
    }
  end

  defp import_summary(%{read: read}, ruleset) do
    [
      %{id: "levels", label: "Уровни", value: "#{read.levels} из #{ruleset.level_cap}"},
      %{id: "race", label: "Раса", value: import_race(ruleset, read.race)},
      %{
        id: "alignment",
        label: "Мировоззрение",
        value: Labels.alignment_name(read.alignment) || "не прочитано"
      },
      %{
        id: "abilities",
        label: "Характеристики",
        value: if(read.abilities?, do: "прочитаны", else: "нет в тексте")
      },
      %{id: "feats", label: "Фиты", value: Integer.to_string(read.feats)},
      %{
        id: "increases",
        label: "Прибавки к характеристикам",
        value: Integer.to_string(read.increases)
      },
      %{id: "skills", label: "Ранги навыков", value: Integer.to_string(read.skill_ranks)}
    ]
  end

  defp import_race(_ruleset, nil), do: "не прочитана"

  defp import_race(ruleset, race),
    do: "#{Labels.race_ru(ruleset, race)} (#{Labels.race_en(ruleset, race)})"

  # Grouped the way `Gaps.summary/3` groups gaps: a flat list of thirty notes is
  # read by nobody. Order of first appearance, so the ladder's own troubles come
  # before the footnotes.
  defp import_groups(issues, ruleset) do
    issues
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {issue, index}, groups ->
      kind = Import.issue_kind(issue)
      item = %{id: index, text: Import.issue_text(issue, ruleset)}

      case Enum.find_index(groups, &(&1.kind == kind)) do
        nil -> groups ++ [%{kind: kind, items: [item]}]
        at -> List.update_at(groups, at, &%{&1 | items: &1.items ++ [item]})
      end
    end)
  end

  def import_flash([]), do: "Билд импортирован — прочиталось всё."

  # Отчёт остаётся в сокете и в окне: список того, что не прочиталось, нужен
  # как раз после применения — с ним игрок идёт править уровни.
  def import_flash(issues),
    do: "Билд импортирован. Не прочиталось: #{length(issues)} — открой «Импорт», список на месте."
end
