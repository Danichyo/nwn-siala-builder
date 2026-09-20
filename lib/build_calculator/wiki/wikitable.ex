defmodule BuildCalculator.Wiki.Wikitable do
  @moduledoc """
  Parses MediaWiki `{| ... |}` tables into a rectangular grid.

  The class pages on Fandom keep their level progressions in wikitables whose
  headers are two rows deep and stitched together with `rowspan`/`colspan`, plus
  blank spacer columns declared as `!rowspan="22" style="background:#ffffff"|&nbsp;`
  that occupy a column in every body row without ever appearing in one. Splitting
  such a row on `||` and zipping it against the first header row lines the numbers
  up against the wrong columns — silently, and only for some classes. So the table
  is resolved properly instead: rows are cut on `|-`, cells on `||`/`!!` (skipping
  separators nested inside `[[…]]`, `{{…}}` or an inner table), cell attributes are
  split off, and `expand/1` materialises spans into a real grid.

  Cell text is returned **verbatim** apart from `&nbsp;` being folded to a space
  and the result trimmed — wiki links are left alone, because a value that keeps
  its `[[…]]` can still be diffed against the page it came from.
  """

  @type cell :: %{
          header?: boolean,
          attrs: binary,
          text: binary,
          rowspan: pos_integer,
          colspan: pos_integer,
          spanned?: boolean
        }

  @type row :: %{attrs: binary, cells: [cell]}
  @type t :: %{attrs: binary, rows: [row]}

  @doc """
  Returns the source of every top-level table on the page, outermost first.

  Nested tables stay inside the cell they belong to (the shifter page wraps two
  form tables in an outer layout table), so the caller sees one entry per table
  that is actually a table on the page.
  """
  @spec find_all(binary) :: [binary]
  def find_all(wikitext) do
    wikitext
    |> String.split("\n")
    |> Enum.reduce({[], [], 0}, fn line, {tables, current, depth} ->
      trimmed = String.trim_leading(line)

      cond do
        String.starts_with?(trimmed, "{|") and depth == 0 ->
          {tables, [line], 1}

        String.starts_with?(trimmed, "{|") ->
          {tables, [line | current], depth + 1}

        String.starts_with?(trimmed, "|}") and depth == 1 ->
          {[Enum.reverse([line | current]) |> Enum.join("\n") | tables], [], 0}

        String.starts_with?(trimmed, "|}") and depth > 1 ->
          {tables, [line | current], depth - 1}

        depth > 0 ->
          {tables, [line | current], depth}

        true ->
          {tables, current, depth}
      end
    end)
    |> then(fn {tables, _current, _depth} -> Enum.reverse(tables) end)
  end

  @doc """
  Parses one table's source (`{|` line through `|}` line) into rows of cells.

  Cells that arrive before the first `|-` still form a row: the purple dragon
  knight page opens its table that way and MediaWiki accepts it.
  """
  @spec parse(binary) :: t
  def parse(source) do
    [first | lines] = String.split(source, "\n")

    attrs =
      first |> String.trim() |> String.replace_prefix("{|", "") |> String.trim()

    state = %{rows: [], cells: [], row_attrs: "", started?: false, nested: 0}

    state = Enum.reduce(lines, state, &line/2)

    %{attrs: attrs, rows: Enum.reverse(close_row(state).rows)}
  end

  defp line(raw, state) do
    trimmed = String.trim_leading(raw)

    cond do
      state.nested > 0 -> nested_line(raw, trimmed, state)
      trimmed == "" -> state
      String.starts_with?(trimmed, "{|") -> append_text(raw, %{state | nested: 1})
      String.starts_with?(trimmed, "|}") -> state
      String.starts_with?(trimmed, "|+") -> state
      String.starts_with?(trimmed, "|-") -> new_row(trimmed, state)
      String.starts_with?(trimmed, "!") -> cells(trimmed, "!", state)
      String.starts_with?(trimmed, "|") -> cells(trimmed, "|", state)
      true -> append_text(raw, state)
    end
  end

  defp nested_line(raw, trimmed, state) do
    cond do
      String.starts_with?(trimmed, "{|") -> append_text(raw, %{state | nested: state.nested + 1})
      String.starts_with?(trimmed, "|}") -> append_text(raw, %{state | nested: state.nested - 1})
      true -> append_text(raw, state)
    end
  end

  defp new_row(trimmed, state) do
    attrs = trimmed |> String.replace_prefix("|-", "") |> String.trim()
    %{close_row(state) | cells: [], row_attrs: attrs, started?: true}
  end

  defp close_row(%{started?: false, cells: []} = state), do: state

  defp close_row(state) do
    row = %{attrs: state.row_attrs, cells: Enum.reverse(state.cells)}
    %{state | rows: [row | state.rows], cells: [], row_attrs: "", started?: false}
  end

  defp cells(trimmed, marker, state) do
    parsed =
      trimmed
      |> String.replace_prefix(marker, "")
      |> split_top(marker <> marker)
      |> Enum.flat_map(&split_header_pipes(&1, marker))
      |> Enum.map(&cell(&1, marker == "!"))

    %{state | cells: Enum.reverse(parsed) ++ state.cells, started?: true}
  end

  # MediaWiki accepts `||` as a same-line cell separator inside a header row
  # (one started with `!`) exactly as it does the "correct" `!!` — real pages
  # mix the two. Siala's `Система оружия` writes its eight-column header as
  # `!…||…||…` throughout with no `!!` anywhere, confirmed against the
  # rendered page (`action=parse`, eight separate `<th>`), and the split above
  # only ever looks for the doubled marker, so that whole line used to survive
  # as one garbled cell. This is the second, narrower pass that finds `||`
  # inside whatever the first pass left whole — a no-op for the far more
  # common `!!`-only header, and for every data row (`marker == "|"`, whose
  # first pass already split on `||`).
  defp split_header_pipes(text, "!"), do: split_top(text, "||")
  defp split_header_pipes(text, _marker), do: [text]

  defp cell(source, header?) do
    {attrs, text} = split_attrs(source)

    %{
      header?: header?,
      attrs: attrs,
      text: clean(text),
      rowspan: span(attrs, "rowspan"),
      colspan: span(attrs, "colspan"),
      spanned?: false
    }
  end

  # Everything before the first unnested `|` is the cell's attributes — but only
  # when it actually looks like attributes. `||11th ||…` (an empty attribute part)
  # and `align=left|bonus feat` are attributes; `[[Dual-wield (feat)|dual-wield]]`
  # is not, and neither is a bare value that happens to contain a pipe.
  defp split_attrs(source) do
    case split_top(source, "|") do
      [_only] ->
        {"", source}

      [prefix | rest] ->
        text = Enum.join(rest, "|")

        if attrs?(prefix) do
          {String.trim(prefix), text}
        else
          {"", source}
        end
    end
  end

  defp attrs?(prefix) do
    String.trim(prefix) == "" or
      (String.contains?(prefix, "=") and not String.contains?(prefix, "[[") and
         not String.contains?(prefix, "{{"))
  end

  defp span(attrs, name) do
    case Regex.run(~r/\b#{name}\s*=\s*"?(\d+)"?/i, attrs) do
      [_, digits] -> max(String.to_integer(digits), 1)
      nil -> 1
    end
  end

  defp append_text(raw, state) do
    case state.cells do
      [] -> state
      [last | rest] -> %{state | cells: [%{last | text: clean(last.text <> "\n" <> raw)} | rest]}
    end
  end

  defp clean(text) do
    text |> String.replace("&nbsp;", " ") |> String.trim()
  end

  @doc """
  Materialises `rowspan`/`colspan` into a rectangular grid of cells.

  A cell covering several positions is repeated in each of them; every copy past
  the first carries `spanned?: true`, so a caller can tell a real cell from the
  shadow of one.
  """
  @spec expand([row]) :: [[cell]]
  def expand(rows) do
    {grid, _pending} =
      Enum.map_reduce(rows, %{}, fn row, pending ->
        place(row.cells, pending, 0, [])
      end)

    grid
  end

  defp place([], pending, column, acc) do
    if Map.has_key?(pending, column) do
      {cell, pending} = take_pending(pending, column)
      place([], pending, column + 1, [cell | acc])
    else
      {Enum.reverse(acc), pending}
    end
  end

  defp place([cell | rest], pending, column, acc) do
    if Map.has_key?(pending, column) do
      {carried, pending} = take_pending(pending, column)
      place([cell | rest], pending, column + 1, [carried | acc])
    else
      columns = column..(column + cell.colspan - 1)//1

      pending =
        if cell.rowspan > 1 do
          Enum.reduce(columns, pending, fn c, acc ->
            Map.put(acc, c, {cell.rowspan - 1, %{cell | spanned?: true}})
          end)
        else
          pending
        end

      copies =
        Enum.map(columns, fn c -> if c == column, do: cell, else: %{cell | spanned?: true} end)

      place(rest, pending, column + cell.colspan, Enum.reverse(copies) ++ acc)
    end
  end

  defp take_pending(pending, column) do
    {remaining, cell} = Map.fetch!(pending, column)

    pending =
      if remaining > 1 do
        Map.put(pending, column, {remaining - 1, cell})
      else
        Map.delete(pending, column)
      end

    {cell, pending}
  end

  @doc """
  Splits `text` on `separator`, ignoring separators inside `[[…]]`, `{{…}}` or `{| … |}`.
  """
  @spec split_top(binary, binary) :: [binary]
  def split_top(text, separator), do: do_split(text, separator, 0, 0, 0, [], [])

  defp do_split(<<"[[", rest::binary>>, sep, t, l, b, current, acc),
    do: do_split(rest, sep, t, l + 1, b, ["[[" | current], acc)

  defp do_split(<<"]]", rest::binary>>, sep, t, l, b, current, acc) when l > 0,
    do: do_split(rest, sep, t, l - 1, b, ["]]" | current], acc)

  defp do_split(<<"{{", rest::binary>>, sep, t, l, b, current, acc),
    do: do_split(rest, sep, t + 1, l, b, ["{{" | current], acc)

  defp do_split(<<"}}", rest::binary>>, sep, t, l, b, current, acc) when t > 0,
    do: do_split(rest, sep, t - 1, l, b, ["}}" | current], acc)

  defp do_split(<<"{|", rest::binary>>, sep, t, l, b, current, acc),
    do: do_split(rest, sep, t, l, b + 1, ["{|" | current], acc)

  defp do_split(<<"|}", rest::binary>>, sep, t, l, b, current, acc) when b > 0,
    do: do_split(rest, sep, t, l, b - 1, ["|}" | current], acc)

  defp do_split(text, sep, 0, 0, 0, current, acc) do
    size = byte_size(sep)

    case text do
      <<^sep::binary-size(^size), rest::binary>> ->
        do_split(rest, sep, 0, 0, 0, [], [flush(current) | acc])

      <<char::utf8, rest::binary>> ->
        do_split(rest, sep, 0, 0, 0, [<<char::utf8>> | current], acc)

      <<byte::binary-size(1), rest::binary>> ->
        do_split(rest, sep, 0, 0, 0, [byte | current], acc)

      <<>> ->
        Enum.reverse([flush(current) | acc])
    end
  end

  defp do_split(<<char::utf8, rest::binary>>, sep, t, l, b, current, acc),
    do: do_split(rest, sep, t, l, b, [<<char::utf8>> | current], acc)

  defp do_split(<<byte::binary-size(1), rest::binary>>, sep, t, l, b, current, acc),
    do: do_split(rest, sep, t, l, b, [byte | current], acc)

  defp do_split(<<>>, _sep, _t, _l, _b, current, acc),
    do: Enum.reverse([flush(current) | acc])

  defp flush(current), do: current |> Enum.reverse() |> IO.iodata_to_binary()
end
