defmodule BuildCalculator.Wiki.Json do
  @moduledoc """
  Deterministic pretty-printed JSON writer for the committed wiki snapshots.

  `Jason` serialises a map in whatever order `:maps.to_list/1` happens to return,
  which is an implementation detail a reviewed, committed snapshot must not depend
  on. Here an object is an explicit ordered list of pairs (`{:obj, [{key, value}]}`),
  so the produced bytes are a pure function of the input and re-running a parser on
  an unchanged cache yields an empty `git diff`.

  Scalar escaping is delegated to `Jason`.
  """

  @type t ::
          nil
          | boolean
          | number
          | binary
          | [t]
          | {:obj, [{binary | atom, t}]}

  @doc "Encodes `value` as pretty JSON (2-space indent) with a trailing newline."
  @spec encode!(t) :: binary
  def encode!(value), do: IO.iodata_to_binary([encode(value, 0), "\n"])

  defp encode({:obj, []}, _level), do: "{}"

  defp encode({:obj, pairs}, level) do
    inner = level + 1

    body =
      Enum.map_intersperse(pairs, ",\n", fn {key, value} ->
        [indent(inner), Jason.encode!(to_string(key)), ": ", encode(value, inner)]
      end)

    ["{\n", body, "\n", indent(level), "}"]
  end

  defp encode([], _level), do: "[]"

  defp encode(list, level) when is_list(list) do
    inner = level + 1
    body = Enum.map_intersperse(list, ",\n", &[indent(inner), encode(&1, inner)])
    ["[\n", body, "\n", indent(level), "]"]
  end

  defp encode(scalar, _level), do: Jason.encode!(scalar)

  defp indent(level), do: String.duplicate("  ", level)
end
