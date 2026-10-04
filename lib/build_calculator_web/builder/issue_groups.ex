defmodule BuildCalculatorWeb.Builder.IssueGroups do
  @moduledoc """
  The issues of an import report, grouped and capped — one copy for both
  import dialogs: the text import (`Builder.ImportPanel`) and the game-log
  import (`Builder.GameLogImportPanel`). Task 4.35. Since task 4.40 the two
  gear lists of the game-log report — «not ours» and «can't add up» — are
  grouped here too: they drew every line, thousands of them on a paste of
  64 KB of item properties.

  Grouped the way `Gaps.summary/3` groups gaps: a flat list of thirty notes is
  read by nobody. Order of first appearance, so the ladder's own troubles come
  before the footnotes.

  ## Capped, because a paste is somebody else's text

  The reader reports every line it did not understand, and it must (the
  moduledoc of `Builder.Import`, «Honesty»). A paste of 64 KB of `(` on every
  line is 32 000 such lines. Drawn whole (measured live, task 4.35, vanilla,
  1440 px): 32 000 `<p>` and 4.4 MB of markup, 1.7 s from «parse» to the
  painted report, and every later click in the builder 0.2 s slower for the
  hidden report still in the page. Capped: 150 lines and 20 KB, 1.3 s — most
  of it the reading itself (`Import.parse/2`, 0.95 s) — and later clicks as
  fast as with no report at all. The game-log dialog on the same paste went
  from 11.4 s and 5.6 MB to 2.0 s and 27 KB. So a group draws its first
  `shown/0` issues and says how many more there are.

  The number is the corpus's, not a guess. Over the 2027 posts of the ECB
  corpus (`tmp/vanilla_corpus/ecb_txt/`, `Import.parse/2`, both rulesets) the
  largest group of a post is 21 issues at the median, 114 at the 99th
  percentile, 296 at most; a group longer than 150 turns up in 8 posts (0.39 %),
  and all eight are «skipped lines» — the prose around a build; six of the
  eight posts yield one level or none. Every group of every other kind is
  shorter than 150 (unrecognised names at most 134), so a real post draws as it
  always did.

  A group that stopped at `shown/0` can be listed whole with one click — up
  to `listed_max/0` issues, which no post of the corpus reaches (296) and which
  still costs a fraction of what a hostile paste did. A longer group only says
  how many more there are: past a thousand lines of one kind the text is not a
  build post, and drawing it whole is exactly the cost this module is here to
  cap.

  ## Texts only for what is drawn

  An issue's text is made when it is drawn, not when the report is built: the
  hostile paste above would otherwise word 32 000 issues to show 150. A group
  keeps the raw issues it may still list (`rest`, at most `listed_max/0` in all)
  and words them in `expand/2`.
  """

  alias BuildCalculatorWeb.InputLimits

  @shown 150
  @listed_max 1_000

  @typedoc "One drawn issue: its place in the report's own list and its words."
  @type item :: %{id: pos_integer(), text: String.t()}

  @typedoc """
  One group. `items` are drawn; `rest` are the raw issues «show all» would
  add (`[]` once listed whole, and for a group longer than `listed_max/0`);
  `hidden` is how many issues of the group are not drawn.
  """
  @type group :: %{
          kind: String.t(),
          total: pos_integer(),
          items: [item()],
          rest: [{pos_integer(), term()}],
          hidden: non_neg_integer(),
          expandable?: boolean()
        }

  @doc "How many issues a group draws before «…and N more»."
  @spec shown() :: pos_integer()
  def shown, do: @shown

  @doc "The longest group «show all» lists whole."
  @spec listed_max() :: pos_integer()
  def listed_max, do: @listed_max

  @doc """
  Groups `issues` by `kind_of/1`, in order of first appearance; words the
  first `shown/0` of each with `text_of/1`.

  An item's `id` is the issue's place in `issues`, counted from 1 — the DOM id
  of its line, the same whichever group and page it lands in.

  One pass, newest first, put in order once (task 4.34: appending each issue to
  the end of its group copied the group every time — a second and more on a
  hostile paste).
  """
  @spec group([term()], (term() -> String.t()), (term() -> String.t())) :: [group()]
  def group(issues, kind_of, text_of) do
    {kinds, kept} =
      issues
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{}}, fn {issue, index}, {kinds, kept} ->
        kind = kind_of.(issue)

        case kept do
          %{^kind => {count, list}} when count < @listed_max ->
            {kinds, %{kept | kind => {count + 1, [{index, issue} | list]}}}

          %{^kind => {count, list}} ->
            {kinds, %{kept | kind => {count + 1, list}}}

          _new ->
            {[kind | kinds], Map.put(kept, kind, {1, [{index, issue}]})}
        end
      end)

    for kind <- Enum.reverse(kinds) do
      {total, list} = Map.fetch!(kept, kind)
      {drawn, rest} = list |> Enum.reverse() |> Enum.split(@shown)
      rest = if total <= @listed_max, do: rest, else: []
      build(kind, total, Enum.map(drawn, &item(&1, text_of)), rest)
    end
  end

  @doc "Lists a group whole: words its `rest`. A group with nothing left is returned as is."
  @spec expand(group(), (term() -> String.t())) :: group()
  def expand(%{rest: []} = group, _text_of), do: group

  def expand(%{rest: rest} = group, text_of),
    do: build(group.kind, group.total, group.items ++ Enum.map(rest, &item(&1, text_of)), [])

  @doc """
  `expand/2` on the group at `at` (the `phx-value-group` a button sends, a
  string), in a list of groups. An index that names no group changes nothing.
  """
  @spec expand_at([group()], term(), (term() -> String.t())) :: [group()]
  def expand_at(groups, at, text_of) do
    # Задача 4.74: число — через `InputLimits.integer/1`, а не
    # `Integer.parse(to_string(at))`: строка длиной в миллион цифр роняла
    # процесс (`SystemLimitError`), карта из события — тоже (`to_string/1`).
    case InputLimits.integer(at) do
      {index, ""} when index >= 0 -> List.update_at(groups, index, &expand(&1, text_of))
      _other -> groups
    end
  end

  defp build(kind, total, items, rest) do
    %{
      kind: kind,
      total: total,
      items: items,
      rest: rest,
      hidden: total - length(items),
      expandable?: rest != []
    }
  end

  defp item({index, issue}, text_of), do: %{id: index, text: text_of.(issue)}
end
