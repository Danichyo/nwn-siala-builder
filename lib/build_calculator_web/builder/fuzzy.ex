defmodule BuildCalculatorWeb.Builder.Fuzzy do
  @moduledoc """
  Subsequence search with ranking, the way fzf does it.

  Not decoration (CLAUDE.md §6): the NWN community writes feats as
  abbreviations anyway and the real names are long and wordy, so `pwatk` has to
  find Power Attack, `ikd` Improved Knockdown, `itwf` Improved Two-Weapon
  Fighting. It also tolerates a dropped letter — `toughnes` still finds
  Toughness.

  Scoring: a bonus for landing on a word boundary and for consecutive hits, a
  penalty for skipping, and, all else equal, the shorter name wins. Greedy
  left-to-right matching decides *whether* a subsequence exists correctly, so
  there are no false negatives; only the score is approximate.

  Matched letters are handed back as positions so the caller can highlight
  them — without that, fuzzy results look random.
  """

  @word_breaks [" ", "-", "'", "/", "(", ",", "."]

  @type match :: %{score: integer(), positions: [non_neg_integer()]}

  @doc """
  Scores `query` against `text`, or `nil` when the letters are not there at all.

  An empty query matches everything with score 0 and no highlights.
  """
  @spec match(String.t(), String.t()) :: match() | nil
  def match(query, text) do
    q = query |> String.trim() |> String.downcase()

    if q == "" do
      %{score: 0, positions: []}
    else
      do_match(String.graphemes(q), String.graphemes(String.downcase(text)), q, text)
    end
  end

  defp do_match(q_chars, t_chars, q, text) do
    case walk(q_chars, t_chars, 0, -2, 0, []) do
      nil ->
        nil

      {score, positions} ->
        lowered = Enum.join(t_chars)

        bonus =
          cond do
            String.starts_with?(lowered, q) -> 20
            String.contains?(lowered, q) -> 12
            true -> 0
          end

        %{
          score: score + bonus - div(String.length(text), 12),
          positions: Enum.reverse(positions)
        }
    end
  end

  defp walk([], _chars, _from, _prev, score, positions), do: {score, positions}

  defp walk([ch | rest], chars, from, prev, score, positions) do
    case index_of(chars, ch, from) do
      nil ->
        nil

      at ->
        score =
          score + 10 +
            boundary_bonus(chars, at) +
            if(at == prev + 1, do: 8, else: 0) -
            min(at - from, 6)

        walk(rest, chars, at + 1, at, score, [at | positions])
    end
  end

  defp boundary_bonus(_chars, 0), do: 12

  defp boundary_bonus(chars, at) do
    if Enum.at(chars, at - 1) in @word_breaks, do: 12, else: 0
  end

  defp index_of(chars, ch, from) do
    chars
    |> Enum.drop(from)
    |> Enum.find_index(&(&1 == ch))
    |> case do
      nil -> nil
      offset -> from + offset
    end
  end

  @doc """
  Splits `text` into `{:hit, part}` / `{:miss, part}` runs for rendering.

  Adjacent characters of the same kind are merged, so the template emits one
  `<mark>` per run rather than one per letter.
  """
  @spec segments(String.t(), [non_neg_integer()]) :: [{:hit | :miss, String.t()}]
  def segments(text, []), do: [{:miss, text}]

  def segments(text, positions) do
    hits = MapSet.new(positions)

    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.chunk_by(fn {_ch, ix} -> MapSet.member?(hits, ix) end)
    |> Enum.map(fn [{_, ix} | _] = chunk ->
      kind = if MapSet.member?(hits, ix), do: :hit, else: :miss
      {kind, Enum.map_join(chunk, fn {ch, _} -> ch end)}
    end)
  end
end
