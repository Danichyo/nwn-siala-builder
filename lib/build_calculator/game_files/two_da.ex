defmodule BuildCalculator.GameFiles.TwoDA do
  @moduledoc """
  Parser of the text `2DA V2.0` tables of NWN (task 4.5).

      2DA V2.0
      <blank, or DEFAULT: value>
      <column names>
      <row label> <value> <value> …

  Values are separated by any run of spaces or tabs; a value with a space inside
  is written in double quotes; `****` is an empty cell and is returned as `nil`.

  ⚠ **A row is addressed by its position, not by its label.** Other tables point
  at rows by number (`FeatIndex` in `cls_feat_*`, `Favored` in `racialtypes`), and
  the number is the row's place in the file; the leading label is only a
  convention of the people who wrote the file. Both are kept: `label/2` returns
  what is printed, `rows/1` numbers rows by position, and `mislabeled/1` lists the
  rows where the two disagree, so a hand-edited table cannot quietly shift every
  reference into it.

  Lines are decoded as latin-1 — the files are ASCII in practice, and a stray
  byte must not turn a whole table into an error.
  """

  defstruct columns: [], rows: {}, labels: {}, default: nil, warnings: []

  @type value :: String.t() | nil
  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: tuple(),
          labels: tuple(),
          default: String.t() | nil,
          warnings: [term()]
        }

  @token ~r/"[^"]*"|\S+/

  @doc "Parses the bytes of a `.2da` file."
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(bytes) when is_binary(bytes) do
    lines =
      bytes
      |> :unicode.characters_to_binary(:latin1)
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing(&1, "\r"))

    with [first | rest] <- lines,
         true <- Regex.match?(~r/^\s*2DA\s+V2\.0/, first) || {:error, :not_a_2da_v2} do
      {default, rest} = preamble(rest, nil)

      case rest do
        [header | body] ->
          columns = tokens(header)
          {rows, labels, warnings} = body(body, columns)

          {:ok,
           %__MODULE__{
             columns: columns,
             rows: List.to_tuple(rows),
             labels: List.to_tuple(labels),
             default: default,
             warnings: warnings
           }}

        [] ->
          {:error, :no_header}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :empty}
    end
  end

  @doc "Like `parse/1`, raising on a malformed table."
  @spec parse!(binary()) :: t()
  def parse!(bytes) do
    case parse(bytes) do
      {:ok, table} -> table
      {:error, reason} -> raise ArgumentError, "not a 2DA V2.0 table: #{inspect(reason)}"
    end
  end

  @doc "Number of rows."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{rows: rows}), do: tuple_size(rows)

  @doc "Row at position `index` as a map column → value, or `nil` past the end."
  @spec row(t(), integer()) :: %{String.t() => value()} | nil
  def row(%__MODULE__{rows: rows}, index) when is_integer(index) do
    if index >= 0 and index < tuple_size(rows), do: elem(rows, index), else: nil
  end

  @doc "All rows as `{position, row}` pairs, in file order."
  @spec rows(t()) :: [{non_neg_integer(), map()}]
  def rows(%__MODULE__{rows: rows}), do: rows |> Tuple.to_list() |> Enum.with_index(&{&2, &1})

  @doc "The label printed at the start of row `index`."
  @spec label(t(), non_neg_integer()) :: String.t() | nil
  def label(%__MODULE__{labels: labels}, index) do
    if index >= 0 and index < tuple_size(labels), do: elem(labels, index), else: nil
  end

  @doc """
  Cell `column` of row `index`. The column name is matched exactly first and
  case-insensitively second (`CLS_SKILL_wM` and friends: BioWare's own casing is
  not consistent between tables).
  """
  @spec get(t(), integer(), String.t()) :: value()
  def get(%__MODULE__{} = table, index, column) do
    case row(table, index) do
      nil -> nil
      row -> Map.get(row, column) || Map.get(row, resolve(table, column))
    end
  end

  @doc "Cell as an integer — decimal or `0x` hex — or `nil` when empty or not a number."
  @spec int(t(), integer(), String.t()) :: integer() | nil
  def int(table, index, column), do: to_int(get(table, index, column))

  @doc "Converts one cell value to an integer (`nil` when it is not one)."
  @spec to_int(value()) :: integer() | nil
  def to_int(nil), do: nil

  def to_int(value) do
    case Regex.run(~r/^\s*(-?)(0[xX][0-9a-fA-F]+|\d+)\s*$/, value) do
      [_, sign, "0" <> <<x, hex::binary>>] when x in [?x, ?X] ->
        apply_sign(sign, String.to_integer(hex, 16))

      [_, sign, digits] ->
        apply_sign(sign, String.to_integer(digits))

      _ ->
        nil
    end
  end

  @doc "Rows whose printed label is not their position — see the moduledoc."
  @spec mislabeled(t()) :: [{non_neg_integer(), String.t()}]
  def mislabeled(%__MODULE__{labels: labels}) do
    labels
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reject(fn {label, index} -> label == Integer.to_string(index) end)
    |> Enum.map(fn {label, index} -> {index, label} end)
  end

  defp apply_sign("-", n), do: -n
  defp apply_sign(_sign, n), do: n

  defp resolve(%__MODULE__{columns: columns}, column) do
    down = String.downcase(column)
    Enum.find(columns, &(String.downcase(&1) == down))
  end

  # Blank lines and a `DEFAULT:` line may sit between the version and the header.
  defp preamble([line | rest] = lines, default) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        preamble(rest, default)

      String.upcase(trimmed) |> String.starts_with?("DEFAULT:") ->
        preamble(rest, default_of(trimmed))

      true ->
        {default, lines}
    end
  end

  defp preamble([], default), do: {default, []}

  defp default_of(line) do
    line |> String.split(":", parts: 2) |> List.last() |> String.trim() |> unquote_token()
  end

  defp body(lines, columns) do
    width = length(columns)

    {rows, labels, warnings} =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.with_index()
      |> Enum.reduce({[], [], []}, fn {line, position}, {rows, labels, warnings} ->
        [label | values] = tokens(line)
        extra = length(values) - width

        warnings =
          if extra > 0, do: [{:extra_values, position, extra} | warnings], else: warnings

        row =
          columns
          |> Enum.zip(Stream.concat(values, Stream.repeatedly(fn -> nil end)))
          |> Map.new(fn {column, value} -> {column, cell(value)} end)

        {[row | rows], [label | labels], warnings}
      end)

    {Enum.reverse(rows), Enum.reverse(labels), Enum.reverse(warnings)}
  end

  defp tokens(line), do: @token |> Regex.scan(line) |> Enum.map(fn [t] -> unquote_token(t) end)

  defp unquote_token(<<?", rest::binary>> = token) when byte_size(token) >= 2 do
    String.trim_trailing(rest, "\"")
  end

  defp unquote_token(token), do: token

  defp cell(nil), do: nil
  defp cell("****"), do: nil
  defp cell(value), do: value
end
