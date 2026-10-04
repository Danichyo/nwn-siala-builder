defmodule BuildCalculatorWeb.Builder.Import.Assembly do
  @moduledoc """
  The build put together out of what the scan read (`assemble/4`): the
  ladder, the scores with the race taken off, the feats placed slot by slot
  the way a click would place them, the increases and class choices stated
  apart from the ladder, the skill guide — and what the two halves of the
  block say about each other and about the rules. A part of
  `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Abilities, Build, ClassChoices, FeatChoices}
  alias BuildCalculatorWeb.Builder.{Feats, PointBuy}
  alias BuildCalculatorWeb.Builder.Import.Names

  import BuildCalculatorWeb.Builder.Import.Ladder,
    only: [ladder: 3, ladder_block: 1, readable?: 1, skipped: 1]

  import BuildCalculatorWeb.Builder.Import.LevelTail, only: [read_extras: 4, unspent?: 1]

  import BuildCalculatorWeb.Builder.Import.Names, only: [resolve_race: 2, resolve_skill: 2]
  import BuildCalculatorWeb.Builder.Import.Sheets, only: [rolled_totals: 2]

  @ability_atoms Map.new(Names.ability_words(), &{&1, String.to_atom(&1)})

  # `notes` — what was done to the paste before it was read (`Scan.paste/1`).
  def assemble(scan, ruleset, index, notes) do
    issues = scan.issues ++ notes
    {ladder_lines, other_lines} = ladder_block(scan.level_lines)
    {levels, issues} = ladder(ladder_lines, ruleset, issues)
    issues = issues ++ skipped(other_lines)
    entries = Map.new(ladder_lines, &{&1.level, &1})

    {race, issues} = race_by_sheet(scan, index, issues)

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: race,
        alignment: scan.alignment,
        levels: levels
      )

    readings =
      Map.new(1..length(levels)//1, fn level ->
        class = Enum.at(levels, level - 1)

        at = %{
          index
          | level_class: class,
            level_first?: Enum.find_index(levels, &(&1 == class)) == level - 1
        }

        {level, read_extras(Map.fetch!(entries, level).extras, level, at, ruleset)}
      end)

    {build, issues} = with_abilities(build, scan, ruleset, issues)
    {build, issues} = with_feats(build, readings, ruleset, issues)
    {build, issues} = with_stated_choices(build, scan.stated_choices, ruleset, issues)
    {build, issues} = with_stated_increases(build, scan.stated_increases, ruleset, issues)
    {build, issues} = with_unnamed_increases(build, scan, ruleset, issues)
    {guide, issues} = skill_guide(scan.skill_lines, index, issues)
    {build, issues} = with_skills(build, scan, guide, readings, issues)
    issues = fold_guesses(issues)
    ladder? = Enum.any?(ladder_lines, &readable?/1)

    %{
      build: build,
      title: scan.title,
      read: read(build, scan),
      issues: issues ++ crosschecks(build, scan, ladder?, ruleset),
      source: %{
        totals: rolled_totals(scan.totals, scan.rolled),
        skills: scan.source_skills,
        declared: scan.declared,
        abilities: scan.printed
      }
    }
  end

  # `Race: Human (for the extra skills) or Elf (for higher Dex)` and, below
  # it, `Human Stats` over the score sheet (task 4.31): the sheet, and every
  # number the post prints after it, are the variant its caption names — so
  # that race is read, and said to be read this way. A caption naming none of
  # the races, or several, leaves the pick to the player.
  defp race_by_sheet(%{race: nil, race_options: [_ | _] = ids} = scan, index, issues) do
    named =
      for id <- ids,
          caption = scan.printed_caption,
          is_binary(caption),
          caption_names_race?(caption, id, index),
          do: id

    case named do
      [id] ->
        issues =
          Enum.map(issues, fn
            {:race_alternatives, text, ^ids} -> {:race_by_sheet, text, id, scan.printed_caption}
            issue -> issue
          end)

        {id, issues}

      _ ->
        {nil, issues}
    end
  end

  defp race_by_sheet(scan, _index, issues), do: {scan.race, issues}

  # Every word and every pair of neighbouring words; a caption of one word is
  # its own pair. `Enum.chunk_every/4`, not a slice per place: slicing a list
  # at a place walks it from the start (task 4.34).
  defp caption_names_race?(caption, id, index) do
    words = String.split(caption, ~RX/[^\p{L}\-]+/u, trim: true)

    Enum.any?(
      for(taken <- [1, 2], chunk <- runs_of(words, taken), do: chunk),
      fn chunk -> resolve_race(index, Enum.join(chunk, " ")) == {:ok, id} end
    )
  end

  defp runs_of(words, taken) when length(words) < taken, do: [words]
  defp runs_of(words, taken), do: Enum.chunk_every(words, taken, 1, :discard)

  # Every name read by a guess, one note for the build (task 4.31): a ladder
  # that writes `Luck of Heros` on three levels made one guess, not three, and
  # thirty notes of «проверь» are read by nobody. Each spelling is named once,
  # at the first level it appears on, in the order of the text.
  defp fold_guesses(issues) do
    guesses =
      for {:feat_guessed, level, text, reading} <- issues,
          uniq: true,
          do: {text, reading, level}

    guesses = Enum.uniq_by(guesses, fn {text, reading, _level} -> {text, reading} end)

    case Enum.split_while(issues, &(not match?({:feat_guessed, _, _, _}, &1))) do
      {_all, []} ->
        issues

      {before, rest} ->
        before ++
          [{:feats_guessed, guesses} | Enum.reject(rest, &match?({:feat_guessed, _, _, _}, &1))]
    end
  end

  # The printed scores are a character sheet, not a point buy: they already carry
  # the racial modifiers, so those come back off (HANDOFF, «Гном Защитник» —
  # CHA 6 is a number the 8..18 scale cannot produce at all). Without a race
  # there is nothing to subtract, and that is said out loud instead of guessed.
  defp with_abilities(build, scan, ruleset, issues) do
    if scan.printed == %{} do
      {build, issues ++ [{:abilities_missing}]}
    else
      racial = Abilities.racial_modifiers(build, ruleset)

      # A sheet short of some scores (task 4.31): the rest is the minimum, and
      # that is said, not left to be taken for the author's.
      missing =
        for ability <- Abilities.keys(),
            not Map.has_key?(scan.printed, Atom.to_string(ability)),
            do: ability

      issues = if missing == [], do: issues, else: issues ++ [{:abilities_partial, missing}]

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
  #
  # ⚠️ Linear in the feats of a level (task 4.34): a level of nine thousand
  # names asked the core about every one of them and appended a note for each.
  # Where a pick goes is a plain function of the build as it stands and the
  # pick, so a pick met again before the build has changed takes the answer
  # already given (`decided`), and the build changes only when a feat goes
  # into a slot. The open slots are the same for every pick while they are
  # sorted, so they are asked once. The notes are gathered newest first and
  # put in order once.
  defp with_feats(build, readings, ruleset, issues) do
    {build, reversed} =
      Enum.reduce(1..length(build.levels)//1, {build, Enum.reverse(issues)}, fn level,
                                                                                {build, reversed} ->
        reading = Map.fetch!(readings, level)

        build =
          build
          |> with_increase(reading.increase, level)
          |> with_choices(reading.choices, ruleset)

        openings = openings(ruleset, build, level, reading.feats)

        {build, reversed, _decided} =
          reading.feats
          |> Enum.sort_by(&Map.fetch!(openings, &1))
          |> Enum.reduce(
            {build, Enum.reverse(reading.issues, reversed), %{}},
            &place_feat(&2, &1, ruleset, level)
          )

        {build, reversed}
      end)

    {build, Enum.reverse(reversed)}
  end

  # How many of the level's open slots take each pick — the pair, not the feat
  # alone (task 4.59): a bonus slot can take the feat and refuse its value.
  defp openings(ruleset, build, level, picks) do
    slots = Feats.open_slots(ruleset, build, level)

    for {feat_id, choice} = pick <- picks,
        into: %{},
        do: {pick, Enum.count(slots, &Feats.slot_takes?(ruleset, &1, feat_id, choice))}
  end

  defp place_feat({build, reversed, decided}, {feat_id, choice} = pick, ruleset, level) do
    case Map.get_lazy(decided, pick, fn -> placement(build, pick, ruleset, level) end) do
      {:slot, slot_id} ->
        {Build.put_feat(build, level, slot_id, feat_id, choice), reversed, %{}}

      {:note, note} = decision ->
        {build, [note | reversed], Map.put(decided, pick, decision)}
    end
  end

  defp placement(build, {feat_id, choice}, ruleset, level) do
    cond do
      feat_id in Build.granted_feats_at(build, ruleset, level) ->
        {:note, {:feat_granted_here, level, feat_id}}

      already_owned?(build, ruleset, level, feat_id, choice) ->
        {:note, {:feat_already_owned, level, feat_id}}

      # Task 4.59: the slot that takes the PAIR. A class's bonus slot can be
      # narrower by value than by feat (`Rules.FeatSlots.choice_refusals/4`), and
      # asked about the feat alone it took `Epic weapon focus (longsword)` of an
      # Arcane archer 14, the core then calling it illegal there.
      slot = Feats.best_slot(ruleset, build, level, feat_id, choice) ->
        {:slot, slot.id}

      # The reason is the core's (task 4.59): until then one sentence stood for
      # a feat Siala switched off, a class ability no slot takes, and a level
      # whose slot was simply spent. A level with no feat slot at all says so
      # (task 4.40, `Feats.unplaced_reason/5`).
      true ->
        {:note,
         {:feat_no_slot, level, feat_id,
          Feats.unplaced_reason(ruleset, build, level, feat_id, choice)}}
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

  # The ability increases the ladder does not name (task 4.31). A post that
  # writes only where a score ended up — `DEX: 16 (28)`, `Dex 16/28`, `STR:
  # 14 -> 28`, `DEX 16 to 32` — says how many increases went where, never at
  # which level. That is enough in exactly one case: the unnamed levels are
  # as many as ONE score's printed end is above ours, and no other printed end
  # disagrees with ours — then every unnamed level took that score, and the
  # order does not matter. Anything else is said, not guessed: two scores
  # short (`DEX +9, CON +1` — which level took the CON?), an end above ours by
  # more or less than the unnamed levels (gear in the printed end, a feat we
  # did not read), no printed end at all.
  #
  # Only on a ladder read to its end: past a line that stopped it, the levels
  # we have are not the ones the printed end was reached with.
  defp with_unnamed_increases(%Build{} = build, scan, ruleset, issues) do
    unnamed =
      for level <- 1..length(build.levels)//1,
          Abilities.increase_level?(ruleset, level),
          not Map.has_key?(build.ability_increases, level),
          do: level

    stopped? =
      Enum.any?(issues, &match?({kind, _, _} when kind in [:level_gap, :level_over_cap], &1)) or
        Enum.any?(issues, &match?({:ladder_stopped, _}, &1))

    ends = printed_ends(scan, ruleset)

    cond do
      unnamed == [] or stopped? ->
        {build, issues}

      ends == %{} ->
        {build, issues ++ [{:increases_unnamed, unnamed}]}

      true ->
        ours = Abilities.scores(build, ruleset)

        short =
          for {ability, final} <- ends,
              final != Map.fetch!(ours, ability),
              into: %{},
              do: {ability, final - Map.fetch!(ours, ability)}

        case Map.to_list(short) do
          [{ability, count}] when count == length(unnamed) ->
            increases = Map.merge(build.ability_increases, Map.new(unnamed, &{&1, ability}))

            {%Build{build | ability_increases: increases},
             issues ++ [{:increases_restored, ability, unnamed, Map.fetch!(ends, ability)}]}

          _ ->
            {build, issues ++ [{:increases_unplaced, unnamed, short}]}
        end
    end
  end

  defp printed_ends(scan, ruleset) do
    for ability <- ruleset.abilities,
        %{final: final} when is_integer(final) <- [Map.get(scan.printed, Atom.to_string(ability))],
        into: %{},
        do: {ability, final}
  end

  # The increases a list states (`increase_list/1`) fill the levels the ladder
  # left without one. A list that names a level granting no increase, or the
  # same level twice, is not a list of increases, and is said to be unread; a
  # level the ladder gives to another score keeps the ladder's, and the
  # disagreement is said.
  defp with_stated_increases(build, [], _ruleset, issues), do: {build, issues}

  defp with_stated_increases(%Build{} = build, stated, ruleset, issues) do
    levels = Enum.map(stated, &elem(&1, 0))

    if Enum.all?(levels, &Abilities.increase_level?(ruleset, &1)) and
         levels == Enum.uniq(levels) do
      Enum.reduce(stated, {build, issues}, fn {level, key}, {%Build{} = build, issues} ->
        ability = Map.fetch!(@ability_atoms, key)

        case Map.get(build.ability_increases, level) do
          _ when level > length(build.levels) ->
            {build, issues}

          nil ->
            {%Build{build | ability_increases: Map.put(build.ability_increases, level, ability)},
             issues}

          ^ability ->
            {build, issues}

          other ->
            {build, issues ++ [{:increase_list_disagrees, level, other, ability}]}
        end
      end)
    else
      {build, issues ++ [{:increase_list_unread, levels}]}
    end
  end

  # `Domains: War and Trickery` (`domains_line/2`) goes to the class of the
  # ladder whose choice is drawn from that domain, when the ladder itself did
  # not name it. A line we could not read whole is said to be unread.
  defp with_stated_choices(build, stated, ruleset, issues) do
    {build, added} =
      Enum.reduce(stated, {build, []}, fn {domain, values, line, number}, {build, added} ->
        classes =
          for class <- Enum.uniq(build.levels),
              ClassChoices.domain(class, ruleset) == domain,
              do: class

        cond do
          classes == [] ->
            {build, [{:ignored_line, number, line} | added]}

          values == nil ->
            {build, [{:class_choice_unread, line} | added]}

          true ->
            build =
              Enum.reduce(classes, build, fn class, build ->
                if Build.class_choice(build, class) == [],
                  do: with_choices(build, Enum.map(values, &{class, &1}), ruleset),
                  else: build
              end)

            {build, added}
        end
      end)

    {build, issues ++ Enum.reverse(added)}
  end

  # A class's own choice read off its level (`class_choice_item/3`): the
  # values in the order written, as many as the class takes, each once.
  defp with_choices(%Build{} = build, [], _ruleset), do: build

  defp with_choices(%Build{} = build, choices, ruleset) do
    Enum.reduce(choices, build, fn {class, value}, build ->
      held = Build.class_choice(build, class)

      case ClassChoices.spec(class, ruleset) do
        %{count: count} when length(held) < count ->
          if value in held,
            do: build,
            else: %Build{
              build
              | class_choices: Map.put(build.class_choices, class, held ++ [value])
            }

        _ ->
          build
      end
    end)
  end

  defp with_increase(%Build{} = build, nil, _level), do: build

  defp with_increase(%Build{} = build, ability, level),
    do: %Build{build | ability_increases: Map.put(build.ability_increases, level, ability)}

  # --------------------------------------------------------------- skills --

  # The per-level skill guide: ours, CBC's chart, or whatever list reads as one.
  # Two lists — a variant, a corrected repost — would add up to nonsense, so the
  # list with the most lines naming a skill is read and the others are listed
  # as lines we did not use; the ladder's own rule, for the same reason.
  defp skill_guide([], _index, issues), do: {%{}, issues}

  defp skill_guide(lines, index, issues) do
    chosen =
      lines
      |> Enum.chunk_by(& &1.block)
      |> Enum.max_by(fn block -> Enum.count(block, &names_a_skill?(&1, index)) end)

    block = hd(chosen).block

    # A name already reported is known by its tag and its name (`once/2`),
    # kept aside so as not to look through every note again (task 4.34).
    named =
      for issue <- issues,
          tuple_size(issue) > 2,
          elem(issue, 0) in [:unknown_skill, :ambiguous_skill],
          into: MapSet.new(),
          do: {elem(issue, 0), elem(issue, 2)}

    {guide, added, _named} =
      for line <- chosen, {name, ranks} <- line.items, reduce: {%{}, [], named} do
        acc -> put_ranks(acc, line.level, name, ranks, index)
      end

    {guide, issues ++ Enum.reverse(added) ++ skipped(Enum.reject(lines, &(&1.block == block)))}
  end

  defp names_a_skill?(line, index),
    do:
      Enum.any?(line.items, fn {name, _ranks} -> match?({:ok, _}, resolve_skill(index, name)) end)

  # A name the chart repeats on every level (`Spcr(1)`, `Tnt(4)`) is one miss,
  # not forty: it is reported at the first level it appears on.
  defp put_ranks({guide, added, named}, level, name, ranks, index) do
    cond do
      unspent?(name) or ranks == 0 ->
        {guide, added, named}

      true ->
        case resolve_skill(index, name) do
          {:ok, id} ->
            at = guide |> Map.get(level, %{}) |> Map.update(id, ranks, &(&1 + ranks))
            {Map.put(guide, level, at), added, named}

          :error ->
            once({guide, added, named}, {:unknown_skill, level, name})

          {:ambiguous, ids} ->
            once({guide, added, named}, {:ambiguous_skill, level, name, ids})
        end
    end
  end

  defp once({guide, added, named}, issue) do
    key = {elem(issue, 0), elem(issue, 2)}

    if MapSet.member?(named, key),
      do: {guide, added, named},
      else: {guide, [issue | added], MapSet.put(named, key)}
  end

  # Skills bought on the level lines themselves fill only the levels the guide
  # does not cover: the same purchase must not be counted twice.
  defp with_skills(%Build{} = build, scan, guide, readings, issues) do
    level = length(build.levels)

    inline =
      for {at, %{skills: bought}} <- readings,
          bought != %{},
          not Map.has_key?(guide, at),
          into: %{},
          do: {at, bought}

    combined = Map.merge(guide, inline)
    {inside, outside} = Enum.split_with(combined, fn {at, _ranks} -> at <= level end)

    issues =
      issues
      |> maybe(outside != [], {:skill_ranks_past_ladder, length(outside)})
      |> maybe(
        scan.source_skills != [] and combined == %{},
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
  #
  # `ladder?` — the text has a ladder at all: a numbered list with at least one
  # line naming a class. A stray `20:24 posts` off a forum page is not one.
  defp crosschecks(build, scan, ladder?, ruleset) do
    actual = Build.class_levels(build)
    used = build.levels |> Enum.uniq() |> length()
    limit = ruleset.max_classes

    mismatches =
      for %{class: class, text: text, levels: declared} <- scan.declared,
          class != nil,
          ladder?,
          Map.get(actual, class, 0) != declared,
          do: {:split_mismatch, text, declared, Map.get(actual, class, 0)}

    unresolved =
      for %{class: nil, text: text} <- scan.declared, do: {:unknown_class_in_header, text}

    []
    |> maybe(not ladder? and scan.declared != [], {:no_leveling_guide})
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
  # Мировоззрение данные называют в двух полях — `requirements.alignment`
  # (раздел Requirements у престиж-классов) и `alignment_restriction`
  # (карточка класса, `AlignRestrict`), — но с задачи 4.23 ядро спрашивает
  # его ОДИН раз: `without_restated_alignment/2` в `level_up.ex` снимает
  # из блока требований буквальный повтор ограничения, так что совпадающие
  # поля дают одну причину, а не две; разные спецификации — по-прежнему две.
  # У `purple_dragon_knight` Сиала целиком заменила `requirements` своим
  # блоком (BAB +4 и четыре навыка) без ключа `alignment`, и мировоззрение
  # приходит только из `alignment_restriction` (`"any lawful"`, «Характер:
  # Любой Законопослушный») — на выходе та же форма
  # `{:requires_alignment, %{require: ["lawful"]}}`. Белому списку поле
  # не важно: он фильтрует по ФОРМЕ причины, а не по тому, откуда она взялась.
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
end
