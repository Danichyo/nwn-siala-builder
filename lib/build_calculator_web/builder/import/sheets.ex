defmodule BuildCalculatorWeb.Builder.Import.Sheets do
  @moduledoc """
  The numbers a post prints about the character: the ability score sheet,
  whose start is read into the build, and the totals — HP, BAB, AB, AC, the
  saves, the saves as a block of three lines — kept exactly as written for
  the comparison and never read into the build. What a printed total is when
  it is not this character's naked number (a companion's, a shape's, a buff's,
  rolled hit points) is said beside it, never dropped. A part of
  `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculatorWeb.Builder.Import.Names

  import BuildCalculatorWeb.Builder.Import.Names,
    only: [ability_key: 1, common_prefix: 2, norm: 1, save_name: 1]

  import BuildCalculatorWeb.Builder.Import.Scan, only: [add_all: 2]

  @ability_words Names.ability_words()

  # What a header over lines that are not this character's own says they are
  # (task 4.31) — a companion's, a shape's, a buff's (`aside/1`) — and
  # the header that says they are the naked ones after all.
  defp aside_kinds do
    [
      companion:
        ~RX/\bcompanions?\b|\bfamiliars?\b|\bsummon(?:s|ed)?\b|\bpets?\b|\bhenchm[ae]n\b|\bcohorts?\b/iu,
      form:
        ~RX/\bshapes?\b|\bshifted\b|\bpolymorph|\bwild\s*shape|\bforms?\b|\bdragon\s+(?:status|form|shape)/iu,
      buffed: ~RX/\bbuffed\b|\bbuffs?\b|\brag(?:e|ing)\b|\bsong\b/iu
    ]
  end

  defp naked_header,
    do: ~RX/\bno\s+buffs?\b|\bunbuffed\b|\bwithout\s+buffs?\b|\bnaked\b|\bbare\b/iu

  # A sheet written as point-buy sums from the minimum (`STR 8+6 +4/2 = 16`,
  # `DEX 8 + 6 = 14`): its lines are read as point-buy sums from a minimum a
  # race moved as well (a Dwarf's `CON 10 + 4 = 14`). Out of such a sheet a
  # sum from ten is where a score started (`INT 10 + 3 = 13`). The sheet so
  # far is the lines standing together above, and this one.
  def point_buy_sheet?(scan, line, index) do
    exact_point_buy?(line, index) or
      (scan.point_buy_at != nil and scan.point_buy_at == scan.position - 1)
  end

  def point_buy_mark(scan, line, index),
    do: if(point_buy_sheet?(scan, line, index), do: scan.position)

  defp exact_point_buy?(line, index), do: Regex.match?(index.point_buy_sum, line)

  # `STR: 16 (20)` — the template's shape — and the hand-written ones: `Str 16`,
  # `Str - 16`, `Strength 9`, `Char: 12 [13]`, `Str 14, Dex 20, Con 12` on one
  # line. The line has to START with a score's name, so `Intimidate 20` out of
  # a skill list and prose that mentions strength in passing are left alone —
  # or with a caption and a colon before a whole sheet of three scores and
  # more: `Starting Characteristics: STR:14, DEX:18, …` (task 4.31).
  #
  # `{scores, caption}`: the caption is the sheet's own, when the line gives
  # one (`abilities/3` reads the start from it).
  def ability_line(line, index) do
    case slash_scores(line) || named_scores(line, index) do
      nil -> captioned_scores(line, index)
      scores -> {scores, nil}
    end
  end

  defp captioned_scores(line, index) do
    with [_, caption, rest] <- Regex.run(~RX/^([^:\d]{2,40}?)\s*:\s*(\p{L}.*)$/u, line),
         [_ | _] = scores <- named_scores(rest, index),
         true <- length(Enum.uniq_by(scores, &elem(&1, 0))) >= 3 do
      {scores, caption}
    else
      _ -> nil
    end
  end

  defp slash_scores(line) do
    with [_, keys, values] <-
           Regex.run(~RX"^([A-Za-z]{3}(?:\s*/\s*[A-Za-z]{3})+)\s*:\s*(\S.*)$"u, line),
         names = split_ability_keys(keys),
         true <- Enum.all?(names, &(&1 in @ability_words)) do
      parts = String.split(values, "/")

      names
      |> Enum.with_index()
      |> Enum.flat_map(fn {name, ix} ->
        case score_values(Enum.at(parts, ix, "")) do
          nil -> []
          {start, final} -> [{name, start, final}]
        end
      end)
    else
      _ -> nil
    end
  end

  defp split_ability_keys(keys) do
    keys
    |> String.split("/")
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
  end

  # Where a score's name stands in the line: a word, and a number within the
  # next few characters. ⚠️ The word is looked for from its first letter only
  # (task 4.34): one that starts inside a word starts at its first letter as
  # well, and a line of one long word was read again from each of its letters.
  defp score_name, do: ~RX/(?:\G|(?<!\p{L}))(\p{L}+)\.?\s*(?:[:=\-–]\s*)?(?=\d)/u

  defp named_scores(line, index) do
    with [_, first] <- Regex.run(~RX/^(\p{L}+)\.?\s*(?:[:=\-–]\s*)?\d/u, line),
         key when is_binary(key) <- ability_key(first) do
      case score_segments(line, index) do
        [] -> nil
        scores -> scores
      end
    else
      _ -> nil
    end
  end

  # Each score's name with the text up to the next score's name — the value
  # and whatever the source wrote about it (`14 (6) to 26`, `8 + 6 = 14`).
  defp score_segments(line, index) do
    marks =
      for [{at, len}, {word_at, word_len}] <- Regex.scan(score_name(), line, return: :index),
          key = ability_key(binary_part(line, word_at, word_len)),
          key != nil,
          do: {key, at + len}

    ends = Enum.map(Enum.drop(marks, 1), fn {_key, from} -> from end) ++ [byte_size(line)]

    marks
    |> Enum.zip(ends)
    |> Enum.flat_map(fn {{key, from}, to} ->
      segment = binary_part(line, from, max(to - from, 0))

      case score_value(segment, index) do
        nil -> []
        {start, final, based?} -> [{key, start, final, based?}]
      end
    end)
    |> two_columns()
  end

  # `Str: 22     Str: 13 (base 08+05)` — the sheet written twice side by side,
  # the end and the start; the one marked `(base …)` is the start (task 4.31).
  # Anywhere else the first score of an ability is the one read.
  defp two_columns(scores) do
    scores
    |> Enum.group_by(&elem(&1, 0))
    |> then(fn by_key ->
      for {key, _start, _final, _based?} <- Enum.uniq_by(scores, &elem(&1, 0)) do
        case Map.fetch!(by_key, key) do
          [{_, a, final_a, false}, {_, b, _final_b, true}] -> {key, b, final_a || a}
          [{_, start, final, _based?} | _] -> {key, start, final}
        end
      end
    end)
  end

  # One score's value:
  #
  #   * `16`, `16 (20)`, `12 [13]` — the start, and where it ended up. A bracket
  #     below the start is not where it ended — `Str 14 (6) to 26` puts the
  #     points spent there (task 4.31);
  #   * `16/28`, `14 -> 28`, `16 to 32` — the start and the end;
  #   * `8 + 6 = 14`, `8 + 4 = 12 + 2 RDD = 14` — a point-buy sum: from the
  #     point-buy minimum (in a point-buy sheet, give or take the two a race
  #     moves it by — `point_buy_sheet?/3`), the first result is the start and
  #     a last one the end. A sum from any other number (`16 + 10 = 26`) is the
  #     start and the end.
  defp score_value(segment, index) do
    based? = Regex.match?(~RX/[\(\[]\s*base\b/iu, segment)

    with [_, first] <- Regex.run(~RX/^\s*(\d{1,3})(?!\d)/u, segment) do
      first = String.to_integer(first)

      results =
        Regex.scan(~RX/=\s*(\d{1,3})(?!\d)/u, segment)
        |> Enum.map(fn [_, n] -> String.to_integer(n) end)

      {start, final} =
        cond do
          results != [] and Regex.match?(~RX/^\s*\d{1,3}\s*\+/u, segment) ->
            if first == index.point_buy_min or
                 (index.point_buy_sheet? and abs(first - index.point_buy_min) <= 2),
               do: {hd(results), if(length(results) > 1, do: List.last(results))},
               else: {first, List.last(results)}

          true ->
            {first, stated_final(segment, first)}
        end

      {start, final, based?}
    else
      _ -> nil
    end
  end

  defp stated_final(segment, start) do
    arrow =
      Regex.run(
        ~RX"^\s*\d{1,3}\s*(?:[\(\[][^\)\]]*[\)\]]\s*)?(?:/|->|→|=>|\bto\b)\s*(\d{1,3})(?!\d)"iu,
        segment
      )

    bracket = Regex.run(~RX/^\s*\d{1,3}\s*[\(\[]\s*(\d{1,3})\s*[\)\]]/u, segment)

    cond do
      arrow ->
        String.to_integer(List.last(arrow))

      bracket && String.to_integer(List.last(bracket)) >= start ->
        String.to_integer(List.last(bracket))

      true ->
        nil
    end
  end

  # `16 (20)` — the first number is where the character started, the second,
  # when bracketed, where it ended up. A signed one (`16 (+2)`) is a modifier,
  # not the end.
  defp score_values(values) do
    case Regex.run(~RX/^\s*(\d{1,3})(?:\s*[\(\[]\s*(\d{1,3})\s*[\)\]])?/u, values) do
      [_, start] -> {String.to_integer(start), nil}
      [_, start, final] -> {String.to_integer(start), String.to_integer(final)}
      _ -> nil
    end
  end

  # `S: 8` / `D: 16 to 30` / `C: 14` / `W: 15 to 18` / `I: 14` / `CH: 8` — a
  # sheet written with letters (task 4.31). One letter is a score's name only
  # inside a run of six such lines that names all six scores, `C` and `Ch`
  # apart; a run that stops short is not a sheet, and its lines are listed as
  # lines we did not use.
  @letter_keys %{
    "s" => "str",
    "d" => "dex",
    "c" => "con",
    "i" => "int",
    "w" => "wis",
    "ch" => "cha",
    "cha" => "cha"
  }

  #
  # `14 STR` / `16 DEX` / `12 CON` — the number first (task 4.31; 63 posts) —
  # counts the same way: only a run of six lines that names all six scores is
  # a sheet (`14 Int` alone may be fourteen ranks of Intimidate).
  def letter_line(line, index) do
    number_first(line, index) || letter_first(line, index)
  end

  defp number_first(line, index) do
    with [_, value, word, rest] <-
           Regex.run(~RX/^(\d{1,2})\s*(?:[:=\-–]\s*)?(\p{L}{3,})\.?(?![\p{L}])\s*(.*)$/u, line),
         key when is_binary(key) <- ability_key(word),
         true <-
           rest == "" or Regex.match?(~RX"^(?:[\(\[].*|(?:/|->|→|=>|to)\s*\d{1,3}.*)$"iu, rest),
         {start, final, _based?} <- score_value(value <> " " <> rest, index) do
      {key, start, final}
    else
      _ -> nil
    end
  end

  defp letter_first(line, index) do
    with [_, letter, value] <- Regex.run(~RX/^(ch|cha|[sdciw])\s*[:=\-–]\s*(\d.*)$/iu, line),
         {:ok, key} <- Map.fetch(@letter_keys, String.downcase(letter)),
         {start, final, _based?} <- score_value(value, index),
         true <-
           Regex.match?(
             ~RX"^\d{1,3}(?:\s*(?:[\(\[][^\)\]]*[\)\]]|(?:/|->|→|=>|to)\s*\d{1,3}))*\s*$"iu,
             String.trim(value)
           ) do
      {key, start, final}
    else
      _ -> nil
    end
  end

  def letters(scan, score, number, line, cap \\ nil) do
    scan =
      if scan.letter_at == scan.position - 1,
        do: scan,
        else: %{flush_letters(scan) | letter_caption: scan.last_line}

    run = scan.letter_run ++ [{score, number, line}]
    keys = run |> Enum.map(fn {{key, _, _}, _, _} -> key end) |> Enum.uniq()

    if length(run) == length(@ability_words) and length(keys) == length(@ability_words) do
      scores = Enum.map(run, fn {score, _number, _line} -> score end)
      caption = scan.letter_caption
      abilities(%{scan | letter_run: [], letter_at: nil}, scores, caption, :whole, cap)
    else
      %{scan | letter_run: run, letter_at: scan.position}
    end
  end

  # A run of letter lines that did not make a sheet: listed, not swallowed.
  def flush_letters(%{letter_run: []} = scan), do: scan

  def flush_letters(scan) do
    unused = for {_score, number, line} <- scan.letter_run, do: {:ignored_line, number, line}
    add_all(%{scan | letter_run: [], letter_at: nil}, unused)
  end

  # Score lines that stand together are one sheet, and a post carries several:
  # the start, `Final Stats (BARE)`, the dragon form — or, before the
  # character's own, the stats of the shape it takes (`Death Slaad Lord has
  # the following stats: STR: 22…`). Neither the first sheet nor the last is
  # the start every time: a full sheet (all six scores) under a caption that
  # says it is the start — `STARTING ABILITIES:` below a `FINAL BUILD` sheet
  # (task 4.31) — is; else the first full one; without one the fullest (the
  # first of equals). Within a sheet the first score of each ability wins.
  #
  # A sheet whose caption says it is the end (`Final stats:`) is never the
  # start: its numbers are where the scores ended up, and they fill in the end
  # the start sheet did not write (`with_end/2`).
  #
  # A sheet's caption is its own (`Starting Characteristics: STR:14, …`) or the
  # line right above it.
  #
  # ⚠️ Which sheet is the start is decided once, after the whole text has been
  # read (`sheet_read/1`, task 4.34): deciding it again at every score line
  # walked every sheet so far, and a paste of score lines under captions of
  # their own took twenty seconds. While the text is read the blocks are kept
  # newest first, and the one thing asked of them — whether a start has been
  # printed at all (`untouched?/1`) — is the flag `printed_any?`, which says
  # exactly what `printed != %{}` would: a sheet `start_sheet/1` does not
  # set aside as an end one (`end_sheet?/1`) has a score. It never goes back
  # to false: a sheet's scores only grow, and a score with its end in it only
  # takes a sheet out of the end ones.
  #
  # `cap` — the ruleset's level cap, for a caption that names it (`Level 40
  # stats:`, `names_level?/2`).
  def abilities(scan, scores, caption, how \\ :line, cap \\ nil) do
    joins? =
      how == :line and scan.ability_at == scan.position - 1 and scan.ability_blocks != [] and
        caption == nil

    [current | earlier] =
      if joins?,
        do: scan.ability_blocks,
        else: [new_sheet(caption || scan.last_line, cap) | scan.ability_blocks]

    current =
      Enum.reduce(scores, current, fn {name, start, final}, acc ->
        %{acc | scores: Map.put_new(acc.scores, name, %{start: start, final: final})}
      end)

    %{
      scan
      | ability_blocks: [current | earlier],
        ability_at: scan.position,
        printed_any?: scan.printed_any? or (current.scores != %{} and not end_sheet?(current))
    }
  end

  @start_words ~w(start starting started initial initially base basic creation created beginning begin original chargen)
  @end_words ~w(final finally end ending ended finish finished total totals maxed current)

  # The caption's verdict is taken once, when the sheet opens: it is the one
  # part of the question that reads a whole line.
  defp new_sheet(caption, cap) do
    %{
      scores: %{},
      caption: caption,
      end_caption?:
        (caption_says?(%{caption: caption}, @end_words) or names_level?(caption, cap)) and
          not caption_says?(%{caption: caption}, @start_words)
    }
  end

  # `Level 40 Naked Stats:`, `Level 40 Abilities` (task 4.36, 122140; eight
  # posts of the corpus): a sheet captioned by the character's last level is
  # where the scores ended up, as `Final Stats:` is. The last level is the
  # ruleset's cap — a ladder shorter than the cap does not caption its end so.
  defp names_level?(caption, cap) when is_binary(caption) and is_integer(cap) do
    case Regex.run(~RX/\b(?:level|lvl|lv)\.?\s*(\d{1,2})\b/iu, caption) do
      [_, level] -> String.to_integer(level) == cap
      nil -> false
    end
  end

  defp names_level?(_caption, _cap), do: false

  # The test `start_sheet/1` sets end sheets aside by, with the caption's half
  # taken from `new_sheet/1`.
  defp end_sheet?(block),
    do: block.end_caption? and not Enum.any?(Map.values(block.scores), &(&1.final != nil))

  # The end of the pass: the start sheet, out of every sheet in the order of
  # the text.
  def sheet_read(scan) do
    {printed, caption} = scan.ability_blocks |> Enum.reverse() |> start_sheet()
    %{scan | printed: printed, printed_caption: caption}
  end

  defp start_sheet(blocks) do
    # `Starting Ability (allocated points upon creation) to Ending:` says both,
    # and is the start; so is a sheet that writes both ends itself, whatever
    # its caption — CBC captions `STR: 10 / DEX: 18 (30)` `Abilities(Final):`.
    {ends, others} = Enum.split_with(blocks, &end_sheet?/1)

    full = Enum.filter(others, &full_sheet?/1)

    chosen =
      Enum.find(full, &caption_says?(&1, @start_words)) || List.first(full) ||
        Enum.max_by(others, &map_size(&1.scores), fn -> nil end)

    # The end a buff, a shape or a companion reached is not the character's.
    ended =
      Enum.find(ends, fn block ->
        full_sheet?(block) and
          not Enum.any?(aside_kinds(), fn {_kind, words} ->
            Regex.match?(words, block.caption || "")
          end)
      end)

    case chosen do
      nil ->
        {%{}, nil}

      %{scores: scores, caption: caption} ->
        {with_end(scores, ended), caption}
    end
  end

  defp full_sheet?(block), do: map_size(block.scores) == length(@ability_words)

  defp with_end(scores, nil), do: scores

  defp with_end(scores, %{scores: ended}) do
    Map.new(scores, fn
      {key, %{final: nil} = score} ->
        case Map.get(ended, key) do
          %{start: final} -> {key, %{score | final: final}}
          nil -> {key, score}
        end

      pair ->
        pair
    end)
  end

  defp caption_says?(%{caption: nil}, _words), do: false

  defp caption_says?(%{caption: caption}, words) do
    caption
    |> String.downcase()
    |> String.split(~RX/[^a-z]+/, trim: true)
    |> Enum.any?(&(&1 in words))
  end

  @total_keys %{
    "hitpoints" => :hp,
    "hp" => :hp,
    "skillpoints" => :skill_points,
    "savingthrows" => :saves,
    "saves" => :saves,
    "bab" => :bab,
    "baseattack" => :bab,
    "ab" => :ab,
    "attackbonus" => :ab,
    "attacksperround" => :apr,
    "apr" => :apr,
    "ac" => :ac
  }

  @total_labels %{
    hp: "Hitpoints",
    skill_points: "Skillpoints",
    saves: "Saving Throws (Fort/Ref/Will)",
    bab: "BAB",
    ab: "AB",
    apr: "Attacks per round",
    ac: "AC"
  }

  # Read only to be shown back for comparison, so the value is kept exactly as
  # the source wrote it — `71 (naked 24)` and `+70/+55` alike. Nothing here is
  # converted to a number, because nothing here reaches the build.
  def totals_line(line) do
    with [_, key, value] <-
           Regex.run(
             ~RX"^([A-Za-z][A-Za-z0-9 ,/()\[\]\.\-+']*?)(?:(?<!\s)|(?<=^.))\s*:\s*(\S.*)$"u,
             line
           ),
         id when id != nil <- total_id(key) do
      total(id, String.trim(key), String.trim(value))
    else
      _ -> nil
    end
  end

  # `caveat` — what the source's number is when it is not this character's own
  # naked number: `{:aside, kind, header}` under a companion's, a shape's or a
  # buff's header, `{:rolled, marker}` when the post says its hit points were
  # rolled (task 4.31). Shown beside the row, never dropped.
  defp total(id, key, value) do
    %{id: id, label: Map.fetch!(@total_labels, id), key: key, value: value, caveat: nil}
  end

  # By whole words from the start of the caption, not by a prefix of letters:
  # `Abilities:` begins with the letters of `AB` and is not the attack bonus,
  # `Saving Throw bonuses:` is not the saves (task 4.8).
  #
  # A caption that narrows the number — `Saves vs spells`, `AB bonus vs evil` —
  # is a conditional extra, not the total, and is not compared either. One that
  # only says which total it is — `Base Max HP`, `Naked AC`, `Final Saves` —
  # names the same total (task 4.31).
  @total_qualifiers ~w(base max maximum maxed final total naked unbuffed)

  defp total_id(key) do
    words = key |> String.downcase() |> String.split(~RX/[^a-z]+/, trim: true)

    if Enum.any?(words, &(&1 in ~w(vs versus bonus bonuses))) do
      nil
    else
      # `Base Attack` is a key of its own before `Base` is a qualifier.
      Enum.find_value([words, Enum.drop_while(words, &(&1 in @total_qualifiers))], fn words ->
        Enum.find_value(1..3, fn count ->
          Map.get(@total_keys, words |> Enum.take(count) |> Enum.join())
        end)
      end)
    end
  end

  def take_total(scan, total, index) do
    {total, scan} = with_paragraph(scan, total, index)
    %{scan | totals: [total | scan.totals]}
  end

  # The caveat a total takes from where it stands: under the header of a
  # companion, a shape or a buff (`aside/2`) — or, task 4.36, under a caption
  # naming the starting values and not the final ones (`starting/1`).
  defp with_paragraph(scan, total, index) do
    {aside, scan} = paragraph_aside(scan, index)
    {caveated(total, aside), scan}
  end

  defp caveated(total, {kind, header}), do: %{total | caveat: {:aside, kind, header}}
  defp caveated(total, nil), do: starting(total)

  # `Saves start` over `Reflex 1` / `Fort 4` / `Will -1` (task 4.36, 223351):
  # the character at its first level, shown beside ours at its last as if the
  # two were one number. A caption that names the start and not the end says
  # so; `Saves ..start/end` names both, and its end is read
  # (`block_value/4`). The words are the start's own: `base`, which starts a
  # score sheet (`@start_words`), means unbuffed over the saves (`Saving
  # Throws (base)`).
  @start_only ~w(start starting started initial initially beginning begin)

  defp starting(total) do
    words = total.key |> String.downcase() |> String.split(~RX/[^a-z]+/, trim: true)

    if Enum.any?(words, &(&1 in @start_only)) and not Enum.any?(words, &(&1 in @end_words)),
      do: %{total | caveat: {:start, total.key}},
      else: total
  end

  # What the paragraph's header says, read once per paragraph (task 4.34): it
  # depends on nothing but the paragraph's top line and the lone line above
  # it, and a paragraph of five thousand totals under a long header read that
  # header five thousand times. `Scan.paragraphs/3` forgets it when a new
  # paragraph opens.
  defp paragraph_aside(%{aside: :unread} = scan, index) do
    aside = aside(scan, index)
    {aside, %{scan | aside: aside}}
  end

  defp paragraph_aside(scan, _index), do: {scan.aside, scan}

  # What the totals line stands under (task 4.31), the way the stand of task
  # 4.9 reads it: the top line of its own paragraph — `Dragon Status (…):`,
  # `With buffs:`, `final numbers (while raging, …)` — or, the line opening
  # the paragraph itself, a header alone in the paragraph right above it
  # (`Animal Companion` / ⏎ / `Ebon Panther` / `HP: 151`). A header is a
  # line of a dozen words at most with no number in it (or one that ends with
  # a colon); one that says the numbers are the naked ones (`With no buffs:`)
  # puts nothing aside. Anything further up is not read as a header over
  # these numbers — a list of cons that mentions buffs is not one.
  defp aside(scan, index) do
    Enum.find_value([scan.paragraph_top, scan.lone_above], fn
      nil -> nil
      header -> aside_kind(header, index)
    end)
  end

  # `own?` — the line is the caption of the saves block the total is read from
  # (`block_aside/4`), and so its header by definition.
  defp aside_kind(line, index, own? \\ false) do
    # A header, not a sentence: `Rage will boost these nicely.` over the saves
    # is a remark about them.
    header? =
      Regex.match?(~RX/^[^:\d]{1,80}:\s*$/u, line) or
        Regex.match?(~RX/^[^:]{1,80}\(.*\):\s*$/u, line) or
        bracket_after_colon?(line, own?) or
        (not Regex.match?(~RX/[\d:]/u, line) and not Regex.match?(~RX/[.!?]\s*$/u, line) and
           length(String.split(line, ~RX/\s+/u, trim: true)) <= 12)

    cond do
      not header? or Regex.match?(naked_header(), line) or natural_form?(line, index) ->
        nil

      kind =
          Enum.find_value(aside_kinds(), fn {kind, words} -> Regex.match?(words, line) && kind end) ->
        {kind, line |> String.trim_trailing(":") |> String.trim()}

      true ->
        nil
    end
  end

  # `Rakshasa form: (with barkskin, owl's insight, …)`, `Saves while in Dragon
  # Shape: (Spell save bonuses & feats)` — a header whose bracket stands after
  # its colon (task 4.36; 208957, 211147). Over other lines only when what
  # stands before the colon is not a total's caption itself: `AB: (raging)`
  # is a line of totals, and does not put its paragraph under a rage. A
  # block's own caption is the block's header whatever it says.
  defp bracket_after_colon?(line, own?) do
    case Regex.run(~RX/^([^:\d]{1,80}):\s*[\(\[][^\)\]]*+[\)\]]\s*$/u, line) do
      [_, head] -> own? or total_id(head) == nil
      nil -> false
    end
  end

  # `Dwarven Form` — the race's own shape, over the character's own numbers.
  defp natural_form?(line, index) do
    case Regex.run(~RX/^(\p{L}+)\s+form\b/iu, String.trim(line)) do
      [_, word] ->
        key = norm(word)

        String.length(key) >= 4 and
          Enum.any?(Map.keys(index.races), fn name ->
            String.length(name) >= 4 and common_prefix(key, name) >= 4
          end)

      _ ->
        false
    end
  end

  # `Saving Throws:` / `Fortitude: 23` / `Reflex: 22` / `Will: 33` — the saves
  # as three lines under a caption of their own (task 4.31; 241 posts of the
  # corpus give them no other way). Each line names one save, first number
  # read (`Fortitude: 30 (+6 against spells)`); a sum (`fortitude: 20 + 3 =
  # 23`), a line that names none, or a save named twice ends the block unread,
  # its lines listed as ones we did not use.
  # The caption may say more — `Saves at Level 40:`, `Saves (+8 vs. spells):`,
  # `Saves, add 4 vs spells`, `Saves: (vs. spells)` — but carries no values of
  # its own (after a colon a bracket at most, fewer than three numbers):
  # `Saves: Fort 21` is a line of totals.
  #
  # ⚠️ The runs in `@block_caption` are possessive (task 4.34): whatever a run
  # gives back cannot make the end of the line match, and giving it back one
  # character at a time read a run of spaces again from each of them.
  defp block_caption,
    do: ~RX/^(saving\s*throws?|saves?)\b[^:]*+(?::\s*+(?:\([^)]*\)[^:\d]*+)?)?\s*$/iu

  # Task 4.36: after the colon, the columns named in words, or a remark on
  # them — `Saves: Normal [Raged]`, `Saving throws: starting - ending`,
  # `Saves: [Find a cloak of fortification …]`: no digit outside brackets.
  # Such a line used to be a line of totals without a number, and stays one
  # when no three saves follow it (`legend_caption/3`, `flush_block/1`):
  # `Saves: Reflex is low, but the RDD immunity to fire will help` is a remark.
  defp legend_caption,
    do: ~RX/^(?:saving\s*throws?|saves?)\b[^:]*+:(?:[^:\d\(\[]|\([^)]*+\)|\[[^\]]*+\])*+$/iu

  # A line of the block opens with a save's name (`Names.save_name/1`).
  defp block_save,
    do: ~RX/^(\p{L}+)\b[^\d=\n]{0,12}?(?:[:\-–]|\s)\s*\+?(\d{1,2})(?!\d)([^=]*)$/u

  # The final column of a line under a caption naming the starting and the
  # final values: `/31`, `( 28)`, ` - 23` after the first number.
  defp end_column, do: ~RX"^\s*+(?:/|[\(\[]|[-–](?=\s))\s*+(-?\d{1,2})(?!\d)"u

  # The numbers a save line starts with, side by side: `24,26`, `31/50`,
  # `12 / 23 / 27`, `23 29 37`, `4 - 23`.
  defp leading_columns,
    do: ~RX"^\d{1,2}(?!\d)(?:\s*+(?:/|,|[-–](?=\s)|(?=\d))\s*+-?\d{1,2}(?!\d))*+"u

  # How a block's value names the saves, whatever the post wrote.
  @block_names %{fort: "Fortitude", ref: "Reflex", will: "Will"}

  def saves_block(scan, number, line, index) do
    cond do
      Regex.match?(block_caption(), line) and length(Regex.scan(~RX/\d+/u, line)) < 3 ->
        open_block(flush_block(scan), number, line, nil)

      fallback = legend_caption(scan, line, index) ->
        {total, scan} = fallback
        open_block(scan, number, line, total)

      block = scan.saves_block ->
        block_line(scan, block, number, line, index)

      true ->
        nil
    end
  end

  # The total the caption would have been as a line of totals, taken where it
  # stands (`with_paragraph/3`) — the reading it keeps when no block follows.
  # A block open above it ends first, as it did when the line was one.
  defp legend_caption(scan, line, index) do
    with true <- Regex.match?(legend_caption(), line),
         true <- length(Regex.scan(~RX/\d+/u, line)) < 3,
         %{} = total <- totals_line(line) do
      scan |> flush_block() |> with_paragraph(total, index)
    else
      _ -> nil
    end
  end

  defp open_block(scan, number, line, fallback) do
    %{
      scan
      | saves_block: %{
          caption: line,
          lines: [{number, line}],
          saves: [],
          at: scan.position,
          columns: start_end(line),
          first: nil,
          remark?: false,
          fallback: fallback
        }
    }
  end

  # `Saves ..start/end` / `Fort 5/31` — which column is the final one
  # (`block_value/4`): the caption names the start and the end, in this order
  # or the other.
  defp start_end(caption) do
    words = caption |> String.downcase() |> String.split(~RX/[^a-z]+/, trim: true)
    start = Enum.find_index(words, &(&1 in @start_words))
    ended = Enum.find_index(words, &(&1 in @end_words))

    cond do
      start == nil or ended == nil -> nil
      start < ended -> :start_end
      true -> :end_start
    end
  end

  defp block_line(scan, block, number, line, index) do
    cond do
      block.at != scan.position - 1 ->
        nil

      # `Saves ..` / `(All +4 Against spells)` / `Fort: 25.` (task 4.36,
      # 245653): a remark in brackets, the whole line, between the caption and
      # the first save — one.
      block.saves == [] and not block.remark? and
          Regex.match?(~RX/^[\(\[][^\)\]]*+[\)\]][.!]?$/u, line) ->
        block = %{
          block
          | lines: block.lines ++ [{number, line}],
            at: scan.position,
            remark?: true
        }

        %{scan | saves_block: block}

      true ->
        block_save_line(scan, block, number, line, index)
    end
  end

  defp block_save_line(scan, block, number, line, index) do
    with [_, {word_at, word_size}, value, {rest_at, rest_size}] <-
           Regex.run(block_save(), line, return: :index),
         id when id != nil <- save_name(binary_part(line, word_at, word_size)) do
      save = Map.fetch!(@block_names, id)
      rest = binary_part(line, rest_at, rest_size)

      if List.keymember?(block.saves, save, 0) do
        nil
      else
        {at, _size} = value

        block = %{
          block
          | lines: block.lines ++ [{number, line}],
            saves: block.saves ++ [{save, block_value(block, line, value, rest)}],
            at: scan.position,
            first: block.first || binary_part(line, at, byte_size(line) - at)
        }

        if length(block.saves) == 3,
          do: block_total(scan, block, index),
          else: %{scan | saves_block: block}
      end
    else
      _ -> nil
    end
  end

  # The number a save line gives the block (task 4.36). The first one, its
  # sign kept: a minus right before it, after a space or a colon, is the
  # number's own — `Fort    -1/19`, `Will -1` — while `Fort-24` and `Fort -
  # 24` only part the name from the number. Under a caption that names the
  # starting and the final values (`Saves ..start/end`, `Saving throws:
  # starting - ending`), the final one — `Fort 5/31`, `Fortitude: 5/ 30`,
  # `Fort: 3( 28)`, `Fortitude 4 - 23`. A line with one number keeps it.
  defp block_value(block, line, {at, size}, rest) do
    first = binary_part(line, at, size)
    first = if negative?(line, at), do: "-" <> first, else: first

    case block.columns == :start_end && Regex.run(end_column(), rest) do
      [_, ended] -> ended
      _ -> first
    end
  end

  defp negative?(line, at) do
    cond do
      at >= 2 and :binary.at(line, at - 1) == ?- -> :binary.at(line, at - 2) in ~c" \t:"
      at >= 4 and binary_part(line, at - 3, 3) == "–" -> :binary.at(line, at - 4) in ~c" \t:"
      true -> false
    end
  end

  defp block_total(scan, block, index) do
    key = block.caption |> String.trim_trailing(":") |> String.trim()
    value = Enum.map_join(block.saves, " / ", fn {save, value} -> "#{save}: #{value}" end)
    scan = %{scan | saves_block: nil}
    {header, legend} = block_header(block)

    total =
      :saves
      |> total(key, value)
      |> Map.put(:form, :block)
      |> caveated(block_aside(scan, block.caption, header, index))
      |> with_legend(legend)

    %{scan | totals: [total | scan.totals]}
  end

  # The paragraph's header over the block, as over any total (`aside/2`) —
  # except that the block's own caption is read by the part of it that names
  # the block, not the columns after the first (`block_header/1`).
  defp block_aside(scan, caption, header, index) do
    Enum.find_value([scan.paragraph_top, scan.lone_above], fn
      nil -> nil
      ^caption -> aside_kind(header, index, true)
      other -> aside_kind(other, index)
    end)
  end

  defp with_legend(total, nil), do: total
  defp with_legend(total, legend), do: Map.put(total, :legend, legend)

  # 🔴 The words of a block's caption that name its columns (task 4.36, the
  # lesson of 4.33: a condition in a block's caption describes the columns
  # after the first). `Saves, buffed (vs. spells, buffed vs. spells)` over
  # `Fort: 24,26 (34,38)` is not a buffed block: "buffed" names its second
  # column. The caption is read so only where the text pairs its names with
  # the columns one to one:
  #
  #   * its parts — cut at `/`, `,`, ` - ` outside brackets — are as many as
  #     the numbers a save line starts with, two or more: `Saves normal/buffed`
  #     over `Fort 31/50`;
  #   * two brackets and more, of the kinds and in the order of the bracketed
  #     numbers on the line: `Saves (vs spells)[Bard Song]` over `Fort: 25
  #     (34)[36]`, `Saves (CoT Bonus)[vs. spells]` over `Fort: 33 (46)[52]`;
  #   * its one bracket cut at `/` or `,` into as many parts as the numbers
  #     the line starts with: `Saves: (Base/+CHA/vs Spells)` over `Fort 12 /
  #     23 / 27`.
  #
  # `{header, legend}`: the header names the block — its first column — and
  # is what `aside_kind/3` reads; the legend is the caption, which the
  # comparison then quotes: the first column is shown, and which one is the
  # total only the caption says. Nothing is guessed: `Saves (CoT Bonus)` puts
  # the class's bonus in the second column, `Saves (vs spells)` a condition.
  #
  # ⚠️ One bracket over one bracketed number is NOT read so. `Saves (Buffed)`
  # over `Fort 33 (41)` names the whole block (its first column is four above
  # the naked save), `Saves (fully buffed)` over `Fort 19 (21)` names the
  # bracket — and the text is the same. Such a caption stays the header.
  #
  # A caption naming the start and the end has its final column read
  # (`block_value/4`): nothing is left for a legend to say.
  defp block_header(%{columns: columns, caption: caption}) when columns != nil,
    do: {caption, nil}

  defp block_header(%{first: first, caption: caption}) do
    plain = leading_count(first)
    numbered = for {kind, true, _from, _to, _inner} <- top_groups(first), do: kind

    groups =
      for {kind, _numbered?, from, to, inner} <- top_groups(caption), do: {kind, from, to, inner}

    parts = outside_parts(caption, groups)
    inner = one_bracket_parts(caption, groups)

    cond do
      plain >= 2 and length(parts) == plain ->
        {hd(parts), caption}

      length(groups) >= 2 and Enum.map(groups, &elem(&1, 0)) == numbered ->
        {without_groups(caption, groups), caption}

      plain >= 2 and inner != nil and length(inner) == plain ->
        {without_groups(caption, groups) <> " " <> hd(inner), caption}

      true ->
        {caption, nil}
    end
  end

  defp leading_count(text) do
    case Regex.run(leading_columns(), text) do
      [run] -> length(Regex.scan(~RX/\d+/u, run))
      nil -> 0
    end
  end

  # The brackets of a text at the top level, `{kind, numbered?, from, to,
  # inner}`: its opening byte, whether a number opens what it holds, its span,
  # and where what it holds ends (its closing byte, or the end of the text for
  # one that never closes). Nested brackets of any kind are inside it. One walk
  # over the bytes (the brackets are ASCII).
  defp top_groups(text), do: top_groups(text, 0, 0, nil, [])

  defp top_groups(text, at, _depth, open, found) when at >= byte_size(text) do
    found = if open, do: [group(text, open, at, at) | found], else: found
    Enum.reverse(found)
  end

  defp top_groups(text, at, depth, open, found) do
    byte = :binary.at(text, at)

    cond do
      byte in ~c"([<" and depth == 0 ->
        top_groups(text, at + 1, 1, at, found)

      byte in ~c"([<" ->
        top_groups(text, at + 1, depth + 1, open, found)

      byte in ~c")]>" and depth == 1 ->
        top_groups(text, at + 1, 0, nil, [group(text, open, at, at + 1) | found])

      byte in ~c")]>" and depth > 1 ->
        top_groups(text, at + 1, depth - 1, open, found)

      true ->
        top_groups(text, at + 1, depth, open, found)
    end
  end

  defp group(text, from, inner, to) do
    inside = binary_part(text, from + 1, inner - from - 1)
    {:binary.at(text, from), Regex.match?(~RX/^\s*+\d/u, inside), from, to, inner}
  end

  # The text cut at `/`, `,` and a spaced dash outside the brackets, the empty
  # pieces dropped.
  defp outside_parts(text, groups) do
    cuts = text |> :binary.matches(["/", ",", " - ", " – "]) |> outside(groups)

    {parts, last} =
      Enum.reduce(cuts, {[], 0}, fn {at, size}, {parts, from} ->
        {[binary_part(text, from, at - from) | parts], at + size}
      end)

    [binary_part(text, last, byte_size(text) - last) | parts]
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # The cuts that stand outside every bracket: both lists are in the order of
  # the text, so one walk over the two (a check of every cut against every
  # bracket was quadratic on a caption of brackets and slashes).
  defp outside([], _groups), do: []
  defp outside(cuts, []), do: cuts

  defp outside([{at, _size} | _] = cuts, [{_kind, _from, to, _inner} | groups]) when to <= at,
    do: outside(cuts, groups)

  defp outside([{at, _size} = cut | cuts], [{_kind, from, _to, _inner} | _] = groups)
       when at < from,
       do: [cut | outside(cuts, groups)]

  defp outside([_inside | cuts], groups), do: outside(cuts, groups)

  defp one_bracket_parts(text, [{_kind, from, _to, inner}]) do
    text
    |> binary_part(from + 1, inner - from - 1)
    |> String.split(["/", ","])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp one_bracket_parts(_text, _groups), do: nil

  defp without_groups(text, groups) do
    {kept, last} =
      Enum.reduce(groups, {[], 0}, fn {_kind, from, to, _inner}, {kept, at} ->
        {[kept, binary_part(text, at, from - at), " "], to}
      end)

    [kept, binary_part(text, last, byte_size(text) - last)]
    |> IO.iodata_to_binary()
    |> String.replace(~RX/\s+/u, " ")
    |> String.trim()
  end

  # A block that did not come to three saves: its lines are listed, as any line
  # we did not use — but for a caption that names its columns in words, which
  # is the line of totals it was before task 4.36 (`legend_caption/3`).
  def flush_block(%{saves_block: nil} = scan), do: scan

  def flush_block(%{saves_block: %{fallback: %{} = total, lines: [_caption | rest]}} = scan) do
    unused = for {number, line} <- rest, do: {:ignored_line, number, line}
    add_all(%{scan | saves_block: nil, totals: [total | scan.totals]}, unused)
  end

  def flush_block(%{saves_block: block} = scan) do
    unused = for {number, line} <- block.lines, do: {:ignored_line, number, line}
    add_all(%{scan | saves_block: nil}, unused)
  end

  # The post says its hit points were rolled, not maxed (task 4.31): a die per
  # level (`Hitpoint dice: 8`, `Hitpoint dice: 4`, …) or a character sheet
  # exported from a saved game (`exported using NWN Tool`). Its `Hit Points:`
  # is shown beside our maximum with that said, not as a disagreement.
  def rolled_marker(body) do
    dice = Regex.scan(~RX/^[ \t]*hit\s*points?\s*dice\s*:\s*\d+/imu, body)

    cond do
      length(dice) >= 2 ->
        dice |> hd() |> hd() |> String.trim()

      found = Regex.run(~RX/exported\s+using\s+NWN\s*Tool[^\n]*/iu, body) ->
        found |> hd() |> String.trim()

      true ->
        nil
    end
  end

  def rolled_totals(totals, nil), do: totals

  def rolled_totals(totals, marker) do
    Enum.map(totals, fn
      %{id: :hp, caveat: nil} = total -> %{total | caveat: {:rolled, marker}}
      total -> total
    end)
  end
end
