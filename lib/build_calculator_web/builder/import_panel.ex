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

  use Gettext, backend: BuildCalculatorWeb.Gettext

  alias BuildCalculator.Rules
  alias BuildCalculatorWeb.Builder.Import
  alias BuildCalculatorWeb.Builder.IssueGroups
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

  # Task 4.53: «не прочитана» / «не прочитано» / «прочитаны» agree with the row's
  # noun in Russian, hence one context per row.
  defp import_summary(%{read: read}, ruleset) do
    [
      %{
        id: "levels",
        label: gettext("Levels"),
        value: gettext("%{levels} of %{cap}", levels: read.levels, cap: ruleset.level_cap)
      },
      %{id: "race", label: gettext("Race"), value: import_race(ruleset, read.race)},
      %{
        id: "alignment",
        label: gettext("Alignment"),
        value: Labels.alignment_name(read.alignment) || pgettext("alignment", "not read")
      },
      %{
        id: "abilities",
        label: gettext("Abilities"),
        value:
          if(read.abilities?,
            do: pgettext("abilities", "read"),
            else: gettext("not in the text")
          )
      },
      %{id: "feats", label: gettext("Feats"), value: Integer.to_string(read.feats)},
      %{
        id: "increases",
        label: gettext("Ability increases"),
        value: Integer.to_string(read.increases)
      },
      %{id: "skills", label: gettext("Skill ranks"), value: Integer.to_string(read.skill_ranks)}
    ]
  end

  defp import_race(_ruleset, nil), do: pgettext("race", "not read")

  defp import_race(ruleset, race),
    do: Labels.race_label(ruleset, race)

  # Grouped and capped by `IssueGroups` — one copy with the game-log dialog
  # (task 4.35): a paste of 64 KB gives thirty thousand notes, and the report
  # draws the first 150 of a group and says how many more there are. Why 150,
  # and what «show all» may list, — its moduledoc.
  defp import_groups(issues, ruleset),
    do: IssueGroups.group(issues, &Import.issue_kind/1, &Import.issue_text(&1, ruleset))

  @doc """
  «Show all» on the report's group at `at` (the button's `phx-value-group`):
  the group is listed whole, up to `IssueGroups.listed_max/0` (task 4.35).
  """
  def expand_group(%{groups: groups} = report, at, ruleset),
    do: %{
      report
      | groups: IssueGroups.expand_at(groups, at, &Import.issue_text(&1, ruleset))
    }

  def import_flash([]), do: gettext("Build imported — everything was read.")

  # Отчёт остаётся в сокете и в окне: список того, что не прочиталось, нужен
  # как раз после применения — с ним игрок идёт править уровни.
  def import_flash(issues),
    do:
      gettext("Build imported. Not read: %{count} — the list is still under “Import…”.",
        count: length(issues)
      )
end
