defmodule BuildCalculator.Wiki.CategoryMembers do
  @moduledoc """
  Which members of a wiki category are *instances* of it, and which merely sit in it.

  Fandom files three kinds of page in `Category:Races`: the 25 racial types, and
  `Subrace`, which is an article *about* races rather than one of them. Counting
  the category naively says 26, and the `Favored enemy` page says there are 25 —
  so something has to tell the two apart, and it must not be a hand-written list
  of exceptions (CLAUDE.md §3: a name that is not in the source is not a name).

  MediaWiki already marks the difference. A category link may carry a **sort
  key** after a pipe, and the convention — followed on both categories this
  project reads — is that a page filed under a heading rather than as a member of
  the set gets one:

      Ooze      [[category:races]]
      Subrace   [[Category: Races| Subrace]]

  The same split appears in `Category:Spell schools`: the eight schools link it
  bare, while the six `Spell school list (bard|cleric|…)` pages are all sort-keyed.
  Two categories, one rule, and both were checked page by page before it was
  written down here.

  The rule is a *reading* of the source, not a proof, so callers are expected to
  pair it with a count taken from prose — `mix wiki.parse` refuses to write a
  dictionary whose size disagrees with the number the wiki states in words.
  """

  @doc """
  Splits cached pages of `category` into its instances and the pages filed under it.

  `pages` are `{index_entry, wikitext}` pairs as `mix wiki.parse` holds them;
  only pages whose index entry lists `category` are considered, so the caller can
  pass the whole cache. Both halves come back sorted by title.
  """
  @spec split([{map, binary}], binary) :: %{instances: [{map, binary}], filed: [{map, binary}]}
  def split(pages, category) do
    {filed, instances} =
      pages
      |> Enum.filter(fn {entry, _wikitext} -> category in entry.categories end)
      |> Enum.sort_by(fn {entry, _wikitext} -> entry.title end)
      |> Enum.split_with(fn {_entry, wikitext} ->
        match?({:key, _key}, sort_key(wikitext, category))
      end)

    %{instances: instances, filed: filed}
  end

  @doc """
  How a page links `category`: `{:key, sort_key}`, `:bare`, or `:unlinked`.

  `:unlinked` means the page never names the category in its own wikitext even
  though the index says it belongs — which happens when the category comes from a
  template rather than a literal link. Such a page is treated as an instance,
  because "no sort key" is what the rule keys on and a template cannot supply one
  here.

  Matching ignores case and padding on both the `Category:` prefix and the name,
  since the wiki writes all of `[[category:races]]`, `[[Category:Races]]` and
  `[[Category: Races| Subrace]]`.
  """
  @spec sort_key(binary, binary) :: {:key, binary} | :bare | :unlinked
  def sort_key(wikitext, category) do
    name = category |> String.replace(~r/^[^:]*:/u, "") |> String.trim()
    pattern = ~r/\[\[\s*category\s*:\s*#{Regex.escape(name)}\s*(\|([^\]]*))?\]\]/iu

    case Regex.run(pattern, wikitext) do
      nil -> :unlinked
      [_all] -> :bare
      [_all, _pipe] -> {:key, ""}
      [_all, _pipe, key] -> {:key, String.trim(key)}
    end
  end
end
