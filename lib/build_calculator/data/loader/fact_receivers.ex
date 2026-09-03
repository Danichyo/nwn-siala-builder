defmodule BuildCalculator.Data.Loader.FactReceivers do
  @moduledoc """
  Получатель факта — `changes[].affects`: **что именно меняет факт шарда**, и четыре
  сторожа, сверяющие это поле с одним и тем же объявленным словарём.

  Живёт это здесь, а не рядом с фитами и навыками, потому что факт лежит
  в `siala_41/classes.json` и приходит от класса; получателем при этом может быть
  что угодно — фит, навык, прибавка, — и сторожа этих получателей
  (`verify_bonus_affects!/4` и соседи) зовут все семь читателей прибавок.
  """

  alias BuildCalculator.Data.Loader.Feats

  # ------------------------------------------- what a shard fact changes --

  # `changes[].affects` — the receiver of a fact: **what it changes**, from the
  # closed vocabulary the same file declares under `_receivers` (task 3.28, Dan
  # 10.08.2026). `our` receivers are what the constructor and the build page
  # print, so a fact naming one of them stays a gap; a fact whose every receiver
  # is `not_our` is about a mechanic the calculator gives no answer about at all,
  # and is not a hole in that answer. `BuildCalculator.Rules.GapReceivers` reads
  # the set and applies the rule; this reads and checks the vocabulary.
  #
  # ⚠ Two things raise here rather than degrading quietly, and both fail towards
  # **showing** the fact:
  #
  #   * a receiver outside the vocabulary. A typo (`"damge"`) would otherwise
  #     silently mean "not ours" — i.e. "do not show" — which is the one outcome
  #     the mechanism may not produce by accident. Same reasoning as
  #     `Rules.Vocabulary` failing the build on a gap form nobody worded.
  #   * `affects` on a fact while the file declares no vocabulary. With an empty
  #     `our` set every labelled fact would vanish at once. A missing field is a
  #     different case and is deliberately allowed: no label means "still a gap".
  def gap_receivers!(:missing), do: %{our: MapSet.new(), not_our: MapSet.new()}

  def gap_receivers!(%{"classes" => entries} = file) do
    receivers = declared_receivers!(file["_receivers"])

    known = MapSet.union(receivers.our, receivers.not_our)

    for entry <- entries, change <- entry["changes"] || [] do
      verify_affects!("siala_41/classes.json", entry["id"], change, known)
    end

    receivers
  end

  def gap_receivers!(_other), do: %{our: MapSet.new(), not_our: MapSet.new()}

  defp declared_receivers!(%{"our" => our, "not_our" => not_our})
       when is_map(our) and is_map(not_our) do
    receivers = %{our: MapSet.new(Map.keys(our)), not_our: MapSet.new(Map.keys(not_our))}

    unless MapSet.disjoint?(receivers.our, receivers.not_our) do
      both = receivers.our |> MapSet.intersection(receivers.not_our) |> Enum.sort()

      raise """
      siala_41/classes.json: _receivers lists #{inspect(both)} as both `our` and `not_our`. \
      A receiver is either something the calculator prints or something it does not — \
      one of the two entries is wrong.
      """
    end

    if MapSet.size(receivers.our) == 0 do
      raise """
      siala_41/classes.json: _receivers declares no `our` receivers, so every labelled \
      fact would stop being a gap at once. Fill the vocabulary or drop `_receivers` \
      together with every `affects` field.
      """
    end

    receivers
  end

  defp declared_receivers!(_absent_or_malformed),
    do: %{our: MapSet.new(), not_our: MapSet.new()}

  # The feat layer's half of the same check (task "фиты: получатели у
  # фактов", data-miner 14.08.2026) — `generated/feats.json` and the
  # hand-written `feats.json` beside it never declare their own `_receivers`;
  # they are checked against the one dictionary `siala_41/classes.json`
  # carries, via the same `verify_affects!/4` the classes file already uses.
  # `:missing` (no shard layer at all — the vanilla ruleset) is silently fine,
  # the same direction `gap_receivers!/1` takes for the same reason.
  def verify_feat_affects!(:missing, _known), do: :ok

  def verify_feat_affects!(file, known) do
    for entry <- Feats.feat_entries(file), change <- entry["changes"] || [] do
      id = entry["id"] || entry["vanilla_id"]
      verify_affects!("siala_41 feat layer (#{feat_source_label(entry)})", id, change, known)
    end

    :ok
  end

  # The skill layer's half of the same check (data-miner, 14.08.2026) —
  # `siala_41/skills.json` never declares its own `_receivers` either, same
  # shape and same reason as the feat layer above. Checked against `entry
  # ["skills"]` only: `global[]` carries five facts that never reach a skill's
  # `siala_changes` at all (see the file's own `_field_note`), so there is
  # nothing there for `affects` to be missing *from* — a `global[]` entry
  # could carry the field and it would simply never be read, which is a
  # dead field, not an unchecked one, so it is deliberately left alone here.
  def verify_skill_affects!(:missing, _known), do: :ok

  def verify_skill_affects!(%{"skills" => entries}, known) do
    for entry <- entries, change <- entry["changes"] || [] do
      id = entry["id"] || entry["vanilla_id"]
      verify_affects!("siala_41/skills.json", id, change, known)
    end

    :ok
  end

  def verify_skill_affects!(_other, _known), do: :ok

  # Which of the two files a raw feat entry came from, purely for the error
  # message: `feat_entries/1` already flattens `feats_generated` and
  # `feats_manual` the same way `apply_feat_layer/2` does, and by the time
  # this runs the two lists have not been zipped together yet, so the entry
  # itself is all there is to go on. Every entry in this layer carries `"id"`
  # (see `siala_record/4` / the hand-written file's own records), so this is
  # a hint for a human reading a raised error, never a value anything branches
  # on.
  def feat_source_label(%{"status" => "parsed"}), do: "generated/feats.json"
  def feat_source_label(_entry), do: "feats.json"

  defp verify_affects!(source, owner_id, change, known) do
    case change["affects"] do
      nil ->
        :ok

      list when is_list(list) and list != [] ->
        for receiver <- list, do: verify_receiver!(source, owner_id, change, receiver, known)

      other ->
        raise """
        #{source}: #{owner_id} / #{change["what"]} carries \
        affects: #{inspect(other)}. Expected a non-empty list of receiver ids — \
        a fact that affects nothing states nothing. Delete the field instead: \
        a fact with no `affects` counts as a gap.
        """
    end
  end

  defp verify_receiver!(source, owner_id, change, receiver, known) do
    cond do
      MapSet.size(known) == 0 ->
        raise """
        #{source}: #{owner_id} / #{change["what"]} names receiver \
        #{inspect(receiver)}, but the file declares no `_receivers` vocabulary to check \
        it against. Every labelled fact would silently stop being a gap.
        """

      receiver in known ->
        :ok

      true ->
        raise """
        #{source}: #{owner_id} / #{change["what"]} names receiver \
        #{inspect(receiver)}, which is in neither `_receivers.our` nor `_receivers.not_our`. \
        A misspelt receiver would quietly mean "not ours", i.e. "do not show" — \
        add it to the vocabulary or fix the spelling.
        """
    end
  end

  # `changes[].affects`'s closed vocabulary, checked a FOURTH time — against
  # all six vanilla bonus-markup files this shape has (`ac_bonuses.json`,
  # `feat_ability_bonuses.json`, `feat_attack_bonuses.json`,
  # `feat_hp_bonuses.json`, `feat_skill_bonuses.json`, `feat_save_bonuses.json`
  # — the sixth caught up 18.08.2026, task про шестой файл; five got it
  # 17.08.2026, task «пять файлов прибавок»). Same field, same meaning
  # («what does this fact change», read by `Rules.GapReceivers`), but a
  # genuinely different situation than the three checks above, and that is
  # why this is a sibling function rather than a fourth call to
  # `verify_affects!/4`.
  #
  # These six files are `vanilla/*.json`: read once and applied to **both**
  # rulesets unchanged, because the fact they record («does this feat add to
  # HP») is true of the game NWN1 describes, not of what the shard changed.
  # `verify_affects!/4`'s sibling `verify_receiver!/5` raises the moment
  # `known` is empty and a receiver is named, and that is correct **there**:
  # an empty vocabulary while a siala fact still carries `affects` can only
  # mean somebody deleted `_receivers` out from under live labels — a real
  # corruption, on the ruleset that is building right now.
  #
  # Here an empty `known` is not corruption, it is the **vanilla** ruleset
  # doing exactly what it is supposed to: `gap_receivers!(:missing)` hands
  # back two empty sets because vanilla carries no shard layer to declare a
  # vocabulary in, and this same file is read again, unedited, while building
  # it. Raising there would fail `mix compile` on a file that has done nothing
  # wrong — the same JSON gets checked for real one call later, while building
  # `siala_41`, whose `known_receivers` is not empty. A misspelt receiver is
  # still caught in the very same compile; it just does not have to be caught
  # twice.
  #
  # Structural checks — `affects` present but not a non-empty list, or an
  # unknown *name* once a vocabulary exists — still raise unconditionally,
  # exactly as `verify_affects!/4` does; only "no vocabulary to check
  # against" is treated differently.
  def verify_bonus_affects!(_source, _name, nil, _known), do: :ok

  def verify_bonus_affects!(source, name, list, known) when is_list(list) and list != [] do
    for receiver <- list, MapSet.size(known) > 0, receiver not in known do
      raise """
      #{source}: #{name} names receiver #{inspect(receiver)}, which is in neither \
      `_receivers.our` nor `_receivers.not_our` (siala_41/classes.json). A misspelt \
      receiver would quietly mean "not ours", i.e. "do not show" — add it to the \
      vocabulary or fix the spelling.
      """
    end

    :ok
  end

  def verify_bonus_affects!(source, name, other, _known) do
    raise """
    #{source}: #{name} carries affects: #{inspect(other)}. Expected a non-empty list of \
    receiver ids — a fact that affects nothing states nothing. Delete the field instead: \
    a fact with no `affects` counts as a gap.
    """
  end
end
