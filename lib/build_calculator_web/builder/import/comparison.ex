defmodule BuildCalculatorWeb.Builder.Import.Comparison do
  @moduledoc """
  The source's own totals beside ours, row by row — documented at
  `BuildCalculatorWeb.Builder.Import.comparison/2`. A part of
  `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  use Gettext, backend: BuildCalculatorWeb.Gettext

  import BuildCalculatorWeb.Builder.Import.Issues, only: [ellipsis: 1, signed: 1]
  import BuildCalculatorWeb.Builder.Import.Names, only: [save_name: 1]

  def comparison(%{source: %{totals: totals}}, stats) do
    for total <- totals do
      caveat = Map.get(total, :caveat)

      %{
        label: total.key,
        source: total.value,
        ours: if(not_ours?(caveat), do: "—", else: ours(total, stats)),
        note: caveat_note(caveat) || legend_note(Map.get(total, :legend))
      }
    end
  end

  # A companion's number, and the character's at its first level (task 4.36):
  # ours at the last level is no number to set beside either.
  defp not_ours?({:aside, :companion, _header}), do: true
  defp not_ours?({:start, _key}), do: true
  defp not_ours?(_caveat), do: false

  # Task 4.36: a block of saves whose caption names its columns
  # (`Sheets.block_header/1`) — the first one is shown, and which is the total
  # only the caption says.
  defp legend_note(nil), do: nil

  defp legend_note(caption),
    do:
      gettext("the caption “%{caption}” names the columns — the first one is shown",
        caption: ellipsis(caption)
      )

  # Task 4.31: why the source's number is not set against ours as it stands.
  defp caveat_note(nil), do: nil

  # Task 4.36: `Saves start` — the first level's numbers.
  defp caveat_note({:start, key}),
    do: gettext("“%{key}” gives the starting values, not the final ones", key: ellipsis(key))

  defp caveat_note({:aside, :companion, header}),
    do: gettext("under “%{header}” — not this character", header: header)

  defp caveat_note({:aside, :form, header}),
    do: gettext("under “%{header}” — a shape the character takes", header: header)

  defp caveat_note({:aside, :buffed, header}),
    do: gettext("under “%{header}” — with buffs, which we do not count", header: header)

  defp caveat_note({:rolled, marker}),
    do: gettext("rolled dice, not the maximum — “%{marker}”", marker: ellipsis(marker))

  # Task 4.40: each of ours carries its name — `Fort +31 / Will +28 / Ref +20`
  # beside the source's `31/28/20` under `(Fortitude/Will/Reflex)`. In the
  # source's order, as before, but bare numbers in an order the reader had to
  # take on trust read as Fort/Ref/Will, the order of our export, and set Will
  # against Reflex. A name and its number are joined by a no-break space: the
  # column is narrow (`.import-cmp-r`: 110 px on the desktop, 82 px measured at
  # 390), and the line may break only between two saves.
  defp ours(%{id: :saves} = total, stats) do
    values = %{fort: stats.fort, ref: stats.ref, will: stats.will}

    total
    |> saves_order()
    |> Enum.map_join(" / ", &"#{save_label(&1)}\u00A0#{signed(Map.fetch!(values, &1))}")
  end

  defp ours(%{id: :hp}, stats), do: number(stats.hp)
  defp ours(%{id: :skill_points}, stats), do: number(stats.skill_points.earned)
  defp ours(%{id: :bab}, stats), do: number(stats.base_attack)
  defp ours(%{id: :ab}, stats), do: signed(stats.attack_bonus)
  defp ours(%{id: :apr}, stats), do: number(stats.attacks_per_round)
  # Task 4.53: the number may be `?` — no plural form hangs on it.
  defp ours(%{id: :ac}, stats), do: gettext("%{ac} naked", ac: number(stats.ac_naked))

  # The order the caption names the three saves in — `(Fortitude/Will/Reflex)`,
  # `(F/W/R)` — or, when the caption names none (`Saving throws: Fortitude 21,
  # Reflex 33, Will 16`), the order the value does. Neither: Fort/Ref/Will, the
  # order of the guild's own template and of our export.
  defp saves_order(%{key: key, value: value}),
    do: named_order(key) || named_order(value) || [:fort, :ref, :will]

  # The saves' names — `Names.save_name/1`, the table the block of saves is
  # read with (task 4.34).
  defp named_order(text) do
    order =
      text
      |> String.downcase()
      |> String.split(~RX/[^a-z]+/, trim: true)
      |> Enum.flat_map(&List.wrap(save_name(&1)))
      |> Enum.uniq()

    if Enum.sort(order) == [:fort, :ref, :will], do: order
  end

  # The saves' names as the totals panel and the export print them — game
  # terms, English in every edition (CLAUDE.md §4).
  defp save_label(:fort), do: "Fort"
  defp save_label(:ref), do: "Ref"
  defp save_label(:will), do: "Will"

  defp number(nil), do: "?"
  defp number(value), do: Integer.to_string(value)
end
