defmodule BuildCalculatorWeb.Builder.Import.Ladder do
  @moduledoc """
  The ladder: which numbered lines are levels and which are a level's skill
  purchases, where a level line's class ends and its contents begin
  (`class_head/2`), and — once the whole text has been seen — which numbered
  list is the ladder and how far it reads (`ladder_block/1`, `ladder/3`). A
  part of `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculator.FeatListTokenizer

  import BuildCalculatorWeb.Builder.Import.LevelTail,
    only: [increase_in: 2, inline_skill: 2, note?: 1, skill_item: 1, split_extras: 1, unspent?: 1]

  import BuildCalculatorWeb.Builder.Import.Names,
    only: [
      ability_key: 1,
      collapse: 1,
      count_below: 2,
      grapheme_starts: 1,
      fuzzy_class: 2,
      fuzzy_class_chars: 0,
      named_class: 2,
      norm: 1,
      prefix_class: 2,
      resolve: 2,
      resolve_class: 2,
      resolve_class: 3,
      resolve_skill: 2,
      tok_text: 1
    ]

  import BuildCalculatorWeb.Builder.Import.Scan, only: [add: 2]

  # How a level is numbered, from the template's `01:` to what people type:
  # `1.`, `3)`, `1 -`, `1-`, `1 BARD`, `Level 1:`, `Lvl. 2`, `L1 -`, `(01)`,
  # `[1]`. Two shapes are refused on purpose: a range (`1-6) Bard`, `1 - 20th
  # level`) is not one level, and `1.8 damage` or `20:24 posts` is not a level
  # at all.
  defp numbered_shapes do
    [
      ~RX/^[\(\[]\s*(\d{1,3})\s*[\)\]]\s*[:.)\-–—]?\s*(.*)$/u,
      ~RX/^(?:level|lvl|lev|lv|l)\.?\s*(\d{1,3})(?!\d)\s*[:.)\]\-–—]*\s*(.*)$/iu,
      ~RX/^(\d{1,3})\s*[:.)\]](?!\d)\s*(.*)$/u,
      ~RX/^(\d{1,3})\s*[-–—]+(?!\s*\d)\s*(.*)$/u,
      ~RX/^(\d{1,3})\s+(?=\p{L})(.*)$/u
    ]
  end

  def numbered_line(line) do
    Enum.find_value(numbered_shapes(), fn shape ->
      with [_, number, rest] <- Regex.run(shape, line),
           {level, ""} <- Integer.parse(number) do
        {level, String.trim(rest)}
      else
        _ -> nil
      end
    end)
  end

  # A numbered line is a level or a level's skill purchases, and which one is
  # read off the line itself, not off the header above it — headers are named a
  # dozen ways and often missing (task 4.8: CBC's `Skills by level` chart
  # arrived as a second ladder and wiped the first).
  #
  # A class read for sure (`{:ok, _}`) makes a level. Otherwise a line whose
  # first item is `Skill(N)`, `Skill +N (M)` or `Skill N` and names a skill is
  # skill purchases — `Disc(4)` would otherwise be read, fuzzily, as Red dragon
  # disciple. Under a skill guide header the scales tip the other way: a line
  # is a level there only when its class is sure and its first item is not a
  # skill.
  def numbered_entry(scan, {_level, ""}, number, line, _index),
    do: add(scan, {:ignored_line, number, line})

  def numbered_entry(scan, {level, rest}, number, line, index) do
    head = rest |> class_head(index) |> tab_cells(rest, index)
    skills? = skill_line?(rest, index)

    cond do
      scan.section == :skill_guide and (skills? or not sure?(head)) ->
        skill_line(scan, level, rest, number, line)

      sure?(head) ->
        level_line(scan, level, head, number, line)

      skills? ->
        skill_line(scan, level, rest, number, line)

      true ->
        level_line(scan, level, head, number, line)
    end
  end

  defp sure?(%{class: {:ok, _id}}), do: true
  defp sure?(_head), do: false

  defp level_line(scan, level, head, number, line) do
    {block, run} = place_level(scan.level_run, level, class_like?(head))

    entry = %{
      level: level,
      block: block,
      number: number,
      position: scan.position,
      line: line,
      class_text: head.text,
      extras: head.extras,
      class: head.class,
      fallback: head.fallback,
      ladder_shaped?: head.ladder_shaped?
    }

    %{scan | level_lines: [entry | scan.level_lines], level_run: run}
  end

  defp skill_line(scan, level, rest, number, line) do
    {block, run} = next_run(scan.skill_run, level)
    items = rest |> split_items() |> Enum.flat_map(&List.wrap(skill_item(&1)))
    entry = %{level: level, block: block, number: number, line: line, items: items}
    %{scan | skill_lines: [entry | scan.skill_lines], skill_run: run}
  end

  # A numbered list goes on while its numbers rise; a number that does not
  # rise starts the next list — the ladder, CBC's skill chart, a variant and a
  # list of notes all start again from 1.
  defp next_run(nil, level), do: {0, {0, level}}
  defp next_run({block, last}, level) when level > last, do: {block, {block, level}}
  defp next_run({block, _last}, level), do: {block + 1, {block + 1, level}}

  # For level lines one more thing: only a line that names a class (or states a
  # class's level) may start a list or jump ahead in it. Any other numbered
  # line joins the list only as its very next number — a level we cannot read,
  # which then stops the ladder honestly — and is otherwise a stray: `4
  # Intimidate` between levels 10 and 11 must not cut the ladder in two, and
  # `0 leftover` above it must not become its first level. A stray has no list
  # (`nil`) and is listed as a line we did not use.
  defp place_level(run, level, _class_like?) when level < 1, do: {nil, run}
  defp place_level(run, level, true), do: next_run(run, level)
  defp place_level(nil, 1, false), do: {0, {0, 1}}

  defp place_level({block, last}, level, false) when level == last + 1,
    do: {block, {block, level}}

  defp place_level(run, _level, false), do: {nil, run}

  defp class_like?(%{class: {kind, _}}) when kind in [:ok, :guess, :ambiguous], do: true
  defp class_like?(%{ladder_shaped?: shaped?}), do: shaped?

  def split_items(text) do
    text
    |> String.split(~RX/[,;]/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # ------------------------------------------------------------ class heads --

  # Where a level line's class ends and the level's contents begin. The shapes
  # that SAY where the class ends come first — `Fighter(1): …`, `(druid 1) - …`,
  # `Fighter 1 - …`, `Rogue1`, `Bard: …`, `BARD - …` — and are read as they
  # stand.
  #
  # The first three carry the class's own level (`Fighter(1)`, `Rogue1`) —
  # a number beside a short token is what makes `CL1` or `SO(1)` a class and
  # not a word, so only there may a two-letter token go to the fuzzy guess.
  # A dash before the level parts it from the class as a slash does: `(24)
  # Asn -14-⇥Great Dex` (task 4.36, 229497) — kept in the class's text, the
  # dash hid `Asn` from the guess, and `14- Great Dex` became a feat's name.
  defp numbered_heads do
    [
      ~RX/^(.+?)\s*\(\s*\d{1,2}\s*\)\s*[:.,;\-–—>]*\s*(.*)$/u,
      ~RX/^\(\s*([^()\d]+?)\s*\d{1,2}\s*\)\s*[:.,;\-–—>]*\s*(.*)$/u,
      ~RX"^(\D+?)\s*(?:/|[-–—](?=\s*\d))?\s*\d{1,2}(?!\d)\s*[:.,;\-–—>]*\s*(.*)$"u
    ]
  end

  defp strict_heads do
    [
      ~RX/^\(\s*([^()\d]+?)\s*\)\s*[:.,;\-–—>]*\s*(.*)$/u,
      ~RX/^([^:]+?)\s*:\s*(.*)$/u,
      ~RX/^(.+?)\s+[-–—>]+\s*(.*)$/u
    ]
  end

  # The looser ones — `Rogue, lightning reflexes`, `RDD (+1 AC)` — and a class
  # followed by the level's contents with nothing between (`Monk Blind Fight`,
  # `(1) Monk		Dodge`) count only when what follows reads as a level's
  # contents: a feat, a bump, a note in brackets. `1. Paladin levels give you
  # divine grace` is prose that starts with a class, not a level.
  defp loose_heads do
    [
      ~RX/^([^,;]+?)\s*[,;]\s*(.*)$/u,
      ~RX/^([^(]+?)\s*(\(.*)$/u
    ]
  end

  # A sure reading anywhere beats a guess anywhere: the guess tier is fuzzy,
  # and a guess made early would shadow a plain name further on.
  #
  # `ladder_shaped?` — the line states a class's own level (`Illusionist(3)`,
  # `Fighter1/Monk1`), so it belongs to the ladder even when the class is not
  # one we know: the ladder stops there rather than ends (`ladder/4`).
  defp class_head(rest, index) do
    text = rest |> collapse() |> table_cells()

    if running_totals?(text, index) do
      case running_split(text, index) do
        {pairs, extras} ->
          %{
            text: text,
            extras: extras,
            class: {:running, pairs},
            fallback: nil,
            ladder_shaped?: true
          }

        nil ->
          %{text: text, extras: "", class: :error, fallback: nil, ladder_shaped?: true}
      end
    else
      # The heads the line is shaped as, then the runs of words it opens with
      # (`word_heads/2`), asked in that order at every tier — the one list
      # they used to be, cut in two so the runs of words can be asked a
      # question once for every head that must answer it the same.
      shaped = head_candidates(text)
      words = word_heads(text, index)

      head =
        first_reading(shaped, index, false, &match?({:ok, _}, &1)) ||
          first_word_reading(words, index, false, &match?({:ok, _}, &1)) ||
          first_reading(shaped, index, true, &match?({:guess, _}, &1)) ||
          first_word_reading(words, index, true, &match?({:guess, _}, &1)) ||
          first_reading(shaped, index, true, &match?({:ambiguous, _}, &1)) ||
          first_word_reading(words, index, true, &match?({:ambiguous, _}, &1)) ||
          unread_head(text)

      head
      |> Map.put(:fallback, if(head.class == :error, do: bare_class(words, index)))
      |> Map.put(:ladder_shaped?, Enum.any?(shaped, &match?({_, _, :numbered}, &1)))
    end
  end

  # A line that opens with a class's name, whatever follows it. Not enough to
  # make a line a level by itself — prose starts with a class's name as often
  # as a ladder does — but inside the list already chosen as the ladder it is:
  # there `Monk Lighning Reflexes` is a level of Monk with a misspelt feat,
  # which is then reported, not a reason to stop the ladder (`settle/1`).
  #
  # ⚠️ The NAME, whole — as written, as the community's shorthand (`RDD`) or
  # in the plural. A shortened name or a guess only for the first word alone
  # (`Sorc Maximise Spell`, `SD Great Dex I`), and a shortened one only when
  # the text does not go on spelling the class out: `Champion of Kord(1)`, a
  # class the author renamed, must stay unread rather than become Champion of
  # Torm by its first two words.
  #
  # A head's name is asked once for its group (`word_group/2`): the heads of a
  # group name the same class or none.
  defp bare_class(nil, _index), do: nil

  defp bare_class(heads, index) do
    {found, _named} =
      Enum.reduce_while(heads.order, {nil, %{}}, fn taken, {nil, named} ->
        group = word_group(heads, taken)

        {class, named} =
          remembered(named, group, fn -> named_class(index, head_text(heads, group)) end)

        case class do
          {:ok, id} ->
            {class_text, extras, _how} = word_head(heads, taken)
            {:halt, {%{text: class_text, extras: extras, class: {:ok, id}}, named}}

          _ ->
            {:cont, {nil, named}}
        end
      end)

    found || first_word_class(word_head(heads, List.last(heads.order)), index)
  end

  defp remembered(memo, key, fun) do
    case memo do
      %{^key => value} ->
        {value, memo}

      _ ->
        value = fun.()
        {value, Map.put(memo, key, value)}
    end
  end

  defp first_word_class({word, extras, _how}, index) do
    key = norm(word)
    next = extras |> String.split(~RX/[^\p{L}]+/u, trim: true) |> List.first("") |> norm()

    class =
      case prefix_class(index, key) do
        {:ok, id} -> if spells_on?(index, id, key, next), do: :error, else: {:ok, id}
        _ -> if guessable?(word), do: fuzzy_class(index, word), else: :error
      end

    if match?({kind, _} when kind in [:ok, :guess], class),
      do: %{text: word, extras: extras, class: class}
  end

  # Whether the word after a shortened class name carries on spelling that
  # name (`Champion` + `of` for `Champion of Torm`).
  defp spells_on?(_index, _id, _key, ""), do: false

  defp spells_on?(index, id, key, next) do
    case Enum.find(index.class_names, &(&1.id == id)) do
      %{key: full} -> String.starts_with?(String.replace_prefix(full, key, ""), next)
      nil -> false
    end
  end

  # `12⇥DD⇥Weapon Focus⇥Con` — a table whose columns a tab parts (task 4.36,
  # 197661): collapsed into a space, the tab glued the feat and the bump into
  # one name (`Weapon Focus Con`). The line is read again with every tab
  # parting two items, as a comma does, and that reading is taken only when
  # it finds the same class as the plain one: the tab then stood among the
  # level's contents. Anywhere else — a class and its level, a skill chart's
  # `8⇥WM⇥08: Discipline(2)` — the plain reading stands, and so does the text
  # an issue quotes. The tabs are cut by hand, not by a pattern of the
  # spaces around them: a run of spaces is read once.
  defp tab_cells(head, rest, index) do
    with true <- String.contains?(rest, "\t"),
         {kind, _} = class when kind in [:ok, :guess] <- head.class,
         cells =
           rest
           |> String.split("\t")
           |> Enum.map(&String.trim/1)
           |> Enum.reject(&(&1 == ""))
           |> Enum.join(", "),
         %{class: ^class} = tabbed <- class_head(cells, index) do
      tabbed
    else
      _ -> head
    end
  end

  # `01. MONK | Dodge | Tumble 4` — a ladder drawn as a table: the first bar
  # ends the class, the others part the cells.
  defp table_cells(text) do
    case String.split(text, "|", parts: 2) do
      [class, cells] -> collapse(class <> ": " <> String.replace(cells, "|", ","))
      [_whole] -> text
    end
  end

  # `{class_text, extras, how}`: `:numbered` and `:strict` read as they stand
  # (only `:numbered` lets a two-letter token be guessed), `:loose` only when
  # the extras look like a level's contents, and a run of words — `:word`, or
  # `:word_fuzzy` when it is one word or the whole line and so may be guessed —
  # under the same condition as `:loose`.
  defp head_candidates(text) do
    shaped(numbered_heads(), text, :numbered) ++
      shaped(strict_heads(), text, :strict) ++
      shaped(loose_heads(), text, :loose)
  end

  defp shaped(shapes, text, how) do
    Enum.flat_map(shapes, fn shape ->
      case split_head(shape, text) do
        {class_text, extras} -> [{class_text, extras, how}]
        nil -> []
      end
    end)
  end

  defp split_head(shape, text) do
    case Regex.run(shape, text) do
      [_, class_text, extras] -> {String.trim(class_text), String.trim(extras)}
      _ -> nil
    end
  end

  # The runs of words a line opens with, as heads: `{class_text, extras, how}`
  # for the first `taken` words, from the longest down (`word_head/2`), `how`
  # `:word`, or `:word_fuzzy` when it is one word or the whole line and so may
  # be guessed. Read under the same condition as `:loose` (`first_reading/4`).
  #
  # ⚠️ Task 4.34, three things, none of them a change in what is read:
  #
  #   * only the heads that can still name a class: a run with more letters
  #     than any class's key has (`index.class_letters`, the bound is argued at
  #     `Names`) names none, and every reader of these heads asks just that —
  #     a line of sixteen thousand words made sixteen thousand heads. Two stay
  #     whatever their length: the one-word head, which `bare_class/2` reads by
  #     its place, and the whole run when nothing follows it and it is short
  #     enough to be guessed (`fuzzy_class/2` counts graphemes, and a grapheme
  #     of Hangul holds any number of letters);
  #   * a head is the text's first bytes, and what follows it is cut where
  #     `String.slice/2` would cut it — after as many graphemes as the head
  #     has (`Names.grapheme_starts/1`) — instead of being joined and sliced
  #     anew for every head;
  #   * the heads of a group ask their questions once (`word_group/2`,
  #     `first_word_reading/4`).
  defp word_heads(text, index) do
    case Regex.run(~RX/^\p{L}[\p{L}' ]*/u, text) do
      [run] ->
        words = String.split(run, " ", trim: true)
        count = length(words)
        reach = within_letters(words, index.class_letters)
        {_table, _keys, by_first} = index.feat_dictionary

        heads = %{
          text: text,
          words: words,
          plain?: not String.contains?(run, "  "),
          ends: word_ends(words),
          graphemes: grapheme_starts(text),
          groups: word_groups(words),
          # `extras_like?/2` reads a rest that opens with `'` the same however
          # many `' ` open it — unless a feat's name in the dictionary does.
          apostrophes_read_alike?: not Map.has_key?(by_first, ?'),
          order: []
        }

        whole =
          with true <- reach < count,
               {class_text, "", _how} <- word_head(heads, count),
               true <- String.length(class_text) <= fuzzy_class_chars() do
            [count]
          else
            _ -> []
          end

        %{heads | order: whole ++ Enum.to_list(reach..1//-1)}

      _ ->
        nil
    end
  end

  defp word_head(heads, taken) do
    class_text = head_text(heads, taken)

    rest =
      if heads.plain? do
        from =
          case count_below(heads.graphemes, byte_size(class_text)) do
            n when n < tuple_size(heads.graphemes) -> elem(heads.graphemes, n)
            _ -> byte_size(heads.text)
          end

        binary_part(heads.text, from, byte_size(heads.text) - from)
      else
        String.slice(heads.text, String.length(class_text)..-1//1)
      end

    extras = String.trim(rest)
    {class_text, extras, if(taken == 1 or extras == "", do: :word_fuzzy, else: :word)}
  end

  # The first `taken` words as the text has them: its first bytes, when the
  # words stand one space apart.
  defp head_text(%{plain?: true} = heads, taken),
    do: binary_part(heads.text, 0, elem(heads.ends, taken - 1))

  defp head_text(heads, taken), do: heads.words |> Enum.take(taken) |> Enum.join(" ")

  defp word_ends(words) do
    words
    |> Enum.map_reduce(-1, fn word, stop ->
      {stop + 1 + byte_size(word), stop + 1 + byte_size(word)}
    end)
    |> elem(0)
    |> List.to_tuple()
  end

  # A head's group is its last word with a letter in it. The heads of a group
  # differ by words of apostrophes only, which `norm/1` drops and `singular`
  # leaves alone: they name the same class or none (task 4.34).
  defp word_groups(words) do
    words
    |> Enum.with_index(1)
    |> Enum.map_reduce(1, fn {word, at}, group ->
      group = if String.replace(word, "'", "") == "", do: group, else: at
      {group, group}
    end)
    |> elem(0)
    |> List.to_tuple()
  end

  defp word_group(heads, taken), do: elem(heads.groups, taken - 1)

  # The word after the head is apostrophes only: the head's rest opens with `'`.
  defp opens_with_apostrophes?(heads, taken),
    do:
      taken < tuple_size(heads.groups) and
        elem(heads.groups, taken) == elem(heads.groups, taken - 1)

  # `first_reading/4` for the runs of words. A class is asked once for each
  # group, and the rest once for each group of heads it opens the same way.
  # When guessing, only the heads a guess is allowed of are asked
  # (`may_guess?/2`: the one-word head and the whole run) — as any head is.
  defp first_word_reading(nil, _index, _fuzzy?, _wanted?), do: nil

  defp first_word_reading(heads, index, true, wanted?) do
    heads.order
    |> Enum.map(&word_head(heads, &1))
    |> Enum.filter(&match?({_, _, :word_fuzzy}, &1))
    |> first_reading(index, true, wanted?)
  end

  defp first_word_reading(heads, index, false, wanted?) do
    {found, _asked} =
      Enum.reduce_while(heads.order, {nil, %{}}, fn taken, {nil, asked} ->
        group = word_group(heads, taken)

        {class, asked} =
          remembered(asked, {:class, group}, fn ->
            resolve_class(index, head_text(heads, group), false)
          end)

        if wanted?.(class) do
          {class_text, extras, _how} = word_head(heads, taken)

          key =
            if heads.apostrophes_read_alike? and opens_with_apostrophes?(heads, taken),
              do: {:rest, group},
              else: {:rest_of, taken}

          {like?, asked} = remembered(asked, key, fn -> extras_like?(extras, index) end)

          if like?,
            do: {:halt, {%{text: class_text, extras: extras, class: class}, asked}},
            else: {:cont, {nil, asked}}
        else
          {:cont, {nil, asked}}
        end
      end)

    found
  end

  # How many of the words hold no more letters than `limit`; one at least.
  defp within_letters(words, limit) do
    words
    |> Enum.reduce_while({0, 0}, fn word, {taken, letters} ->
      letters = letters + letters_in(word)
      if letters > limit, do: {:halt, {taken, letters}}, else: {:cont, {taken + 1, letters}}
    end)
    |> elem(0)
    |> max(1)
  end

  # A word of the run is letters and `'`: its letters are its characters but
  # the apostrophes — characters, not graphemes, as `norm/1` keeps them.
  defp letters_in(word), do: word |> String.replace("'", "") |> String.to_charlist() |> length()

  # The class is asked before the rest of the line is (task 4.34): both are
  # plain questions, and the second one reads the rest of the line.
  defp first_reading(candidates, index, fuzzy?, wanted?) do
    Enum.find_value(candidates, fn {class_text, extras, how} ->
      with true <- class_text != "",
           true <- fuzzy? == false or may_guess?(how, class_text),
           class = resolve_class(index, class_text, fuzzy?),
           true <- wanted?.(class),
           true <- how in [:numbered, :strict] or extras_like?(extras, index) do
        %{text: class_text, extras: extras, class: class}
      else
        _ -> nil
      end
    end)
  end

  defp may_guess?(:numbered, _class_text), do: true

  defp may_guess?(how, class_text),
    do: how in [:strict, :loose, :word_fuzzy] and guessable?(class_text)

  # Three letters and more, or two written as an abbreviation is: `SD`, `BG`
  # (Shadowdancer, Blackguard — one-word names no rule shortens), but not the
  # `Is` of `2. Is Dodge worth it?`, a subsequence of Red dragon disciple.
  defp guessable?(text),
    do: String.length(text) >= 3 or Regex.match?(~RX/^\p{Lu}{2}$/u, text)

  # The same split the reader always reported an unknown class with: the
  # template's `Name(N)`, else the part before a colon, else the whole line.
  defp unread_head(text) do
    {class_text, extras} =
      split_head(hd(numbered_heads()), text) || split_head(Enum.at(strict_heads(), 1), text) ||
        {text, ""}

    %{text: class_text, extras: extras, class: :error}
  end

  # `Fighter1/Monk1`, `M(2), F(1): Toughness` — a ladder that writes the running
  # split instead of the class taken. Reading its first name would give every
  # level to that class, the plausible wrong answer this module refuses; so it
  # is not read at all, and the ladder stops there with the line quoted.
  #
  # ⚠️ Both names have to be classes for sure, not by the fuzzy guess:
  # `Wizard3, Str18` is a level of Wizard and a score, and `Str` fits Shifter
  # as a subsequence.
  #
  # Task 4.31 reads such a line after all (`running_split/2`), and the gate is
  # the same in spirit: two names of the split at least are classes for sure,
  # wherever they stand — `brd 5/rdd 8/wm 2` has two, `Wizard3, Str18` one.
  defp running_totals?(text, index) do
    case running_split(text, index) do
      {pairs, _extras} -> Enum.count(pairs, &match?({_, _, :ok}, &1)) >= 2
      nil -> false
    end
  end

  # The whole running split — `rogue 9/shadowdancer 1 (hide in plain sight)`,
  # `brd 5/rdd 8/wm 2` — as `{[{class, count, how}], extras}`, two classes at
  # least, a shorthand read by the guess allowed (`how` is `:ok` or `:guess`);
  # `nil` when a name is no class at all (task 4.31). Which class the level
  # took is decided against the ladder read so far (`add_level/3`), never off
  # the line alone — and a guess that makes the counts disagree stops the
  # ladder like any unread line.
  defp running_split(text, index) do
    case running_pairs(text, index) do
      {[_, _ | _] = pairs, extras} -> {pairs, extras}
      _ -> nil
    end
  end

  # ⚠️ One pass over the line (task 4.34). Pair by pair, the rest of the line
  # used to be matched again — its end-to-end capture and slicing, and a regex
  # on it, which checks the whole rest is UTF-8 on every call — so a line of
  # eight thousand `Fighter1/` took seconds. The pairs are read by one scan
  # instead, each match starting where the one before it ended (`\G`) and
  # taking the separator after its pair, and then walked the way the
  # recursion walked them: a pair whose class is not read ends the reading
  # (and the whole line is no running split when it is the first), a pair
  # without a separator after it is the last.
  defp running_pair,
    do: ~RX"\G\s*(\D+?)\s*\(?\s*(\d{1,2})\s*\)?(?=\s*(?:[/,&+]|$|[\s:\-–—(]))(\s*[/,&+]\s*)?"u

  defp running_pairs(text, index) do
    running_pair()
    |> Regex.scan(text, return: :index)
    |> pair_chain(text, index, [])
  end

  defp pair_chain([], _text, _index, _pairs), do: nil

  defp pair_chain([[{at, length}, name, count | separator] | later], text, index, pairs) do
    with {how, class} when how in [:ok, :guess] <-
           resolve_class(index, String.trim(part(text, name))) do
      pairs = [{class, String.to_integer(part(text, count)), how} | pairs]
      stop = at + length
      rest = binary_part(text, stop, byte_size(text) - stop)

      case separator do
        [{separator_at, _}] when separator_at >= 0 ->
          pair_chain(later, text, index, pairs) || {Enum.reverse(pairs), String.trim(rest)}

        _ ->
          {Enum.reverse(pairs), rest |> String.replace(~RX/^[\s:\-–—]+/u, "") |> String.trim()}
      end
    else
      _ -> nil
    end
  end

  defp part(text, {at, length}), do: binary_part(text, at, length)

  # Whether what follows a class reads as a level's contents: nothing, CBC's
  # list of grants, a bump, an ability's name, a skill purchase, a feat, a
  # note shaped like one (`+1 AC`) — or a bracket whose own contents do.
  # `Paladin (the best class) is…` is prose, `RDD (+1 AC)` is a level.
  defp extras_like?(extras, index) do
    item = extras |> String.replace(~RX/^[\s:,;.\-–—>]+/u, "") |> split_extras() |> List.first("")
    first_word = item |> String.split(~RX/[^\p{L}]+/u, trim: true) |> List.first("")

    cond do
      item == "" or String.starts_with?(item, "{") ->
        true

      inside = leading_bracket(item) ->
        after_bracket = item |> String.replace(~RX/^[\(\[][^\)\]]*[\)\]]/u, "") |> String.trim()

        extras_like?(inside, index) or
          (after_bracket != "" and extras_like?(after_bracket, index))

      true ->
        increase_in(item, index) != nil or ability_key(first_word) != nil or
          inline_skill(item, index) != nil or note?(item) or feat_start?(item, index)
    end
  end

  defp leading_bracket(item) do
    case Regex.run(~RX/^[\(\[]([^\)\]]*)[\)\]]/u, item) do
      [_, inside] -> inside
      _ -> nil
    end
  end

  defp feat_start?(item, index) do
    case FeatListTokenizer.tokenize(tok_text(item), index.feat_dictionary) do
      [%{value: value} | _] when value != nil -> true
      _ -> match?({:ok, _}, resolve(index.feats, item))
    end
  end

  # ------------------------------------------------------------- skill lines --

  # The FIRST item has to be a purchase of a skill we know (or CBC's `Save`):
  # `DwD22, Armor Skin, Con22` and `BG - C1, H1, CA11` are levels whose tails
  # happen to hold a skill's shorthand, not skill lines.
  defp skill_line?(rest, index) do
    case split_items(rest) do
      [first | _] -> skill_or_unspent?(first, index)
      [] -> false
    end
  end

  defp skill_or_unspent?(item, index) do
    case skill_item(item) do
      {name, _ranks} -> unspent?(name) or match?({:ok, _}, resolve_skill(index, name))
      nil -> false
    end
  end

  # ------------------------------------------------------------------ ladder --

  # The ladder is the numbered list with the most lines that name a class —
  # the first such list when two tie, the first list at all when none names
  # one (so an unreadable ladder is still reported as one, class by class).
  # Every level line of the other lists is listed as a line we did not use.
  def ladder_block(lines) do
    case Enum.reject(lines, &is_nil(&1.block)) do
      [] ->
        {[], lines}

      placed ->
        chosen =
          placed
          |> Enum.chunk_by(& &1.block)
          |> Enum.max_by(fn block -> Enum.count(block, &readable?/1) end)

        block = hd(chosen).block
        {settle(chosen), Enum.reject(lines, &(&1.block == block))}
    end
  end

  def readable?(%{class: {kind, _id}}) when kind in [:ok, :guess, :running], do: true
  def readable?(_line), do: false

  # Inside the ladder, a line that opens with a class's name is that class —
  # the looser reading `bare_class/2` kept aside for exactly this. ⚠️ Only in
  # a list that IS a ladder by its own plain lines — two of them at least, and
  # half the list: a lone `1. Paladin levels give Divine Grace early` is prose.
  defp settle(block) do
    readable = Enum.count(block, &readable?/1)

    if readable >= 2 and readable * 2 >= length(block),
      do: Enum.map(block, &settle_line/1),
      else: block
  end

  defp settle_line(%{class: :error, fallback: %{} = fallback} = line),
    do: %{line | class: fallback.class, class_text: fallback.text, extras: fallback.extras}

  defp settle_line(line), do: line

  # A level line not read, and the lines under it that read as its feats
  # (`Lines`, task 4.36): nothing a line said is dropped without a word.
  def skipped(lines), do: Enum.flat_map(lines, &[{:ignored_line, &1.number, &1.line} | below(&1)])

  defp below(line),
    do:
      for(
        {number, text} <- Enum.reverse(Map.get(line, :below, [])),
        do: {:ignored_line, number, text}
      )

  # The spine. A level that cannot be read stops the ladder instead of letting
  # the levels after it slide up one: order decides base attack and saves past
  # 20 outright (CLAUDE.md §3), so a shifted ladder is a different character and
  # a plausible-looking wrong answer is worse than a short right one.
  #
  # ⚠️ A ladder can also simply END, and that is not a gap: when nothing left in
  # the list names a class or states a class's level (`42 AC`, `43
  # Concentration` — totals written as numbered lines), or the character is
  # already at the cap and the line is not the next level. What is left is then
  # listed as lines we did not use. A gap, an unknown class or a level past the
  # cap is reported only while the ladder demonstrably goes on.
  def ladder(lines, ruleset, issues), do: ladder(lines, ruleset, [], issues)

  defp ladder([], _ruleset, taken, issues), do: {taken, issues}

  defp ladder([line | rest] = lines, ruleset, taken, issues) do
    expected = length(taken) + 1
    cap = ruleset.level_cap

    cond do
      not Enum.any?(lines, &classy?/1) or (length(taken) >= cap and line.level != cap + 1) ->
        {taken, issues ++ skipped(lines)}

      line.level != expected ->
        {taken, issues ++ [{:level_gap, expected, line.level} | unread_below(lines)]}

      line.level > cap ->
        {taken, issues ++ [{:level_over_cap, line.level, cap} | unread_below(lines)]}

      true ->
        case add_level(taken, issues, line) do
          {:cont, {taken, issues}} -> ladder(rest, ruleset, taken, issues)
          {:halt, {taken, issues}} -> {taken, issues ++ unread_below(lines)}
        end
    end
  end

  # The ladder stopped: the levels past the stop are named by the stop's own
  # issue, and the lines under them that read as their feats (task 4.36) are
  # listed as the lines we did not use they were before.
  defp unread_below(lines), do: Enum.flat_map(lines, &below/1)

  # Names a class, even ambiguously — an ambiguous line is the ladder refusing
  # to guess, not the ladder having ended — or states one's level.
  defp classy?(%{class: {kind, _}}) when kind in [:ok, :guess, :ambiguous, :running], do: true
  defp classy?(%{ladder_shaped?: true}), do: true
  defp classy?(_line), do: false

  defp add_level(taken, issues, line) do
    case line.class do
      {:ok, id} ->
        {:cont, {taken ++ [id], issues}}

      # `Fighter1/Monk1` after `Fighter1` (task 4.31): the level took the class
      # whose count grew by one — and only if exactly one did, by exactly one,
      # and no class the ladder already has went missing from the line. Any
      # other line is not a level we can read, and the ladder stops there.
      {:running, pairs} ->
        counts = Enum.frequencies(taken)
        written = Map.new(pairs, fn {class, count, _how} -> {class, count} end)

        grown =
          for {class, count} <- written, count == Map.get(counts, class, 0) + 1, do: class

        steady? =
          Enum.all?(written, fn {class, count} ->
            count in [Map.get(counts, class, 0), Map.get(counts, class, 0) + 1]
          end) and Enum.all?(Map.keys(counts), &Map.has_key?(written, &1))

        case grown do
          [class] when steady? ->
            {:cont, {taken ++ [class], issues}}

          _ ->
            {:halt,
             {taken, issues ++ [{:unknown_class, line.level, line.class_text}, stopped(taken)]}}
        end

      # Read off a shorthand nobody wrote down: `Ftr`, `Drd`, `Bbn`. Reported
      # rather than trusted quietly — a guess the player can see in the ladder
      # and reject is tolerance, a silent one is invention. Once per shorthand,
      # at the first level it reads on: a ladder that writes `DwDef` twenty
      # times made the same one guess, not twenty.
      {:guess, id} ->
        guessed = {:class_guessed, line.level, line.class_text, id}

        if Enum.any?(
             issues,
             &match?({:class_guessed, _, text, ^id} when text == line.class_text, &1)
           ),
           do: {:cont, {taken ++ [id], issues}},
           else: {:cont, {taken ++ [id], issues ++ [guessed]}}

      :error ->
        {:halt,
         {taken, issues ++ [{:unknown_class, line.level, line.class_text}, stopped(taken)]}}

      {:ambiguous, ids} ->
        {:halt,
         {taken, issues ++ [{:ambiguous_class, line.level, line.class_text, ids}, stopped(taken)]}}
    end
  end

  defp stopped(taken), do: {:ladder_stopped, length(taken)}
end
