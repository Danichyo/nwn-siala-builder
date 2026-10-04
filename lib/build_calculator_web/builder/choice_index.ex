defmodule BuildCalculatorWeb.Builder.ChoiceIndex do
  @moduledoc """
  Free text off some source → a feat choice's value, resolved against
  `ruleset.choice_domains`.

  Extracted from `BuildCalculatorWeb.Builder.Import` (task 3.111) the moment a
  second reader needed the exact same lookup: `BuildCalculatorWeb.Builder.
  GameLogImport` turns the `.билд` chat dump's own `Weapon Focus (bastard
  sword)` into `{:weapon_focus, :bastard_sword}` the same way `Import` turns a
  forum paste's `Weapon focus (longsword)` into one. Both read the same
  domains off the same ruleset field — CLAUDE.md/AGENTS.md's own rule against
  a second implementation of one reading (`BuildCalculator.FeatListTokenizer`'s
  own moduledoc makes the identical argument for tokenising a feat list) applies
  here just the same. `Import`'s own tests are the regression: this module's
  behaviour is a verbatim extraction, not a rewrite.

  Deliberately narrow — only the **domain** index and its resolver moved here.
  `Import`'s other four indexes (classes, races, feats, skills) answer a
  different question ("what id does this whole *name* refer to") with their own
  aliasing rules (acronyms, wiki redirects, a unique class prefix) that a choice
  domain does not have, so duplicating *that* machinery would be the mistake
  this module exists to avoid, not a shortcut around it.
  """

  @typedoc "`{name => [value]}`, one per choice domain the ruleset declares."
  @type index :: %{atom() => %{String.t() => [term()]}}

  @doc """
  One `{name => [value]}` map per choice domain in `ruleset.choice_domains`.

  A domain with no dictionary at all (`weapon` before task 3.5 gave it one) is
  simply absent from the result rather than present with an empty map — the two
  answer different questions for a caller asking `Map.get(index, domain)`:
  `nil` means "we do not carry names for this domain", an empty map would have
  meant "we do, and none matched", which is not true.
  """
  @spec build(map()) :: index()
  def build(ruleset) do
    for {domain, %{values: %MapSet{} = values} = info} <-
          Map.get(ruleset, :choice_domains, %{}),
        into: %{} do
      names = Map.get(info, :names) || %{}
      carried = carried_dictionary(ruleset, info)

      index =
        for value <- values, reduce: %{} do
          acc ->
            entry = Map.get(carried, value) || %{}

            [Atom.to_string(value), Map.get(names, value), entry[:name], entry[:ru]]
            |> Enum.reduce(acc, &put_key(&2, &1, value))
        end

      {domain, index}
    end
  end

  @doc """
  Looks `text` up in one domain's `{name => [value]}` map.

  `{:ok, value}` on a clean hit, `:error` when nothing matches, `{:ambiguous,
  values}` when two or more entries answer to the same normalised text — guessing
  which one the source meant would be the same sin as guessing a number
  (CLAUDE.md §3), so a caller has to decide what an ambiguous match means to it.
  """
  @spec resolve(%{String.t() => [term()]}, String.t()) ::
          {:ok, term()} | :error | {:ambiguous, [term()]}
  def resolve(index, text) do
    case Map.get(index, norm(text), []) do
      [id] -> {:ok, id}
      [] -> :error
      many -> {:ambiguous, many}
    end
  end

  defp carried_dictionary(ruleset, %{source: {:ruleset, kind}}), do: Map.get(ruleset, kind, %{})
  defp carried_dictionary(_ruleset, _info), do: %{}

  defp put_key(index, nil, _id), do: index

  defp put_key(index, name, id) do
    case norm(name) do
      "" -> index
      key -> Map.update(index, key, [id], &Enum.uniq([id | &1]))
    end
  end

  defp norm(nil), do: ""

  defp norm(text) do
    text
    |> String.downcase()
    |> String.replace("ё", "е")
    |> String.replace(~r/[\s_\-–—.'’"`]+/u, "")
  end
end
