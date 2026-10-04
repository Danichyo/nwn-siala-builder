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
  lack", and about half of it never was that. `family/1` sorts every tuple into
  one of six families by its **form** (the head, as the core wrote it), and
  those sort cleanly into three **tiers** that answer three different questions:

    * **`:real`** — `:missing_data` / `:not_modelled` / `:build_breaks_rule`
      («Данных нет» / «Не смоделировано» / «Билд нарушает правила»): an actual
      hole the model cannot fill. These are what the header figure ought to
      have counted from the start.
    * **`:resolved`** — `:conflict` / `:derived` («Источники спорят» /
      «Выведено, не прочитано»): not a hole at all, a *decision* — how a
      conflict between two wiki pages (Fandom arguing with itself, Siala
      nowhere in it) was settled, or how a fact was derived rather than read
      verbatim. The opposite of "not carried over".
    * **`:assumed`** — `:assumed` («Допущения»): a constant or a fallback this
      layer had to pick without a page stating it outright — `base_ac`, the
      ability-modifier formula, falling back to vanilla's attacks-per-round
      table. Worth naming, not worth alarming over; two of these used to claim
      no source exists at all and that was a lie until 18.08.2026
      (`Labels.gap/2`'s own comment).

  An unclassified form (`family/1`'s `_other` clause, `:other`, printed
  «Прочее»; of the registered forms only `{:unknown_class, _}` lands there)
  sorts into `:real` rather than being swallowed quietly: the direction of
  error stays towards showing, exactly as CLAUDE.md §9 asks for everywhere
  else in this project.

  ## 🔴 Tier and order are decided by FORM, never by the translated heading (task 4.3)

  Until 4.3 the groups were keyed by `Labels.gap_kind/1`'s *translated*
  label and the tiers compared those labels with Russian literals. Under the
  `en` locale nothing matched, every group fell through to `:real`, and the
  "part of the rules is missing" banner, the export footer gate and the
  `/sources` sections opened for any ruleset (VANILLA.md §3.5). The heading
  is now only printed (`Labels.gap_family_name/1`); grouping, tier and order
  read `family/1`.

  `summary/3` and the header both read off `data_real_count` now, not
  `data_count` — the standing total is still there for whoever wants the whole
  count, but it is no longer what greets the player as "N problems".
  """

  alias BuildCalculator.Rules.GapReceivers
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

  @typedoc "What a gap is, by its form — `family/1`. Language-free on purpose."
  @type family ::
          :missing_data
          | :not_modelled
          | :build_breaks_rule
          | :conflict
          | :derived
          | :assumed
          | :other

  @typedoc "`family` decides grouping, tier and order; `kind` is only its printed heading."
  @type group :: %{
          family: family(),
          kind: String.t(),
          items: [String.t()],
          total: non_neg_integer()
        }
  @type tier :: :real | :resolved | :assumed

  # Порядок групп на экране. ⚠️ Это прежний порядок сортировки по РУССКОЙ
  # подписи («Билд нарушает правила», «Выведено, не прочитано», «Данных нет»,
  # «Допущения», «Источники спорят», «Не смоделировано», «Прочее»),
  # замороженный списком форм в задаче 4.3: сиальский экран не сдвинулся ни на
  # одну группу, а английский больше не пересортировывается по своему
  # алфавиту. Переставить по смыслу (настоящие дыры первыми) — отдельное
  # решение, а не побочный эффект перевода.
  @family_order [
    :build_breaks_rule,
    :derived,
    :missing_data,
    :assumed,
    :conflict,
    :not_modelled,
    :other
  ]

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

  @doc """
  Which of the three tiers a group (or a bare family) belongs to — see moduledoc.

  Reads the group's `family`, never its printed `kind`: the heading is
  translated, the tier is not (task 4.3).
  """
  @spec tier(group() | family()) :: tier()
  def tier(%{family: family}), do: tier(family)
  def tier(family) when family in [:conflict, :derived], do: :resolved
  def tier(:assumed), do: :assumed
  def tier(_family), do: :real

  @doc """
  The family of one gap tuple, by its form.

  ⚠️ Clauses match by ARITY as well as by head, exactly as the labels did
  before 4.3: `{:assumed, _}`, `{:assumed, _, _}` and `{:assumed, _, _, _}` are
  three shapes of one family (task 3.49 added the four-element one so the
  sentence could carry its source), while a `{:derived, _}` nobody produces
  would fall to `:other` — and so to `:real`, towards showing.
  `{:missing_file, _}` shares `:missing_data`'s heading and group on purpose.
  """
  @spec family(tuple()) :: family()
  def family({:missing_data, _}), do: :missing_data
  def family({:missing_file, _}), do: :missing_data
  def family({:not_modelled, _}), do: :not_modelled
  def family({:conflict, _}), do: :conflict
  def family({:assumed, _, _, _}), do: :assumed
  def family({:assumed, _, _}), do: :assumed
  def family({:assumed, _}), do: :assumed
  def family({:derived, _, _}), do: :derived
  def family({:skill_over_cap, _, _, _, _}), do: :build_breaks_rule
  def family(_other), do: :other

  @doc "Every family, in the order groups are printed."
  @spec families() :: [family()]
  def families, do: @family_order

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

  @doc """
  Whether the ruleset carries a shard's own facts on top of the base game —
  anything the shard layer read into classes, feats or skills
  (`Rules.GapReceivers.census/1`).

  The gate for sentences that talk ABOUT the shard's data (task 4.4): the
  «Правила шарда» section of `/sources`, the view screen's «среди них —
  кастомные системы шарда…», the clause about numbers corrected for the
  private server. Asked of the data, never of the ruleset's name (VANILLA.md
  §2, principle 1): vanilla's census is zero in every layer, and the moment a
  ruleset carries no shard layer the sentences have nothing to say.

  ⚠️ «Any layer is non-empty», not a sum: `census/1`'s own rule is that the
  layers' totals are different kinds of number and must never be added up.
  """
  @spec shard_facts?(map()) :: boolean()
  def shard_facts?(ruleset) do
    ruleset |> GapReceivers.census() |> Map.values() |> Enum.any?(&(&1.total > 0))
  end

  defp group(gaps, ruleset, limit) do
    gaps
    |> Enum.group_by(&family/1)
    |> Enum.map(fn {family, entries} ->
      %{
        family: family,
        kind: Labels.gap_family_name(family),
        total: length(entries),
        items: entries |> take(limit) |> Enum.map(&Labels.gap(&1, ruleset))
      }
    end)
    |> Enum.sort_by(&order/1)
  end

  defp order(%{family: family}), do: Enum.find_index(@family_order, &(&1 == family))

  defp take(entries, :all), do: entries
  defp take(entries, limit) when is_integer(limit), do: Enum.take(entries, limit)
end
