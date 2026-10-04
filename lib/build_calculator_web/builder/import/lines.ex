defmodule BuildCalculatorWeb.Builder.Import.Lines do
  @moduledoc """
  Which shape each line of the paste is. `classify_line/3` asks the shapes in
  order — the order is the reading: moving one shape up or down changes what
  a line becomes — and hands the line to the part that owns the shape. The
  small shapes nobody else owns live here: section headers, the `SKILLS`
  totals, a list of increases apart from the ladder, a `Domains:` line, and a
  bump written out on the line under a level. A part of
  `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculatorWeb.Builder.ChoiceIndex

  import BuildCalculatorWeb.Builder.Import.Header,
    only: [
      claim_loose_split: 2,
      class_split: 2,
      labelled: 5,
      labelled_line: 2,
      loose_split: 2,
      split_segments: 1,
      title: 3,
      title_tail: 3,
      who_line: 3
    ]

  import BuildCalculatorWeb.Builder.Import.Ladder,
    only: [numbered_entry: 5, numbered_line: 1, split_items: 1]

  import BuildCalculatorWeb.Builder.Import.LevelTail, only: [increase_in: 2, read_extras: 4]

  import BuildCalculatorWeb.Builder.Import.Names,
    only: [ability_key: 1, ability_word?: 1, only_ok: 1, prefix_value: 2]

  import BuildCalculatorWeb.Builder.Import.Scan, only: [add: 2, untouched?: 1]

  import BuildCalculatorWeb.Builder.Import.Sheets,
    only: [
      abilities: 5,
      ability_line: 2,
      flush_block: 1,
      letter_line: 2,
      letters: 5,
      point_buy_mark: 3,
      point_buy_sheet?: 3,
      saves_block: 4,
      take_total: 3,
      totals_line: 1
    ]

  def classify(scan, {number, line}, index) do
    case increase_head_list(scan, number, line) do
      %{} = listed ->
        listed

      nil ->
        scan = flush_head(scan)

        case saves_block(scan, number, line, index) do
          %{} = claimed -> claimed
          nil -> classify_line(flush_block(scan), {number, line}, index)
        end
    end
  end

  # `numbered_line/1` is asked once: the section headers ask it first.
  defp classify_line(scan, {number, line}, index) do
    numbered = numbered_line(line)

    cond do
      section = section_header(line, numbered) ->
        section(scan, section, line)

      named = domains_line(line, index) ->
        %{scan | stated_choices: [Tuple.insert_at(named, 3, number) | scan.stated_choices]}

      word = increase_head(line) ->
        %{scan | increase_head: {word, number, line}}

      (stated = increase_list(line)) != [] ->
        %{scan | stated_increases: Enum.reverse(stated, scan.stated_increases)}

      labelled = labelled_line(line, index) ->
        labelled(scan, labelled, number, line, index)

      sheet = ability_line(line, %{index | point_buy_sheet?: point_buy_sheet?(scan, line, index)}) ->
        {scores, caption} = sheet

        scan = %{
          abilities(scan, scores, caption, :line, index.ruleset.level_cap)
          | point_buy_at: point_buy_mark(scan, line, index)
        }

        # `Human,neutral alligment,starting stats:str8,dex16,con10` — the
        # caption of a sheet can be the race line too.
        (caption && who_line(scan, caption, index)) || scan

      score = letter_line(line, index) ->
        letters(scan, score, number, line, index.ruleset.level_cap)

      total = totals_line(line) ->
        take_total(scan, total, index)

      entry = numbered ->
        numbered_entry(scan, entry, number, line, index)

      total = scan.section == :skills && skill_total_line(line) ->
        %{scan | source_skills: [total | scan.source_skills]}

      scan.section == :feats and scan.level_lines == [] ->
        %{scan | loose_feats: [line | scan.loose_feats]}

      continued = continued_level(scan, line, index) ->
        continued

      claimed = who_line(scan, line, index) ->
        claimed

      # The title is the block's first line and nothing else. A paste that
      # starts mid-build has no title, and prose further down is prose — reading
      # it as a name would put "Этот билд я собрал в 2019" in the save form.
      scan.title == nil and untouched?(scan) ->
        title(scan, line, index)

      # The class split further down, when the paste did not start with it —
      # a forum page's own header lines come first.
      split = scan.declared == [] && class_split(line, index) ->
        title_tail(%{scan | declared: split}, split_segments(line), index)

      loose = scan.declared == [] && loose_split(line, index) ->
        claim_loose_split(scan, loose)

      below = feats_below(scan, number, line, index) ->
        below

      true ->
        add(scan, {:ignored_line, number, line})
    end
  end

  # `Bump strength at levels: 4,8,12,16,20`, `Boost Dex at lvls 4, 12, 20, 24`,
  # `Strength at levels 4, 8, 12`, `+Str at levels 4/8/12`, `Raise Strength at
  # levels 4 and 8, Constitution at levels 12, 16, 20, and 24` (task 4.31; 37
  # posts): the increases as a list apart from the ladder. `[{level, word}]`,
  # the word an ability's name; the levels are checked against the ruleset's
  # own when applied (`with_stated_increases/4`). Only a clause that starts
  # the line or a list, or follows a word that raises — `Great Charisma at
  # lvl 27` is a feat taken there, not an increase.
  #
  # Task 4.36: a `;` between the levels too (`Level 4; 8; 12; 28`, 222157), and
  # the levels named first — `levels 4,8,12,16,20,24 in Strength, levels
  # 28,32,36,40 into Charisma` (209708) — and the two shapes below. The word
  # has to name a score, and the levels are the ruleset's to check, as always.
  defp increase_clause,
    do:
      ~RX"(?:^|[,;.]\s*|\b(?:bump|raise|boost|increase|put|pump|add)\s+(?:your\s+)?|\+\s*)(\p{L}+)\.?\s+(?:score\s+)?(?:at|on)\s+(?:levels?|lvls?|lv)\.?\s*:?\s*(\d{1,2}(?:\s*(?:,|;|&|/|\band\b|,\s*and\b)\s*\d{1,2})*)"iu

  defp levels_first_clause,
    do:
      ~RX"\b(?:levels?|lvls?|lv)\.?\s*:?\s*(\d{1,2}(?:\s*(?:,|;|&|/|\band\b|,\s*and\b)\s*\d{1,2})*)\s+(?:in|into|to|for|on)\s+(\p{L}+)"iu

  # `Increase Str- 4,8,12,16` (228702): the verb, the score, a dash or a colon,
  # the levels.
  defp dashed_clause,
    do:
      ~RX"\b(?:bump|raise|boost|increase|put|pump|add)\s+(?:your\s+)?(\p{L}+)\.?\s*+[-–—:]++\s*+(\d{1,2}(?:\s*+(?:,|;|&|/|\band\b)\s*+\d{1,2})*+)(?!\d)"iu

  # `Stats 4,8,12,16,20 Wisdom 24,28,32,36,40 Charisma` (228750): a line of
  # levels, each run followed by the score it went to.
  defp pairs_line,
    do:
      ~RX"^(?:stats?|bumps?|stat\s+(?:bumps?|increases?|points?)|ability\s+(?:increases?|bumps?))\s*+:?\s*+((?:\d{1,2}(?:\s*+[,;&/]\s*+\d{1,2})*+\s++\p{L}++\s*+)++)$"iu

  defp increase_list(line) do
    listed = for [_, word, list] <- Regex.scan(increase_clause(), line), do: {word, list}

    listed =
      listed ++ for [_, list, word] <- Regex.scan(levels_first_clause(), line), do: {word, list}

    listed = listed ++ for [_, word, list] <- Regex.scan(dashed_clause(), line), do: {word, list}

    listed =
      case Regex.run(pairs_line(), line) do
        [_, pairs] ->
          listed ++
            for [_, list, word] <-
                  Regex.scan(~RX"(\d{1,2}(?:\s*[,;&/]\s*\d{1,2})*)\s+(\p{L}+)"u, pairs),
                do: {word, list}

        nil ->
          listed
      end

    for {word, list} <- listed,
        ability_word?(word),
        level <- Regex.scan(~RX/\d{1,2}/u, list),
        do: {String.to_integer(hd(level)), ability_key(word)}
  end

  # `Raise CON at:` and, on the next line, `Level 4; 8; 12; 28` (task 4.36,
  # 222157) — the list of increases with its head on a line of its own. The
  # head waits one line for its levels (`increase_head_list/3`); the next line
  # not being them, it is a line we did not use, as it was.
  defp increase_head(line) do
    with [_, word] <-
           Regex.run(
             ~RX/^(?:bump|raise|boost|increase|put|pump|add)\s++(?:your\s++)?(\p{L}+)\.?\s++(?:score\s++)?(?:at|on)\s*+(?:(?:levels?|lvls?|lv)\.?)?\s*+:?\s*+$/iu,
             line
           ),
         true <- ability_word?(word) do
      word
    else
      _ -> nil
    end
  end

  defp increase_head_list(%{increase_head: {word, head_number, _head}} = scan, number, line)
       when number == head_number + 1 do
    case Regex.run(
           ~RX"^(?:(?:levels?|lvls?|lv)\.?)?\s*+:?\s*+(\d{1,2}(?:\s*+(?:,|;|&|/|\band\b)\s*+\d{1,2}(?!\d))*+)\s*+\.?$"iu,
           line
         ) do
      [_, list] ->
        stated =
          for [level] <- Regex.scan(~RX/\d{1,2}/u, list),
              do: {String.to_integer(level), ability_key(word)}

        %{
          scan
          | increase_head: nil,
            stated_increases: Enum.reverse(stated, scan.stated_increases)
        }

      nil ->
        nil
    end
  end

  defp increase_head_list(_scan, _number, _line), do: nil

  # ⚠️ The runs of spaces in both patterns are possessive: a line of a head's
  # words and a run of spaces was read again from each of them (task 4.34's
  # trap, `Header`'s attributes).

  # A head no list followed: the line we did not use it always was.
  def flush_head(%{increase_head: {_word, number, line}} = scan),
    do: add(%{scan | increase_head: nil}, {:ignored_line, number, line})

  def flush_head(scan), do: scan

  # `Domains: War and Trickery`, `Cleric Domains: Strength, Heal (recommended)`
  # — a class's own choice on a line of its own (task 4.31; 71 posts of the
  # corpus). `{domain, values, text}`: every value named has to be one of the
  # domain's, by its name or a start of it (`Heal`); a line with a word that
  # is not (`Air, Your Choice`) is kept whole and said to be unread.
  defp domains_line(line, index) do
    with [_, text] <- Regex.run(~RX/^(?:cleric\s+)?domains?\s*:\s*(\S.*)$/iu, line),
         values when is_map(values) <- Map.get(index.choices, :domain) do
      words =
        text
        |> String.replace(~RX/\([^)]*\)?/u, " ")
        |> String.split(~RX"(?:\G|(?<!\s))\s*(?:,|&|/|\band\b)\s*"iu, trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      found = Enum.map(words, &domain_value(values, &1))

      {:domain, if(Enum.member?(found, nil) or found == [], do: nil, else: Enum.uniq(found)),
       line}
    else
      _ -> nil
    end
  end

  defp domain_value(values, word) do
    with :error <- only_ok(ChoiceIndex.resolve(values, word)),
         :error <- prefix_value(values, word) do
      nil
    else
      {:ok, value} -> value
    end
  end

  # `24. Shifter- Great WIS …` and on the next line `Con +1` (task 4.31): a
  # bump written out, alone on the line right under a level, is that level's.
  # Only a bump written out (`CON +1`, `+1 Con`) — a bare name or a score
  # under a level is as likely the next paragraph.
  # `level_lines` is newest first while the text is read (`Scan.finish/1`).
  defp continued_level(%{level_lines: [last | earlier]} = scan, line, index) do
    with true <- last.position == scan.position - 1,
         {_ability, ""} <- increase_in(line, index) do
      grow = fn extras -> if extras in [nil, ""], do: line, else: extras <> ", " <> line end

      last = %{
        last
        | extras: grow.(last.extras),
          fallback: last.fallback && %{last.fallback | extras: grow.(last.fallback.extras)}
      }

      %{scan | level_lines: [last | earlier]}
    else
      _ -> nil
    end
  end

  defp continued_level(_scan, _line, _index), do: nil

  # `1. Fighter 1 Disc 4, Heal 4, Intimidate 2, Tumble 2` and on the next line
  # `Luck of Heroes, Dodge` (task 4.36, 117663): the level's feats written
  # under it. Asked last, of a line nobody else could read, right under the
  # level line — no blank line between — and read only when all of it reads
  # as a level's contents (`LevelTail.read_extras/4`) with a feat among it,
  # every name known for sure: a remark under a level (`Knockdown is great in
  # PvP`, `Feat- FE`) stays a line we did not use. Three lines to a level at
  # most. The lines are kept with the level (`below`): a level the ladder does
  # not read lists them with it (`Ladder.skipped/1`).
  @lines_below 3

  defp feats_below(%{level_lines: [last | earlier]} = scan, number, line, index) do
    below = Map.get(last, :below, [])

    with true <- length(below) < @lines_below,
         true <- number == below_number(last, below) + 1,
         reading = read_extras(line, last.level, index, index.ruleset),
         true <- reading.feats != [],
         false <-
           Enum.any?(
             reading.issues,
             &(elem(&1, 0) in [:unknown_feat, :ambiguous_feat, :feat_guessed])
           ) do
      grow = fn extras -> if extras in [nil, ""], do: line, else: extras <> ", " <> line end

      last =
        Map.merge(last, %{
          extras: grow.(last.extras),
          fallback: last.fallback && %{last.fallback | extras: grow.(last.fallback.extras)},
          below: [{number, line} | below]
        })

      %{scan | level_lines: [last | earlier]}
    else
      _ -> nil
    end
  end

  defp feats_below(_scan, _number, _line, _index), do: nil

  defp below_number(level, []), do: level.number
  defp below_number(_level, [{number, _line} | _]), do: number

  # ------------------------------------------------------------- line shapes --

  # Headers that open a ladder. They only end whatever section came before —
  # which numbered line is a level is decided by the line itself.
  @level_headers [
    "leveling guide",
    "levelling guide",
    "level guide",
    "leveling sequence",
    "levelling sequence",
    "leveling progression",
    "levelling progression",
    "level progression",
    "level advancement"
  ]

  # `SKILL GUIDE` (ours), `Skills by level`, `Skills per level`, `Skill-chart:`,
  # `Skills Progression` — CBC and the forums name the per-level skill list
  # a dozen ways, always as "skill(s)" plus one of these words.
  @skill_guide_words ~w(guide level levels lvl chart progression progress sequence distribution breakdown per)

  defp section_header(line, numbered) do
    words = header_words(line)

    cond do
      # A numbered line is never a header, whatever words it carries:
      # `12: Skill Focus (Hide), level 12 bonus` is a level.
      numbered -> nil
      Enum.any?(@level_headers, &String.starts_with?(words, &1)) -> :levels
      skill_guide_header?(words, line) -> :skill_guide
      String.starts_with?(words, "skills") -> :skills
      String.starts_with?(words, "feats") -> :feats
      true -> nil
    end
  end

  defp header_words(line) do
    line
    |> String.downcase()
    |> String.replace(~RX/[^a-zа-яё ]/u, " ")
    |> String.replace(~RX/\s+/u, " ")
    |> String.trim()
  end

  # ⚠️ Without a digit, and that is the whole difference from `Skills (at
  # level 40):`, which opens the totals, and `Skill points per level: 4`, which
  # is a number and not a header.
  defp skill_guide_header?(words, line) do
    case String.split(words, " ", trim: true) do
      [first | rest] when first in ["skill", "skills", "skillpoint", "skillpoints"] ->
        not Regex.match?(~RX/\d/u, line) and Enum.any?(rest, &(&1 in @skill_guide_words))

      _ ->
        false
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
      {:feats, rest} -> %{scan | loose_feats: Enum.reverse(split_items(rest), scan.loose_feats)}
      {_section, _rest} -> scan
    end
  end

  defp skill_total(scan, item) do
    case skill_total_line(item) do
      nil -> scan
      entry -> %{scan | source_skills: [entry | scan.source_skills]}
    end
  end

  # The bracketed number is the skill's *value*, and it is read as a string on
  # purpose: our own export prints `?` there when the key ability is named on no
  # wiki, and either way it is somebody else's arithmetic that never reaches the
  # build — the same rule as the header's Hitpoints.
  #
  # ⚠️ Written so that a run of spaces is read once (task 4.34; the guards are
  # explained at `Header`'s attributes): the name does not end inside a run of
  # spaces, the spaces around a missing bracket have one way to be shared, and
  # the value is the bracket's contents without their spaces — a lazy value
  # followed by spaces read the rest of a run again from each of its spaces.
  defp skill_total_line(line) do
    case Regex.run(
           ~RX/^(.+?)(?:(?<!\s)|(?<=^.))\s+(\d+)\s*(?:\(\s*((?:[^)\s](?:[^)]*[^)\s])?)?)\s*\)\s*)?$/u,
           String.trim(line)
         ) do
      [_, name, ranks] -> %{name: String.trim(name), ranks: ranks, total: nil}
      [_, name, ranks, total] -> %{name: String.trim(name), ranks: ranks, total: total}
      _ -> nil
    end
  end
end
