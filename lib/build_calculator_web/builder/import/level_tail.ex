defmodule BuildCalculatorWeb.Builder.Import.LevelTail do
  @moduledoc """
  One level's contents — the tail of a ladder line after its class: the
  ability bump, the skill purchases written on the line, the source's own
  notes and arithmetic (passed over), and what is left, the feat names,
  handed to `BuildCalculatorWeb.Builder.Import.FeatList`. A part of
  `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculator.Rules.Abilities
  alias BuildCalculatorWeb.Builder.Import.FeatList

  import BuildCalculatorWeb.Builder.Import.Names,
    only: [
      ability_key: 1,
      ability_word?: 1,
      collapse: 1,
      feat_by_forms: 2,
      name_forms: 1,
      name_words: 1,
      near_feat_by_forms: 3,
      norm: 1,
      resolve: 2,
      resolve_skill: 2
    ]

  # CBC's skill chart closes a level with the points carried on to the next —
  # `Save(8)` — and hand-written charts say `Free(20)`, `Bank 4` or `S - 3`. A
  # word of the FORMAT, not of the game, so it is passed over without a note:
  # carried points are arithmetic our own budget redoes.
  #
  # One list for both places they are written in (task 4.34; there were two,
  # of nine words and of five): beside a count, as a chart's entry
  # (`unspent?/1`), and as a phrase on the level line (`unspent_note?/1`) —
  # `save 4 points`, `Save All`, `save the rest`. In a phrase the first five
  # say it on their own; `s`, `free`, `remaining` and `left` begin other things
  # too — `s* Improved Combat Casting`, `Free Feat, choose what you like` — and
  # say it only with the count right after them: `free 4 points`.
  @unspent_words %{
    "save" => :alone,
    "saved" => :alone,
    "bank" => :alone,
    "unspent" => :alone,
    "unused" => :alone,
    "s" => :counted,
    "free" => :counted,
    "remaining" => :counted,
    "left" => :counted
  }

  # One level's tail — `STR+1, Automatic Still Spell I, (STR=16)` — read into
  # the feats picked, the +1 to an ability, and any skill purchases written on
  # the same line (`Discipline(5)`, `Disc +1`).
  #
  # CBC's reminders go first, while they are still whole, because they carry
  # commas of their own: `{Cleave, Evasion}` and `M: (Cleave, Evasion)` are
  # what a class hands over by itself, `(STR=16)` is the score after the bump.
  # Then each item is asked, in this order, whether it is the bump, a skill
  # purchase, a bare ability's name on a level that grants the bump (`- STR`,
  # `(Con)`, `WIS15`), a note (`(20)`, `+1 AC`, `d8 hp`); what remains is feats.
  #
  # ⚠️ A bracket is NOT a note by itself. Hand-written ladders put the level's
  # picks in brackets — `Sorcerer1 (Toughness)`, `RDD3 (Breath Weapon,
  # PowerAttack)` — so a bracketed item is opened and its contents read like
  # any other; only what is shaped like a note is passed over, and a name we
  # do not know is reported, in brackets or not.
  def read_extras(text, level, index, ruleset) do
    grants_bump? = Abilities.increase_level?(ruleset, level)

    items =
      text
      |> String.replace(~RX/^[\s:,;.\-–—>|]+/u, "")
      |> strip_notes(index)
      |> split_extras()

    reading = %{texts: [], increase: nil, increase_by: nil, skills: %{}}
    reading = Enum.reduce(items, reading, &read_item(&2, &1, grants_bump?, index))
    # `texts` is gathered newest first (task 4.34).
    {picks, issues} = FeatList.read_feats(Enum.reverse(reading.texts), level, index, ruleset)
    {choices, feats} = Enum.split_with(picks, &match?({:class_choice, _, _}, &1))
    {increase, off_level} = on_increase_level(reading.increase, grants_bump?, level)

    %{
      feats: feats,
      choices: for({:class_choice, class, value} <- choices, do: {class, value}),
      increase: increase,
      skills: reading.skills,
      issues: off_level ++ issues
    }
  end

  # 🔴 A bump the line writes out (`DEX+1`, `+1 Con`, `Con +1` on the line
  # under it) on a level that grants none is not put into the build, and
  # that is said (task 4.36). The core adds every increase the build holds
  # up to a level (`Abilities.scores_at/3`), so a bump the text misplaced —
  # `30.Arcane Archer-DEX+1`, a thirty-first increase of a build that took ten
  # on the right levels — raised the score, and until task 4.37 nothing named
  # it. Only a bump written out can reach here: one read off a bare name or a
  # bracket is asked for on a level that grants one only.
  #
  # Which levels grant one is the core's question (`Abilities.increase_level?/2`,
  # task 4.37), the same one `Rules.illegal_increases/2` asks of a finished
  # build; the import kept its own reading of the same field until then. The
  # answer to the text stays the import's: `Rules.illegal_increases/2` judges
  # a build that holds such an increase, and the import does not put one in —
  # it says, in its own report, that the bump was not carried over.
  defp on_increase_level(nil, _grants_bump?, _level), do: {nil, []}
  defp on_increase_level(ability, true, _level), do: {ability, []}

  defp on_increase_level(ability, false, level),
    do: {nil, [{:increase_off_level, level, ability}]}

  defp strip_notes(text, index) do
    text
    |> String.replace(~RX/\{[^}]*\}?/u, " ")
    |> drop_score_notes()
    |> strip_grant_notes(index)
    |> strip_slot_labels(index)
    |> String.replace(["*", "#"], "")
    |> String.replace(~RX/(?:\G|(?<!\s))\s+(?:&|\+|and|[-–—]+)\s+/iu, ", ")
  end

  # `(STR=16)` — the score after the bump, written beside it: a reminder,
  # never the bump itself (CBC writes the bump as `STR+1` and the score after
  # it as `(STR=16)`; `36: Cleric(18): WIS+1, Great Strength V, (STR=28),
  # (WIS=20)` has a note of each on a level whose bump is Wisdom). The word is
  # a score's by `Names.ability_word?/1` (task 4.34).
  #
  # ⚠️ Only inside brackets (task 4.36): `(STR=16)`, `(RDD STR=18)`. `4
  # Cleric(3) Wis=16`, `12 Barbarian 12 Power Attack, Dex = 19` (245368,
  # 230819) write nothing else on the level: the score after the bump is how
  # the post names it, the way `WIS15` or `Str 18` does — and it is read as
  # they are (`read_one/5`): the bump on a level that grants one and nothing
  # else wrote it, the source's arithmetic anywhere else. A bump written out
  # beats it, on either side of it.
  defp drop_score_notes(text) do
    text
    |> drop_notes(~RX/\(\s*(\p{L}+)\s*=\s*\d+\s*\)/u)
    |> then(
      &Regex.replace(~RX/[\(\[][^\(\)\[\]]*+[\)\]]/u, &1, fn group ->
        drop_notes(group, ~RX/\b(\p{L}+)\s*=\s*\d+\b/u)
      end)
    )
  end

  defp drop_notes(text, note),
    do:
      Regex.replace(note, text, fn whole, word -> if ability_word?(word), do: " ", else: whole end)

  # `(Bonus Feat): Epic Toughness`, `CFeat: Armor Skin`, `RFeat: Crippling
  # Strike`, `Feat: Dodge`, `Fighter bonus: Cleave` — which slot the author
  # meant, written before the feat (task 4.31). The slot is redone the way a
  # click would do it (`with_feats/4`), so the label is passed over — and not
  # read as the feat's choice after a colon, which is what `Epic Toughness`
  # used to become (`Great Strength VI, (Bonus Feat): Epic Toughness`).
  # A label that is itself a feat's name is left for the feat reader.
  #
  # A label stands at the start of the text or right after a comma or a
  # semicolon (`(^|[,;])`); the pattern is asked at those places only, one
  # piece of the text at a time (`strip_slot_labels/2`, task 4.34). The spaces
  # around a bracket are `\s*(?:[\(\[]\s*)?`, not `\s*[\(\[]?\s*` — the same
  # text, without the ways of sharing a run of spaces between two `\s*` when
  # no bracket stands in it, which a piece opening with a long run of spaces
  # tried all of (task 4.34).
  defp slot_label,
    do:
      ~RX/^([,;]?)\s*(?:[\(\[]\s*)?((?:epic\s+|class\s+|general\s+)?(?:bonus\s+)?feats?|bonus|\p{L}{1,3}\s*feats?|\p{L}+\s+bonus(?:\s+feats?)?)\s*(?:[\)\]]\s*)?:(?!\s*[\(\[])/iu

  # A text without a colon has no label in it, and is not read for one; one
  # without a comma or a semicolon can have it only at its start, and is asked
  # there alone (task 4.34: the search for a place to start read all of it
  # from every character).
  #
  # With commas or semicolons the text is cut before each of them and every
  # piece is asked at its start: a label and what follows it up to the colon
  # hold neither, so no match reaches from one piece into the next, and the
  # pieces are what the global search read in turn — without trying every
  # character between them.
  defp strip_slot_labels(text, index) do
    cond do
      not String.contains?(text, ":") ->
        text

      String.contains?(text, [",", ";"]) ->
        pieces = label_pieces(text)
        read = Enum.map(pieces, &replace_label(&1, index))
        # Nothing taken off: the text as it stands, not a copy of it.
        if read == pieces, do: text, else: Enum.join(read)

      true ->
        replace_label(text, index)
    end
  end

  # The label at the start of a piece, if there is one. Before its colon a
  # label is made of letters, spaces and brackets (and the comma or semicolon
  # opening the piece), and after the colon the pattern looks at spaces and
  # one character more: when all that ends inside the piece's first 256
  # bytes, the window is asked instead of the piece (a regex checks its whole
  # text is UTF-8, and a piece may be most of a long line).
  defp replace_label(piece, index) do
    window = utf8_prefix(piece, 256)
    asked = if window == piece or label_decided_in?(window), do: window, else: piece

    case Regex.run(slot_label(), asked) do
      [whole, lead, label] ->
        kept = if resolve(index.feats, label) == :error, do: lead <> " ", else: whole
        kept <> binary_part(piece, byte_size(whole), byte_size(piece) - byte_size(whole))

      nil ->
        piece
    end
  end

  defp label_decided_in?(window) do
    [{0, before}] = Regex.run(~RX/^[,;]?[\s\(\[\)\]\p{L}]*/u, window, return: :index)

    upto =
      if before < byte_size(window) and :binary.at(window, before) == ?: do
        after_colon = binary_part(window, before + 1, byte_size(window) - before - 1)
        [{0, spaces}] = Regex.run(~RX/^\s*/u, after_colon, return: :index)
        before + 1 + spaces
      else
        before
      end

    upto + 4 <= byte_size(window)
  end

  # The text cut before every comma and semicolon; the first piece is the
  # start, every other one opens with its comma or semicolon.
  defp label_pieces(text) do
    cuts = for {at, _} <- :binary.matches(text, [",", ";"]), at > 0, do: at
    starts = [0 | cuts]
    stops = cuts ++ [byte_size(text)]
    Enum.zip_with(starts, stops, fn from, to -> binary_part(text, from, to - from) end)
  end

  # `Ro: (Evasion)`, `RDD: (Darkvision)`, `M: (Cleave, Evasion)`, `Human: (Quick
  # to Master)` — one word, a colon, the grants in brackets, at the start of an
  # item. `Weapon Focus: (Kama)` never matches (the word before the colon does
  # not open the item), and a word that is itself a feat (`WF: (Kama)`) is left
  # for the feat reader.
  defp strip_grant_notes(text, index) do
    Regex.replace(
      ~RX/(^|[,;])\s*([\p{L}][\p{L}.]{0,11})\s*:\s*\([^)]*\)?/u,
      text,
      fn whole, lead, label ->
        if resolve(index.feats, label) == :error, do: lead <> " ", else: whole
      end
    )
  end

  # Items are cut at commas, semicolons and slashes (`Expertise/Improved
  # Expertise`), never inside brackets: `(D8 hp, +2 STR)` is one note. An item
  # that OPENS with a bracket ends where the bracket closes — `(+4 STR, wings)
  # STR` is a note and then the bump — while a bracket after a name stays with
  # it: `Weapon focus (longsword)`.
  #
  # ⚠️ Whether the item opened with a bracket is kept as the item grows (task
  # 4.34): it is decided by its first grapheme that is not a space, and was
  # looked for again from the item's start at every closing bracket — `x(a)(a)…`
  # made that quadratic.
  def split_extras(text) do
    {items, current, _depth, _led} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], [], 0, nil}, fn ch, {items, current, depth, led} ->
        led = if led == nil and ch != " ", do: ch in ["(", "["], else: led

        cond do
          ch in ["(", "["] ->
            {items, [ch | current], depth + 1, led}

          ch in [")", "]"] and depth == 1 and led == true ->
            {[[ch | current] | items], [], 0, nil}

          ch in [")", "]"] ->
            {items, [ch | current], max(depth - 1, 0), led}

          ch in [",", ";", "/"] and depth == 0 ->
            {[current | items], [], 0, nil}

          true ->
            {items, [ch | current], depth, led}
        end
      end)

    [current | items]
    |> Enum.reverse()
    |> Enum.map(&(&1 |> Enum.reverse() |> Enum.join() |> collapse()))
    |> Enum.reject(&(&1 == ""))
  end

  # 🔴 How deep one item is read is bounded (task 4.34): a score parted off it
  # (`split_score/2`) and a bracket opened (`read_one/5`) each read what is
  # left again, whole, one level down. The corpus goes two levels down at
  # most (2 posts of 2027); a paste of scores glued without commas (`Str 16
  # Str 16 … )`) or of brackets inside brackets went thousands of levels down,
  # each reading all that was left — 64 KB took minutes. Past `@item_depth`
  # levels the rest is read as it stands: a feat's name, a note, a bump.
  @item_depth 8

  defp read_item(reading, item, grants_bump?, index, depth \\ 0) do
    item =
      item
      |> strip_slot_labels(index)
      |> String.trim()
      |> strip_trailing_marks()
      |> strip_leading_colon()

    case depth < @item_depth && (split_score(item, index) || split_skill(item, index)) do
      {first, second} ->
        reading
        |> read_item(first, grants_bump?, index, depth + 1)
        |> read_item(second, grants_bump?, index, depth + 1)

      _ ->
        read_one(reading, item, grants_bump?, index, depth)
    end
  end

  # `Extend Spell Str 15`, `Rapid Shot Wis 21`, `Wis 22 RFeat: Skill Mastery`
  # — a score written into the same item as a feat, without a comma (task
  # 4.31). Parted, each half is read on its own: on a level that grants the
  # bump the score is the bump, anywhere else the source's arithmetic.
  # `Great Str I Str 18` parts too, into the feat and the score it left.
  #
  # ⚠️ A score, not a count: ten and more, and not beside a skill bought —
  # `Tumble 4 Con 5` is two purchases, the second of Concentration.
  #
  # The score's word is any word here, and a score's by `score_split?/3`
  # (`Names.ability_word?/1`, task 4.34).
  defp split_score(item, index) do
    trailing =
      if number_may_end?(item, ~c")]"),
        do:
          Regex.run(
            ~RX/^(.*\S)\s+((\p{L}+\.?)\s*[:=]?\s*[\(\[]?\s*(\d{1,2})\s*[\)\]]?)$/u,
            item
          )

    leading = leading_score(item)

    cond do
      match?([_, _, _, _, _], trailing) and
        score_split?(Enum.at(trailing, 3), Enum.at(trailing, 4), Enum.at(trailing, 1), index) and
        not names_feat?(index, Enum.at(trailing, 1), Enum.at(trailing, 3), true) and
          not Regex.match?(~RX/\+\s*1$/u, Enum.at(trailing, 1)) ->
        {Enum.at(trailing, 1), Enum.at(trailing, 2)}

      match?([_, _, _, _, _], leading) and
          score_split?(Enum.at(leading, 2), Enum.at(leading, 3), Enum.at(leading, 4), index) ->
        {Enum.at(leading, 1), Enum.at(leading, 4)}

      true ->
        nil
    end
  end

  # `Discipline 1 Great Constitution I`, `Spot 10 Cleave` — a skill bought
  # and a feat with nothing between them, where a table's columns ran
  # together (task 4.36; 146826, 146828). Parted only when the words before
  # the count are a skill we know for sure (`inline_skill/2`): a name we do
  # not know stays whole, and is reported whole. The item is collapsed, so
  # its spaces are single ones; a skill's name is four words at most.
  #
  # `Hide 5 Ranks` is one purchase: the word of its count, all that follows
  # it, is its own (`Point Blank Shot` after a count is a feat).
  #
  # ⚠️ Not when what follows is an ability's name and a count: `Tumble 4 Con
  # 5` is two purchases or a purchase and a score, and parting it would leave
  # `Con 5` to be read as the bump — the text does not say which.
  defp split_skill(item, index) do
    with [_, name, count, rest] <-
           Regex.run(~RX/^(\p{L}+(?: \p{L}+){0,3}) (\d{1,2}) (\p{L}.*)$/u, item),
         {_skill, _ranks} <- inline_skill(name <> " " <> count, index),
         false <- ability_count?(rest) do
      {name <> " " <> count, String.replace(rest, ~RX/^(?:ranks?|points?|pts)\.?$/iu, "")}
    else
      _ -> nil
    end
  end

  defp ability_count?(text) do
    case skill_item(text) do
      {word, _count} -> ability_word?(word)
      nil -> false
    end
  end

  # `~RX/^((\p{L}+\.?)\s*[:=]?\s*(\d{1,2}))\s+(\p{L}.*)$/u`: what is
  # left after the score starts with a letter and runs to the end — asked as a
  # look at that one letter, and taken by its place, not read to the end. A
  # text with a line break in it (`.` stops there) is read the old way.
  #
  # The start is read in a window of its first 256 bytes (a regex checks every
  # byte of its text is UTF-8, so a pattern that looks at ten bytes still
  # costs the whole rest): a match whose next letter lies inside the window
  # was found looking at the window only, and is the match the whole text
  # gives. Anything else is read off the whole text.
  defp leading_score(item) do
    if String.contains?(item, "\n") do
      Regex.run(
        ~RX/^((\p{L}+\.?)\s*[:=]?\s*(?|(\d{1,2})|[\(\[]\s*(\d{1,2})\s*[\)\]]))(?:\s+|(?<=[\)\]]))([\p{L}\(\[].*)$/u,
        item
      )
    else
      window = utf8_prefix(item, 256)

      case score_start(window) do
        [{0, rest_at} | _] = found when rest_at + 4 <= byte_size(window) ->
          score_parts(item, found)

        found when window == item ->
          found && score_parts(item, found)

        _ ->
          (found = score_start(item)) && score_parts(item, found)
      end
    end
  end

  # Task 4.36: the score may stand in brackets and run into the name after it
  # — `CON(22)Epic Weapon Focus (Warhammer)` (222793) — and what follows it may
  # open with a bracket: `Dex 21 (Monk Speed, Still Mind)`, `Dex 25 [Favored
  # Enemy: Dwarves]` (273501, 273313), the grants of the level after its bump.
  defp score_start(text),
    do:
      Regex.run(
        ~RX/^((\p{L}+\.?)\s*[:=]?\s*(?|(\d{1,2})|[\(\[]\s*(\d{1,2})\s*[\)\]]))(?:\s+|(?<=[\)\]]))(?=[\p{L}\(\[])/u,
        text,
        return: :index
      )

  defp score_parts(item, [{0, rest_at}, score, word, value]) do
    [
      item,
      binary_part(item, elem(score, 0), elem(score, 1)),
      binary_part(item, elem(word, 0), elem(word, 1)),
      binary_part(item, elem(value, 0), elem(value, 1)),
      binary_part(item, rest_at, byte_size(item) - rest_at)
    ]
  end

  # At most `size` bytes off the start, cut before a character, not inside one.
  defp utf8_prefix(text, size) when byte_size(text) <= size, do: text

  defp utf8_prefix(text, size) do
    case :binary.at(text, size) do
      byte when byte in 0x80..0xBF -> utf8_prefix(text, size - 1)
      _ -> binary_part(text, 0, size)
    end
  end

  # `36 Monk 22⇥(1) Imp.SR I⇥⇥|STR` (task 4.36, 235913): a table's bar, which
  # `Ladder` reads as the end of the class, leaves the cell after it opening
  # with a colon once the tabs part the cells — the colon belongs to no name.
  defp strip_leading_colon(":" <> rest), do: String.trim_leading(rest)
  defp strip_leading_colon(text), do: text

  # `~RX/(?<![.;:])[.;:]+$/u`, asked of a text that ends with one of them — or
  # with a line break, before which `$` stands as well.
  defp strip_trailing_marks(text) do
    if may_end_with?(text, ~c".;:\n"),
      do: String.replace(text, ~RX/(?<![.;:])[.;:]+$/u, ""),
      else: text
  end

  # Whether the text's last byte is one of `bytes` — or any byte of a longer
  # character, which a pattern's `\d` or `\s` may read (task 4.34).
  defp may_end_with?("", _bytes), do: false

  defp may_end_with?(text, bytes) do
    last = :binary.last(text)
    last >= 128 or last in bytes
  end

  # Whether the text can end the way a number ends a pattern — `\d\s*[)]?$`,
  # `\d\s*\)\s*$`: read from the end, spaces (a line break among them, `$`
  # standing before a last one), one of `closers`, spaces, and then a digit —
  # or a byte of a longer character, which `\d` or `\s` may read. A cheap
  # answer the patterns' own could only repeat (task 4.34); where it says yes
  # they are asked.
  defp number_may_end?(text, closers) do
    at = skip_spaces(text, byte_size(text) - 1)
    at = if at >= 0 and :binary.at(text, at) in closers, do: at - 1, else: at
    at = skip_spaces(text, at)
    at >= 0 and (:binary.at(text, at) >= 128 or :binary.at(text, at) in ?0..?9)
  end

  defp skip_spaces(text, at) do
    if at >= 0 and :binary.at(text, at) in ~c" \t\n\v\f\r",
      do: skip_spaces(text, at - 1),
      else: at
  end

  # ⚠️ Not beside a skill bought, and that is a skill we know (task 4.36):
  # `Tumble 4 Con 15` is two purchases, but `Great Smiting 8 CHA(26)` (186693)
  # is a feat with its rank, and then the bump — any `name N` used to count.
  defp score_split?(word, score, other, index) do
    ability_word?(String.trim_trailing(word, ".")) and String.to_integer(score) >= 10 and
      inline_skill(other, index) == nil
  end

  defp read_one(reading, item, grants_bump?, index, depth) do
    {item, reading} = take_increase(item, reading, grants_bump?, index)

    case inline_skills(item, index) do
      :unspent ->
        reading

      [_ | _] = bought ->
        skills =
          Enum.reduce(bought, reading.skills, fn {id, ranks}, acc ->
            Map.update(acc, id, ranks, &(&1 + ranks))
          end)

        %{reading | skills: skills}

      nil ->
        written = item
        item = drop_scores(item)

        cond do
          bump = grants_bump? and reading.increase == nil and bare_ability(item, index) ->
            %{reading | increase: bump, increase_by: :implied}

          inside = depth < @item_depth && bracketed(item) ->
            inside
            |> split_extras()
            |> Enum.reduce(reading, &read_item(&2, &1, grants_bump?, index, depth + 1))

          bump = grants_bump? and reading.increase == nil and number_first_bump(written, index) ->
            %{reading | increase: bump, increase_by: :implied}

          # `STR (25)` on a level that grants no bump: the score a class moved
          # (a Red Dragon Disciple's), written down — seen before its bracket
          # was dropped as the source's arithmetic (task 4.31). And what is left
          # of `Ability: Str (str16)` once the bracket gave the bump.
          note?(item) or score_note?(item, index) or score_note?(written, index) or
            unspent_note?(item) or bare_ability(item, index) != nil ->
            reading

          true ->
            %{reading | texts: [item | reading.texts]}
        end
    end
  end

  # One purchase, or several run together without commas — `discipline +4
  # hide +4 move silently +4` — each of which reads as a skill.
  defp inline_skills(item, index) do
    case inline_skill(item, index) do
      nil ->
        pieces = String.split(item, ~RX/(?<=\+\d|\+\d\d)\s+(?=\p{L})/u)

        with [_, _ | _] <- pieces,
             bought = Enum.map(pieces, &inline_skill(&1, index)),
             true <- Enum.all?(bought, &is_tuple/1) do
          bought
        else
          _ -> nil
        end

      :unspent ->
        :unspent

      one ->
        [one]
    end
  end

  def bracketed(item) do
    case Regex.run(~RX/^[\(\[](.*)[\)\]]$/u, item) do
      [_, inside] -> inside
      _ -> nil
    end
  end

  # The ability bump is pulled out of whatever item it was written into, because
  # it is not always its own: our own export writes `+1 STR, 19` as two items,
  # but a forum line reads `Weapon focus (longsword) +1 str`. What is left of the
  # item is still a feat name. The first bump on a line wins. On a level that
  # grants the bump, an ability's name in brackets anywhere in the item is the
  # bump too — `Improved Critical - Unarmed (Str)`, `(Str +1 =17)`.
  #
  # ⚠️ A bump written out (`CON +1`) beats one read off a bare name or a
  # bracket (`STR (31)`, `(CHA 23)`), whichever comes first on the line (task
  # 4.31): `STR (31), CHA (8), CON +1 (21)` on a Red Dragon Disciple's level is
  # two scores the class moved and then the bump, and `Great Charisma III (CHA
  # 23), WIS +1 (WIS 22)` a feat with the score it left and then the bump.
  defp take_increase(item, reading, grants_bump?, index) do
    case increase_in(item, index) do
      {id, rest} when reading.increase_by in [nil, :implied] ->
        {rest, %{reading | increase: id, increase_by: :explicit}}

      {_id, rest} ->
        {rest, reading}

      nil when grants_bump? and reading.increase == nil ->
        bracketed_bump(item, reading, index)

      nil ->
        {item, reading}
    end
  end

  # `(Dex)`, `(Str +1 =17)`, `(chr16)` — and the number first, `(17 Char)`
  # (task 4.31).
  defp bracketed_bump,
    do:
      ~RX/[\(\[]\s*(?:\+\s*1\s*)?(?:\d{1,2}\s+)?(\p{L}{3,})\s*(?:\+\s*1)?\s*=?\s*\d{0,2}\s*[\)\]]/u

  # Every bracket is asked, not only the first: in `Epic Wpn Spec (Rapier)
  # (Dex)` the first one is the weapon.
  defp bracketed_bump(item, reading, index) do
    found =
      Enum.find_value(Regex.scan(bracketed_bump(), item), fn [whole, word] ->
        with key when is_binary(key) <- ability_key(word),
             {:ok, id} <- resolve(index.abilities, key) do
          {whole, id}
        else
          _ -> nil
        end
      end)

    case found do
      {whole, id} ->
        {item |> String.replace(whole, " ", global: false) |> collapse(),
         %{reading | increase: id, increase_by: :implied}}

      nil ->
        {item, reading}
    end
  end

  # A skill bought on the level line itself. ⚠️ An ability's name is never read
  # as one here: `Int 16` on a level line is the score, and a skill prefix would
  # have made it sixteen ranks of Intimidate.
  def inline_skill(item, index) do
    with {name, ranks} <- skill_item(item),
         nil <- ability_key(name) do
      cond do
        unspent?(name) -> :unspent
        ranks == 0 -> nil
        true -> with {:ok, id} <- resolve_skill(index, name), do: {id, ranks}, else: (_ -> nil)
      end
    else
      _ -> nil
    end
  end

  # The score written after a bump or a feat — `(20)`, `(+2)`, `=17` — is the
  # source's own arithmetic, like every other computed number in the block.
  #
  # Task 4.40: a score that closes a bracket after a word takes the space
  # before it along — `Whirlwind (Intimidate = 4)` (186693) is `Whirlwind
  # (Intimidate)`, not `Whirlwind (Intimidate )` with a hole where the number
  # stood. A bracket that holds the score alone (`Graet CHA II (=25)`, 281200)
  # is left to the old rule and stays an empty bracket, `( )`. The feat reader
  # reads an empty bracket alike with a space inside or without one (task
  # 4.40, third pass, `FeatList.bracketed_qualifier/1`) — until then `()` fell
  # through to the colon and `( )` did not, and the first version of the rule
  # above, leaving `()`, moved the reading of two posts. Taking the empty
  # bracket away altogether would move it too: `EF:Great Strength II` reads
  # its `EF:` as Epic Fortitude (170330), the bracket keeps it the unknown name
  # it is. The text is collapsed first, so the space before `=` is one
  # character at most and the pattern asks a fixed number of them at each
  # place.
  defp drop_scores(item) do
    item
    |> collapse()
    |> String.replace(~RX/(?<![\(\[\s]) ?=\s*+\d++ ?(?=[\)\]])/u, "")
    |> String.replace(~RX/\(\s*[+\-]?\d+\s*\)|=\s*\d+/u, " ")
    |> collapse()
  end

  # `STR`, `(Con)`, `+CHA`, `Str.`; with the new score after it — `WIS15`,
  # `(DEX 19)`, `Dex: 18`, `Str to 18`; said in words — `Ability: Strength`,
  # `Dex Increase [17]`, `Raise DEX`, `DEX up`. On a level that grants the
  # bump, and only there, a bare ability's name is the bump.
  defp bare_ability,
    do:
      ~RX/^[\(\[+]*\s*(?:(?:ability|stat)(?:\s+(?:point|points|increase|bump|raise))?\s*[:=\-]?\s*|(?:raise|boost|increase|inc|bump|add)\s+)?(\p{L}{3,})\s*(?:increase|bump|up)?\s*(?:to\s+)?[:=]?\s*(?:\+\s*1)?\s*[\(\[]?\s*(\d{0,2})\s*[\)\]]?\s*[\)\]]?\.?$/iu

  def bare_ability(item, index) do
    with [_, word | _] <- Regex.run(bare_ability(), item),
         key when is_binary(key) <- ability_key(word),
         {:ok, id} <- resolve(index.abilities, key) do
      id
    else
      _ -> nil
    end
  end

  # `17 Char`, `(16 Str)` on a level that grants the bump: the bump, the score
  # after it written first (task 4.31).
  defp number_first_bump(item, index) do
    with true <- number_first_score?(item, index),
         [_, word] <- Regex.run(~RX/(\p{L}{3,})\s*[\)\]]?$/u, item),
         key when is_binary(key) <- ability_key(word),
         {:ok, id} <- resolve(index.abilities, key) do
      id
    else
      _ -> nil
    end
  end

  # `CHA 16`, `(STR 18)` on a level that grants no bump: the score, written
  # down for the reader — the source's arithmetic again.
  def score_note?(item, index) do
    case Regex.run(bare_ability(), item) do
      [_, _word, score] -> score != "" and bare_ability(item, index) != nil
      _ -> number_first_score?(item, index)
    end
  end

  # `(16 Str)`, `17 Char` — the score written number first (task 4.31).
  defp number_first_score?(item, index) do
    with [_, word] <- Regex.run(~RX/^[\(\[]?\s*\d{1,2}\s+(\p{L}{3,})\s*[\)\]]?$/u, item),
         key when is_binary(key) <- ability_key(word) do
      match?({:ok, _}, resolve(index.abilities, key))
    else
      _ -> false
    end
  end

  # `save 4 points`, `Save All`, `save extra pts.`, `free 4 points` — the skill
  # points carried on, written on the level line (`@unspent_words`).
  defp unspent_note?(item) do
    case name_words(item) do
      [first | rest] ->
        case {Map.get(@unspent_words, first), rest} do
          {:alone, _rest} -> true
          {:counted, [count | _]} -> Regex.match?(~RX/^\d+$/u, count)
          _other -> false
        end

      [] ->
        false
    end
  end

  # A bare number, punctuation, or what a class hands over written as the
  # number it moves — `+1 AC`, `+2 STR from RDD`, `STR +2`, `d8 hp`, `4d10
  # breath` — no feat's name starts with a sign or a die, and the one bump a
  # level grants (`STR +1`) was taken before this is asked. Nothing a level
  # decides.
  #
  # `[bonus]`, `(bonus feat)` — which slot the author meant — is a note too.
  def note?(item) do
    item == "" or Regex.match?(~RX/^[\d\s.,:;=+\-–—>%]*$/u, item) or
      Regex.match?(~RX/^(?:[+\-–]\s*\d|\d*d\d+\b)/iu, item) or ability_modifier?(item) or
      Regex.match?(~RX/^bonus(?:\s+feats?)?$/iu, item)
  end

  defp ability_modifier?(item) do
    case Regex.run(~RX/^(\p{L}{3,})\s*[+\-–]\s*\d+\b/u, item) do
      [_, word] -> ability_key(word) != nil
      _ -> false
    end
  end

  # `+1 STR`, `+1 to Str`, `STR +1`, `+1Wisdom(16)`, `Charisma +1 (17)`, and the
  # same bump written at the end of a feat. Returns the ability and whatever
  # else the item said.
  #
  # ⚠️ Every shape is tried until one names an ability: `choose +1 STR` fits the
  # second shape with `choose` in the ability's place, and stopping there lost
  # the bump the third shape reads.
  #
  # The fourth shape — the bump written after a feat, the ability first:
  # `Devastating Critical: Scimitar Str +1`, `Epic Fortitude CON +1 (21)`
  # (task 4.31) — would also read `Great Dex +1 (23)`, which is Great
  # Dexterity taken once more with the score it left, so a name that makes a
  # feat with the word before it is not a bump.
  #
  # Task 4.36: the bump after a feat's name in three more shapes (249776,
  # 216553, 239740, 198965) — with the score it left after it (`Epic Weapon
  # Specialization Longbow +1 Dex (17)`), without the one (`Weapon
  # Specialization Kukri +Dex`, `Improved Critical +Con 18`), and in brackets
  # (`imp two weapon fighting (+dex)`). A sign or a one is what makes them a
  # bump: `Great Dex` alone after a name is not one.
  defp increase_shapes do
    [
      {~RX/^\+\s*1?\s*(?:to\s+)?(\p{L}{3,})\b\s*(.*)$/u, 0, 1},
      {~RX/^(\p{L}{3,})\s*\+\s*1\b\s*(.*)$/u, 0, 1},
      {~RX/^(.*?\S)\s*\+\s*1\s*(?:to\s+)?(\p{L}{3,})\b\s*(?:[\(\[]\s*\d{1,2}\s*[\)\]])?\.?$/u, 1,
       0},
      {~RX/^(.*?\S)\s+(\p{L}{3,})\s*\+\s*1\b\s*(?:[\(\[]\s*\d{1,2}\s*[\)\]])?\.?$/u, 1, 0},
      {~RX/^(.*?\S)\s+\+\s*(\p{L}{3,})\b\s*(?:[\(\[]\s*\d{1,2}\s*[\)\]]|\d{1,2})?\.?$/u, 1, 0},
      {~RX/^(.*?\S)\s*[\(\[]\s*\+\s*1?\s*(\p{L}{3,})\s*[\)\]]\.?$/u, 1, 0}
    ]
  end

  def increase_in(item, index) do
    Enum.find_value(increase_shapes(), fn {shape, ability_at, rest_at} ->
      case Regex.run(shape, item) do
        nil -> nil
        match -> increase(match, index, ability_at, rest_at)
      end
    end)
  end

  defp increase([_whole | groups], index, ability_at, rest_at) do
    word = Enum.at(groups, ability_at, "")
    rest = groups |> Enum.at(rest_at, "") |> String.trim()

    with key when is_binary(key) <- ability_key(word),
         {:ok, id} <- resolve(index.abilities, key),
         false <- ability_at > rest_at and names_feat?(index, rest, word) do
      {id, rest}
    else
      _ -> nil
    end
  end

  # Whether the text before the ability's word makes a feat's name with it.
  # A name read by the guess counts too (task 4.36, 213089): `GRT WIS (17)` is
  # the community's Great Wisdom with the score it left, and parted as `GRT`
  # and a score it lost the feat. The feat reader then reads it by the same
  # guess, and says so.
  #
  # `guess?` — asked where a score is parted off an item (`split_score/2`):
  # a bump written out (`increase/4`) is read without the guess, as it was.
  defp names_feat?(index, rest, word, guess? \\ false) do
    last = rest |> String.split(~RX/[\s:,;]+/u, trim: true) |> List.last("")

    Enum.any?([rest <> " " <> word, last <> " " <> word], fn name ->
      forms = name_forms(name)

      match?({kind, _} when kind in [:ok, :ambiguous], feat_by_forms(index, forms)) or
        (guess? and match?({:guess, _}, near_feat_by_forms(index, forms, false)))
    end)
  end

  # --------------------------------------------------------- skill purchases --

  # Three shapes of one purchase: ours (`Discipline +4 (4) x2`, the bracket is
  # the running total, the tail the price), a bare count (`Discipline 4`), and
  # CBC's chart (`Discipline(4)`, the bracket IS the ranks bought).
  #
  # ⚠️ A skill line comes here untrimmed of the spaces inside it, so the
  # patterns are written to read a run of spaces once (task 4.34; the guards
  # are explained at `Header`'s attributes).
  def skill_item(item) do
    text = String.trim(item)

    cond do
      # Both shapes end on a number, maybe in brackets, maybe with spaces
      # after it: a text that ends otherwise is neither, and is not read to
      # find out (task 4.34).
      not number_may_end?(text, ~c")") ->
        nil

      match = bare_count(text) ->
        [_, name, ranks] = match
        {String.trim(name), String.to_integer(ranks)}

      match = Regex.run(~RX/^(.+?)(?:(?<!\s)|(?<=^.))\s*\(\s*(\d+)\s*\)\s*(?:x\s*\d+)?$/u, text) ->
        [_, name, ranks] = match
        {String.trim(name), String.to_integer(ranks)}

      true ->
        nil
    end
  end

  # `~RX/^(.+?)(?:(?<!\s)|(?<=^.))\s*(?:\+\s*)?(\d+)\s*(?:\(\s*\d+\s*\)\s*)?(?:x\s*\d+\s*)?$/u`,
  # read in two parts (task 4.34): tried as it was, the name stopped at every
  # digit of a long number — `Tumble(99…9)` — and read the rest of the number
  # from each, a whole line of such purchases took seconds.
  #
  # The number ends where its run of digits ends (what may follow it starts
  # with no digit), and it starts where the run starts — the name is tried
  # shortest first, and with any character before the run the name can end
  # there — except for a text that opens with the run: then the name is its
  # first digit and the number the rest (`12` is a name `1` and 2 ranks, as
  # the one pattern read it).
  defp bare_count(text) do
    Regex.run(~RX/^(\d)(\d++)\s*(?:\(\s*\d+\s*\)\s*)?(?:x\s*\d+\s*)?$/u, text) ||
      Regex.run(
        ~RX/^(.+?)(?:(?<!\s)|(?<=^.))\s*(?:\+\s*)?(?<!\d)(\d+)\s*(?:\(\s*\d+\s*\)\s*)?(?:x\s*\d+\s*)?$/u,
        text
      )
  end

  def unspent?(name), do: Map.has_key?(@unspent_words, norm(name))
end
