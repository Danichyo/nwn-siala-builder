defmodule BuildCalculatorWeb.Builder.Import.Header do
  @moduledoc """
  The block's header, wherever the post writes it: the title and the class
  split it states (`Dwarf-tank - Fighter(41)`), the race and the alignment
  (`Race: Dwarf`, `Гном (Dwarf), Lawful Good`, `Human Rogue 19 / Ftr 14 /
  WM 7`). The class split is kept for the cross-check and never becomes
  levels (see `BuildCalculatorWeb.Builder.Import`). The names themselves are
  resolved by `BuildCalculatorWeb.Builder.Import.Names`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  import BuildCalculatorWeb.Builder.Import.Names,
    only: [
      exact_race: 2,
      named_class: 2,
      race_value: 2,
      read_alignment: 2,
      resolve_class: 2,
      resolve_race: 2
    ]

  import BuildCalculatorWeb.Builder.Import.Scan, only: [add: 2]

  # ⚠️ Linear on any line (task 4.34). A line is not trimmed of the spaces in
  # it, and two shapes of pattern read a run of spaces again from every one of
  # its characters: a separator that may start with spaces, and a lazy name
  # followed by spaces. Both keep their meaning with the guards below.
  #
  #   * `(?:\G|(?<!\s))` before a separator that starts with spaces: it is
  #     looked for from the start of a run of spaces only (or where the search
  #     resumes). One that starts inside the run starts at the run's start as
  #     well, and that is where it is found first.
  #   * `(?:(?<!\s)|(?<=^.))` after a lazy name followed by spaces: the name
  #     does not end inside a run of spaces, unless it is one character long.
  #     Where the name ends one space later, what follows it reads the same.
  #   * `\s*(?:[\(\[]\s*)?` for `\s*[\(\[]?\s*`: the same text, without two
  #     ways of sharing the spaces around a missing bracket.
  defp name_and_level, do: ~RX/^(\D+?)(?:(?<!\s)|(?<=^.))\s*(?:[\(\[]\s*)?(\d{1,2})\s*[\)\]]?$/u
  defp race_then_alignment, do: ~RX/,|(?:\G|(?<!\s))\s+[-–—]\s+/u
  defp who_separators, do: ~RX/,|;|(?:\G|(?<!\s))\s+[-–—]\s+|(?:\G|(?<!\s))\s*:(?!\d)\s*/u
  defp split_separators, do: ~RX"(?:\G|(?<!\s))\s*[/,|]\s*"u

  # `Race: Dwarf` and `Alignment: Any non-lawful`, each on a line of its own —
  # how most hand-written posts give what the template writes as `<Race>,
  # <Alignment>`. Read before anything else can claim the line: as the paste's
  # first line it used to become the build's title, silently.
  #
  # `Race Elf` without the colon counts too, but only when what follows IS a
  # race or an alignment: `Alignment restriction: none` is not an alignment
  # line.
  def labelled_line(line, index) do
    case Regex.run(~RX/^(race|alignment|align)\s*[:=\-–—]\s*(.*)$/iu, line) do
      [_, label, value] ->
        {label_kind(label), String.trim(value)}

      _ ->
        with [_, label, value] <- Regex.run(~RX/^(race|alignment|align)\s+(\S.*)$/iu, line),
             kind = label_kind(label),
             true <- plain_label_value?(kind, String.trim(value), index) do
          {kind, String.trim(value)}
        else
          _ -> nil
        end
    end
  end

  defp label_kind(label), do: if(String.downcase(label) == "race", do: :race, else: :alignment)

  # `Race⇥Human⇥⇥Alignment⇥Lawful Neutral` — the race is what stands before
  # the other label.
  defp plain_label_value?(:race, value, index) do
    race = value |> String.split(~RX/\balign(?:ment)?\b/iu, parts: 2) |> hd() |> String.trim()
    match?({:ok, _}, resolve_race(index, race))
  end

  defp plain_label_value?(:alignment, value, index),
    do: match?({kind, _} when kind in [:ok, :restriction], read_alignment(index, value))

  # Only the first of each counts, as with the template's own line. A second
  # one saying the same is nothing new; saying something else, it is listed as
  # a line we did not use rather than a quiet overwrite.
  #
  # `Race: Halfling  Alignment: Any Evil` — both on one line — is read as both.
  #
  # `Race: Human / Alignment: …`, `Race⇥Human⇥Alignment⇥…`, `Race - Elf.
  # Subrace - Drow.` — what stands after the race is cut off (task 4.31), and
  # the race is read the way only a line that says `Race` earns
  # (`race_value/2`): a pick among races, a misspelt name.
  def labelled(scan, {:race, text}, number, line, index) do
    [race_part | alignment_part] =
      String.split(text, ~RX/\balign(?:ment)?\b\s*[:=\-–—]?/iu, parts: 2)

    race_text = race_part |> String.split(",", parts: 2) |> hd() |> String.trim()
    race = race_value(index, race_text)

    # `Race: Human - Lawful good -` — the race and the alignment on the label's
    # line, apart the way a line of their own parts them (task 4.31).
    {race, alignment_part} =
      case {race, who_parts(race_part, index)} do
        {:error, %{race: id, alignment: alignment}} when id != nil and alignment_part == [] ->
          {{:ok, id}, if(alignment, do: [elem(alignment, 1)], else: [])}

        _ ->
          {race, alignment_part}
      end

    scan =
      cond do
        race_text == "" -> add(scan, {:ignored_line, number, line})
        scan.race == nil and scan.race_options == nil -> claim_race(scan, race, race_text)
        race == {:ok, scan.race} -> scan
        true -> add(scan, {:ignored_line, number, line})
      end

    case alignment_part do
      [alignment_text] ->
        labelled(scan, {:alignment, String.trim(alignment_text)}, number, line, index)

      [] ->
        scan
    end
  end

  def labelled(scan, {:alignment, text}, number, line, index) do
    alignment = read_alignment(index, text)

    cond do
      text == "" -> add(scan, {:ignored_line, number, line})
      scan.alignment == nil -> claim_alignment(scan, alignment, text)
      alignment == {:ok, scan.alignment} -> scan
      true -> add(scan, {:ignored_line, number, line})
    end
  end

  # ------------------------------------------------------ race and alignment --

  # `Гном (Dwarf), Lawful Good`. Claimed only when at least one half resolves, so
  # a sentence of prose with a comma in it is not read as a character sheet.
  # A line of one name — `Human` above `Lawful Good`, the way hand-written posts
  # list them — is a race or an alignment when it is exactly that.
  #
  # `Halfling - Lawful Good` — a spaced dash parts the two as well as a comma.
  #
  # Task 4.31 read more of the shapes posts write the same thing in, each part
  # of the line one of a race, an alignment or its restriction, a class with
  # its level, or a bracket of what the race hands over:
  #
  #   * `Human: (Quick to Master)` — CBC's race line;
  #   * `Halfling:Any non Lawful`, `Non-Evil, Human`, `Lawful, Non-Evil, Human`;
  #   * `Human :Bard(23), Druid(15), Monk(2)`, `Barbarian16, Ranger21,
  #     Assassin3, Human` — a class split with the race in it;
  #   * `Elf Lawful Good`, `Human Any Chaotic`, `Human Rogue`, `Half elf of any
  #     non lawful alignment` — a race and what follows it, with no comma;
  #   * `Human*` — a footnote's mark.
  #
  # A part that is none of these leaves the line to the older, looser reading
  # below, which claims a race or an alignment beside prose.
  def who_line(scan, line, index) do
    case who_parts(line, index) do
      %{} = parts when scan.race == nil and scan.alignment == nil and scan.race_options == nil ->
        claim_parts(scan, parts)

      _ ->
        case line |> String.split(race_then_alignment(), parts: 2) |> Enum.map(&String.trim/1) do
          [race_text, alignment_text] -> pair_line(scan, race_text, alignment_text, index)
          [single] -> single_line(scan, single, index)
        end
    end
  end

  defp who_parts(line, index) do
    parts =
      line
      |> top_level_split(who_separators())
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(&who_part(&1, index))

    races = for {:race, id} <- parts, uniq: true, do: id
    alignment = one_alignment(for {:alignment, found} <- parts, do: found)

    if parts != [] and not Enum.member?(parts, :other) and length(races) <= 1 and
         alignment != :conflict and (races != [] or alignment != nil) and
         (races != [] or length(parts) > 1) do
      %{
        race: List.first(races),
        alignment: alignment,
        declared: for({:class, declared} <- parts, do: declared)
      }
    end
  end

  # `Lawful, Non-Evil, Human` — a restriction in two parts is one restriction;
  # two alignments that are not the same one are no reading at all.
  defp one_alignment([]), do: nil
  defp one_alignment([one]), do: one

  defp one_alignment(found) do
    case Enum.uniq(for {{:ok, id}, _text} <- found, do: id) do
      [] ->
        text = Enum.map_join(found, ", ", fn {_alignment, text} -> text end)
        {{:restriction, text}, text}

      [id] ->
        Enum.find(found, &match?({{:ok, ^id}, _}, &1))

      _ ->
        :conflict
    end
  end

  # One part of such a line — `[]` for a bracket of what the race hands over.
  defp who_part(part, index) do
    alignment = if String.length(part) > 1, do: read_alignment(index, part), else: :error

    cond do
      Regex.match?(~RX/^[\(\[].*[\)\]]$/u, part) ->
        []

      match?({:ok, _}, race = exact_race(index, part)) ->
        [{:race, elem(race, 1)}]

      match?({kind, _} when kind in [:ok, :restriction], alignment) ->
        [{:alignment, {alignment, part}}]

      declared = split_class(part, index) ->
        [{:class, declared}]

      prefixed = race_prefixed(part, index) ->
        prefixed

      true ->
        [:other]
    end
  end

  # `Elf Lawful Good`, `Human Rogue`, `Half elf of any non lawful alignment`:
  # the first word or two a race, the rest an alignment, its restriction or a
  # class's name.
  defp race_prefixed(part, index) do
    words = String.split(part, ~RX/\s+/u, trim: true)

    Enum.find_value([1, 2], fn taken ->
      {head, rest} = Enum.split(words, taken)
      rest = Enum.join(rest, " ")

      with true <- rest != "",
           {:ok, race} <- exact_race(index, Enum.join(head, " ")) do
        alignment = read_alignment(index, rest)

        cond do
          match?({kind, _} when kind in [:ok, :restriction], alignment) ->
            [{:race, race}, {:alignment, {alignment, rest}}]

          match?({:ok, _}, named_class(index, rest)) ->
            [{:race, race}]

          true ->
            nil
        end
      else
        _ -> nil
      end
    end)
  end

  # `Bard(23)`, `Barbarian16`, `Druid 15` — one class of a split, read for sure.
  defp split_class(part, index) do
    with [_, name, levels] <- Regex.run(name_and_level(), part),
         {:ok, class} <- named_class(index, String.trim(name)) do
      %{text: String.trim(name), title: nil, class: class, levels: String.to_integer(levels)}
    else
      _ -> nil
    end
  end

  defp claim_parts(scan, parts) do
    scan =
      case parts.race do
        nil -> scan
        race -> %{scan | race: race}
      end

    scan =
      case parts.alignment do
        nil -> scan
        {alignment, text} -> claim_alignment(scan, alignment, text)
      end

    if parts.declared != [] and scan.declared == [],
      do: %{scan | declared: parts.declared},
      else: scan
  end

  # A split at the separators that stand outside brackets: `Halfling:
  # (Fearless, Good Aim, Skill Affinity: Listen)` is two parts, not five. A
  # bracket runs from `(` or `[` to the first `)` or `]` after it, or to the end
  # of the text, and a separator that starts inside one splits nothing.
  #
  # ⚠️ By position (task 4.34). The brackets used to be masked one by one with
  # a marker — `\u0001`, a number, `\u0001` — split, and put back by searching
  # the parts for the markers: each step rewrote the whole text, so a line of
  # `()()()…` took seconds, and the search put brackets back in the wrong
  # place wherever the text itself spelled a marker: a paste with `\u0001` in
  # it, or `(1)0(Str)`, whose two markers and the `0` between them spell
  # marker №0. A separator never reaches into a bracket or out of one — none
  # of them holds a bracket's character — so the separators found in the text
  # as it stands, less the ones that start inside a bracket, are the ones the
  # masked text split at.
  defp top_level_split(text, separators) do
    brackets =
      for [{at, length}] <- Regex.scan(~RX/[\(\[][^\)\]]*(?:[\)\]]|$)/u, text, return: :index),
          do: {at, at + length}

    cuts =
      for [{at, length}] <- Regex.scan(separators, text, return: :index), do: {at, at + length}

    text
    |> cut_at(outside(cuts, brackets), 0, [])
    |> Enum.map(&String.trim/1)
  end

  # The cuts that start outside every bracket; both lists in the order of the text.
  defp outside([], _brackets), do: []
  defp outside(cuts, []), do: cuts

  defp outside([{from, _} | _] = cuts, [{_start, stop} | brackets]) when from >= stop,
    do: outside(cuts, brackets)

  defp outside([{from, _} = cut | cuts], [{start, _stop} | _] = brackets) when from < start,
    do: [cut | outside(cuts, brackets)]

  defp outside([_inside | cuts], brackets), do: outside(cuts, brackets)

  defp cut_at(text, [], from, parts),
    do: Enum.reverse([binary_part(text, from, byte_size(text) - from) | parts])

  defp cut_at(text, [{start, stop} | cuts], from, parts),
    do: cut_at(text, cuts, stop, [binary_part(text, from, start - from) | parts])

  defp pair_line(scan, race_text, alignment_text, index) do
    if scan.race || scan.alignment do
      nil
    else
      race = resolve_race(index, race_text)
      alignment = read_alignment(index, alignment_text)

      if match?({:ok, _}, race) or match?({:ok, _}, alignment) do
        scan
        |> claim_race(race, race_text)
        |> claim_alignment(alignment, alignment_text)
      end
    end
  end

  # ⚠️ One letter is not an alignment on a line of its own: `N` there is far
  # more likely a stray initial than True Neutral.
  defp single_line(scan, text, index) do
    race = if scan.race == nil, do: resolve_race(index, text), else: :error

    alignment =
      if scan.alignment == nil and String.length(text) > 1,
        do: read_alignment(index, text),
        else: :error

    cond do
      match?({:ok, _}, race) -> claim_race(scan, race, text)
      match?({:ok, _}, alignment) -> claim_alignment(scan, alignment, text)
      true -> nil
    end
  end

  defp claim_race(scan, {:ok, id}, _text), do: %{scan | race: id}
  defp claim_race(scan, {:ambiguous, ids}, text), do: add(scan, {:ambiguous_race, text, ids})
  defp claim_race(scan, :error, text), do: add(scan, {:unknown_race, text})

  defp claim_race(scan, {:guess, id}, text),
    do: add(%{scan | race: id}, {:race_guessed, text, id})

  defp claim_race(scan, {:chosen, id, ids}, text),
    do: add(%{scan | race: id}, {:race_chosen, text, id, ids})

  defp claim_race(scan, {:alternatives, ids}, text),
    do: add(%{scan | race_options: ids}, {:race_alternatives, text, ids})

  defp claim_alignment(scan, {:ok, id}, _text), do: %{scan | alignment: id}
  defp claim_alignment(scan, nil, _text), do: scan

  defp claim_alignment(scan, {:restriction, _text}, text),
    do: add(scan, {:alignment_restriction, text})

  defp claim_alignment(scan, :error, text), do: add(scan, {:unknown_alignment, text})

  # ------------------------------------------------------------------- title --

  # `Тестовый билд - Fighter(4), Dwarven defender(6)`. The name is separated from
  # the class split by a spaced dash, which is what lets a title keep a dash of
  # its own (`Dwarf-tank - Fighter(41)`).
  def title(scan, line, index) do
    segments = split_segments(line)

    declared =
      Enum.flat_map(segments, fn {segment, ix} -> declared_class(segment, ix, index) end)

    scan = %{scan | title: title_text(line, declared), declared: declared}
    if declared == [], do: scan, else: title_tail(scan, segments, index)
  end

  def split_segments(line), do: line |> String.split(",") |> Enum.with_index()

  # A line that states a class split: some `Class(N)` in it names a class, and
  # every other comma segment is a race or an alignment. Prose that mentions `a
  # Fighter(4) dip` in passing is not one.
  def class_split(line, index) do
    declared =
      line
      |> split_segments()
      |> Enum.flat_map(fn {segment, ix} -> declared_class(segment, ix, index) end)

    if Enum.any?(declared, &(&1.class != nil)) and
         Enum.all?(split_segments(line), fn {segment, _ix} -> split_part?(segment, index) end),
       do: declared
  end

  # `Cleric19/Bard20/Shadowdancer1, Human`, `The EDR SCV ED Guy Halfling Bard 7
  # / Shadowdancer 26 / RDD 7`, `Human Rogue 19 / Ftr 14 / WM 7` (task 4.31): a
  # split written with slashes and bare levels. Two classes at least, each read
  # for sure; after the last, a race or an alignment; before the first,
  # whatever the post calls the build — and when the word or two right before
  # the first class are a race, that is the build's race.
  def loose_split(line, index) do
    case top_level_split(line, split_separators()) |> Enum.reject(&(&1 == "")) do
      [first | rest] ->
        with {lead, declared} <- led_class(first, index),
             tail = Enum.map(rest, &loose_part(&1, index)),
             false <- Enum.member?(tail, :other),
             classes = [declared | for({:class, d} <- tail, do: d)],
             true <- length(classes) >= 2 do
          %{
            declared: classes,
            race: lead_race(lead, index) || Enum.find_value(tail, &race_of/1),
            alignment: Enum.find_value(tail, &alignment_of/1)
          }
        else
          _ -> nil
        end

      [] ->
        nil
    end
  end

  defp race_of({:race, id}), do: id
  defp race_of(_part), do: nil
  defp alignment_of({:alignment, found}), do: found
  defp alignment_of(_part), do: nil

  defp loose_part(part, index) do
    alignment = read_alignment(index, part)

    cond do
      declared = split_class(part, index) ->
        {:class, declared}

      match?({:ok, _}, race = exact_race(index, part)) ->
        {:race, elem(race, 1)}

      match?({kind, _} when kind in [:ok, :restriction], alignment) ->
        {:alignment, {alignment, part}}

      true ->
        :other
    end
  end

  # The first part: `… Halfling Bard 7` — the longest run of words before the
  # level that is a class for sure, and what stands before it.
  defp led_class(part, index) do
    with [_, name, levels] <- Regex.run(name_and_level(), part) do
      words =
        name |> String.split(~RX/\s+/u, trim: true) |> Enum.filter(&Regex.match?(~RX/\p{L}/u, &1))

      Enum.find_value(min(length(words), 4)..1//-1, fn taken ->
        {lead, class_words} = Enum.split(words, length(words) - taken)
        text = Enum.join(class_words, " ")

        case named_class(index, text) do
          {:ok, class} ->
            {lead, %{text: text, title: nil, class: class, levels: String.to_integer(levels)}}

          _ ->
            nil
        end
      end)
    else
      _ -> nil
    end
  end

  defp lead_race([], _index), do: nil

  defp lead_race(lead, index) do
    Enum.find_value([2, 1], fn taken ->
      words = Enum.take(lead, -taken)

      case length(words) == taken && exact_race(index, Enum.join(words, " ")) do
        {:ok, id} -> id
        _ -> nil
      end
    end)
  end

  def claim_loose_split(scan, loose) do
    scan = %{scan | declared: loose.declared}
    scan = if scan.race == nil and loose.race, do: %{scan | race: loose.race}, else: scan

    case loose.alignment do
      {alignment, text} when scan.alignment == nil -> claim_alignment(scan, alignment, text)
      _ -> scan
    end
  end

  # Every comma segment of a split line is a `Class(N)`, a race or an alignment.
  defp split_part?(segment, index) do
    text = String.trim(segment)

    Regex.match?(~RX/^.+?(?:(?<!\s)|(?<=^.))\s*\(\s*\d+\s*\)\s*$/u, text) or
      match?({:ok, _}, resolve_race(index, text)) or match?({:ok, _}, read_alignment(index, text))
  end

  # `Barbarian(17), Champion of Kord(18), Harper Scout(5), Half-Orc` — a class
  # split that ends with the race (sometimes the alignment too) instead of
  # giving them a line of their own. Only a segment that is exactly a race or
  # an alignment counts.
  def title_tail(scan, segments, index) do
    Enum.reduce(segments, scan, fn {segment, ix}, scan ->
      text = String.trim(segment)
      race = resolve_race(index, text)
      alignment = read_alignment(index, text)

      cond do
        ix == 0 or Regex.match?(~RX/\(\s*\d+\s*\)/u, text) ->
          scan

        scan.race == nil and match?({:ok, _}, race) ->
          claim_race(scan, race, text)

        scan.alignment == nil and match?({:ok, _}, alignment) ->
          claim_alignment(scan, alignment, text)

        true ->
          scan
      end
    end)
  end

  defp declared_class(segment, index_in_line, index) do
    case Regex.run(~RX/^(.+?)(?:(?<!\s)|(?<=^.))\s*\(\s*(\d+)\s*\)/u, String.trim(segment)) do
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
    case Regex.run(~RX/^(.*\S)\s+[-–—]\s+(\S.*)$/u, name) do
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
end
