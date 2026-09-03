defmodule BuildCalculatorWeb.Builder.GameLogImportPanel do
  @moduledoc """
  The "here's what we read" report for the game-log import dialog.

  The socket-facing half of `BuildCalculatorWeb.Builder.GameLogImport`, split
  out the same way `BuildCalculatorWeb.Builder.ImportPanel` sits beside
  `Builder.Import`: that module is named for the parse, this one for the form,
  the summary rows and the grouped issue list `BuilderLive` renders on top of
  it.
  """

  alias BuildCalculatorWeb.Builder.GameLogImport
  alias BuildCalculatorWeb.Builder.Labels

  import Phoenix.Component, only: [to_form: 2]

  # ------------------------------------------------------------- the import --

  def text(%{"game_log_import" => %{"text" => text}}) when is_binary(text), do: text
  def text(_params), do: ""

  def form(text), do: to_form(%{"text" => text}, as: :game_log_import)

  def report(result, text, ruleset) do
    %{
      text: text,
      result: result,
      summary: summary(result, ruleset),
      groups: groups(result.issues, ruleset),
      issue_count: length(result.issues),
      apply?: result.read.anything?
    }
  end

  defp summary(%{read: read}, ruleset) do
    [
      %{id: "levels", label: "Уровни", value: "#{read.levels} из #{read.level_cap}"},
      %{id: "race", label: "Раса", value: race_value(ruleset, read.race)},
      %{id: "feats-placed", label: "Фиты в слотах", value: Integer.to_string(read.feats_placed)},
      %{
        id: "feats-auto",
        label: "Авто (класс/раса)",
        value: Integer.to_string(read.feats_auto)
      },
      %{
        id: "feats-unresolved",
        label: "Фиты не распознаны",
        value: Integer.to_string(read.feats_unresolved)
      },
      %{
        id: "feats-not-placed",
        label: "Фиты не перенесены",
        value: Integer.to_string(read.feats_not_placed)
      },
      %{
        id: "increases",
        label: "Прибавки к характеристикам",
        value: Integer.to_string(read.ability_increases)
      },
      %{id: "skills", label: "Ранги навыков", value: Integer.to_string(read.skill_ranks)}
    ]
  end

  defp race_value(_ruleset, nil), do: "не прочитана"

  defp race_value(ruleset, race),
    do: "#{Labels.race_ru(ruleset, race)} (#{Labels.race_en(ruleset, race)})"

  # Same move `Builder.ImportPanel.import_groups/2` makes: order of first
  # appearance, so the ladder's own troubles come before the footnotes.
  defp groups(issues, ruleset) do
    issues
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {issue, index}, groups ->
      kind = GameLogImport.issue_kind(issue)
      item = %{id: index, text: GameLogImport.issue_text(issue, ruleset)}

      case Enum.find_index(groups, &(&1.kind == kind)) do
        nil -> groups ++ [%{kind: kind, items: [item]}]
        at -> List.update_at(groups, at, &%{&1 | items: &1.items ++ [item]})
      end
    end)
  end

  def flash([{:alignment_unavailable}]),
    do: "Билд перенесён — прочиталось всё, что лог несёт. Мировоззрение впиши вручную."

  def flash(issues),
    do:
      "Билд перенесён. Не всё легло без вопросов (#{length(issues)}) — открой окно снова, " <>
        "список на месте."
end
