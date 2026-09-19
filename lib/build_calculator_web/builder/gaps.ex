defmodule BuildCalculatorWeb.Builder.Gaps do
  @moduledoc """
  Everything the calculator could not work out honestly, gathered for display.

  `Rules.compute/2` returns `nil` for what it cannot compute and puts the reason
  in `stats.gaps`; the data layer does the same for the shard rules that were
  never transcribed. **That is the honesty mechanism of the whole project
  (CLAUDE.md §9), and it only exists if the interface shows it** — an unshown
  gap is indistinguishable from a confident wrong answer.

  Three sources, kept apart because they mean different things:

    * **этот билд** — `stats.gaps`: what is missing *for these numbers*, plus
      the web layer's own (a taken feat whose prerequisites are prose).
    * **данные** — `ruleset.gaps`: rules of Siala not carried across yet. This
      list is long by design and stays long until the wiki is fully mined; the
      header banner used to summarise it unconditionally (CLAUDE.md §6,
      "постоянная, а не по требованию"). Task 3.88 (24.08.2026, Dan) narrowed
      that: once the `:real` tier of this list hits zero, everything left in
      it is a *decision* (a resolved conflict, an accepted constant), not a
      hole, and showing a "part of the rules is missing" banner over a list
      of decisions would be the wrong kind of dishonest. The banner is a gate
      on `data_real_count`, not a fixed fixture — see `builder_live.html.heex`
      and `build_view_live.html.heex` for the two places it lives, and
      `Export.footer/3` for the same gate in the text export.
    * **веб-слой** — assumptions this layer had to make. The point-buy table
      used to be one of them; it now comes from `priv/rules/` like everything
      else, and the gap it owed is gone.

  ## `ruleset.gaps` is not one list, it is three (task 3.49, 18.08.2026)

  Dan read the standing "38 пробелов" figure as "38 things Siala's rules still
  lack", and about half of it never was that. `Labels.gap_kind/1` already sorts
  every tuple into one of five Russian labels, and those five sort cleanly into
  three **tiers** that answer three different questions:

    * **`:real`** — "Данных нет" / "Не смоделировано" / "Билд нарушает
      правила": an actual hole the model cannot fill. These are what the header
      figure ought to have counted from the start.
    * **`:resolved`** — "Источники спорят" / "Выведено, не прочитано": not a
      hole at all, a *decision* — how a conflict between two wiki pages (Fandom
      arguing with itself, Siala nowhere in it) was settled, or how a fact was
      derived rather than read verbatim. The opposite of "not carried over".
    * **`:assumed`** — "Допущения": a constant or a fallback this layer had to
      pick without a page stating it outright — `base_ac`, the ability-modifier
      formula, falling back to vanilla's attacks-per-round table. Worth naming,
      not worth alarming over; two of these used to claim no source exists at
      all and that was a lie until 18.08.2026 (`Labels.gap/2`'s own comment).

  An unclassified kind (`gap_kind/1`'s `_other` clause, "Прочее" — should not
  happen, nothing produces it today) sorts into `:real` rather than being
  swallowed quietly: the direction of error stays towards showing, exactly as
  CLAUDE.md §9 asks for everywhere else in this project.

  `summary/3` and the header both read off `data_real_count` now, not
  `data_count` — the standing total is still there for whoever wants the whole
  count, but it is no longer what greets the player as "N problems".
  """

  alias BuildCalculatorWeb.Builder.{Feats, Labels}

  # Long enough to be useful, short enough that the panel stays a panel.
  @per_group 8

  # ⚠️ Данных гэпов на два порядка больше, чем своих: 127 против единиц
  # (`siala_41`, посчитано `length(ruleset.gaps)` 09.08.2026 — 105 из них
  # в группе «Не смоделировано»). Поэтому у них своя, меньшая выборка, и она
  # живёт **здесь**, а не в шаблоне: до 09.08.2026 обрезаний было два — восемь
  # тут и ещё три в `builder_live.html.heex`, — и модуль не мог назвать, сколько
  # строк игрок в самом деле видит. Панель обязана называть размер выборки
  # (`data_shown`), иначе «оно и так в гэпах» превращается в «оно есть в списке,
  # которого не видно» — ровно та ловушка, на которой задача 3.8 поймала себя
  # (перенос текста «в гэпы» убрал бы его с экрана целиком: строка стояла 98-й).
  @per_data_group 3

  @type group :: %{kind: String.t(), items: [String.t()], total: non_neg_integer()}
  @type tier :: :real | :resolved | :assumed

  # `gap_kind/1`'s five labels, sorted into the three tiers `@moduledoc`
  # describes. A kind not listed here (should not happen — `gap_kind/1`'s
  # only unlisted output is "Прочее", produced by nothing today) falls through
  # to `:real` in `tier/1` below rather than vanishing from the count.
  @resolved_kinds MapSet.new(["Источники спорят", "Выведено, не прочитано"])
  @assumed_kinds MapSet.new(["Допущения"])

  @doc """
  Gap summary for the current build and ruleset.

  `build_count` is the number worth reacting to; `data_count` is the standing
  total of everything `ruleset.gaps` carries (real holes, resolved conflicts
  and accepted assumptions alike); `data_real_count` is what the header and the
  gaps toggle actually lead with — real holes only, the tier described in the
  moduledoc. `data_shown` is how many example sentences the panel prints across
  all three tiers combined — the panel says so, because a sample presented as a
  list reads as the whole list.
  """
  @spec summary(map(), BuildCalculator.Rules.Build.t(), map()) :: %{
          build_count: non_neg_integer(),
          data_count: non_neg_integer(),
          data_real_count: non_neg_integer(),
          data_resolved_count: non_neg_integer(),
          data_assumed_count: non_neg_integer(),
          data_shown: non_neg_integer(),
          build_groups: [group()],
          data_groups_real: [group()],
          data_groups_resolved: [group()],
          data_groups_assumed: [group()]
        }
  def summary(ruleset, build, stats) do
    build_gaps = stats.gaps ++ Feats.gaps(ruleset, build)
    data_gaps = ruleset.gaps
    data_groups = group(data_gaps, ruleset, @per_data_group)
    by_tier = Enum.group_by(data_groups, &tier/1)
    real = Map.get(by_tier, :real, [])
    resolved = Map.get(by_tier, :resolved, [])
    assumed = Map.get(by_tier, :assumed, [])

    %{
      build_count: length(build_gaps),
      data_count: length(data_gaps),
      data_real_count: Enum.sum_by(real, & &1.total),
      data_resolved_count: Enum.sum_by(resolved, & &1.total),
      data_assumed_count: Enum.sum_by(assumed, & &1.total),
      data_shown: Enum.sum_by(data_groups, &length(&1.items)),
      build_groups: group(build_gaps, ruleset, @per_group),
      data_groups_real: real,
      data_groups_resolved: resolved,
      data_groups_assumed: assumed
    }
  end

  @doc "Which of the three tiers a `Labels.gap_kind/1` group belongs to — see moduledoc."
  @spec tier(group()) :: tier()
  def tier(%{kind: kind}) do
    cond do
      MapSet.member?(@resolved_kinds, kind) -> :resolved
      MapSet.member?(@assumed_kinds, kind) -> :assumed
      true -> :real
    end
  end

  @doc """
  Every data-tier group, **unsampled**, sorted the same three ways as
  `summary/3` — the methodology `/sources` prints (task 3.88, 24.08.2026):
  once a real hole no longer justifies a warning on the build screens, the
  resolved conflicts and accepted constants that used to sit next to it in
  the same panel still need a place that answers "откуда правила" honestly,
  in full, not as a three-item sample. `summary/3` keeps its own sampled
  call to `group/3` (`@per_data_group`, a space-constrained panel) rather
  than reusing this — the two answer different questions on purpose.
  """
  @spec data_tiers(map()) :: %{real: [group()], resolved: [group()], assumed: [group()]}
  def data_tiers(ruleset) do
    by_tier = ruleset.gaps |> group(ruleset, :all) |> Enum.group_by(&tier/1)

    %{
      real: Map.get(by_tier, :real, []),
      resolved: Map.get(by_tier, :resolved, []),
      assumed: Map.get(by_tier, :assumed, [])
    }
  end

  defp group(gaps, ruleset, limit) do
    gaps
    |> Enum.group_by(&Labels.gap_kind/1)
    |> Enum.map(fn {kind, entries} ->
      %{
        kind: kind,
        total: length(entries),
        items: entries |> take(limit) |> Enum.map(&Labels.gap(&1, ruleset))
      }
    end)
    |> Enum.sort_by(& &1.kind)
  end

  defp take(entries, :all), do: entries
  defp take(entries, limit) when is_integer(limit), do: Enum.take(entries, limit)
end
