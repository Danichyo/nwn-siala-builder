defmodule BuildCalculatorWeb.Builder.WikiBlocks do
  @moduledoc """
  A shard page's wikitext down to the few block shapes the feat info popover
  draws — paragraph, bulleted list, numbered list, preformatted line,
  heading (task 4.71).

  The eleven shard-only feats have no Fandom prose, so their popover shows the
  shard's page itself (`Labels.feat_info/2`, `:shard_page`), and there the
  page's *block* structure carries meaning that running text would lose: the
  proficiency pages say «Все оружие поделено на четыре группы:» and then
  number the four groups — the tiers a character unlocks at 1, 10, 20 and 30
  — and Instinctive throw's cooldown formula sits on a line of its own under
  the bullet it belongs to. So blocks are kept, as data the hook draws with
  `document.createElement` from a fixed set of tags and `textContent` — never
  as HTML.

  ## What is kept and what is not

    * **Blocks are kept.** A run of running-text lines is one paragraph — a
      single source newline inside it is a space, as MediaWiki renders it and
      as `Reading.strip_wiki_prose/1` folds it (task 4.70). An empty line ends
      a block. `*` / `#` lines are list items (a list ends where the run of
      items does — MediaWiki starts a new list there too, numbering included);
      a line opening with whitespace is preformatted; `== title ==` is a
      heading; `:` / `;` lines and table syntax are paragraphs of their own;
      `----` is dropped.
    * **Inline markup is read down to text**, by the same
      `Reading.strip_wiki_prose/1` every other quote in the popover goes
      through: `'''bold'''` and `''italic''` lose their quotes,
      `[[Page|label]]` becomes its label, tags are dropped and their content
      kept, struck-through history is cut. Bold and italic are not carried
      over as `<strong>`/`<em>`: on these pages they only set off the damage
      dice and the critical range, whose own form («2-6», «20/х2») already
      tells them apart, and keeping them would mean re-implementing
      MediaWiki's apostrophe rules here for decoration.
    * **External links** `[http://… label]` become their label — the one
      inline form `strip_wiki_prose/1` has no rule for (none of the 600-odd
      texts it reads carries one). Nothing here ever becomes a link: an
      internal link points into the shard's wiki, which the site never names
      or links to (CLAUDE.md §3, licence), and an external one is the page's
      business, not a target this popover vouches for. A bracket in any other
      form (`[javascript:…]`, `[1]`) is not a link on MediaWiki either and
      stays the literal text it is there.

  Pure: wikitext in, a list of maps out, `[]` for a page with nothing to show.
  """

  alias BuildCalculator.Data.Loader.Reading

  @type block ::
          %{kind: String.t(), text: String.t()}
          | %{kind: String.t(), items: [String.t()]}

  @heading ~r/^(=+)\s*(.*?)\s*\1\s*$/u
  @external_link ~r/\[(?:https?:\/\/|ftp:\/\/|mailto:)[^\s\]]*\s+([^\]]+)\]/u

  @spec blocks(String.t() | nil) :: [block()]
  def blocks(nil), do: []

  def blocks(raw) when is_binary(raw) do
    raw
    |> String.split("\n")
    |> Enum.map(&line/1)
    |> group([])
    |> Enum.flat_map(&finish/1)
  end

  # One source line → what it opens. The order of the clauses is the order
  # MediaWiki asks the same questions in: blank, rule, heading, list, indent,
  # table, preformatted, text.
  defp line(raw) do
    trimmed = String.trim(raw)

    cond do
      trimmed == "" -> :blank
      String.starts_with?(raw, "----") -> :blank
      match = Regex.run(@heading, raw) -> {:heading, Enum.at(match, 2)}
      String.starts_with?(raw, "*") -> {:ul, strip_markers(raw)}
      String.starts_with?(raw, "#") -> {:ol, strip_markers(raw)}
      String.starts_with?(raw, [":", ";"]) -> {:own, strip_markers(raw)}
      String.starts_with?(raw, ["{|", "|", "!"]) -> {:own, raw}
      # Kept with its leading whitespace: `strip_wiki_prose/1` folds a newline
      # between two running-text lines, and an indented line is not one — so
      # a preformatted block of several lines keeps them.
      String.starts_with?(raw, [" ", "\t"]) -> {:pre, raw}
      true -> {:text, raw}
    end
  end

  defp strip_markers(raw), do: String.replace(raw, ~r/^[*#:;]+/u, "")

  # Lines → raw blocks, most recent first while building. A block stays open
  # while the next line is of its own kind; a blank line, a heading and a
  # paragraph of its own close it — by pushing `:break`, which no clause below
  # takes for an open block, and which `finish/1` drops.
  defp group([], acc), do: Enum.reverse(acc)

  defp group([:blank | rest], acc), do: group(rest, [:break | acc])

  defp group([{:text, text} | rest], [{:p, open} | acc]),
    do: group(rest, [{:p, open <> " " <> text} | acc])

  defp group([{:text, text} | rest], acc), do: group(rest, [{:p, text} | acc])

  defp group([{:pre, text} | rest], [{:pre, open} | acc]),
    do: group(rest, [{:pre, open <> "\n" <> text} | acc])

  defp group([{:pre, text} | rest], acc), do: group(rest, [{:pre, text} | acc])

  defp group([{kind, item} | rest], [{kind, items} | acc]) when kind in [:ul, :ol],
    do: group(rest, [{kind, items ++ [item]} | acc])

  defp group([{kind, item} | rest], acc) when kind in [:ul, :ol],
    do: group(rest, [{kind, [item]} | acc])

  defp group([{:heading, text} | rest], acc), do: group(rest, [:break, {:h, text} | acc])
  defp group([{:own, text} | rest], acc), do: group(rest, [:break, {:p, text} | acc])

  defp finish(:break), do: []
  defp finish({:p, text}), do: text_block("p", text)
  defp finish({:h, text}), do: text_block("h", text)
  defp finish({:pre, text}), do: text_block("pre", text)

  defp finish({kind, items}) when kind in [:ul, :ol] do
    case items |> Enum.map(&inline/1) |> Enum.reject(&is_nil/1) do
      [] -> []
      items -> [%{kind: Atom.to_string(kind), items: items}]
    end
  end

  defp text_block(kind, text) do
    case inline(text) do
      nil -> []
      text -> [%{kind: kind, text: text}]
    end
  end

  defp inline(text) do
    text
    |> String.replace(@external_link, "\\1")
    |> Reading.strip_wiki_prose()
  end
end
