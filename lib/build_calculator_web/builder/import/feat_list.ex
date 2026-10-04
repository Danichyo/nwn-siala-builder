defmodule BuildCalculatorWeb.Builder.Import.FeatList do
  @moduledoc """
  The feat names of one level: cut apart by `BuildCalculator.FeatListTokenizer`,
  their roman ranks, the choice written after a name (`Weapon Focus:
  Warhammer`), a class's own choice written among the feats (`Domain War`),
  and a name the dictionary does not hold as it stands. A part of
  `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculator.FeatListTokenizer
  alias BuildCalculator.Rules.ClassChoices
  alias BuildCalculatorWeb.Builder.ChoiceIndex

  import BuildCalculatorWeb.Builder.Import.LevelTail,
    only: [bare_ability: 2, bracketed: 1, note?: 1, score_note?: 2]

  import BuildCalculatorWeb.Builder.Import.Names,
    only: [
      choice_value: 4,
      collapse: 1,
      feat_by_forms: 2,
      feat_by_name: 2,
      name_forms: 1,
      near_feat_by_forms: 2,
      near_value: 4,
      norm: 1,
      resolve: 2,
      resolve_skill: 2,
      tok_text: 1
    ]

  # The feat names of one level, cut apart by the same longest-match reader the
  # wiki's build pages and the `.билд` log use (`FeatListTokenizer`, CLAUDE.md
  # §9: a second implementation of one reading is the mistake to avoid). It
  # hands back a roman rank as a rank — `Great Strength II` is `Great strength`
  # taken again, and the core counts takes, not ranks — and a run it does not
  # know as it stands, which is then asked of the looser name index (acronyms,
  # `Blindfight`) before it is reported.
  #
  # The reader wants lower case, so the entries come back lower case; the text
  # a player is shown is recovered from the original at the same place.
  def read_feats([], _level, _index, _ruleset), do: {[], []}

  #
  # The picks and the notes are gathered newest first and put in order once
  # (task 4.34): a level of nine thousand names appended to both lists.
  def read_feats(texts, level, index, ruleset) do
    original = Enum.join(texts, ", ")
    normal = tok_text(original)

    {feats, issues, _last} =
      normal
      |> FeatListTokenizer.tokenize(index.feat_dictionary)
      |> recover(original, normal)
      |> merge_arguments(index, ruleset)
      |> continue_ranks()
      |> Enum.reduce({[], [], nil}, &feat_step(&2, &1, level, index, ruleset))

    {Enum.reverse(feats), Enum.reverse(issues)}
  end

  # `Great Dex II, III` (task 4.36, 205934) — the next rank after a name the
  # tokenizer did not know as it stands and the looser index read
  # (`resolve_feat/6`). `continue_ranks/1` sees only what the tokenizer knew,
  # and the numeral after such a name was passed over as a note: the third
  # take of Great Dexterity was lost without a word. `last` is the feat the
  # entry before gave, with its rank; a numeral above that rank is the feat
  # taken again, as `continue_ranks/1` reads it.
  defp feat_step({feats, issues, last}, entry, level, index, ruleset) do
    case next_rank(entry, last) do
      {feat, rank} ->
        {[feat | feats], issues, {feat, rank}}

      nil ->
        {grown, issues} = feat_entry({feats, issues}, entry, level, index, ruleset)
        {grown, issues, ranked(grown, feats, entry)}
    end
  end

  defp next_rank(%{value: nil, raw: raw}, {feat, rank}) when is_integer(rank) do
    case bare_rank(raw) do
      {_numeral, higher} when higher > rank -> {feat, higher}
      _ -> nil
    end
  end

  defp next_rank(_entry, _last), do: nil

  # The feat an entry added — one, on top of the list it was given — and its
  # rank: the tokenizer's, or the numeral that ends the name as written.
  defp ranked([feat | feats], feats, entry), do: {feat, entry_rank(entry)}
  defp ranked(_grown, _feats, _entry), do: nil

  defp entry_rank(%{rank: rank}) when is_binary(rank), do: known_rank(roman(rank))

  defp entry_rank(%{raw: raw}) do
    case Regex.run(~RX/\s([ivx]+)\+?$/iu, raw) do
      [_, numeral] -> known_rank(roman(numeral))
      nil -> nil
    end
  end

  defp known_rank(0), do: nil
  defp known_rank(rank), do: rank

  # `Great Wisdom I & II` — the next rank of the feat just read, written as a
  # bare numeral after it (task 4.31). A rank higher than the one before it
  # is that feat taken again; a numeral with nothing ranked before it stays
  # what it was (`feat_entry/5` passes it over as a note). A score in brackets
  # after the numeral (`II (WIS 22)`) is the source's arithmetic, as anywhere.
  defp continue_ranks(entries) do
    {entries, _last} =
      Enum.map_reduce(entries, nil, fn
        %{value: {:feat, _id}, rank: rank} = entry, _last when is_binary(rank) ->
          {entry, entry}

        %{value: nil, raw: raw} = entry, %{rank: rank} = last ->
          with {numeral, higher} <- bare_rank(raw),
               true <- higher > roman(rank) do
            taken = %{last | raw: raw, rank: numeral}
            {taken, taken}
          else
            _ -> {entry, nil}
          end

        entry, _last ->
          {entry, nil}
      end)

    entries
  end

  @romans ~w(i ii iii iv v vi vii viii ix x) |> Enum.with_index(1) |> Map.new()

  defp bare_rank(raw) do
    with [_, numeral] <-
           Regex.run(~RX/^([ivx]+)\+?\s*(?:[\(\[][^\)\]]*[\)\]])?$/iu, String.trim(raw)),
         numeral = String.downcase(numeral),
         value when is_integer(value) <- Map.get(@romans, numeral) do
      {numeral, value}
    else
      _ -> nil
    end
  end

  defp roman(rank),
    do: Map.get(@romans, rank |> String.downcase() |> String.trim_trailing("+"), 0)

  # Lower-casing keeps every byte where it was for the scripts this text is
  # written in, so a fragment found in the lower-case text sits at the same
  # place in the original. Where it would not (a letter whose cases differ in
  # length), the lower-case fragment is shown as it is.
  defp recover(entries, original, normal) do
    aligned? = byte_size(original) == byte_size(normal)

    {entries, _cursor} =
      Enum.map_reduce(entries, 0, fn entry, cursor ->
        {raw, cursor} = locate(entry.raw, original, normal, cursor, aligned?)

        {argument, cursor} =
          case entry.argument do
            argument when argument in [nil, ""] -> {nil, cursor}
            argument -> locate(argument, original, normal, cursor, aligned?)
          end

        {%{entry | raw: raw, argument: argument}, cursor}
      end)

    entries
  end

  defp locate(fragment, original, normal, cursor, aligned?) do
    case :binary.match(normal, fragment, scope: {cursor, byte_size(normal) - cursor}) do
      {at, length} when aligned? -> {binary_part(original, at, length), at + length}
      {at, length} -> {fragment, at + length}
      :nomatch -> {fragment, cursor}
    end
  end

  # `Weapon Focus: Warhammer` and `Epic Energy Resistance Fire I` — a feat with a
  # choice, the choice written after it without brackets. The reader stops at
  # the name, so the run after it is joined back: always after a colon, and
  # without one only when it IS a value of that feat's choice.
  defp merge_arguments(
         [%{value: {:feat, _id}, argument: nil} = hit, %{value: nil} = run | rest],
         index,
         ruleset
       ) do
    case attach(hit, run.raw, index, ruleset) do
      {:ok, argument} -> merge_arguments([%{hit | argument: argument} | rest], index, ruleset)
      :no -> [hit | merge_arguments([run | rest], index, ruleset)]
    end
  end

  defp merge_arguments([entry | rest], index, ruleset),
    do: [entry | merge_arguments(rest, index, ruleset)]

  defp merge_arguments([], _index, _ruleset), do: []

  defp attach(%{value: {:feat, id}}, raw, index, ruleset) do
    cond do
      String.starts_with?(raw, ":") ->
        case raw |> String.trim_leading(":") |> String.trim() do
          "" -> :no
          argument -> {:ok, argument}
        end

      match?({:ok, _value}, choice_value(ruleset, index, id, raw)) ->
        {:ok, raw}

      true ->
        :no
    end
  end

  defp feat_entry(
         {feats, issues},
         %{value: {:feat, id}, argument: argument},
         level,
         index,
         ruleset
       ) do
    {choice, issues} = resolve_choice(ruleset, index, id, argument, level, issues)
    {[{id, choice} | feats], issues}
  end

  defp feat_entry(
         {feats, issues},
         %{value: {:ambiguous, ids}, raw: raw, argument: argument},
         level,
         index,
         ruleset
       ) do
    case narrow(index, ruleset, ids, argument, raw) do
      {:ambiguous, ids} ->
        {feats, [{:ambiguous_feat, level, raw, ids} | issues]}

      {how, id} ->
        {choice, issues} = resolve_choice(ruleset, index, id, argument, level, issues)
        guessed = if how == :guess, do: [{:feat_guessed, level, raw, id}], else: []
        {[{id, choice} | feats], Enum.reverse(guessed, issues)}
    end
  end

  # A bracket left over after a feat that already took one (`Weapon Focus
  # (Longsword) (STR 20)`) is read the way a bracketed item is: a score or a
  # note is passed over, anything else is still a name to look up.
  defp feat_entry({feats, issues}, %{value: nil, raw: raw}, level, index, ruleset) do
    inside = bracketed(raw)

    cond do
      note?(raw) or Regex.match?(~RX/^[ivx]+\+?$/iu, raw) ->
        {feats, issues}

      inside && (note?(inside) or score_note?(inside, index) or bare_ability(inside, index)) ->
        {feats, issues}

      # `Knockdown Ability: Str (str17)` — the bracket gave the bump, and the
      # words that named it are no feat (task 4.31).
      bare_ability(raw, index) != nil ->
        {feats, issues}

      choice = class_choice_item(raw, index, ruleset) ->
        {[choice | feats], issues}

      true ->
        resolve_feat(raw, level, index, ruleset, feats, issues)
    end
  end

  # `Domain War, Domain Trickery` on a Cleric's level — how CBC prints the
  # class's own choice among the feats (task 4.31) — or, on the class's first
  # level only, the value alone (`[Trickery, War]`). Read as the class's
  # choice (`Build.class_choices`), from the domain the class draws it from;
  # a word the domain does not have stays a feat's name to look up.
  defp class_choice_item(raw, %{level_class: class} = index, ruleset) when class != nil do
    with domain when domain != nil <- ClassChoices.domain(class, ruleset),
         values when is_map(values) <- Map.get(index.choices, domain),
         {named?, text} <- choice_words(raw, domain),
         true <- named? or index.level_first?,
         {:ok, value} <- ChoiceIndex.resolve(values, text) do
      {:class_choice, class, value}
    else
      _ -> nil
    end
  end

  defp class_choice_item(_raw, _index, _ruleset), do: nil

  # `Domain War`, `War Domain`, `Domain (magic)`, `School (divination)` — the
  # value named as one of its kind; else the bare word.
  defp choice_words(raw, domain) do
    text = String.trim(raw)

    with %Regex{} = pattern <- choice_kind_pattern(domain),
         [_ | _] = found <- Regex.run(pattern, text) do
      {true, found |> Enum.drop(1) |> Enum.find(&(&1 != "")) |> String.trim()}
    else
      _ -> {false, text}
    end
  end

  # The words a kind is named by, written into its pattern: put in by
  # interpolation, they had it compiled anew for every item (task 4.34).
  defp choice_kind_pattern(:domain),
    do: ~RX/^(?:(?:domain)\s*:?\s*[\(\[]?\s*([^\)\]]+?)\s*[\)\]]?|(.+?)\s+(?:domain))$/iu

  defp choice_kind_pattern(:spell_school),
    do:
      ~RX/^(?:(?:school|specialization|specialisation)\s*:?\s*[\(\[]?\s*([^\)\]]+?)\s*[\)\]]?|(.+?)\s+(?:school|specialization|specialisation))$/iu

  defp choice_kind_pattern(_domain), do: nil

  # What the longest-match reader did not know is asked of the looser index —
  # acronyms, spacing (`Blindfight`), a qualifier in brackets or after a colon —
  # and reported only when that fails too.
  #
  # Last comes the community's word-by-word shorthand: `Great Dex II`, `Imp
  # Crit: Longbow`, `Weap. Focus`, `Great Str 3` — every word the start of the
  # name's word in the same place, a rank (roman or arabic) at the end left
  # off. The same unique-prefix rule classes and skills read by, word by word;
  # two feats that fit are refused as ambiguous.
  #
  # ⚠️ The name is read with every empty bracket closed up — `( )` as `()` —
  # and written back to the player as it was (task 4.40, third pass): a space
  # inside a bracket that holds nothing must not change what is read, and it
  # did — `Weapon ( ) Focus Longsword` was an unknown name and `Weapon ()
  # Focus Longsword` Weapon Focus. `bracketed_qualifier/1` reads `()` as it
  # read `( )` before, so the bracket that `LevelTail.drop_scores/1` leaves of
  # a score (`(=25)` → `( )`) is read as it always was.
  defp resolve_feat(written, level, index, ruleset, feats, issues) do
    item = close_empty_brackets(written)
    spelled_out = item |> String.replace(~RX/[:()\[\]]/u, " ") |> collapse()

    # A name's forms (`Names.name_forms/1`) are worked out once for each text
    # asked about here (`known`), not once per question (task 4.34): a name
    # with a thousand tails to take off was taken apart four times.
    {name, qualifier, known} =
      if match?({:ok, _}, resolve(index.feats, item)) do
        {item, nil, %{}}
      else
        # `Weapon Proficiency: Exotic`, `Weapon Prof.: Martial` — the choice is
        # part of this feat's name.
        {found, known} = named(index, spelled_out, %{})

        if match?({:ok, _}, found) do
          {spelled_out, nil, known}
        else
          {name, qualifier} = split_qualifier(item)
          {name, qualifier, known}
        end
      end

    {name, qualifier, known} =
      with nil <- qualifier,
           {:error, known} <- named(index, name, known) do
        case unbracketed_choice(index, ruleset, name) do
          {feat, value} -> {feat, value, known}
          nil -> {name, nil, known}
        end
      else
        {_found, known} -> {name, qualifier, known}
        _qualifier -> {name, qualifier, known}
      end

    case feat_reading(index, ruleset, name, qualifier, known) do
      {:ok, id} ->
        {choice, issues} = resolve_choice(ruleset, index, id, qualifier, level, issues)
        {[{id, choice} | feats], issues}

      {:guess, id} ->
        {choice, issues} = resolve_choice(ruleset, index, id, qualifier, level, issues)
        {[{id, choice} | feats], [{:feat_guessed, level, written, id} | issues]}

      :error ->
        case two_feats(item, index) do
          {first, second} -> {[{second, nil}, {first, nil} | feats], issues}
          nil -> {feats, [{:unknown_feat, level, written} | issues]}
        end

      {:ambiguous, ids} ->
        {feats, [{:ambiguous_feat, level, written, ids} | issues]}
    end
  end

  # `( )`, `[ ]` → `()`, `[]`: the spaces between an opening bracket and the
  # closing one right after them. Linear: the spaces are one run each, and the
  # lookahead asks one character past it.
  defp close_empty_brackets(text), do: String.replace(text, ~RX/([\(\[])\s+(?=[\)\]])/u, "\\1")

  # `Great Wis V Great Wis VI`, `Great Charisma IV Great Wisdom I` — two names
  # written without a comma (task 4.36; 302439, 146828). Read as two only when
  # exactly one place parts the words into two names each known for sure — as
  # written, or by the starts of its words (`feat_by_forms/2`), never a guess;
  # anything else is the one unknown name it was. A dozen words at most: each
  # place asks two questions.
  @two_feats_words 12

  defp two_feats(item, index) do
    words = String.split(item, ~RX/\s+/u, trim: true)
    count = length(words)

    found =
      if count in 2..@two_feats_words,
        do:
          for(
            taken <- 1..(count - 1),
            {first, second} = {Enum.take(words, taken), Enum.drop(words, taken)},
            {:ok, a} <- [feat_by_forms(index, name_forms(Enum.join(first, " ")))],
            {:ok, b} <- [feat_by_forms(index, name_forms(Enum.join(second, " ")))],
            do: {a, b}
          ),
        else: []

    case found do
      [one] -> one
      _ -> nil
    end
  end

  # `WF Heavy Crossbow`, `EWS Shortsword`, `Skill Focus Discipline` — a feat
  # and its choice with nothing between them (task 4.31). Read only when the
  # words after the name are a value of that feat's choice for sure; `WF`
  # being Weapon Focus and Weapon Finesse is then settled by the value too
  # (`narrow/5`).
  defp unbracketed_choice(index, ruleset, name) do
    words = String.split(name, ~RX/\s+/u, trim: true)

    Enum.find_value(1..min(length(words) - 1, 3)//1, fn taken ->
      {head, rest} = Enum.split(words, taken)
      {feat, value} = {Enum.join(head, " "), Enum.join(rest, " ")}

      ids =
        case feat_by_name(index, feat) do
          {:ok, id} -> [id]
          {:ambiguous, ids} -> ids
          :error -> []
        end

      if Enum.count(ids, &match?({:ok, _}, choice_value(ruleset, index, &1, value))) == 1,
        do: {feat, value}
    end)
  end

  defp feat_reading(index, ruleset, name, qualifier, known) do
    forms = Map.get_lazy(known, name, fn -> name_forms(name) end)

    case feat_by_forms(index, forms) do
      {:ambiguous, ids} -> narrow(index, ruleset, ids, qualifier, name)
      :error -> near_feat_by_forms(index, forms)
      found -> found
    end
  end

  # `Names.feat_by_name/2`, the forms kept for the next question.
  defp named(index, text, known) do
    forms = Map.get_lazy(known, text, fn -> name_forms(text) end)
    {feat_by_forms(index, forms), Map.put(known, text, forms)}
  end

  # Two feats answer to one name — `LoH` is Luck of Heroes and Lay on Hands,
  # `ESF` Epic Skill Focus and Epic Spell Focus (task 4.31). A choice written
  # with it settles it for sure when only one of them takes that value (`ESF:
  # Spot`). Without one, when only one of them is a feat anybody PICKS — no
  # slot of any class takes Lay on Hands, a class hands it over — that one is
  # read, but as a guess the player is told about: a ladder may name a class's
  # own gift too.
  #
  # ⚠️ Not for two letters (`IC`, `WS`, `MS` — Weapon Specialization and Wild
  # Shape, Maximize Spell and Move Silently), not for a name a skill answers
  # to as well, and not on a level whose class hands the other one over: on a
  # Paladin's level `LoH` may well be Lay on Hands.
  defp narrow(index, ruleset, ids, qualifier, text) do
    by_choice =
      if qualifier,
        do: Enum.filter(ids, &match?({:ok, _}, choice_value(ruleset, index, &1, qualifier))),
        else: []

    {choosable, handed} = Enum.split_with(ids, &MapSet.member?(index.choosable, &1))

    guessable? =
      String.length(norm(text)) >= 3 and resolve_skill(index, text) == :error and
        not Enum.any?(handed, &granted_by_level_class?(ruleset, &1, index.level_class))

    case {by_choice, choosable} do
      {[id], _choosable} -> {:ok, id}
      {_by_choice, [id]} when guessable? -> {:guess, id}
      _ -> {:ambiguous, ids}
    end
  end

  defp granted_by_level_class?(_ruleset, _feat, nil), do: false

  defp granted_by_level_class?(ruleset, feat, class) do
    case ruleset.feats do
      %{^feat => %{granted_by: %MapSet{} = by}} -> MapSet.member?(by, class)
      _ -> false
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
    case choice_value(ruleset, index, id, qualifier) do
      {:ok, choice} ->
        {choice, issues}

      # `Great Wisdom I (WIS 21)`, `Great Dex +1 (23)` — the score after the
      # feat, in the bracket a choice would stand in: the source's arithmetic,
      # not a choice to drop (task 4.31).
      _missing when is_binary(qualifier) ->
        cond do
          note?(qualifier) or score_note?(qualifier, index) ->
            {nil, issues}

          guess = near_value(ruleset, index, id, qualifier) ->
            {guess, [{:feat_guessed, level, qualifier, {id, guess}} | issues]}

          true ->
            dropped_choice(ruleset, index, id, qualifier, level, issues)
        end
    end
  end

  defp dropped_choice(ruleset, index, id, qualifier, level, issues) do
    case choice_value(ruleset, index, id, qualifier) do
      :no_domain -> {nil, [{:feat_qualifier_dropped, level, id, qualifier} | issues]}
      :error -> {nil, [{:feat_choice_unknown, level, id, qualifier} | issues]}
    end
  end

  # `Weapon focus (longsword)` and `Skill focus: discipline` each name a feat and
  # a choice inside it.
  defp split_qualifier(item) do
    cond do
      match = bracketed_qualifier(item) ->
        [_, name, qualifier] = match
        {String.trim(name), String.trim(qualifier)}

      match = Regex.run(~RX/^(.+?)\s*[:—–]\s*(.+)$/u, item) ->
        [_, name, qualifier] = match
        {String.trim(name), String.trim(qualifier)}

      true ->
        {item, nil}
    end
  end

  # `~r/^(.+?)\s*[\(\[]\s*([^\)\]]*)[\)\]]\s*$/u` on the item — but only from
  # the closing bracket before the last one on (task 4.34). The bracket it
  # reads closes the item, and what it holds has no closing bracket in it, so
  # it opens after that earlier one; tried from every opening bracket before
  # it, the regex read up to it again from each — a name followed by a
  # thousand `(` took seconds.
  #
  # ⚠️ An empty bracket is read too, with or without a space inside (task
  # 4.40): `( )` and `()` alike are the bracket of a choice that holds nothing,
  # and the name is everything before it. Until then `( )` was read so and
  # `()` was not — the item fell through to the colon (`EF:Great Strength II
  # ()` read as Epic Fortitude, `( )` as the unknown name it is), and what
  # `LevelTail.drop_scores/1` leaves of a bracket that held a score alone
  # (`(=25)`) was read differently depending on a space.
  defp bracketed_qualifier(item) do
    closings = :binary.matches(item, [")", "]"])

    with [_ | _] <- closings,
         {last, _} = List.last(closings),
         true <-
           Regex.match?(~RX/^\s*$/u, binary_part(item, last + 1, byte_size(item) - last - 1)) do
      case Enum.at(closings, -2) do
        nil ->
          Regex.run(~RX/^(.+?)\s*[\(\[]\s*([^\)\]]*)[\)\]]\s*$/u, item)

        {before, _} ->
          head = binary_part(item, 0, before + 1)
          rest = binary_part(item, before + 1, byte_size(item) - before - 1)

          case Regex.run(~RX/^(.*?)\s*[\(\[]\s*([^\)\]]*)[\)\]]\s*$/u, rest) do
            [whole, name, qualifier] -> [head <> whole, head <> name, qualifier]
            nil -> nil
          end
      end
    else
      _ -> nil
    end
  end
end
