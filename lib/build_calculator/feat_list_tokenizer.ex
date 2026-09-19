defmodule BuildCalculator.FeatListTokenizer do
  @moduledoc """
  Longest-match tokenizer for a free-text list of feat names.

  Extracted 26.08.2026 (task 3.111) out of `test/support/wiki_build_page.ex`,
  where it first shipped to read the Siala wiki's build pages. A second source
  needed the exact same reading — `BuildCalculator.GameLog`, parsing the
  `.билд` chat command — and CLAUDE.md §9 is explicit that a second
  implementation of "tokenise by longest dictionary match" is the mistake to
  avoid, not a shortcut. `WikiBuildPage` lives in `test/support/`, compiled only
  for `:test`, so a `lib/` consumer cannot call it directly; this module is the
  shared home both sides call instead. `WikiBuildPage`'s own tests
  (`wiki_builds_test.exs`, `import_test.exs`) are the regression for this
  extraction: they exercise the algorithm unchanged, just one hop further away.

  ## Why "split on commas" does not work

  A feat's own name can contain a comma — `Energy Resistance, Fire I` is one
  feat, not two (the shard's five elemental variants are captioned that way on
  the wiki, and the community writes it the same way in `.билд` dumps). A
  comma-split would read a phantom feat called "Fire I". So the text is walked
  from the front: at every position, the **longest** dictionary key that
  matches there wins, and only *then* is whatever follows read as a
  parenthesised argument (`(Bastard sword)`) or a trailing roman-numeral rank
  (`Great strength III`). Longest-first matters because a short key can be a
  genuine prefix of a longer one at the same position — `weapon focus` on its
  own would swallow the first eleven characters of `Epic weapon focus`,
  wrongly turning "Epic" into an unread leftover — while shorter keys that are
  simply unrelated text starting differently (`Weapon focus` vs `Epic weapon
  focus`) are never a hazard in the first place, since a literal prefix check
  already tells them apart.

  Nothing outside the dictionary is ever guessed at: a run of text the
  dictionary does not recognise is handed back verbatim (up to the next comma
  or semicolon) with `value: nil`, so a caller can report it rather than lose
  it silently.

  ## What this module does not decide

  The dictionary — which names map to which value, and under what aliases — is
  entirely the caller's business. Two callers can disagree about what a name
  *means* (a wiki page's feat id versus a ruleset feat id merged with
  parser-specific special tokens) without disagreeing about how a list of
  names is *cut apart*, and that is exactly the boundary this module draws:
  it takes a normalised string in, a name → value table, and returns entries
  whose `value` is whatever the table said, untouched.
  """

  @typedoc "A `name => value` table, plus its keys sorted longest-first."
  @type dictionary :: {%{String.t() => term()}, [String.t()]}

  @typedoc """
  One token read off the text: a dictionary hit (`value` set) or an unread run
  (`value: nil`, `raw` is the verbatim text up to the next separator).
  """
  @type entry :: %{
          value: term() | nil,
          raw: String.t(),
          argument: String.t() | nil,
          rank: String.t() | nil
        }

  # Written as a bare suffix after the name — `Great strength IV`, `Improved
  # spell resistance IX` — and kept as text, never turned into a number: the
  # rules core models a repeated feat as repeated slots, not a rank. A single
  # trailing `+` right after the numeral is read along with it and kept in
  # the returned rank text (`Uncanny Dodge VI+`, the shard's `.билд` dump,
  # task 3.116) rather than dropped or left unread: it is not typo noise, it
  # is the label `Uncanny dodge`'s own wiki page already prints for that
  # feat's uncapped sixth-and-later tier ("'''VI+:''' This feat grants a +5
  # bonus…") — the game client and the wiki agree on the "+", so both readers
  # of this shared tokenizer should too.
  @roman ~w(i ii iii iv v vi vii viii ix x)

  @doc "Builds a dictionary from a `name => value` map: keys sorted longest-first."
  @spec dictionary(%{String.t() => term()}) :: dictionary()
  def dictionary(table) do
    {table, Enum.sort_by(Map.keys(table), &(-String.length(&1)))}
  end

  @doc """
  Tokenises already-normalised text (trimmed, lower-cased, whitespace
  collapsed to single spaces) against `dictionary`.

  Comma- and semicolon-led separators between entries are consumed silently;
  everything else about the text is either a dictionary hit or reported back
  raw.
  """
  @spec tokenize(String.t(), dictionary()) :: [entry()]
  def tokenize(text, dictionary), do: read_entries(text, dictionary, [])

  defp read_entries(text, dictionary, acc) do
    case String.replace(text, ~r/^[\s,;.\-–—]+/u, "") do
      "" ->
        Enum.reverse(acc)

      rest ->
        {entry, tail} = read_entry(rest, dictionary)
        read_entries(tail, dictionary, [entry | acc])
    end
  end

  defp read_entry(text, {table, keys}) do
    case Enum.find(keys, &name_at?(text, &1)) do
      nil ->
        # Nothing in the dictionary starts here. Give back the run up to the
        # next separator verbatim; guessing what it meant is the caller's
        # business, not this module's.
        run =
          case Regex.run(~r/^[^,;]+/u, text) do
            [run] -> run
            _ -> text
          end

        {%{value: nil, raw: String.trim(run), argument: nil, rank: nil}, drop(text, run)}

      key ->
        rest = text |> drop(key) |> String.trim_leading(" ")
        {argument, rest} = read_argument(rest)
        {rank, rest} = read_rank(String.trim_leading(rest, " "))

        {%{value: Map.fetch!(table, key), raw: key, argument: argument, rank: rank}, rest}
    end
  end

  defp drop(text, prefix), do: String.slice(text, String.length(prefix)..-1//1)

  # A dictionary entry only counts when the text ends there or continues with
  # something that cannot be part of a name — otherwise `dodge` would match
  # inside a longer word nobody named.
  defp name_at?(text, key) do
    String.starts_with?(text, key) and
      case drop(text, key) do
        "" -> true
        rest -> Regex.match?(~r/^[\s(,;.\-–—]/u, rest)
      end
  end

  # `(Bastard sword)`, `(Necromancy)`, `(+1d6)` — kept verbatim and never
  # interpreted here: what the parenthetical *means* (a weapon, a school, a
  # damage die, a stage number) is the caller's dictionary's business, not
  # this tokenizer's. The closing bracket is optional because at least one
  # real-world source forgets it.
  defp read_argument(text) do
    case Regex.run(~r/^\(([^)]*)\)?/u, text) do
      [whole, inner] -> {String.trim(inner), drop(text, whole)}
      _ -> {nil, text}
    end
  end

  defp read_rank(text) do
    with [_, numeral, plus] <- Regex.run(~r/^([ivx]+)(\+?)(?=$|[\s,;.])/u, text),
         true <- numeral in @roman do
      {numeral <> plus, drop(text, numeral <> plus)}
    else
      _ -> {nil, text}
    end
  end
end
