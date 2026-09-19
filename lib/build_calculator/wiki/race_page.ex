defmodule BuildCalculator.Wiki.RacePage do
  @moduledoc """
  Reads one Fandom playable-race page into the fields a build calculator needs.

  There are seven such pages and none of them carries a template or a single bold
  label: every fact is an English sentence. Only three shapes repeat reliably
  across the seven, and this module reads exactly those:

    * the lead's **ability adjustments** line — `Dwarven [[ability]] adjustments:
      +2 [[Con]], -2 [[Cha]]`. Five pages have one; human and half-elf have none,
      which is how "this race adjusts nothing" is written, so a missing line maps
      to an empty list rather than to `nil`.
    * the lead's **favored class** line — `[[Favored class]] ([[Fighter]]): …`,
      or `(Any)` on human and half-elf.
    * the `== Special abilities ==` bullet list. Every top-level bullet opens with
      a link to the **feat** that implements it (`*[[Stonecunning]]: …`), which is
      the one genuinely machine-readable thing on these pages: all 29 members of
      Fandom's `Category:Racial feats` are reachable this way, so the list of
      feats a race grants is derived from the wiki rather than transcribed by
      hand. The bullets are also returned verbatim, sub-bullets included.

  Four further sentences are turned into structure, each matched **whole and
  anchored** so that an edit to the wording produces no match — and therefore a
  reported problem and a `nil` — instead of a plausible wrong number:

    * `+2 racial bonus to [[lore]] checks.` → `%{"lore" => 2}`. Only this exact
      shape counts. Dwarven stonecunning (`+2 racial bonus **on** [[Search]]
      checks **made in subterranean areas**`) and the small-stature size bonus
      are conditional or multi-skill, and structuring them would mean deciding
      what the condition means. They are listed in `skill_bonuses_prose` instead,
      so that a consumer of `skill_bonuses` can see the field is not the whole
      story rather than quietly under-counting.
    * `1 extra [[feat]] at 1st level.` → `%{level: 1, count: 1}` (human only).
    * `4 extra [[skill point]]s at 1st level, plus 1 additional skill point at
      each following level.` → `%{level: 1, extra: 4, per_level: 1}` (human only).
    * The `[[Small stature]]` bullet (gnome, halfling only) opens `"<Race>s are
      small creatures"` → `size: "small"`. Two of its sub-bullets are legality
      rules rather than colour — `Cannot use [[tower shield]]s.` and `Cannot use
      [[weapon size|large weapons]].` — and are read into
      `cannot_use_tower_shields` / `cannot_use_large_weapons` (AGENT_QUEUE.md
      §3.44). A page carrying no such bullet returns `size: nil`: five of the
      seven race pages never call themselves "medium" in so many words, and
      that absence is for `wiki.parse.ex` to resolve against a different page
      (the way it already resolves `granted_feats` against a class page *and* a
      feat page), not for this single-page module to guess at.

  Everything else — darkvision, immunities, the bonus against giants, the elven
  weapon proficiencies, and the rest of the `Small stature` bullet itself (the
  size modifiers to attack rolls and AC, the stealth bonus, the
  character-creation caveat) — stays verbatim in the bullet text. Structuring it
  is a later, human-reviewed step (CLAUDE.md §3: never invent game numbers).
  """

  alias BuildCalculator.Wiki.Wikitext

  @type ability :: %{
          link: binary | nil,
          name: binary,
          text: binary | nil,
          raw: binary
        }

  # Both spellings the pages use, abbreviated and full.
  @ability_names %{
    "str" => "STR",
    "strength" => "STR",
    "dex" => "DEX",
    "dexterity" => "DEX",
    "con" => "CON",
    "constitution" => "CON",
    "int" => "INT",
    "intelligence" => "INT",
    "wis" => "WIS",
    "wisdom" => "WIS",
    "cha" => "CHA",
    "charisma" => "CHA"
  }

  @adjustments ~r/ability\s+adjustments\s*:/iu
  @favored_class ~r/favored\s+class\s*\(([^)]*)\)/iu
  @leading_link ~r/^\[\[([^\[\]|]+)(?:\|([^\[\]]*))?\]\](\p{L}*)/u
  @skill_bonus ~r/^([+-]\d+)\s+racial bonus to \[\[([^\[\]|]+)\]\] checks\.$/u
  @skill_bonus_prose ~r/bonus\s+(?:to|on)\b[^.]*\bchecks?\b/iu
  @extra_feats ~r/^(\d+)\s+extra\s+\[\[feats?\]\]s?\s+at\s+(\d+)\w{2}\s+level\.$/u
  @bonus_skill_points ~r/^(\d+)\s+extra\s+\[\[skill points?\]\]s?\s+at\s+(\d+)\w{2}\s+level,\s+plus\s+(\d+)\s+additional\s+skill\s+point\s+at\s+each\s+following\s+level\.$/u

  # AGENT_QUEUE.md §3.44. Only gnome and halfling open their `Small stature`
  # bullet this way — anchored so a rewording is a reported problem, not a
  # wrong guess at which five races count as "the rest".
  @small_creatures ~r/^\p{L}+ are small creatures\b/u
  @bullet_marker ~r/^\s*\*+\s*/u
  @tower_shield_ban "Cannot use [[tower shield]]s."
  @large_weapon_ban "Cannot use [[weapon size|large weapons]]."

  @doc """
  Parses a race page.

  Returns the parsed fields plus `problems` — human-readable strings for
  everything the page did not yield, which the caller is expected to report
  rather than swallow.
  """
  @spec parse(binary) :: map
  def parse(wikitext) do
    [lead | sections] = Wikitext.sections(wikitext)

    adjustments = find_line(lead.body, @adjustments)
    {modifiers, modifier_problems} = ability_modifiers(adjustments)

    favored = find_line(lead.body, @favored_class)
    {favored_name, favored_any?, favored_problems} = favored_class(favored)

    {abilities, ability_problems} = abilities(section(sections, "special abilities"))

    {skill_bonuses, prose} = skill_bonuses(abilities)

    {extra_feats, extra_feat_problems} =
      one_of(abilities, @extra_feats, &extra_feats_value/1, "feat")

    {bonus_skill_points, skill_point_problems} =
      one_of(abilities, @bonus_skill_points, &bonus_skill_points_value/1, "skill point")

    {size, cannot_use_tower_shields, cannot_use_large_weapons, small_stature_raw, size_problems} =
      small_stature(abilities)

    %{
      ability_modifiers: modifiers,
      ability_modifiers_raw: raw(adjustments),
      favored_class_name: favored_name,
      favored_class_any?: favored_any?,
      favored_class_raw: raw(favored),
      abilities: abilities,
      skill_bonuses: skill_bonuses,
      skill_bonuses_prose: prose,
      extra_feats: extra_feats,
      bonus_skill_points: bonus_skill_points,
      size: size,
      cannot_use_tower_shields: cannot_use_tower_shields,
      cannot_use_large_weapons: cannot_use_large_weapons,
      small_stature_raw: small_stature_raw,
      problems:
        modifier_problems ++
          favored_problems ++
          ability_problems ++
          extra_feat_problems ++ skill_point_problems ++ size_problems
    }
  end

  # ── lead ──────────────────────────────────────────────────────────────────

  # The lead is prose, so a fact is found by what the line *says* once its links
  # are rendered away — `[[Favored class]] ([[Fighter]])` and `Favored class
  # (Any)` have to be found by one and the same test. The original line is kept
  # alongside so the snapshot can still store it with its markup.
  defp find_line(body, regex) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      stripped = Wikitext.strip_links(line)
      if Regex.match?(regex, stripped), do: {String.trim(line), stripped}
    end)
  end

  defp raw(nil), do: nil
  defp raw({line, _stripped}), do: line

  # No adjustments line at all is how human and half-elf say "no modifiers" —
  # every race that adjusts something has one. A line that is present but not
  # understood is a different matter and yields `nil` plus a problem.
  defp ability_modifiers(nil), do: {[], []}

  defp ability_modifiers({line, stripped}) do
    tail = stripped |> String.split(@adjustments, parts: 2) |> List.last()
    pairs = Regex.scan(~r/([+-]\d+)\s+(\p{L}+)/u, tail)
    numbers = Regex.scan(~r/[+-]\d+/u, tail)

    modifiers =
      Enum.map(pairs, fn [_match, amount, name] ->
        {Map.get(@ability_names, String.downcase(name)), String.to_integer(amount)}
      end)

    cond do
      pairs == [] or length(pairs) != length(numbers) ->
        {nil, ["ability adjustments not understood: #{line}"]}

      Enum.any?(modifiers, &(elem(&1, 0) == nil)) ->
        {nil, ["unknown ability name in adjustments: #{line}"]}

      true ->
        {modifiers, []}
    end
  end

  defp favored_class(nil), do: {nil, false, ["no favored class line"]}

  defp favored_class({line, stripped}) do
    case Regex.run(@favored_class, stripped) do
      [_match, inside] ->
        inside = String.trim(inside)

        if String.downcase(inside) == "any",
          do: {nil, true, []},
          else: {inside, false, []}

      nil ->
        {nil, false, ["favored class not understood: #{line}"]}
    end
  end

  # ── special abilities ─────────────────────────────────────────────────────

  defp section(sections, title) do
    Enum.find(sections, fn section ->
      section.title && String.downcase(String.trim(section.title)) == title
    end)
  end

  defp abilities(nil), do: {[], ["no `== Special abilities ==` section"]}

  defp abilities(section) do
    {groups, problems} =
      section.body
      |> String.split("\n")
      |> Enum.reduce({[], []}, &group_bullet/2)

    entries = groups |> Enum.reverse() |> Enum.map(&Enum.reverse/1) |> Enum.map(&entry/1)

    {Enum.map(entries, & &1.ability),
     Enum.reverse(problems) ++ Enum.flat_map(entries, & &1.problems)}
  end

  # A `*` opens an ability, `**` and any stray continuation line belong to the one
  # above it: the small-stature bullet carries six sub-bullets that are part of
  # the same ability and must not become five nameless ones.
  defp group_bullet(line, {groups, problems}) do
    cond do
      String.trim(line) == "" -> {groups, problems}
      Regex.match?(~r/^\s*\*\*/u, line) -> continue(line, groups, problems)
      Regex.match?(~r/^\s*\*/u, line) -> {[[line] | groups], problems}
      true -> continue(line, groups, problems)
    end
  end

  defp continue(line, [], problems),
    do: {[], ["text outside a bullet: #{String.trim(line)}" | problems]}

  defp continue(line, [current | rest], problems), do: {[[line | current] | rest], problems}

  defp entry(lines) do
    raw = Enum.join(lines, "\n")
    first = lines |> List.first() |> String.replace(~r/^\s*\*+\s*/u, "")

    case Regex.run(@leading_link, first) do
      [match, target, display, suffix] ->
        rest = String.replace_prefix(first, match, "")

        %{
          ability: %{
            link: target,
            name: display(display, target) <> suffix,
            text: text(rest),
            raw: raw
          },
          problems: []
        }

      nil ->
        %{
          ability: %{link: nil, name: Wikitext.strip_links(first), text: text(first), raw: raw},
          problems: ["ability bullet does not start with a feat link: #{first}"]
        }
    end
  end

  defp display("", target), do: target
  defp display(display, _target), do: display

  defp text(rest) do
    case rest |> String.trim() |> String.replace_prefix(":", "") |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  # ── numbers ───────────────────────────────────────────────────────────────

  defp skill_bonuses(abilities) do
    {structured, rest} =
      Enum.split_with(abilities, &(&1.text && Regex.match?(@skill_bonus, &1.text)))

    bonuses =
      Enum.map(structured, fn ability ->
        [_match, amount, skill] = Regex.run(@skill_bonus, ability.text)
        {skill, String.to_integer(amount)}
      end)

    {bonuses,
     rest |> Enum.filter(&Regex.match?(@skill_bonus_prose, &1.raw)) |> Enum.map(& &1.raw)}
  end

  # Both of these sentences exist on exactly one page (human), so more than one
  # match means the wiki changed shape and the caller should look rather than
  # have this module pick a winner.
  defp one_of(abilities, regex, build, label) do
    case Enum.filter(abilities, &(&1.text && Regex.match?(regex, &1.text))) do
      [] -> {nil, []}
      [ability] -> {build.(Regex.run(regex, ability.text)), []}
      many -> {nil, ["#{length(many)} bullets grant extra #{label}s, expected one"]}
    end
  end

  defp extra_feats_value([_match, count, level]),
    do: %{level: String.to_integer(level), count: String.to_integer(count)}

  defp bonus_skill_points_value([_match, extra, level, per_level]),
    do: %{
      level: String.to_integer(level),
      extra: String.to_integer(extra),
      per_level: String.to_integer(per_level)
    }

  # AGENT_QUEUE.md §3.44: the one ability bullet that is also a legality rule,
  # not just colour. Present only on gnome and halfling; its absence on the
  # other five pages is not read as "medium" here — no single page states that
  # in so many words, so `wiki.parse.ex` resolves it against a different page,
  # same as it already resolves a class's proficiencies against a class page
  # *and* a feat page rather than guessing from one alone.
  defp small_stature(abilities) do
    case Enum.find(abilities, &(&1.link == "Small stature")) do
      nil ->
        {nil, nil, nil, nil, []}

      ability ->
        lines =
          ability.raw
          |> String.split("\n")
          |> Enum.map(&(&1 |> String.trim() |> String.replace(@bullet_marker, "")))

        opens_with_small_creatures? =
          ability.text != nil and Regex.match?(@small_creatures, ability.text)

        tower_shield_banned? = @tower_shield_ban in lines
        large_weapons_banned? = @large_weapon_ban in lines

        problems =
          []
          |> note_unless(
            opens_with_small_creatures?,
            "Small stature bullet does not open with \"<Race>s are small creatures\": #{ability.text}"
          )
          |> note_unless(
            tower_shield_banned?,
            "Small stature bullet has no tower shield ban: #{ability.raw}"
          )
          |> note_unless(
            large_weapons_banned?,
            "Small stature bullet has no large weapon ban: #{ability.raw}"
          )

        size = if opens_with_small_creatures?, do: "small"

        {size, tower_shield_banned?, large_weapons_banned?, ability.raw, problems}
    end
  end

  defp note_unless(problems, true, _message), do: problems
  defp note_unless(problems, false, message), do: [message | problems]
end
