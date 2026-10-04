defmodule BuildCalculator.Data.Snapshot do
  @moduledoc """
  A canonical, line-per-leaf rendering of a **loaded** ruleset, and the diff
  between two such renderings.

  This exists for one job: to answer «ruleset не изменился ни в одном поле»
  while `BuildCalculator.Data.Loader` is being cut into modules (task 3.46).
  A refactor announces itself as behaviour-preserving *by the tests*, and tests
  only cover what somebody thought of; several such passes in a row drift.
  A snapshot of the whole loaded structure does not care what anybody thought of.

  ## Not the same guard as `BuildCalculator.Wiki.ParsedSnapshotTest`

  That one pins the **JSON files** in `priv/rules/` — the output of
  `mix wiki.parse`, i.e. the parsers under `lib/build_calculator/wiki/`.
  This one pins the **loaded structure** — what `BuildCalculator.Data.ruleset!/1`
  returns, i.e. the output of `loader.ex`, which is the layer about to be cut up.
  The two are one layer apart and neither implies the other: `wiki.parse` can be
  frozen while the loader quietly reads a field differently, and the loader can
  be untouched while the parser rewrites a file. Deleting either as "a duplicate
  of the other" removes a guard, not a duplicate.

  ## What is canonicalised, and what deliberately is not

    * **Maps** — keys sorted by Erlang term order (so level 10 follows level 9,
      not level 1), with the rendered key as the tie-break. Erlang does not
      promise a map *iteration* order across releases, so an unsorted dump would
      "fail" on an OTP upgrade and get switched off within the week.
    * **Sets** (`MapSet`) — sorted the same way, and printed on **one** line
      rather than as indexed members. A set has no order, so sorting loses
      nothing; one line means adding a member is a one-line diff instead of a
      shift of every member after it.
    * **Lists — order is kept, on purpose.** A list here is data, not a bag:
      `attack_ability.rules` is scanned in order, and `gaps` reaches the player
      in order. Sorting them would hide a real change (which rule wins, what the
      build says first) behind a tidier file. The cost is that inserting into the
      middle of a list shifts the lines after it — that is a real difference and
      it should look like one.
    * **Tuples** — one line, in their own order. `{:missing_data, :max_classes}`
      is a record with a fixed shape, and it is written that way everywhere else.
    * **Empty containers still print a line** (`%{}`, `[]`, `#set[]`). Otherwise
      "the key holds nothing" and "the key is gone" look identical — and the
      second is the interesting one.

  A struct other than `MapSet` (none today) renders as the map it is, with its
  `:__struct__` key in place — verbose, but nothing is invented and nothing is
  hidden.

  Types stay distinguishable: `:foo` ≠ `"foo"`, `1` ≠ `1.0` ≠ `"1"`,
  `[]` ≠ `%{}` ≠ `#set[]`. Values are rendered with `limit: :infinity` and
  `printable_limit: :infinity`, because `inspect/1` truncates a string past 4096
  bytes by default and the Siala class layer carries quotes longer than that —
  a truncated value would compare equal to a different truncated value.

  ## Pure

  No file is read or written here: `render/1` takes the ruleset and returns a
  string, `compare/2` takes two strings. Reading the committed snapshot is the
  test's job and writing it is `mix data.snapshot`'s. `golden_path/1` is a name,
  not an access — it lives here so the task and the test cannot drift apart
  about where the file is.
  """

  @doc """
  Where the committed snapshot of `version` lives, relative to the project root.
  """
  @spec golden_path(String.t()) :: String.t()
  def golden_path(version) when is_binary(version),
    do: Path.join(["test", "snapshots", "ruleset_#{version}.snap"])

  @doc """
  The whole snapshot as text: three comment lines of header, then one line per
  leaf, `<path> = <value>`.
  """
  @spec render(map()) :: String.t()
  def render(ruleset) when is_map(ruleset) do
    version = Map.fetch!(ruleset, :version)

    header = [
      "# BuildCalculator ruleset snapshot — #{inspect(version)}",
      "# Written by `mix data.snapshot --write`, compared by ruleset_snapshot_test.exs.",
      "# One line per leaf. Maps and sets are sorted; lists keep their order. Do not edit."
    ]

    IO.iodata_to_binary(Enum.map(header ++ lines(ruleset), &[&1, ?\n]))
  end

  @doc """
  The leaf lines only, in file order.
  """
  @spec lines(term()) :: [String.t()]
  def lines(term) do
    term
    |> flatten([])
    |> Enum.map(fn {path, value} -> path <> " = " <> value end)
  end

  # --- flattening ---------------------------------------------------------

  defp flatten(%MapSet{} = set, path), do: [{path(path), term(set)}]

  defp flatten(map, path) when is_map(map) and map_size(map) == 0, do: [{path(path), "%{}"}]

  defp flatten(map, path) when is_map(map) do
    map
    |> sorted_pairs()
    |> Enum.flat_map(fn {rendered_key, value} -> flatten(value, [rendered_key | path]) end)
  end

  defp flatten([], path), do: [{path(path), "[]"}]

  defp flatten(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> flatten(value, ["[#{index}]" | path]) end)
  end

  defp flatten(value, path), do: [{path(path), term(value)}]

  defp path([]), do: "."
  defp path(reversed), do: reversed |> Enum.reverse() |> Enum.join("/")

  # --- rendering one term -------------------------------------------------

  @doc """
  One term, canonically. Public because the test asserts on the shapes above
  directly rather than by finding them in three megabytes of snapshot.
  """
  @spec term(term()) :: String.t()
  def term(%MapSet{} = set) do
    "#set[" <> (set |> Enum.sort_by(&sort_key/1) |> Enum.map(&term/1) |> Enum.join(", ")) <> "]"
  end

  def term(map) when is_map(map) do
    body =
      map
      |> sorted_pairs()
      |> Enum.map(fn {rendered_key, value} -> rendered_key <> " => " <> term(value) end)
      |> Enum.join(", ")

    "%{" <> body <> "}"
  end

  def term(list) when is_list(list),
    do: "[" <> (list |> Enum.map(&term/1) |> Enum.join(", ")) <> "]"

  def term(tuple) when is_tuple(tuple),
    do: "{" <> (tuple |> Tuple.to_list() |> Enum.map(&term/1) |> Enum.join(", ")) <> "}"

  # `printable_limit` is the one that matters: its default is 4096 bytes, and
  # `siala_41/classes.json` carries quotes past that. A truncated quote compares
  # equal to a *different* truncated quote, which is the one failure mode a
  # snapshot may not have.
  def term(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)

  # Sorted by the **term**, not by its rendering: string order would put level 4
  # between 36 and 40 and level 10 before level 2, and a snapshot nobody can read
  # is a snapshot nobody checks. Erlang's term order is total and stable, so this
  # is no less deterministic than sorting strings.
  #
  # The rendering is the tie-break, and it is not decoration: `1` and `1.0`
  # compare *equal* under `<`, so two such keys in one map would otherwise have
  # no defined order between them. Nothing in the data does that today.
  defp sorted_pairs(map) do
    map
    |> Enum.map(fn {key, value} -> {key, term(key), value} end)
    |> Enum.sort_by(fn {key, rendered, _} -> {key, rendered} end)
    |> Enum.map(fn {_key, rendered, value} -> {rendered, value} end)
  end

  defp sort_key(term), do: {term, term(term)}

  # --- comparing two snapshots --------------------------------------------

  @typedoc """
  Where two snapshots part company. `first` is the first difference **in file
  order** — the same place a diff tool would open at.
  """
  @type report :: %{
          first: {:changed | :added | :removed, non_neg_integer(), String.t(), String.t()},
          changed: non_neg_integer(),
          added: non_neg_integer(),
          removed: non_neg_integer(),
          sections: [{String.t(), non_neg_integer()}],
          committed_lines: non_neg_integer(),
          current_lines: non_neg_integer()
        }

  @doc """
  `:ok` when the two renderings are byte-identical, otherwise a report naming
  the first difference.
  """
  @spec compare(String.t(), String.t()) :: :ok | {:mismatch, report()}
  def compare(committed, current) when is_binary(committed) and is_binary(current) do
    if committed == current, do: :ok, else: {:mismatch, report(committed, current)}
  end

  defp report(committed, current) do
    expected = entries(committed)
    actual = entries(current)

    expected_paths = MapSet.new(expected, &elem(&1, 0))
    actual_paths = MapSet.new(actual, &elem(&1, 0))
    actual_values = Map.new(actual)

    removed = MapSet.difference(expected_paths, actual_paths)
    added = MapSet.difference(actual_paths, expected_paths)

    changed =
      for {path, value} <- expected,
          MapSet.member?(actual_paths, path),
          Map.fetch!(actual_values, path) != value,
          do: path

    touched = Enum.map(changed ++ MapSet.to_list(added) ++ MapSet.to_list(removed), &section/1)

    %{
      first: first_difference(expected, actual, expected_paths, actual_paths),
      changed: length(changed),
      added: MapSet.size(added),
      removed: MapSet.size(removed),
      sections: touched |> Enum.frequencies() |> Enum.sort_by(fn {name, n} -> {-n, name} end),
      committed_lines: length(expected),
      current_lines: length(actual)
    }
  end

  # Positional, not by sorted path: both files are written by the same code in
  # the same order, so the first line that differs is the first hunk a human
  # will see in `git diff`. Lists make this the honest reading — an inserted
  # element shifts everything after it, and calling that "one changed value"
  # somewhere in the middle would send the reader to the wrong place.
  defp first_difference(expected, actual, expected_paths, actual_paths) do
    index =
      Enum.find_index(Enum.zip(expected, actual), fn {left, right} -> left != right end) ||
        min(length(expected), length(actual))

    case {Enum.at(expected, index), Enum.at(actual, index)} do
      # Every leaf line matches and the files still differ: only the header did.
      # Worth saying out loud rather than crashing — a hand-edited header is the
      # one difference that is not about the ruleset at all.
      {nil, nil} ->
        {:changed, index, ".", "заголовок файла (строки данных совпали все)"}

      {nil, {path, value}} ->
        {:added, index, path, value}

      {{path, value}, nil} ->
        {:removed, index, path, value}

      {{path, expected_value}, {other_path, actual_value}} ->
        cond do
          path == other_path ->
            {:changed, index, path, "#{expected_value}  →  #{actual_value}"}

          not MapSet.member?(actual_paths, path) ->
            {:removed, index, path, expected_value}

          not MapSet.member?(expected_paths, other_path) ->
            {:added, index, other_path, actual_value}

          true ->
            {:changed, index, path, "порядок строк: #{path}  →  #{other_path}"}
        end
    end
  end

  # Values may contain " = " (the Siala layer is prose); paths, as of today, may
  # not — `no path contains the separator` is asserted in the test, so the split
  # on the first occurrence is exact rather than merely usually right.
  defp entries(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line ->
      case :binary.split(line, " = ") do
        [path, value] -> {path, value}
        [path] -> {path, ""}
      end
    end)
  end

  defp section(path), do: path |> :binary.split("/") |> hd()

  @doc """
  The report as the sentence a human needs: which ruleset, which section, which
  path, and how to regenerate once the change is meant.
  """
  @spec explain(String.t(), report()) :: String.t()
  def explain(version, report) do
    {kind, index, path, value} = report.first

    """
    ruleset #{inspect(version)} разошёлся с эталоном #{golden_path(version)}

      первое расхождение — раздел #{section(path)}, строка #{index + 1}
        #{verb(kind)}
        путь:  #{path}
        #{label(kind)}: #{value}

      строк изменено: #{report.changed}, только в эталоне: #{report.removed}, только сейчас: #{report.added}
      разделы: #{sections_line(report.sections)}
      всего строк: эталон #{report.committed_lines}, сейчас #{report.current_lines}

    Если правка задумана — перезаписать эталон и посмотреть diff глазами:

        mix data.snapshot --write && git diff #{Path.dirname(golden_path(version))}
    """
  end

  defp verb(:changed), do: "значение изменилось"
  defp verb(:added), do: "путь появился (в эталоне его нет)"
  defp verb(:removed), do: "путь исчез (в эталоне он есть)"

  defp label(:changed), do: "было → стало"
  defp label(:added), do: "значение"
  defp label(:removed), do: "значение"

  defp sections_line([]), do: "—"

  defp sections_line(sections),
    do: sections |> Enum.map(fn {name, n} -> "#{name} #{n}" end) |> Enum.join(", ")
end
