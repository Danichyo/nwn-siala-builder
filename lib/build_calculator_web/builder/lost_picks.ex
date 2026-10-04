defmodule BuildCalculatorWeb.Builder.LostPicks do
  @moduledoc """
  Picks whose level no longer grants the slot they stand in, taken out of the
  build — feats (task 4.62) and known spells (task 4.63), one rule for both.

  Which picks those are is the core's answer, `Rules.lost_slot_picks/2`: a level's
  slots are `FeatSlots.at/3` and `Spells.slots_at/3`, the lists the builder draws
  its chips from, and a level below the first grants none. This module only
  decides what the builder does about them — takes them out, because it has no
  chip to show such a pick on, while the number (a feat) or the printed guide
  (a spell) would keep it.

  The slots depend on the race, on the level and on the class of the level (its
  class level counts every earlier level of that class), so two edits leave such
  a pick behind — the race changed, or the class of an earlier level, which
  renumbers the class levels after it. A slot that stayed (the same id on the
  same level) keeps its pick, whatever happened around it.

  ⚠ Only the slot is asked. A known spell in a slot that is still there but not
  on the list of the level's new class (a Sorcerer's `Electric jolt` in a Bard's
  cantrip slot) stays: its chip shows it and clears it, and the ladder marks it
  (`Rules.illegal_spells/2`, `{:not_on_spell_list, …}`) — the way a feat the new
  class forbids stays in the general slot with a ⚠. So does a spell its class
  already knows from an earlier pick (`{:spell_already_known, …}`, task 4.64 — an
  old link; the list refuses it since): which of the two picks the player meant to
  keep is his decision, and taking one out would be ours.
  """

  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Spells}

  @typedoc "What a prune took out, by kind — the shape of `Rules.lost_slot_picks/2`."
  @type lost :: %{feats: [Rules.lost_feat_pick()], spells: [Spells.lost_pick()]}

  @doc """
  The build without its lost picks, and those picks — `{build, %{feats: [{level,
  slot_id, pick}], spells: [{level, slot_id, spell_id, reason}]}}`, each by level
  and then slot order. A spell comes with the core's reason
  (`{:spell_slot_not_granted, circle, granted}`), which its sentence needs.

  Nothing to take out — the build comes back as it was, not rebuilt.
  """
  @spec prune(map(), Build.t()) :: {Build.t(), lost()}
  def prune(ruleset, %Build{} = build) do
    lost = Rules.lost_slot_picks(build, ruleset)

    if none?(lost) do
      {build, lost}
    else
      {%Build{
         build
         | feats: drop(build.feats, lost.feats),
           spells: drop(build.spells, lost.spells)
       }, lost}
    end
  end

  @doc "Whether a prune took nothing out."
  @spec none?(lost()) :: boolean()
  def none?(%{feats: [], spells: []}), do: true
  def none?(%{feats: _, spells: _}), do: false

  # A level left with no picks drops out of the map, as the builder's own
  # `clear_slot`/`clear_spell` leave it. A lost pick is `{level, slot, …}` — a
  # spell carries its reason as a fourth element.
  defp drop(by_level, lost) do
    Enum.reduce(lost, by_level, fn pick, acc ->
      {level, slot} = {elem(pick, 0), elem(pick, 1)}

      rest = acc |> Map.fetch!(level) |> Map.delete(slot)
      if rest == %{}, do: Map.delete(acc, level), else: Map.put(acc, level, rest)
    end)
  end
end
