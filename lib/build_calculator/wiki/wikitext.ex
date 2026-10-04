defmodule BuildCalculator.Wiki.Wikitext do
  @moduledoc """
  Small helpers for reading Fandom pages that carry no template.

  Class pages are hand-written prose: the numbers a calculator needs sit in
  bold-label lines (`'''Hit die:''' d10`) and in section headings, not in named
  template parameters. These functions cut a page into sections and lift the
  bold labels out; interpreting the values is the caller's job.
  """

  @heading ~r/^\s*(={2,6})\s*(.*?)\s*\1\s*$/

  @type section :: %{level: non_neg_integer, title: binary | nil, body: binary}

  @doc """
  Cuts a page into sections at its `== headings ==`.

  The first entry is always the lead — the text above the first heading, where
  class pages keep their stat labels — with `level: 0` and `title: nil`.
  """
  @spec sections(binary) :: [section]
  def sections(wikitext) do
    wikitext
    |> String.split("\n")
    |> Enum.reduce([%{level: 0, title: nil, lines: []}], fn line, [current | rest] = acc ->
      case Regex.run(@heading, line) do
        [_, equals, title] ->
          [%{level: String.length(equals), title: title, lines: []} | acc]

        nil ->
          [%{current | lines: [line | current.lines]} | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn section ->
      %{
        level: section.level,
        title: section.title,
        body: section.lines |> Enum.reverse() |> Enum.join("\n")
      }
    end)
  end

  @doc """
  Lifts `'''Label''': value` lines out of a chunk of wikitext.

  A label's value runs until the next label line or the end of the chunk, because
  the wiki routinely puts it on the following lines (`'''Unavailable feats:'''`
  is always a list underneath) or lets a table follow it.

  Handles the three ways the wiki writes the colon — inside the bold
  (`'''Hit die:''' d10`), after it (`'''Hit die''': d10`) and swallowing the
  value whole (`'''Base attack bonus: +1/level'''`) — as well as the bold run
  that someone forgot to close.

  Returns `{label, value}` pairs in page order, both verbatim apart from
  trimming; `label` still carries its `[[…]]` markup.
  """
  @spec labels(binary) :: [{binary, binary}]
  def labels(text) do
    text
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      case label_line(line) do
        {:ok, label, value} -> [{label, [value]} | acc]
        :no -> continue(acc, line)
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {label, lines} ->
      {label, lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()}
    end)
  end

  @bullet_marker ~r/^\s*\*+\s*(''')/u

  @doc """
  Same as `labels/1`, but also accepts a label introduced by a list marker.

  Skill pages write every one of their labels as a bullet (`*'''Ability''':
  [[dexterity]]`, `* '''Classes''': …`), which `labels/1` alone would not see.
  Only the marker in front of a bold run is removed, so a plain prose bullet
  still reads as the continuation of the label above it.
  """
  @spec bullet_labels(binary) :: [{binary, binary}]
  def bullet_labels(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &String.replace(&1, @bullet_marker, "\\1"))
    |> labels()
  end

  defp continue([], _line), do: []
  defp continue([{label, lines} | rest], line), do: [{label, [line | lines]} | rest]

  defp label_line(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, "'''") do
      {bold, tail} = split_bold(String.replace_prefix(trimmed, "'''", ""))

      case colon_offset(bold, 0, 0) do
        nil ->
          {:ok, String.trim(bold), tail |> String.trim_leading() |> strip_colon()}

        offset ->
          {:ok, bold |> binary_part(0, offset) |> String.trim(), rest(bold, offset) <> tail}
      end
    else
      :no
    end
  end

  defp split_bold(rest) do
    case String.split(rest, "'''", parts: 2) do
      [bold, tail] -> {bold, tail}
      [bold] -> {bold, ""}
    end
  end

  defp rest(bold, offset),
    do: bold |> binary_part(offset + 1, byte_size(bold) - offset - 1) |> String.trim_leading()

  defp strip_colon(":" <> value), do: String.trim_leading(value)
  defp strip_colon(value), do: value

  # First `:` that is not inside a wiki link — `[[Saving throw|Primary saving
  # throw(s)]]:` must split after the link, not inside its target.
  defp colon_offset(<<"[[", rest::binary>>, link, offset),
    do: colon_offset(rest, link + 1, offset + 2)

  defp colon_offset(<<"]]", rest::binary>>, link, offset) when link > 0,
    do: colon_offset(rest, link - 1, offset + 2)

  defp colon_offset(<<":", _rest::binary>>, 0, offset), do: offset

  defp colon_offset(<<char::utf8, rest::binary>>, link, offset),
    do: colon_offset(rest, link, offset + byte_size(<<char::utf8>>))

  defp colon_offset(<<_byte::binary-size(1), rest::binary>>, link, offset),
    do: colon_offset(rest, link, offset + 1)

  defp colon_offset(<<>>, _link, _offset), do: nil

  @sentence_break ~r/(?:[.!?:]\s|[|*=>])/u
  @sentence_end ~r/[.!?:](?=\s|$)/u

  @doc """
  The sentence of `text` that contains `anchor`, or `:error` when it does not.

  This exists so that a quote stored in the snapshot is *lifted from the page*
  rather than retyped: a curated table names the phrase a decision rests on, and
  the sentence around it comes back verbatim from the cache. Retyping a quote by
  hand is how a number nobody can find in the source ends up in the data.

  Verbatim here means every character that carries meaning, `[[…]]` markup
  included; only runs of whitespace are collapsed to a single space, because the
  wiki wraps sentences mid-line (`Self concealment` breaks between "may" and
  "be") and a quote must not inherit the column width of the source.

  Sentences are cut at `.!?:` followed by a space, and additionally at the
  structural marks `| * = >` so that a sentence opening a template parameter
  (`|desc=This feat may be taken…`) does not swallow the parameter name.
  """
  @spec sentence_with(binary, binary) :: {:ok, binary} | :error
  def sentence_with(text, anchor) do
    flat = flatten(text)
    needle = flatten(anchor)

    case :binary.match(flat, needle) do
      :nomatch ->
        :error

      {start, length} ->
        tail_start = start + length
        opening = flat |> binary_part(0, start) |> after_last_break()
        closing = flat |> binary_part(tail_start, byte_size(flat) - tail_start) |> up_to_end()

        {:ok, String.trim(opening <> needle <> closing)}
    end
  end

  defp flatten(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp after_last_break(before) do
    case Regex.scan(@sentence_break, before, return: :index) do
      [] ->
        before

      matches ->
        [{start, length} | _] = List.last(matches)
        cut = start + length
        binary_part(before, cut, byte_size(before) - cut)
    end
  end

  defp up_to_end(rest) do
    case Regex.run(@sentence_end, rest, return: :index) do
      [{start, length}] -> binary_part(rest, 0, start + length)
      nil -> rest
    end
  end

  @link ~r/\[\[([^\[\]|]+)(?:\|[^\[\]]*)?\]\]/u

  @doc """
  Every `[[target]]` / `[[target|shown]]` in `text`, as targets, in page order.

  Comma-separated link lists are how both wikis write "which classes" and "which
  skills", and the target is the stable half of the link: `[[Heal (skill)|heal]]`
  and `[[heal (skill)]]` name the same page under two display texts.
  """
  @spec link_targets(binary) :: [binary]
  def link_targets(text), do: for([_, target] <- Regex.scan(@link, text), do: target)

  @doc """
  Folds a bold label down to a lookup key.

  Links are rendered, a parenthesised aside dropped, and everything that is not
  a lowercase letter becomes a single space — so `'''[[Cross-class skill|Cross-
  class]]'''`, `'''Cross-class:'''` and `'''Cross class'''` all key on
  `"cross class"`, and the punctuation styles the two wikis mix stop mattering.
  """
  @spec normalize_label(binary) :: binary
  def normalize_label(label) do
    label
    |> strip_links()
    |> String.replace(~r/\(.*?\)/u, " ")
    |> String.downcase()
    |> String.replace(~r/[^\p{Ll} ]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc """
  Renders `[[target|shown]]` and `[[target]]` down to their display text.

  Used only to *read* a value (is this `d10`? is this `+3/4 levels`?) — the value
  stored in the snapshot keeps its markup.
  """
  @spec strip_links(binary) :: binary
  def strip_links(text) do
    text
    |> String.replace(~r/\[\[(?:[^\[\]|]*\|)?([^\[\]|]*)\]\]/u, "\\1")
    |> String.replace(~r/<[^>]*>/u, " ")
    |> String.replace("'''", "")
    |> String.replace("''", "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
