defmodule BuildCalculator.Rules.Epic do
  @moduledoc """
  Epic levels (21+) — the part of the calculation that is easiest to get wrong.

  Three rules, all verified against Fandom and recorded in
  `priv/rules/vanilla/epic.json` (CLAUDE.md §3):

    1. Odd character levels 21, 23 … grant +1 to base attack; even levels
       22, 24 … grant +1 to **all three** saves. By level 40 that is +10 and +10.
       Siala's level 41 is odd and behaves like a vanilla epic level, so the cap
       ends at +11 attack / +10 saves. Both tables come from the ruleset — this
       module never names a level or a bonus.
    2. **Class levels taken after character level 20 contribute nothing** to base
       attack or base saves; only the first 20 character levels count. Hence
       `Fighter 20 -> Wizard 20` = BAB 30 while `Wizard 20 -> Fighter 20` = BAB 20:
       the order the classes were taken in is irreversible.
    3. **Attacks per round are frozen by the BAB at character level 20.** Epic
       attack bonus raises the numbers but never adds an attack.
  """

  @doc "Cumulative epic attack bonus at `character_level`."
  @spec attack_bonus(map(), non_neg_integer()) :: non_neg_integer()
  def attack_bonus(ruleset, character_level) do
    lookup(ruleset.epic.attack_bonus, character_level)
  end

  @doc "Cumulative epic bonus to each of the three saves at `character_level`."
  @spec save_bonus(map(), non_neg_integer()) :: non_neg_integer()
  def save_bonus(ruleset, character_level) do
    lookup(ruleset.epic.save_bonus, character_level)
  end

  @doc "Whether `character_level` is an epic level for this ruleset."
  @spec epic_level?(map(), non_neg_integer()) :: boolean()
  def epic_level?(ruleset, character_level), do: character_level >= ruleset.epic.starts_at

  @doc """
  How many of the build's character levels feed base attack and base saves.

  Twenty, in every ruleset seen so far — but it is `epic_starts_at - 1`, read
  from the data, not a literal.
  """
  @spec counted_levels(map()) :: pos_integer()
  def counted_levels(ruleset), do: ruleset.epic.class_levels_count_up_to

  # Tables are sparse (a bonus only appears on the levels that grant one), so the
  # bonus at level N is the entry for the highest granting level at or below N.
  defp lookup(table, character_level) do
    table
    |> Enum.filter(fn {level, _bonus} -> level <= character_level end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.max(fn -> 0 end)
  end
end
