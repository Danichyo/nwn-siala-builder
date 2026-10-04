defmodule BuildCalculator.Wiki.Template do
  @moduledoc """
  Extracts MediaWiki template calls (`{{feat|type=general|...}}`) out of raw wikitext.

  Written as a brace-balanced scanner rather than a regex because template
  parameters routinely contain `|` inside wiki links (`[[attack roll|attack]]`),
  nested templates and even whole `{| ... |}` tables — all of which a naive
  `String.split(text, "|")` would shred silently.

  Values are returned **verbatim**, wiki markup included. Interpreting them is the
  caller's job; this module never guesses.
  """

  @type template :: %{
          name: binary,
          params: %{binary => binary},
          positional: [binary],
          duplicate_params: [binary]
        }

  @doc """
  Finds every `{{name|...}}` call in `wikitext`.

  Matching on the template name is case-insensitive, since wikis are inconsistent
  about the leading capital. Returns `{templates, unbalanced_count}` where
  `unbalanced_count` counts calls whose braces never close — a broken page, which
  the caller is expected to report rather than paper over.
  """
  @spec find_all(binary, binary) :: {[template], non_neg_integer}
  def find_all(wikitext, name) do
    pattern = ~r/\{\{\s*#{Regex.escape(name)}\s*(?=[|}])/iu

    wikitext
    |> then(&Regex.scan(pattern, &1, return: :index))
    |> Enum.reduce({[], 0}, fn [{start, _len}], {found, broken} ->
      body_start = start + 2
      body = binary_part(wikitext, body_start, byte_size(wikitext) - body_start)

      case scan(body, 1, 0, 0, [], []) do
        {:ok, parts} -> {[build(name, parts) | found], broken}
        :unbalanced -> {found, broken + 1}
      end
    end)
    |> then(fn {found, broken} -> {Enum.reverse(found), broken} end)
  end

  @doc """
  Finds the single `{{name|...}}` call on a page.

  `{:error, :none}` when the page has no such template (plenty of pages in the feat
  and spell categories are prose or overview pages), `{:error, :ambiguous}` when
  there is more than one — the caller must decide, this module will not pick.
  """
  @spec find_one(binary, binary) :: {:ok, template} | {:error, :none | :ambiguous | :unbalanced}
  def find_one(wikitext, name) do
    case find_all(wikitext, name) do
      {[template], 0} -> {:ok, template}
      {[], 0} -> {:error, :none}
      {[], _broken} -> {:error, :unbalanced}
      {_many, _} -> {:error, :ambiguous}
    end
  end

  defp build(name, [_template_name | args]) do
    {params, positional, duplicates} =
      Enum.reduce(args, {%{}, [], []}, fn arg, {params, positional, duplicates} ->
        case split_param(arg) do
          {:named, key, value} ->
            duplicates = if Map.has_key?(params, key), do: [key | duplicates], else: duplicates
            {Map.put(params, key, value), positional, duplicates}

          {:positional, value} ->
            {params, [value | positional], duplicates}
        end
      end)

    %{
      name: name,
      params: params,
      positional: Enum.reverse(positional),
      duplicate_params: Enum.sort(duplicates)
    }
  end

  # depth: {{ }} nesting, link: [[ ]] nesting, table: {| |} nesting.
  defp scan(<<"{{", rest::binary>>, depth, link, table, current, parts),
    do: scan(rest, depth + 1, link, table, ["{{" | current], parts)

  defp scan(<<"}}", _rest::binary>>, 1, _link, _table, current, parts),
    do: {:ok, Enum.reverse([flush(current) | parts])}

  defp scan(<<"}}", rest::binary>>, depth, link, table, current, parts),
    do: scan(rest, depth - 1, link, table, ["}}" | current], parts)

  defp scan(<<"[[", rest::binary>>, depth, link, table, current, parts),
    do: scan(rest, depth, link + 1, table, ["[[" | current], parts)

  defp scan(<<"]]", rest::binary>>, depth, link, table, current, parts) when link > 0,
    do: scan(rest, depth, link - 1, table, ["]]" | current], parts)

  defp scan(<<"{|", rest::binary>>, depth, link, table, current, parts),
    do: scan(rest, depth, link, table + 1, ["{|" | current], parts)

  defp scan(<<"|}", rest::binary>>, depth, link, table, current, parts) when table > 0,
    do: scan(rest, depth, link, table - 1, ["|}" | current], parts)

  defp scan(<<"|", rest::binary>>, 1, 0, 0, current, parts),
    do: scan(rest, 1, 0, 0, [], [flush(current) | parts])

  defp scan(<<char::utf8, rest::binary>>, depth, link, table, current, parts),
    do: scan(rest, depth, link, table, [<<char::utf8>> | current], parts)

  defp scan(<<byte::binary-size(1), rest::binary>>, depth, link, table, current, parts),
    do: scan(rest, depth, link, table, [byte | current], parts)

  defp scan(<<>>, _depth, _link, _table, _current, _parts), do: :unbalanced

  defp flush(current), do: current |> Enum.reverse() |> IO.iodata_to_binary()

  defp split_param(arg) do
    case equals_offset(arg, 0, 0, 0) do
      nil ->
        {:positional, String.trim(arg)}

      offset ->
        key = arg |> binary_part(0, offset) |> String.trim()
        rest = binary_part(arg, offset + 1, byte_size(arg) - offset - 1)
        {:named, key, String.trim(rest)}
    end
  end

  defp equals_offset(<<"{{", rest::binary>>, depth, link, offset),
    do: equals_offset(rest, depth + 1, link, offset + 2)

  defp equals_offset(<<"}}", rest::binary>>, depth, link, offset) when depth > 0,
    do: equals_offset(rest, depth - 1, link, offset + 2)

  defp equals_offset(<<"[[", rest::binary>>, depth, link, offset),
    do: equals_offset(rest, depth, link + 1, offset + 2)

  defp equals_offset(<<"]]", rest::binary>>, depth, link, offset) when link > 0,
    do: equals_offset(rest, depth, link - 1, offset + 2)

  defp equals_offset(<<"=", _rest::binary>>, 0, 0, offset), do: offset

  defp equals_offset(<<char::utf8, rest::binary>>, depth, link, offset),
    do: equals_offset(rest, depth, link, offset + byte_size(<<char::utf8>>))

  defp equals_offset(<<_byte::binary-size(1), rest::binary>>, depth, link, offset),
    do: equals_offset(rest, depth, link, offset + 1)

  defp equals_offset(<<>>, _depth, _link, _offset), do: nil
end
