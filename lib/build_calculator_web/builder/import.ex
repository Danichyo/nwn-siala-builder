defmodule BuildCalculatorWeb.Builder.Import do
  @moduledoc """
  Somebody else's build, out of the community's text block.

  The other half of `BuildCalculatorWeb.Builder.Export`: the Epic Character
  Builders posting format (CLAUDE.md §3) is what forums and Discord actually
  exchange, so a player who found a build there must be able to paste it and
  open it here.

  Two properties matter more than how much of the text is understood.

  ## Tolerance

  Nobody formats the block the same way. Case, spacing, `01:` versus `1.`,
  community class shorthand (`WM`, `DD`, `CoT`), Siala's Russian race names,
  Discord quote markers and code fences, prose paragraphs in the middle — all of
  it is normal, and all of it has to survive. Every name is resolved through an
  index built from the ruleset itself: the English name, the shard's Russian
  name, the wiki alias (`ruleset.name_map`), any of those with the spaces taken
  out (`Shadow dancer`), a mechanically derived acronym (`ITWF`), and — for
  classes — a unique prefix. Nothing here carries a hand written synonym table,
  and a key two entries answer to is reported as ambiguous rather than guessed.

  ## Honesty

  Whatever did not parse is **reported, never invented** (CLAUDE.md §3). The
  result carries an `issues` list beside the build and the interface shows it
  before the player accepts the import. Three consequences are worth naming:

    * **A line the reader cannot parse stops the ladder** instead of letting the
      levels after it slide up one. Order decides base attack and saves past
      character level 20 outright, so a build with one level missing is not
      "almost right", it is a different character.
    * **The class split in the header never becomes levels.** `Fighter(10),
      Wizard(20)` states totals, not order, and `Fighter 20 → Wizard 20` is not
      the same build as the reverse. Without a `LEVELING GUIDE` the levels stay
      empty and the header split is shown for the player to rebuild from.
    * **The `SKILLS` totals are not imported.** A rank is priced and capped by
      the level it was bought at, and the totals block does not say which level
      that was. Only a per-level `SKILL GUIDE` can be read back.

  ## The source's own numbers are not the build's

  `Hitpoints`, `AB`, `AC` and the rest of the header are somebody else's
  arithmetic, usually with gear and buffs folded in. They are carried in
  `source.totals` so the player can compare them against ours, and they never
  reach the build — mixing a foreign result into our own calculation is exactly
  the confident lie this project is built to avoid.
  """

  alias BuildCalculator.Ids
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, Build, FeatChoices, FeatSlots}
  alias BuildCalculatorWeb.Builder.{ChoiceIndex, Feats, Fuzzy, Labels, PointBuy}

  # A build block is a couple of kilobytes. The ceiling is here so a pasted
  # forum thread cannot ask the parser to walk a megabyte.
  @max_bytes 64_000

  @ability_words ~w(str dex con int wis cha)

  @typedoc "A machine-readable note about something the text did not give us."
  @type issue :: tuple()

  @type result :: %{
          build: Build.t(),
          title: String.t() | nil,
          read: map(),
          issues: [issue()],
          source: map()
        }

  @doc """
  Reads a text block into a build, plus everything that did not read.

  Never raises and never returns an error: an unreadable paste is an empty build
  with a list of issues saying so, which is what the interface has to show
  anyway.
  """
  @spec parse(term(), map()) :: result()
  def parse(text, ruleset) when is_binary(text) do
    {body, clipped} = clamp(text)
    index = indexes(ruleset)

    scan =
      body
      |> lines()
      |> Enum.reduce(empty_scan(), &classify(&2, &1, index))

    assemble(scan, ruleset, index, clipped)
  end

  def parse(_text, ruleset), do: parse("", ruleset)

  defp clamp(text) do
    if byte_size(text) > @max_bytes,
      do: {binary_part(text, 0, @max_bytes), true},
      else: {text, false}
  end

  defp empty_scan do
    %{
      section: :head,
      title: nil,
      declared: [],
      race: nil,
      alignment: nil,
      printed: %{},
      levels: %{},
      skill_guide: %{},
      source_skills: [],
      loose_feats: [],
      totals: [],
      issues: []
    }
  end

  # ------------------------------------------------------------------- lines --

  # Quote markers, bullets and code fences are decoration a paste picks up on the
  # way here — Discord and forum quoting, not anything the format states — so
  # stripping them costs nothing and buys every second paste.
  defp lines(body) do
    body
    |> String.replace(~r/\r\n?/, "\n")
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, number} -> {number, undecorate(line)} end)
    |> Enum.reject(fn {_number, line} -> skip_line?(line) end)
  end

  defp undecorate(line) do
    line
    |> String.replace(~r/^[\s>|•*]+/u, "")
    |> String.replace(~r/^-\s+/u, "")
    |> String.trim()
  end

  defp skip_line?(line) do
    line == "" or String.starts_with?(line, "```") or Regex.match?(~r/^[-=_*~·—–]+$/u, line)
  end

  defp classify(scan, {number, line}, index) do
    cond do
      section = section_header(line) ->
        section(scan, section, line)

      pair = ability_line(line) ->
        abilities(scan, pair)

      total = totals_line(line) ->
        %{scan | totals: scan.totals ++ [total]}

      entry = numbered_line(line) ->
        numbered_entry(scan, entry, number, index)

      total = scan.section == :skills && skill_total_line(line) ->
        %{scan | source_skills: scan.source_skills ++ [total]}

      scan.section == :feats and scan.levels == %{} ->
        %{scan | loose_feats: scan.loose_feats ++ [line]}

      claimed = who_line(scan, line, index) ->
        claimed

      # The title is the block's first line and nothing else. A paste that
      # starts mid-build has no title, and prose further down is prose — reading
      # it as a name would put "Этот билд я собрал в 2019" in the save form.
      scan.title == nil and untouched?(scan) ->
        title(scan, line, index)

      true ->
        add(scan, {:ignored_line, number, line})
    end
  end

  defp add(scan, issue), do: %{scan | issues: scan.issues ++ [issue]}

  defp untouched?(scan) do
    scan.section == :head and scan.race == nil and scan.alignment == nil and
      scan.printed == %{} and scan.totals == [] and scan.levels == %{}
  end

  # ------------------------------------------------------------- line shapes --

  defp section_header(line) do
    words =
      line
      |> String.downcase()
      |> String.replace(~r/[^a-zа-яё ]/u, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    cond do
      String.starts_with?(words, "leveling guide") -> :levels
      String.starts_with?(words, "levelling guide") -> :levels
      String.starts_with?(words, "level guide") -> :levels
      String.starts_with?(words, "skill guide") -> :skill_guide
      String.starts_with?(words, "skills") -> :skills
      String.starts_with?(words, "feats") -> :feats
      true -> nil
    end
  end

  # `SKILLS: Discipline 43 (48), Tumble 40 (45)` is a section header and its
  # contents on one line — the guild's own template writes it that way.
  defp section(scan, section, line) do
    rest = line |> String.split(":", parts: 2) |> Enum.at(1, "") |> String.trim()
    scan = %{scan | section: section}

    case {section, rest} do
      {_section, ""} -> scan
      {:skills, rest} -> Enum.reduce(split_items(rest), scan, &skill_total(&2, &1))
      {:feats, rest} -> %{scan | loose_feats: scan.loose_feats ++ split_items(rest)}
      {_section, _rest} -> scan
    end
  end

  defp skill_total(scan, item) do
    case skill_total_line(item) do
      nil -> scan
      entry -> %{scan | source_skills: scan.source_skills ++ [entry]}
    end
  end

  # The bracketed number is the skill's *value*, and it is read as a string on
  # purpose: our own export prints `?` there when the key ability is named on no
  # wiki, and either way it is somebody else's arithmetic that never reaches the
  # build — the same rule as the header's Hitpoints.
  defp skill_total_line(line) do
    case Regex.run(~r/^(.+?)\s+(\d+)\s*(?:\(\s*([^)]*?)\s*\))?\s*$/u, String.trim(line)) do
      [_, name, ranks] -> %{name: String.trim(name), ranks: ranks, total: nil}
      [_, name, ranks, total] -> %{name: String.trim(name), ranks: ranks, total: total}
      _ -> nil
    end
  end

  defp ability_line(line) do
    with [_, keys, values] <-
           Regex.run(~r/^([A-Za-z]{3}(?:\s*\/\s*[A-Za-z]{3})*)\s*:\s*(\S.*)$/u, line),
         names = split_ability_keys(keys),
         true <- Enum.all?(names, &(&1 in @ability_words)) do
      {names, values}
    else
      _ -> nil
    end
  end

  defp split_ability_keys(keys) do
    keys
    |> String.split("/")
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
  end

  defp abilities(scan, {[name], values}), do: put_ability(scan, name, values)

  defp abilities(scan, {names, values}) do
    parts = String.split(values, "/")

    names
    |> Enum.with_index()
    |> Enum.reduce(scan, fn {name, ix}, acc -> put_ability(acc, name, Enum.at(parts, ix, "")) end)
  end

  # `STR: 16 (20)` — the first number is where the character started, the second
  # is where it ended up. Only the first is a decision; the second is arithmetic
  # over the +1s, which the level lines already carry.
  defp put_ability(scan, name, values) do
    numbers =
      ~r/-?\d+/
      |> Regex.scan(values)
      |> List.flatten()
      |> Enum.map(&String.to_integer/1)

    case numbers do
      [] ->
        scan

      [start | rest] ->
        printed = Map.put(scan.printed, name, %{start: start, final: List.first(rest)})
        %{scan | printed: printed}
    end
  end

  @total_keys [
    {"hitpoints", :hp, "Hitpoints"},
    {"hp", :hp, "Hitpoints"},
    {"skillpoints", :skill_points, "Skillpoints"},
    {"savingthrows", :saves, "Saving Throws (Fort/Ref/Will)"},
    {"saves", :saves, "Saving Throws (Fort/Ref/Will)"},
    {"bab", :bab, "BAB"},
    {"ab", :ab, "AB"},
    {"attacksperround", :apr, "Attacks per round"},
    {"ac", :ac, "AC"}
  ]

  # Read only to be shown back for comparison, so the value is kept exactly as
  # the source wrote it — `71 (naked 24)` and `+70/+55` alike. Nothing here is
  # converted to a number, because nothing here reaches the build.
  defp totals_line(line) do
    with [_, key, value] <- Regex.run(~r/^([A-Za-z][A-Za-z0-9 \/()\.\-]*?)\s*:\s*(\S.*)$/u, line),
         flat = key |> String.downcase() |> String.replace(~r/[^a-z]/, ""),
         {_prefix, id, label} <- Enum.find(@total_keys, &String.starts_with?(flat, elem(&1, 0))) do
      %{id: id, label: label, key: String.trim(key), value: String.trim(value)}
    else
      _ -> nil
    end
  end

  defp numbered_line(line) do
    with [_, number, rest] <- Regex.run(~r/^(\d{1,3})\s*[:.)\]]\s*(.*)$/u, line),
         {level, ""} <- Integer.parse(number) do
      {level, String.trim(rest)}
    else
      _ -> nil
    end
  end

  defp numbered_entry(scan, {level, rest}, number, index) do
    cond do
      scan.section == :skill_guide -> skill_guide(scan, level, rest, index)
      skill_shaped?(rest) -> skill_guide(scan, level, rest, index)
      true -> level_line(scan, level, rest, number)
    end
  end

  # `01: Discipline +4 (4), Spot +2 (2)` lands here whenever the SKILL GUIDE
  # header was cut off the paste. A level line never starts with a rank, so a
  # `+N` before the first bracket is what tells the two apart.
  defp skill_shaped?(rest) do
    case Regex.run(~r/^(.*?)\(/u, rest) do
      [_, head] -> Regex.match?(~r/\+\s*\d/u, head)
      _ -> not String.contains?(rest, ":") and Regex.match?(~r/\+\s*\d/u, rest)
    end
  end

  # ------------------------------------------------------------- level lines --

  defp level_line(scan, level, rest, number) do
    case split_level(rest) do
      nil ->
        add(scan, {:ignored_line, number, rest})

      {class_text, extras} ->
        entry = %{class_text: class_text, extras: extras}
        %{scan | levels: Map.put(scan.levels, level, entry)}
    end
  end

  defp split_level(rest) do
    cond do
      match = Regex.run(~r/^(.+?)\s*\(\s*\d+\s*\)\s*[:.\-–]?\s*(.*)$/u, rest) ->
        [_, class_text, extras] = match
        {String.trim(class_text), extras}

      String.contains?(rest, ":") ->
        [class_text, extras] = String.split(rest, ":", parts: 2)
        {String.trim(class_text), extras}

      rest != "" ->
        {rest, ""}

      true ->
        nil
    end
  end

  defp split_items(text) do
    text
    |> String.split(~r/[,;]/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # ------------------------------------------------------------- skill guide --

  defp skill_guide(scan, level, rest, index) do
    Enum.reduce(split_items(rest), scan, fn item, acc ->
      case skill_item(item) do
        nil -> acc
        {name, ranks} -> put_ranks(acc, level, name, ranks, index)
      end
    end)
  end

  defp put_ranks(scan, level, name, ranks, index) do
    case resolve(index.skills, name) do
      {:ok, id} ->
        at = scan.skill_guide |> Map.get(level, %{}) |> Map.update(id, ranks, &(&1 + ranks))
        %{scan | skill_guide: Map.put(scan.skill_guide, level, at)}

      :error ->
        add(scan, {:unknown_skill, level, name})

      {:ambiguous, ids} ->
        add(scan, {:ambiguous_skill, level, name, ids})
    end
  end

  defp skill_item(item) do
    case Regex.run(~r/^(.+?)\s*\+?\s*(\d+)\s*(?:\(\s*\d+\s*\))?\s*(?:x\s*\d+)?\s*$/u, item) do
      [_, name, ranks] -> {String.trim(name), String.to_integer(ranks)}
      _ -> nil
    end
  end

  # ------------------------------------------------------ race and alignment --

  # `Гном (Dwarf), Lawful Good`. Claimed only when at least one half resolves, so
  # a sentence of prose with a comma in it is not read as a character sheet.
  defp who_line(scan, line, index) do
    if scan.race || scan.alignment do
      nil
    else
      parts = line |> String.split(",", parts: 2) |> Enum.map(&String.trim/1)
      race_text = Enum.at(parts, 0, "")
      alignment_text = Enum.at(parts, 1)

      race = resolve_race(index, race_text)
      alignment = alignment_text && resolve_alignment(alignment_text)

      if match?({:ok, _}, race) or match?({:ok, _}, alignment) do
        scan
        |> claim_race(race, race_text)
        |> claim_alignment(alignment, alignment_text)
      end
    end
  end

  defp claim_race(scan, {:ok, id}, _text), do: %{scan | race: id}
  defp claim_race(scan, {:ambiguous, ids}, text), do: add(scan, {:ambiguous_race, text, ids})
  defp claim_race(scan, :error, text), do: add(scan, {:unknown_race, text})

  defp claim_alignment(scan, {:ok, id}, _text), do: %{scan | alignment: id}
  defp claim_alignment(scan, nil, _text), do: scan
  defp claim_alignment(scan, :error, text), do: add(scan, {:unknown_alignment, text})

  # `Гном (Dwarf)` gives two chances to resolve. Both are tried because both are
  # real names: the shard rebuilt the races rather than translating them, so
  # `Гном` is the name a Siala player uses and `Dwarf` the one the engine does
  # (CLAUDE.md §4) — and mind the collision, `Карлик` is Gnome.
  defp resolve_race(index, text) do
    outer = text |> String.replace(~r/\(.*\)/u, "") |> String.trim()
    inner = with [_, inside] <- Regex.run(~r/\(([^)]*)\)/u, text), do: String.trim(inside)

    Enum.find_value([text, outer, inner], :error, fn candidate ->
      case candidate && resolve(index.races, candidate) do
        {:ok, id} -> {:ok, id}
        {:ambiguous, ids} -> {:ambiguous, ids}
        _ -> nil
      end
    end)
  end

  defp resolve_alignment(text) do
    key = norm(text)

    Enum.find_value(alignment_index(), :error, fn {alias_key, id} ->
      if alias_key == key, do: {:ok, id}
    end)
  end

  # Built off `Ids.alignments/0` rather than typed out: the full name, the id,
  # and the two-letter shorthand the community writes. `N` is added by hand
  # because "Neutral" on its own is how True Neutral is written everywhere.
  defp alignment_index do
    base =
      for {id, name} <- Ids.alignments(),
          key <- [norm(name), norm(Atom.to_string(id)), initials(name)],
          do: {key, id}

    base ++ [{"n", :true_neutral}, {"neutral", :true_neutral}]
  end

  defp initials(name) do
    name
    |> String.split(~r/[\s\-]+/u, trim: true)
    |> Enum.map_join(&String.first/1)
    |> String.downcase()
  end

  # ------------------------------------------------------------------- title --

  # `Тестовый билд - Fighter(4), Dwarven defender(6)`. The name is separated from
  # the class split by a spaced dash, which is what lets a title keep a dash of
  # its own (`Dwarf-tank - Fighter(41)`).
  defp title(scan, line, index) do
    declared =
      line
      |> String.split(",")
      |> Enum.with_index()
      |> Enum.flat_map(fn {segment, ix} -> declared_class(segment, ix, index) end)

    %{scan | title: title_text(line, declared), declared: declared}
  end

  defp declared_class(segment, index_in_line, index) do
    case Regex.run(~r/^(.+?)\s*\(\s*(\d+)\s*\)/u, String.trim(segment)) do
      [_, name, levels] ->
        {title, name} = if index_in_line == 0, do: strip_title(name), else: {nil, name}

        [
          %{
            text: name,
            title: title,
            class: resolved_class(index, name),
            levels: String.to_integer(levels)
          }
        ]

      _ ->
        []
    end
  end

  defp strip_title(name) do
    case Regex.run(~r/^(.*\S)\s+[-–—]\s+(\S.*)$/u, name) do
      [_, title, class] -> {String.trim(title), String.trim(class)}
      _ -> {nil, name}
    end
  end

  defp resolved_class(index, name) do
    case resolve_class(index, name) do
      {:ok, id} -> id
      {:guess, id} -> id
      _ -> nil
    end
  end

  defp title_text(_line, [%{title: title} | _]) when is_binary(title), do: blank_to_nil(title)
  defp title_text(_line, [_ | _]), do: nil
  defp title_text(line, []), do: blank_to_nil(String.trim(line))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text

  # ---------------------------------------------------------------- assembly --

  defp assemble(scan, ruleset, index, clipped) do
    issues = if clipped, do: scan.issues ++ [{:text_clipped, @max_bytes}], else: scan.issues
    {levels, issues} = ladder(scan, ruleset, index, issues)

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: scan.race,
        alignment: scan.alignment,
        levels: levels
      )

    {build, issues} = with_abilities(build, scan, ruleset, issues)
    {build, issues} = with_feats(build, scan, ruleset, index, issues)
    {build, issues} = with_skills(build, scan, issues)

    %{
      build: build,
      title: scan.title,
      read: read(build, scan),
      issues: issues ++ crosschecks(build, scan, ruleset),
      source: %{
        totals: scan.totals,
        skills: scan.source_skills,
        declared: scan.declared,
        abilities: scan.printed
      }
    }
  end

  # The spine. A level that cannot be read stops the ladder instead of letting
  # the levels after it slide up one: order decides base attack and saves past
  # 20 outright (CLAUDE.md §3), so a shifted ladder is a different character and
  # a plausible-looking wrong answer is worse than a short right one.
  defp ladder(scan, ruleset, index, issues) do
    scan.levels
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce_while({[], issues}, fn level, {taken, issues} ->
      entry = Map.fetch!(scan.levels, level)

      cond do
        level != length(taken) + 1 ->
          {:halt, {taken, issues ++ [{:level_gap, length(taken) + 1, level}]}}

        level > ruleset.level_cap ->
          {:halt, {taken, issues ++ [{:level_over_cap, level, ruleset.level_cap}]}}

        true ->
          add_level(taken, issues, level, entry, index)
      end
    end)
  end

  defp add_level(taken, issues, level, entry, index) do
    case resolve_class(index, entry.class_text) do
      {:ok, id} ->
        {:cont, {taken ++ [id], issues}}

      # Read off a shorthand nobody wrote down: `Ftr`, `Drd`, `Bbn`. Reported
      # every time rather than trusted quietly — a guess the player can see in
      # the ladder and reject is tolerance, a silent one is invention.
      {:guess, id} ->
        {:cont, {taken ++ [id], issues ++ [{:class_guessed, level, entry.class_text, id}]}}

      :error ->
        {:halt, {taken, issues ++ [{:unknown_class, level, entry.class_text}, stopped(taken)]}}

      {:ambiguous, ids} ->
        {:halt,
         {taken, issues ++ [{:ambiguous_class, level, entry.class_text, ids}, stopped(taken)]}}
    end
  end

  defp stopped(taken), do: {:ladder_stopped, length(taken)}

  # The printed scores are a character sheet, not a point buy: they already carry
  # the racial modifiers, so those come back off (HANDOFF, «Гном Защитник» —
  # CHA 6 is a number the 8..18 scale cannot produce at all). Without a race
  # there is nothing to subtract, and that is said out loud instead of guessed.
  defp with_abilities(build, scan, ruleset, issues) do
    if scan.printed == %{} do
      {build, issues ++ [{:abilities_missing}]}
    else
      racial = Abilities.racial_modifiers(build, ruleset)

      {scores, issues} =
        Enum.reduce(Abilities.keys(), {%{}, issues}, fn ability, {scores, issues} ->
          case Map.get(scan.printed, Atom.to_string(ability)) do
            nil ->
              {Map.put(scores, ability, PointBuy.min_score(ruleset)), issues}

            %{start: start} ->
              base = start - Map.get(racial, ability, 0)

              {Map.put(scores, ability, clamp_score(base)),
               off_scale(issues, ruleset, ability, base)}
          end
        end)

      issues = if build.race, do: issues, else: issues ++ [{:abilities_without_race}]
      {%Build{build | base_abilities: scores}, issues}
    end
  end

  defp clamp_score(score), do: score |> max(0) |> min(255)

  defp off_scale(issues, ruleset, ability, score) do
    if score < PointBuy.min_score(ruleset) or score > PointBuy.max_score(ruleset),
      do: issues ++ [{:ability_off_point_buy, ability, score}],
      else: issues
  end

  # Slots are not interchangeable (CLAUDE.md §6) and the text never says which
  # one a feat went into, so the placement is redone the way a click would do it:
  # the narrowest slot that accepts the feat. The most constrained feats are
  # placed first, or a general-only feat finds the general slot already spent on
  # something the class bonus would have taken for free.
  defp with_feats(build, scan, ruleset, index, issues) do
    Enum.reduce(1..length(build.levels)//1, {build, issues}, fn level, {build, issues} ->
      extras = scan.levels |> Map.get(level, %{}) |> Map.get(:extras, "")
      {items, increase} = extras(extras, index)
      build = with_increase(build, increase, level)
      {feats, issues} = feat_ids(items, level, index, ruleset, issues)

      feats
      |> Enum.sort_by(&openings(ruleset, build, level, &1))
      |> Enum.reduce({build, issues}, &place_feat(&2, &1, ruleset, level))
    end)
  end

  # The ability bump is pulled out of whatever item it was written into, because
  # it is not always its own: our own export writes `+1 STR, 19` as two items,
  # but a forum line reads `Weapon focus (longsword) +1 str`. What is left of the
  # item is still a feat name.
  #
  # The score printed after the bump is the source's own arithmetic and is
  # dropped on the floor, like every other computed number in the block.
  defp extras(extras, index) do
    {items, increase} =
      extras
      |> split_items()
      |> Enum.map_reduce(nil, fn item, found ->
        case increase_in(item, index) do
          nil -> {item, found}
          {id, rest} -> {rest, found || id}
        end
      end)

    {Enum.reject(items, &drop_item?/1), increase}
  end

  defp drop_item?(item), do: item == "" or Regex.match?(~r/^\d+$/, item)

  defp feat_ids(items, level, index, ruleset, issues) do
    Enum.reduce(items, {[], issues}, fn item, {feats, issues} ->
      resolve_feat(item, level, index, ruleset, feats, issues)
    end)
  end

  defp resolve_feat(item, level, index, ruleset, feats, issues) do
    {name, qualifier} = split_qualifier(item)

    case resolve(index.feats, name) do
      {:ok, id} ->
        {choice, issues} = resolve_choice(ruleset, index, id, qualifier, level, issues)
        {feats ++ [{id, choice}], issues}

      :error ->
        {feats, issues ++ [{:unknown_feat, level, item}]}

      {:ambiguous, ids} ->
        {feats, issues ++ [{:ambiguous_feat, level, item, ids}]}
    end
  end

  # `Spell Focus (Evocation)` — имя фита и то, с чем он взят. Раньше уточнение
  # некуда было положить, и оно честно выбрасывалось с оговоркой; теперь у пика
  # есть второе поле, и школа доезжает до билда целиком.
  #
  # Три исхода, и они не одно и то же:
  #
  #   * значение нашлось → кладём, оговорки нет;
  #   * справочника у домена нет (`weapon` — оружие мы не моделируем и не будем
  #     до армори) → прежняя оговорка `{:feat_qualifier_dropped, …}`;
  #   * справочник есть, а значение в нём не нашлось → это НЕ то же самое:
  #     игрок написал школу, которой мы не знаем, и молча приравнять её
  #     к «мы такое не храним» значило бы спрятать опечатку.
  defp resolve_choice(_ruleset, _index, _id, nil, _level, issues), do: {nil, issues}

  defp resolve_choice(ruleset, index, id, qualifier, level, issues) do
    domain = Rules.feat_choice_domain(id, ruleset)

    case domain && Map.get(index.choices, domain) do
      nil ->
        {nil, issues ++ [{:feat_qualifier_dropped, level, id, qualifier}]}

      values ->
        case resolve(values, qualifier) do
          {:ok, choice} -> {choice, issues}
          _not_found -> {nil, issues ++ [{:feat_choice_unknown, level, id, qualifier}]}
        end
    end
  end

  # `Weapon focus (longsword)` and `Skill focus: discipline` each name a feat and
  # a choice inside it. The feat resolves; the choice has nowhere to live in the
  # build, so it is reported rather than dropped — the same register as the
  # core's `{:not_modelled, {:feat_qualifier, …}}`.
  defp split_qualifier(item) do
    cond do
      match = Regex.run(~r/^(.+?)\s*[\(\[]\s*([^\)\]]+)[\)\]]\s*$/u, item) ->
        [_, name, qualifier] = match
        {String.trim(name), String.trim(qualifier)}

      match = Regex.run(~r/^(.+?)\s*[:—–]\s*(.+)$/u, item) ->
        [_, name, qualifier] = match
        {String.trim(name), String.trim(qualifier)}

      true ->
        {item, nil}
    end
  end

  defp openings(ruleset, build, level, {feat_id, _choice}) do
    ruleset
    |> Feats.open_slots(build, level)
    |> Enum.count(&FeatSlots.accepts?(ruleset, &1, feat_id))
  end

  defp place_feat({build, issues}, {feat_id, choice}, ruleset, level) do
    cond do
      feat_id in Build.granted_feats_at(build, ruleset, level) ->
        {build, issues ++ [{:feat_granted_here, level, feat_id}]}

      already_owned?(build, ruleset, level, feat_id, choice) ->
        {build, issues ++ [{:feat_already_owned, level, feat_id}]}

      slot = Feats.best_slot(ruleset, build, level, feat_id) ->
        {Build.put_feat(build, level, slot.id, feat_id, choice), issues}

      true ->
        {build, issues ++ [{:feat_no_slot, level, feat_id}]}
    end
  end

  # ⚠️ Одного `feats_owned` мало с тех пор, как фиты стали повторяемыми:
  # второй `Epic toughness` и `Spell focus` в другой школе — законные пики,
  # а по членству в множестве они неотличимы от дубликата.
  #
  # Поэтому вопрос задаётся дважды, и второй раз — ядру, причём именно
  # `FeatChoices.reasons/3`, а не `validate_feat_pick/3`: первое говорит только
  # про повторяемость и параметр, второе добавило бы проверку требований,
  # которую импорт сознательно не делает (иначе отчёт утонет в шуме — см.
  # AGENT_QUEUE, долг 3).
  defp already_owned?(build, ruleset, level, feat_id, choice) do
    MapSet.member?(Build.feats_owned(build, ruleset, level), feat_id) and
      FeatChoices.reasons(build, %{feat: feat_id, choice: choice, at: level}, ruleset) != []
  end

  defp with_increase(%Build{} = build, nil, _level), do: build

  defp with_increase(%Build{} = build, ability, level),
    do: %Build{build | ability_increases: Map.put(build.ability_increases, level, ability)}

  # `+1 STR`, `+1 to Str`, `STR +1`, and the same bump written at the end of a
  # feat. Returns the ability and whatever else the item said.
  defp increase_in(item, index) do
    cond do
      match = Regex.run(~r/^\+\s*1?\s*(?:to\s+)?(\p{L}{3})\b\s*(.*)$/u, item) ->
        increase(match, index, 0, 1)

      match = Regex.run(~r/^(\p{L}{3})\s*\+\s*1\b\s*(.*)$/u, item) ->
        increase(match, index, 0, 1)

      match = Regex.run(~r/^(.*?\S)\s*\+\s*1\s*(?:to\s+)?(\p{L}{3})\b\.?$/u, item) ->
        increase(match, index, 1, 0)

      true ->
        nil
    end
  end

  defp increase([_whole | groups], index, ability_at, rest_at) do
    word = groups |> Enum.at(ability_at, "") |> String.downcase()

    case word in @ability_words && resolve(index.abilities, word) do
      {:ok, id} -> {id, groups |> Enum.at(rest_at, "") |> String.trim()}
      _ -> nil
    end
  end

  defp with_skills(%Build{} = build, scan, issues) do
    level = length(build.levels)
    {inside, outside} = Enum.split_with(scan.skill_guide, fn {at, _ranks} -> at <= level end)

    issues =
      issues
      |> maybe(outside != [], {:skill_ranks_past_ladder, length(outside)})
      |> maybe(
        scan.source_skills != [] and scan.skill_guide == %{},
        {:skills_not_placed, length(scan.source_skills)}
      )
      |> maybe(scan.loose_feats != [], {:feats_without_levels, length(scan.loose_feats)})

    {%Build{build | skills: Map.new(inside)}, issues}
  end

  defp maybe(issues, false, _issue), do: issues
  defp maybe(issues, true, issue), do: issues ++ [issue]

  # What the two halves of the block say about each other. The header states
  # totals per class and the ladder states order; when they disagree, one of them
  # was edited by hand and only the player can say which.
  defp crosschecks(build, scan, ruleset) do
    actual = Build.class_levels(build)
    used = build.levels |> Enum.uniq() |> length()
    limit = ruleset.max_classes

    mismatches =
      for %{class: class, text: text, levels: declared} <- scan.declared,
          class != nil,
          scan.levels != %{},
          Map.get(actual, class, 0) != declared,
          do: {:split_mismatch, text, declared, Map.get(actual, class, 0)}

    unresolved =
      for %{class: nil, text: text} <- scan.declared, do: {:unknown_class_in_header, text}

    []
    |> maybe(scan.levels == %{} and scan.declared != [], {:no_leveling_guide})
    |> maybe(limit != nil and used > limit, {:too_many_classes, used, limit})
    |> Enum.concat(mismatches)
    |> Enum.concat(unresolved)
    |> Enum.concat(illegal_levels(build, ruleset))
  end

  # Формы отказа, которые зависят ТОЛЬКО от лестницы, — и потому проверяемы
  # на импорте.
  #
  # ⚠️ Список белый, а не чёрный, и это принципиально. Импорт по контракту
  # переносит не всё: блок `SKILLS` он не читает вовсе, а фит может не лечь
  # в слот — на каждый такой случай у него уже есть своя оговорка. Включив
  # `requires_feat` или `requires_skill_ranks`, отчёт получил бы по шесть-семь
  # отказов на каждый вход в престиж-класс, и все они были бы про то, чего
  # импорт не дочитал, а не про билд. Отчёт, который научились пролистывать,
  # не работает вовсе.
  #
  # Белый список заодно и есть фильтр против `{:missing_data, …}`: под ванильным
  # ruleset'ом нет overrides, и `max_classes` дал бы 41 одинаковую строку.
  #
  # `{:requires_character_level, …}` ВКЛЮЧЁН волной 5 — раньше был исключён,
  # потому что `Rules.LevelUp.prestige_pre_epic/4` считал уровни престижа по
  # билду ЦЕЛИКОМ, а уровень персонажа — по моменту, и на готовом билде эти
  # две половины не сходились: у «Воин 10 / Мастер оружия 31» на 11-м уровне
  # видно было 31 уровень престижа при персонаже 10-го, и ядро отказывало
  # легальному билду (форма «Мастер оружия Сагровик» с вики). Волна 4 починила
  # обе половины считать от одного момента (см. комментарий у самой функции
  # в `level_up.ex` и тест-пин в `level_up_test.exs`) — на этой же лестнице
  # отказа больше нет, а лестница на уровень раньше (по-настоящему нелегальная)
  # по-прежнему ловится, и ровно на том уровне, где правило нарушено.
  # Проверено на всех восьми готовых лестницах вики (`WikiBuildPage`), не
  # только на «Сагровике» — см. `describe "нелегальная лестница"` ниже.
  #
  # `{:requires_race, …}` и `{:requires_alignment, …}` ВКЛЮЧЕНЫ волной 6.
  # Раса и мировоззрение — вторая строка канонического формата
  # («Раса, Мировоззрение»), читается так же надёжно, как и сама лестница:
  # критерий тот же, что уже применён к `requires_character_level` — форма
  # зависит только от того, что импорт читает прочно, а не от `SKILLS` или
  # размещения фита по слоту.
  #
  # ⚠️ Поправка к предпосылке волны 5. Та же фраза стояла и в `level_up.ex`
  # («shard layer already provides them for Purple Dragon Knight and Harper
  # Scout»); ✅ там она **исправлена 10.08.2026** (долг §7), так что чинить
  # её больше не надо — здесь остаётся сам замер. Проверено по данным напрямую:
  # структура
  # `requirements` есть у ВСЕХ 12 престиж-классов (`arcane_archer`, `assassin`,
  # `blackguard`, `champion_of_torm`, `dwarven_defender`, `harper_scout`,
  # `pale_master`, `purple_dragon_knight`, `red_dragon_disciple`,
  # `shadowdancer`, `shifter`, `weapon_master`) — ключи `alignment`,
  # `base_attack_bonus`, `feats`, `skills`, `race`, `spellcasting`/
  # `arcane_spellcasting`. Сырой `unparsed`-остаток висит только у
  # `arcane_archer` (неоднозначность расы и вида «владения оружием» в
  # требовании — TODO админам) и `red_dragon_disciple` (класс-донор каста).
  # Значит правка работает на всех двенадцати, а не на двух, как было
  # записано раньше.
  #
  # Расовое требование (`requirements.race`) при этом есть только у ДВУХ:
  # `arcane_archer` (`[:elf, :half_elf]`) и `dwarven_defender` (`[:dwarf]`).
  # Требование мировоззрения приходит ДВУМЯ независимыми путями ядра с
  # одинаковой формой причины на выходе — `requirements.alignment` (assassin,
  # blackguard, champion_of_torm, dwarven_defender, harper_scout, pale_master)
  # и отдельное поле `alignment_restriction`, которое `level_up.ex` проверяет
  # своей веткой (тот же механизм, что несёт ограничение Monk/Barbarian,
  # CLAUDE.md §9). ⚠️ У `purple_dragon_knight` Сиала целиком заменила
  # `requirements` своим блоком (BAB +4 и четыре навыка), и в новой карте
  # ключа `alignment` нет — `class.requirements.alignment == nil` в рантайме
  # (проверено). Но шард отдельно объявляет `alignment_restriction: "any
  # lawful"` («Характер: Любой Законопослушный» на странице класса), и он
  # проверяется ВТОРЫМ, независимым путём — на выходе та же форма
  # `{:requires_alignment, %{require: ["lawful"]}}` (проверено прямым вызовом
  # `Rules.validate_level_up/3`). Белому списку это ничем не грозит: он
  # фильтрует по ФОРМЕ причины, а не по тому, из какого поля ядра она взялась.
  #
  # `{:requires_class_level, …}` и `{:max_character_level, …}` ВКЛЮЧЕНЫ волной 8
  # (AGENT_QUEUE.md §7, «Белый список импорта можно расширять дальше») — и это
  # редкий случай, когда включение формы измеримо НИЧЕГО не меняет на живых
  # данных, а не «наверное безопасно».
  #
  # `class_levels` («нужен уровень другого класса») стоит только у трёх
  # классов (`pale_master`, `arcane_archer`, `red_dragon_disciple`,
  # `priv/rules/vanilla/class_requirements.json`), и на всех трёх — ВНУТРИ
  # дизъюнкции (`any_of: [{class_levels: {bard: N}}, {class_levels: {sorcerer:
  # N}}, …]` — Pale Master принимает Барда, Соркерера ИЛИ Мага). `Prereqs`
  # разбирает дизъюнкцию в ОДНУ причину `{:requires_any_of, [[...], [...]]}`
  # и не разворачивает её ветки наружу («`any_of` — одна дизъюнкция» в
  # `prereqs.ex`), так что голая форма `{:requires_class_level, class, n}`
  # не всплывает первым элементом кортежа нигде в данных — только внутри
  # списков `requires_any_of`. Проверено вызовом на всех трёх классов и на
  # живом билде «Fighter 1 / Red dragon disciple 1» без единого уровня
  # Барда/Соркерера: `Rules.illegal_class_levels/2` отдаёт ДВЕ претензии
  # (`{:requires_skill_ranks, :lore, 8}`, по праву исключена, и
  # `{:requires_any_of, [[{:requires_class_level, :bard, 1}], [{:requires_class_level,
  # :sorcerer, 1}]]}`). Волна 8 включила саму форму `:requires_class_level`
  # в список, но этим ложную легальность у этих трёх классов НЕ закрыла —
  # голова претензии здесь `:requires_any_of`, а её тогда в списке не было.
  # Задача осталась отдельным пунктом AGENT_QUEUE.md §7 («`Builder.Import`
  # не ловит „нужен уровень другого класса“»).
  #
  # ✅ ЗАКРЫТО 17.08.2026, и `:requires_any_of` В ЭТОТ МАССИВ НЕ ДОБАВЛЕН —
  # намеренно. Членство головы здесь означает «форма читаема ВСЕГДА»,
  # а дизъюнкция читаема только УСЛОВНО, если читаема каждая её ветка —
  # ветка сама может нести `skill_ranks` или `feats`, которых импорт не
  # переносит. Условие проверяет `ladder_reason?/1` под `illegal_levels/2`
  # ниже: причина, названная `:requires_any_of`, печатается, только если
  # КАЖДАЯ причина внутри КАЖДОЙ ветки сама читаема — рекурсивно, потому что
  # ветка — целый список причин (конъюнкция), а не одна причина. У всех
  # трёх классов ветка — это ровно один `{:requires_class_level, class, n}`
  # (проверено обходом `class_requirements.json` на обоих ruleset'ах,
  # включая сиальскую замену блока целиком у `arcane_archer` — она повторяет
  # ту же дизъюнкцию слово в слово, см. `siala_41/classes.json`), то есть
  # ветка читаема целиком и претензия доезжает до игрока.
  #
  # 🔴 Рекурсия — не перестраховка, а суть задачи, и направление проверки
  # здесь ОБРАТНОЕ привычному: обычно лучше сказать лишнее, чем промолчать,
  # а здесь лишнее — это обвинить билд в нарушении, которого, возможно, нет.
  # День, когда дизъюнкция обзаведётся веткой из `skill_ranks` или `feats`,
  # проверка одной только ГОЛОВЫ `:requires_any_of` начала бы обвинять
  # ложно: игрок вставил чужой билд и не может понять, чего от него хотят.
  # Билд мог закрыть альтернативу как раз той половиной, которую импорт не
  # читает (блок `SKILLS`, размещение фита по слоту), и отказ по прочитанной
  # половине был бы обвинением без права на ответ. Поэтому непрочитанная
  # ветка гасит ВСЮ дизъюнкцию целиком, а не только себя.
  #
  # Печать не потребовала новой фразы: `issue_text({:illegal_level, …})` уже
  # зовёт `Labels.reason/2`, а она умеет `:requires_any_of` тем же текстом
  # («нужен Bard 1 или нужен Sorcerer 1 или нужен Wizard 1»), что видит
  # игрок у конструктора и экрана просмотра — `Builder.Labels.@illegal_reasons`
  # несёт эту форму давно. Заводить вторую формулировку для одного и того же
  # факта значило бы то самое расхождение, которого этот файл сознательно
  # избегает и в других местах (`save_prereq_exceptions/1` в `labels.ex`) —
  # один факт называется одной фразой, а не выбором между двумя на глаз.
  #
  # `max_character_level` («взять можно НЕ ПОЗЖЕ уровня N») сегодня не стоит
  # ни у одного класса вовсе — только у фитов (`vanilla/feats.json`,
  # `siala_41/generated/feats.json`); поиск по `requirements` обоих ruleset'ов
  # пуст, что созвучно и `level_up.ex`: «nothing in a class's requirements
  # asks for a character level today». Но `Prereqs` — один интерпретатор для
  # блока класса и блока фита (его же moduledoc), и ключ уже читается для
  # класса ровно как `class_levels`, если он там появится, — просто пока
  # ни один class_requirements.json/classes.json его не пишет. Включение —
  # не починка дыры, а закрытая заранее дыра под будущую запись; механизм
  # проверен синтетическим классом (`ImportTest`, «нелегальная лестница») —
  # обе формы печатаются, а `requires_feat`/`requires_skill_ranks` на том же
  # билде по-прежнему нет.
  #
  # `requires_bab` НЕ включён — попутная проверка, а не отдельное решение по
  # нему. В отличие от `class_levels`, голая форма (не в `any_of`) стоит сразу
  # у ШЕСТИ престиж-классов (`arcane_archer` 6, `blackguard` 6,
  # `champion_of_torm` 7, `dwarven_defender` 7, `purple_dragon_knight` 4,
  # `weapon_master` 5) — включение изменило бы поведение массово, не «нулём»,
  # как оба пункта выше. На всех восьми готовых лестницах вики
  # (`WikiBuildPage`) ложных срабатываний не нашлось, но ни одна из восьми не
  # похожа на тот край, которого опасается сам долг (Monk с
  # `bab_progression: "high"`, добавочные атаки Arcane Archer) — это честное
  # «не проверено», а не довод «безопасно», поэтому форма остаётся снаружи.
  #
  # По-прежнему не включены `requires_feat` и `requires_skill_ranks` — импорт
  # не читает блок `SKILLS`, а фит может не лечь в слот, так что на каждый
  # вход в престиж посыпалось бы по шесть-семь отказов не про билд, а про
  # недочитанный импортом текст (см. предупреждение в начале списка выше).
  @ladder_reasons [
    :class_level_cap,
    :requires_character_level,
    :requires_race,
    :requires_alignment,
    :requires_class_level,
    :max_character_level
  ]

  # Лестница проигрывается заново, уровень за уровнем — но не здесь. Волна 7
  # (баг 1.3) подняла саму прогонку в ядро (`Rules.illegal_class_levels/2`):
  # конструктору нужен ТОТ ЖЕ вопрос — «что в этой лестнице уже не выполняется,
  # если проверить билд, как он выглядит прямо сейчас» — только с другим
  # ответом на «какие формы стоит печатать» и без сжатия до одной строки на
  # класс (колонка прогрессии обязана отметить КАЖДЫЙ задетый уровень, а не
  # только самый ранний). Одна прогонка на двоих значит, что раздвоить два
  # прочтения одного вопроса больше нечем — белый список ниже это ЕДИНСТВЕННОЕ,
  # что здесь осталось местного.
  #
  # `level_cap` и `max_classes` сюда НЕ входят не потому, что они шумные,
  # а потому что импорт ловит их своими проверками (`{:level_over_cap, …}`,
  # `{:too_many_classes, …}`) и словами точнее. Дублировать значило бы
  # напечатать одну претензию дважды.
  defp illegal_levels(%Build{} = build, ruleset) do
    for {level, class, reason} <- Rules.illegal_class_levels(build, ruleset),
        ladder_reason?(reason) do
      {:illegal_level, level, class, reason}
    end
    # Одна претензия — одна строка. Потолок уровней класса — свойство билда
    # целиком, поэтому ядро повторяет его на КАЖДОМ уровне этого класса:
    # у Мастера оружия 32-го уровня это 32 одинаковые строки. Называем самый
    # ранний уровень — тот, с которого билд перестал быть легальным.
    |> Enum.uniq_by(fn {_tag, _level, class, reason} -> {class, reason} end)
  end

  # Читаема ли причина — то есть достойна печати. Плоская причина проверяется
  # членством головы в `@ladder_reasons`, как и раньше; дизъюнкция —
  # рекурсивно по каждой причине каждой ветки (см. разбор у самого массива
  # выше). Ветка — это конъюнкция целиком, а не одна причина, поэтому нельзя
  # спросить только про голову `:requires_any_of`: она ничего не говорит
  # о том, что лежит внутри.
  #
  # Рекурсия — не декорация: ветка сама может оказаться другой дизъюнкцией
  # (`Prereqs` `any_of` внутри `any_of` не запрещает), и предикат обязан
  # быть готов к структуре, которой в сегодняшних данных нет ни разу, —
  # ровно так же, как сам список уже несёт формы, ничего сегодня не меняющие
  # (`max_character_level`, см. комментарий у списка).
  defp ladder_reason?({:requires_any_of, branches}),
    do: Enum.all?(branches, fn branch -> Enum.all?(branch, &ladder_reason?/1) end)

  defp ladder_reason?(reason) when is_tuple(reason), do: elem(reason, 0) in @ladder_reasons
  defp ladder_reason?(_not_a_tuple), do: false

  defp read(build, scan) do
    feats = build.feats |> Map.values() |> Enum.map(&map_size/1) |> Enum.sum()

    ranks =
      for {_level, bought} <- build.skills, {_id, count} <- bought, reduce: 0 do
        sum -> sum + count
      end

    %{
      race: build.race,
      alignment: build.alignment,
      levels: length(build.levels),
      feats: feats,
      increases: map_size(build.ability_increases),
      skill_ranks: ranks,
      abilities?: scan.printed != %{},
      anything?:
        build.levels != [] or build.race != nil or build.alignment != nil or scan.printed != %{}
    }
  end

  # ------------------------------------------------------------- name lookup --

  # One index per dictionary, built from the ruleset itself. A key two entries
  # answer to refuses instead of picking one: guessing which of two feats the
  # player meant is the same sin as guessing a number.
  defp indexes(ruleset) do
    %{
      classes: name_index(ruleset, ruleset.classes),
      races: race_index(ruleset),
      feats: name_index(ruleset, ruleset.feats, &acronym/1),
      skills: name_index(ruleset, ruleset.skills),
      abilities: Map.new(ruleset.abilities, &{Atom.to_string(&1), [&1]}),
      choices: choice_index(ruleset),
      class_short: short_index(ruleset),
      class_names:
        for {id, class} <- ruleset.classes do
          %{id: id, key: norm(class.name || ""), name: class.name || Atom.to_string(id)}
        end
    }
  end

  # Значения, с которыми берутся фиты: школы магии, расы-враги, типы урона,
  # навыки. Домен без справочника (`weapon`, до задачи 3.5) даёт пустой индекс:
  # сопоставлять не с чем, и это честный ответ, а не пропуск.
  #
  # ⚠️ Сама индексация переехала в `BuildCalculatorWeb.Builder.ChoiceIndex`
  # (26.08.2026, задача 3.111) — вторым читателем стал `GameLogImport`, а
  # второй implementation одной и той же выборки был бы ровно той ошибкой,
  # от которой уже спасает `FeatListTokenizer`. Поведение не изменилось —
  # это чистое извлечение, регрессия — тесты этого модуля.
  defp choice_index(ruleset), do: ChoiceIndex.build(ruleset)

  defp name_index(ruleset, dictionary, extra \\ fn _name -> nil end) do
    Enum.reduce(dictionary, %{}, fn {id, entry}, acc ->
      name = Map.get(entry, :name)

      [name, Map.get(entry, :ru), name && Map.get(ruleset.name_map, name), extra.(name)]
      |> Enum.reduce(acc, &put_key(&2, &1, id))
    end)
  end

  defp race_index(ruleset) do
    Enum.reduce(ruleset.races, %{}, fn {id, race}, acc ->
      shard = Map.get(race, :siala) || %{}

      [Map.get(race, :name), Map.get(race, :ru), Map.get(shard, "en")]
      |> Enum.concat(Map.get(shard, "ru_spellings") || [])
      |> Enum.reduce(acc, &put_key(&2, &1, id))
    end)
  end

  defp short_index(ruleset) do
    Enum.reduce(ruleset.classes, %{}, fn {id, _class}, acc ->
      put_key(acc, Labels.class_short(ruleset, id), id)
    end)
  end

  defp put_key(index, nil, _id), do: index

  defp put_key(index, name, id) do
    case norm(name) do
      "" -> index
      key -> Map.update(index, key, [id], &Enum.uniq([id | &1]))
    end
  end

  # `Improved two-weapon fighting` → `itwf`, the way the community writes it.
  # Derived, never a table: a feat added to the data gets its shorthand for free,
  # and a shorthand two feats share is refused as ambiguous instead of guessed.
  defp acronym(nil), do: nil

  defp acronym(name) do
    case String.split(name, ~r/[\s\-]+/u, trim: true) do
      [_single] -> nil
      words -> words |> Enum.map_join(&String.first/1) |> String.downcase()
    end
  end

  defp resolve(index, text) do
    case Map.get(index, norm(text), []) do
      [id] -> {:ok, id}
      [] -> :error
      many -> {:ambiguous, many}
    end
  end

  # Classes get three chances more than everything else, because the ladder is
  # where shorthand actually gets written. In order of how much they claim:
  # `WM`, `DD`, `CoT` off `Labels.class_short/2`; `Sorc` or `Dwarven def` off a
  # unique prefix; and finally `Ftr`, `Bbn`, `Rgr` — the community's consonant
  # shorthand, which no rule derives — through the same subsequence matcher the
  # feat search uses. Only the last tier returns `{:guess, id}`, and only it is
  # reported to the player, because only it could plausibly be wrong.
  defp resolve_class(index, text) do
    key = norm(text)

    with :error <- resolve(index.classes, text),
         :error <- resolve(index.class_short, key),
         :error <- prefix_class(index, key) do
      fuzzy_class(index, text)
    end
  end

  defp prefix_class(_index, key) when byte_size(key) < 3, do: :error

  defp prefix_class(index, key) do
    case Enum.filter(index.class_names, &String.starts_with?(&1.key, key)) do
      [class] -> {:ok, class.id}
      [] -> :error
      many -> {:ambiguous, Enum.map(many, & &1.id)}
    end
  end

  # Only for something short enough to be an abbreviation, and only when one
  # class scores strictly better than every other: `Pal` matches Paladin and
  # Pale master equally well, and picking either would be a coin toss dressed
  # up as a reading.
  defp fuzzy_class(index, text) do
    trimmed = String.trim(text)

    if String.length(trimmed) in 2..24 do
      index.class_names
      |> Enum.flat_map(fn class ->
        case Fuzzy.match(trimmed, class.name) do
          nil -> []
          match -> [{match.score, class.id}]
        end
      end)
      |> Enum.sort_by(fn {score, id} -> {-score, Atom.to_string(id)} end)
      |> best_class()
    else
      :error
    end
  end

  defp best_class([]), do: :error
  defp best_class([{_score, id}]), do: {:guess, id}

  defp best_class([{score, id}, {runner_up, other} | _]) do
    if score > runner_up, do: {:guess, id}, else: {:ambiguous, [id, other]}
  end

  defp norm(nil), do: ""

  defp norm(text) do
    text
    |> String.downcase()
    |> String.replace("ё", "е")
    |> String.replace(~r/[\s_\-–—.'’"`]+/u, "")
  end

  # ------------------------------------------------------------- the wording --

  @doc """
  One issue, in Russian.

  Same register as `Labels.gap/2`: what the reader could not do is said plainly
  and the source's own text is quoted, so the player can see whether it is their
  paste or our dictionary that came up short.
  """
  @spec issue_text(issue(), map()) :: String.t()
  def issue_text({:unknown_class, level, text}, _ruleset),
    do: "уровень #{level}: класс «#{text}» не распознан"

  def issue_text({:ambiguous_class, level, text, ids}, ruleset),
    do:
      "уровень #{level}: «#{text}» подходит нескольким классам (" <>
        Enum.map_join(ids, ", ", &Labels.class_name(ruleset, &1)) <>
        ") — выбирать за тебя не будем"

  def issue_text({:class_guessed, level, text, class}, ruleset),
    do:
      "уровень #{level}: «#{text}» прочитано как #{Labels.class_name(ruleset, class)} " <>
        "по сокращению — проверь, так ли это"

  def issue_text({:ladder_stopped, kept}, _ruleset),
    do:
      "лестница оборвана на #{kept} уровнях: порядок классов после непрочитанной строки " <>
        "додумывать нельзя — от него зависят BAB и спасы после 20-го"

  def issue_text({:level_gap, expected, found}, _ruleset),
    do: "в лестнице нет уровня #{expected} (следующая строка — #{found}), дальше не читаем"

  def issue_text({:level_over_cap, level, cap}, _ruleset),
    do: "уровень #{level} выше капа #{cap} — обрезано"

  def issue_text({:unknown_class_in_header, text}, _ruleset),
    do: "в шапке класс «#{text}» не распознан"

  def issue_text({:no_leveling_guide}, _ruleset),
    do:
      "в тексте нет лестницы уровней (LEVELING GUIDE), а из шапки порядок классов " <>
        "не восстановить: она называет только сумму по каждому классу"

  def issue_text({:split_mismatch, text, declared, actual}, _ruleset),
    do: "шапка обещает #{text}(#{declared}), в лестнице набралось #{actual}"

  def issue_text({:too_many_classes, used, limit}, _ruleset),
    do: "в билде #{used} классов при лимите #{limit} — на Сиале такой билд не собрать"

  def issue_text({:unknown_race, text}, _ruleset), do: "раса «#{text}» не распознана"

  def issue_text({:ambiguous_race, text, _ids}, _ruleset),
    do: "раса «#{text}» подходит сразу нескольким — не выбираем"

  def issue_text({:unknown_alignment, text}, _ruleset),
    do: "мировоззрение «#{text}» не распознано"

  def issue_text({:unknown_feat, level, text}, _ruleset),
    do: "уровень #{level}: фита «#{text}» нет в справочнике"

  def issue_text({:ambiguous_feat, level, text, ids}, ruleset),
    do:
      "уровень #{level}: «#{text}» подходит нескольким фитам (" <>
        Enum.map_join(ids, ", ", &Labels.feat_name(ruleset, &1)) <> ")"

  # ⚠️ Формулировка изменилась вместе с механикой: школы магии, расы-враги, типы
  # урона и навыки теперь ХРАНЯТСЯ, и обещать обратное было бы неправдой.
  # Осталось ровно оружие — справочника нет и не будет до армори.
  def issue_text({:feat_qualifier_dropped, level, feat, qualifier}, ruleset),
    do:
      "уровень #{level}: #{Labels.feat_name(ruleset, feat)} взят, но уточнение " <>
        "«#{qualifier}» мы не храним — справочника под него нет"

  # Формулировку самого отказа даёт `Labels.reason/2` — тот же текст, который
  # игрок видит в конструкторе. Своя копия разошлась бы с ней.
  def issue_text({:illegal_level, level, class, reason}, ruleset),
    do:
      "уровень #{level}: #{Labels.class_name(ruleset, class)} здесь взять нельзя — " <>
        Labels.reason(reason, ruleset)

  def issue_text({:feat_choice_unknown, level, feat, qualifier}, ruleset),
    do:
      "уровень #{level}: #{Labels.feat_name(ruleset, feat)} взят без выбора — " <>
        "«#{qualifier}» в справочнике не нашлось"

  def issue_text({:feat_no_slot, level, feat}, ruleset),
    do:
      "уровень #{level}: #{Labels.feat_name(ruleset, feat)} некуда положить — " <>
        "подходящего свободного слота на этом уровне нет"

  def issue_text({:feat_granted_here, level, feat}, ruleset),
    do:
      "уровень #{level}: #{Labels.feat_name(ruleset, feat)} класс выдаёт сам — " <>
        "слот остался свободным"

  def issue_text({:feat_already_owned, level, feat}, ruleset),
    do: "уровень #{level}: #{Labels.feat_name(ruleset, feat)} у персонажа уже есть — пропущен"

  def issue_text({:unknown_skill, level, text}, _ruleset),
    do: "уровень #{level}: навык «#{text}» не распознан"

  def issue_text({:ambiguous_skill, level, text, _ids}, _ruleset),
    do: "уровень #{level}: навык «#{text}» подходит нескольким — не выбираем"

  def issue_text({:skills_not_placed, count}, _ruleset),
    do:
      "навыки (#{count}) в билд не перенесены: блок SKILLS даёт только итог, а ранг стоит " <>
        "и упирается в потолок того уровня, на котором куплен"

  def issue_text({:skill_ranks_past_ladder, count}, _ruleset),
    do: "ранги навыков на #{count} уровнях выше прочитанной лестницы отброшены"

  def issue_text({:feats_without_levels, count}, _ruleset),
    do: "фиты (#{count}) перечислены списком без уровней — разложить их по слотам нечем"

  def issue_text({:abilities_missing}, _ruleset),
    do: "характеристик в тексте нет — поставлен минимум поинт-бая"

  def issue_text({:abilities_without_race}, _ruleset),
    do:
      "раса не распознана, поэтому расовые модификаторы из характеристик не вычтены — " <>
        "проверь стартовые числа"

  def issue_text({:ability_off_point_buy, ability, score}, _ruleset),
    do:
      "#{Labels.ability(ability)} #{score} после вычета расы вне шкалы поинт-бая — " <>
        "перенесено как есть"

  def issue_text({:text_clipped, bytes}, _ruleset),
    do: "текст обрезан на #{bytes} байтах — дальше не читали"

  def issue_text({:ignored_line, number, text}, _ruleset),
    do: "строка #{number}: «#{ellipsis(text)}» — не поняли, что это"

  def issue_text(other, _ruleset), do: inspect(other)

  defp ellipsis(text) do
    if String.length(text) > 60, do: String.slice(text, 0, 57) <> "…", else: text
  end

  @doc """
  Short Russian name of an issue family, for grouping the list.

  The move `Labels.gap_kind/1` makes, for the same reason: a flat list of thirty
  notes is read by nobody, and the three groups answer different questions —
  what the dictionary did not know, what the format cannot carry, and what the
  source contradicts about itself.
  """
  @spec issue_kind(issue()) :: String.t()
  def issue_kind({:unknown_class, _level, _text}), do: "Не распознано"
  def issue_kind({:ambiguous_class, _level, _text, _ids}), do: "Не распознано"
  def issue_kind({:unknown_class_in_header, _text}), do: "Не распознано"
  def issue_kind({:unknown_race, _text}), do: "Не распознано"
  def issue_kind({:ambiguous_race, _text, _ids}), do: "Не распознано"
  def issue_kind({:unknown_alignment, _text}), do: "Не распознано"
  def issue_kind({:unknown_feat, _level, _text}), do: "Не распознано"
  def issue_kind({:ambiguous_feat, _level, _text, _ids}), do: "Не распознано"
  def issue_kind({:unknown_skill, _level, _text}), do: "Не распознано"

  # Опечатка в школе — это «не распознано», а не «не перенесено»: строку писал
  # человек, и разница между «мы такого не знаем» и «мы такое не храним»
  # для него — разница между «поправь» и «ничего не поделать».
  def issue_kind({:feat_choice_unknown, _level, _feat, _text}), do: "Не распознано"
  def issue_kind({:ambiguous_skill, _level, _text, _ids}), do: "Не распознано"

  # Its own group, and not out of tidiness: «не нашли такой фит» is a question
  # about our dictionary, «не поняли, что это за строка» is a question about the
  # paste. Mixed together, the prose lines bury the misses that matter.
  def issue_kind({:ignored_line, _number, _text}), do: "Пропущенные строки"

  # A guess is neither a miss nor a loss: it is a reading the player has to
  # confirm, and it belongs in the group they are most likely to actually read.
  def issue_kind({:class_guessed, _level, _text, _class}), do: "Прочитано с допущением"

  # Своя группа: остальные «спорит с собой» — про то, что в тексте одно место
  # противоречит другому. Здесь текст внутренне непротиворечив, а спорит он
  # с правилами шарда, и починить это можно только правкой билда.
  def issue_kind({:illegal_level, _level, _class, _reason}), do: "Нарушает правила"

  def issue_kind({:split_mismatch, _text, _declared, _actual}), do: "Источник спорит с собой"
  def issue_kind({:too_many_classes, _used, _limit}), do: "Источник спорит с собой"
  def issue_kind({:ability_off_point_buy, _ability, _score}), do: "Источник спорит с собой"

  def issue_kind(_other), do: "Не перенесено"

  @doc """
  Every issue shape this module can produce, filled with sample values.

  A guard for the tests, in the spirit of `labels_test.exs`: an issue nobody
  worded renders through `inspect/1` and the interface shows a player a tuple.
  The list is the contract — a constructor added above has to be added here too,
  and the test fails until it has Russian wording.
  """
  @spec issue_forms() :: [issue()]
  def issue_forms do
    [
      {:unknown_class, 5, "Ftr"},
      {:ambiguous_class, 5, "Pal", [:paladin, :pale_master]},
      {:class_guessed, 2, "Ftr", :fighter},
      {:ladder_stopped, 4},
      {:level_gap, 5, 7},
      {:level_over_cap, 42, 41},
      {:unknown_class_in_header, "Ftr"},
      {:no_leveling_guide},
      {:split_mismatch, "Fighter", 10, 9},
      {:too_many_classes, 5, 4},
      {:unknown_race, "Полурослик"},
      {:ambiguous_race, "Эльф", [:elf, :half_elf]},
      {:unknown_alignment, "Хаотично-добрый"},
      {:unknown_feat, 3, "Неведомый фит"},
      {:ambiguous_feat, 3, "GC", [:great_cleave, :grand_cleave]},
      {:feat_qualifier_dropped, 3, :weapon_focus, "longsword"},
      {:feat_choice_unknown, 3, :spell_focus, "Evokation"},
      {:illegal_level, 32, :weapon_master, {:class_level_cap, :weapon_master, 31}},
      {:feat_no_slot, 3, :toughness},
      {:feat_granted_here, 1, :toughness},
      {:feat_already_owned, 6, :toughness},
      {:unknown_skill, 1, "Ремесло"},
      {:ambiguous_skill, 1, "Разоружение", [:disarm]},
      {:skills_not_placed, 12},
      {:skill_ranks_past_ladder, 3},
      {:feats_without_levels, 14},
      {:abilities_missing},
      {:abilities_without_race},
      {:ability_off_point_buy, :str, 20},
      {:text_clipped, @max_bytes},
      {:ignored_line, 12, "какая-то проза"}
    ]
  end

  # -------------------------------------------------------------- comparison --

  @doc """
  The source's own totals beside ours, row by row.

  The header of somebody else's block is their arithmetic — usually with gear
  and buffs in it — so it is never imported (see the moduledoc). Showing it next
  to what we computed is the useful half: a wild disagreement is how a player
  finds out the build was posted wearing its equipment, and a small one is how
  they find out that one of us is wrong.
  """
  @spec comparison(result(), map()) :: [
          %{label: String.t(), source: String.t(), ours: String.t()}
        ]
  def comparison(%{source: %{totals: totals}}, stats) do
    for total <- totals do
      %{label: total.key, source: total.value, ours: ours(total.id, stats)}
    end
  end

  defp ours(:hp, stats), do: number(stats.hp)
  defp ours(:skill_points, stats), do: number(stats.skill_points.earned)

  defp ours(:saves, stats),
    do: "#{signed(stats.fort)}/#{signed(stats.ref)}/#{signed(stats.will)}"

  defp ours(:bab, stats), do: number(stats.base_attack)
  defp ours(:ab, stats), do: signed(stats.attack_bonus)
  defp ours(:apr, stats), do: number(stats.attacks_per_round)
  defp ours(:ac, stats), do: "#{number(stats.ac_naked)} голым"

  defp number(nil), do: "?"
  defp number(value), do: Integer.to_string(value)

  defp signed(nil), do: "?"
  defp signed(value) when value >= 0, do: "+#{value}"
  defp signed(value), do: Integer.to_string(value)
end
