defmodule BuildCalculator.WikiBuildPage do
  @moduledoc """
  Reads a Siala wiki *build* page out of `priv/wiki_cache/siala/` into a fixture.

  ## What these pages are, and what they are not

  They are **test fixtures, not a source of rules** (CLAUDE.md §3: `игрок в игре >
  страница правил > страница билда > Fandom`). A build page is one player's
  worked example, arithmetic included, and the arithmetic has been wrong before —
  two of them are off by +13 skill points in the same direction and three others
  are exact. So this module's job is to read a page *faithfully*, not to decide
  who is right; that judgement lives in the reference test next to the numbers.

  ## Why it lives in `test/support/`

  The parser is deliberately not in `lib/`: none of it is a rule, and the shape it
  produces — race, alignment, starting abilities, one class per character level,
  ranks — is the same shape the community text format has (CLAUDE.md §3), so a
  future importer can reuse the mapping tables rather than reinvent them.

  ## What is read

  A page qualifies when it has a `'''Повышение уровня:'''` section — a numbered
  line per character level. Everything else on these pages is prose.

      :12. <span style="color: blue;">'''Мастер оружия'''</span></p> - Blind-Fight

  Also read: race (`'''Раса:''' Гном (Dwarf)`), alignment, the starting ability
  block, the declared skill totals, and — recorded but never compared — the
  finished character's attack bonus and saving throws.

  ## Two traps in this data

    * **The printed ability scores are post-racial.** They are the character
      sheet, not the point buy: `Гном Защитник` prints `Харизма - 6`, which is
      impossible as a point-buy score (the scale starts at 8) and is exactly
      8 − 2 for a Dwarf. Under that reading all eight pages come to exactly the
      30-point budget, and under the pre-racial reading two of them do not. So
      `abilities` here is what the page prints, and `base_abilities/2` subtracts
      the racial modifiers to get back the point buy the calculator wants.
    * **Class names on build pages are not the class page titles.** `Гном
      Защитник` (the build) is `Гномий защитник` (the class), `Ассасин` is
      `Убийца`, `Плут` and `Вор` are both Rogue. Hence `@class_aliases`.

  ## Feats

  The tail of every ladder line is the feats taken on that level, and they are
  read (`declared_feats`) and laid into the core's slot model (`feat_plan/2`).
  Nothing about them is free text once parsed: a token either resolves to a feat
  id or is handed back raw so the reference test can declare it unreadable.

  Splitting the tail on punctuation does not work, and the reason is worth
  keeping: `Energy Resistance, Fire I` **contains a comma** and is one feat, so a
  comma-split would invent a feat called "Fire I". So the tail is tokenised by
  **longest match against the feat dictionary** instead — the name is found
  first, and only then is whatever follows it read as an argument
  (`(Bastard Sword)`), a rank (`III`) or a separator. Nothing outside the
  dictionary is ever guessed at.

  The tokenizer itself moved out to `BuildCalculator.FeatListTokenizer` on
  26.08.2026 (task 3.111): `BuildCalculator.GameLog` needed the exact same
  reading for the `.билд` chat dump, and it lives in `lib/`, where this module
  — compiled only for `:test` — cannot be called from. This module still owns
  the *dictionary* (which names resolve to which feat, and this page's own
  typos and aliases); the tokenizer only owns how a list gets cut apart.
  """

  alias BuildCalculator.FeatListTokenizer
  alias BuildCalculator.Rules.{Build, FeatSlots, Skills}

  @cache_dir Path.expand("../../priv/wiki_cache/siala", __DIR__)

  @typedoc "One page, read as far as it reads."
  @type t :: %__MODULE__{}

  defstruct [
    :title,
    :revid,
    :race,
    :race_ru,
    :race_en,
    :alignment_ru,
    :alignment_en,
    abilities: %{},
    ability_increases: %{},
    levels: [],
    level_notes: %{},
    declared_feats: %{},
    declared_skill_points: nil,
    declared_free_skill_points: nil,
    declared_skills: [],
    declared_attack_bonus: nil,
    declared_saves: nil,
    # ⚠ Единственное «итоговое» число страницы, которое МОЖНО сверять с моделью
    # напрямую, и потому оно читается отдельно от двух соседей выше: AB, AC
    # и сейвы у всех восьми страниц — числа со шмотом, баффами и мини-сетами,
    # а сопротивление заклинаниям не даёт ни один предмет и ни один бафф,
    # которые эти билды носят. Называет его ровно одна страница из восьми.
    declared_spell_resistance: nil,
    problems: []
  ]

  # ---------------------------------------------------------------- tables --

  # source: priv/rules/siala_41/classes.json, field `ru` (each entry cites its own
  # Siala class page and revid). Only the spellings that differ from that file are
  # listed here — everything else is matched against the ruleset directly, so a
  # renamed class does not need a second edit here.
  #
  # Each alias below is a spelling a *build* page uses:
  #   "Гном Защитник"       Гном Защитник revid 19525 (class page: «Гномий защитник»)
  #   "Теневой Танцор"      Мастер Вор revid 17941    (class page: «Теневой танцор»)
  #   "Ассасин"             Мастер Монах revid 17944  (class page: «Убийца»)
  #   "Плут"                Мастер Ловушек revid 17928 (class page: «Вор»)
  #   "Черный страж"        Бледный Призыватель revid 18469 (class page: «Чёрный страж»)
  @class_aliases %{
    "гном защитник" => :dwarven_defender,
    "защитник гномов" => :dwarven_defender,
    "теневой танцор" => :shadowdancer,
    "ассасин" => :assassin,
    "плут" => :rogue,
    "черный страж" => :blackguard
  }

  # Канонические русские имена классов больше НЕ читаются отсюда своим копиём
  # `siala_41/classes.json`: с волны 4 загрузчик поднимает `ru` в сам ruleset,
  # и `ruleset_class_id/1` ниже спрашивает его. Источник у имени один, а этот
  # разбор стал его первым потребителем: пропади `ru` из ruleset'а — восемь
  # страниц вики перестанут читаться, и регрессия скажет об этом сразу.

  # source: the ability block of every build page, e.g. Мастер оружия Сагровик
  # revid 17916 («*Сила - 16 (+10 на прокачке)»). Russian labels only; the
  # English identifiers are the ones the rules core uses (CLAUDE.md §4).
  @ability_labels %{
    "сила" => :str,
    "ловкость" => :dex,
    "телосложение" => :con,
    "интеллект" => :int,
    "мудрость" => :wis,
    "харизма" => :cha
  }

  # source: priv/rules/name_map.json (47 EN↔RU pairs harvested from Siala's own
  # redirects) plus the English names the build pages themselves use. Build pages
  # write skills in English, so this table only has to survive spelling and case.
  # `heal_skill` and `craft_*` carry the disambiguating suffix the data layer uses.
  @skill_labels %{
    "hide" => :hide,
    "move silently" => :move_silently,
    "spot" => :spot,
    "listen" => :listen,
    "search" => :search,
    "discipline" => :discipline,
    "heal" => :heal_skill,
    "tumble" => :tumble,
    "intimidate" => :intimidate,
    "taunt" => :taunt,
    "lore" => :lore,
    "spellcraft" => :spellcraft,
    "concentration" => :concentration,
    "use magic device" => :use_magic_device,
    "set trap" => :set_trap,
    "craft trap" => :craft_trap,
    "open lock" => :open_lock,
    "disable trap" => :disable_trap,
    "persuade" => :persuade,
    "bluff" => :bluff,
    "parry" => :parry,
    "ride" => :ride,
    "appraise" => :appraise,
    "pick pocket" => :pick_pocket,
    "perform" => :perform,
    "animal empathy" => :animal_empathy
  }

  # Spellings a *build* page uses for a feat that the dictionary does not carry.
  # Everything else resolves against `ruleset.feats` directly (English `name`,
  # and the shard's `ru` page title for the six feats that have no English name),
  # so a feat renamed in the data needs no second edit here.
  #
  #   "Energy resistance, <type>"  is the in-game name of the family whose wiki
  #                                page is titled «Epic energy resistance» — the
  #                                page opens with all five icon captions
  #                                (`Energy resistance, acid`, …). Occurrences:
  #                                Бледный Призыватель 18469 lvl 23, Гном
  #                                Защитник 19525 lvl 36/39, Сагровик 17916 36/39.
  #   "Blind-Fight"                hyphenated on six pages; the page title is
  #                                «Blind fight».
  #   "Blibd Fight"                typo, Паладин Адры 19670 lvl 24.
  #   "Great Strenght"             typo, Сагровик 17916 lvl 24/27/30/33 and
  #                                Паладин Адры 19670 lvl 27/30.
  #   "Владение клинковыми оружиями"  plural, Мастер Вор 17941 / Ловушек 17928 /
  #                                Монах 17944 lvl 1; the feat page is titled
  #                                «Владение клинковым оружием».
  #   "Владение стрелковым"        Паладин метатель 17981 lvl 3 — the shard's
  #                                ranged proficiency, whose page is titled
  #                                «Владение оружием дальнего боя». The build is
  #                                a shuriken thrower, so the referent is not in
  #                                doubt.
  @feat_aliases %{
    "energy resistance, acid" => :epic_energy_resistance,
    "energy resistance, cold" => :epic_energy_resistance,
    "energy resistance, electrical" => :epic_energy_resistance,
    "energy resistance, fire" => :epic_energy_resistance,
    "energy resistance, sonic" => :epic_energy_resistance,
    "blind-fight" => :blind_fight,
    "blibd fight" => :blind_fight,
    "great strenght" => :great_strength,
    "владение клинковыми оружиями" => :siala_blade_proficiency,
    "владение стрелковым" => :siala_ranged_proficiency
  }

  # Ranks are written as roman numerals after the name — `Great Strength IV`,
  # `Improved Spell Resistance IX`. Read and kept, never turned into a number:
  # the core models a repeated feat as repeated slots and knows nothing of
  # ranks. The roman-numeral table itself now lives in `FeatListTokenizer`.

  # source: the alignment line of the build pages themselves, which print both
  # languages — «'''Характер''' Законопослушно-добрый (Lawful Good)». Only the
  # English half is mapped; the Russian half is kept verbatim as written, because
  # the pages are not consistent about hyphens or case.
  @alignment_labels %{
    "lawful good" => :lawful_good,
    "lawful neutral" => :lawful_neutral,
    "lawful evil" => :lawful_evil,
    "neutral good" => :neutral_good,
    "true neutral" => :true_neutral,
    "neutral evil" => :neutral_evil,
    "chaotic good" => :chaotic_good,
    "chaotic neutral" => :chaotic_neutral,
    "chaotic evil" => :chaotic_evil
  }

  # ------------------------------------------------------------- discovery --

  # `title => %{file:, revid:}`, folded in at compile time so a test run neither
  # globs the cache nor re-parses 63 KB of index per page. The revid travels with
  # the fixture: it is what tells a reader which revision of a page an expected
  # number was read off, and what fails first if the cache is refreshed.
  #
  # File names carry a `~pageid` suffix where two Siala titles differ only in
  # case (CLAUDE.md §3 — `Ученик красного дракона` the class and `Ученик Красного
  # дракона` the build), so the mapping has to come from the index and cannot be
  # derived from the name.
  @index_json Path.join(@cache_dir, "_index.json")
  @external_resource @index_json
  @index @index_json
         |> File.read!()
         |> Jason.decode!()
         |> Map.new(&{&1["title"], %{file: &1["file"], revid: &1["revid"]}})

  @doc """
  Titles of every cached Siala page that looks like a levelled build.

  The marker is the `Повышение уровня` heading — the only thing the eight
  structured build pages have and the twelve prose ones do not. Discovery is by
  content and not by a list of names on purpose: a new build page appearing in the
  cache must show up as "found 9, read 8", not vanish.
  """
  @spec discover() :: [String.t()]
  def discover, do: matching("Повышение уровня")

  @doc """
  Titles of every cached page the wiki itself files as a build.

  The marker is a link back to the hub «Билды для новичков», which every build
  page carries and nothing else does. This is a wider net than `discover/0` on
  purpose: twelve of these pages have no structured ladder, and the difference
  between the two lists is exactly the set that has to be *declared unreadable*
  rather than quietly dropped.
  """
  @spec discover_candidates() :: [String.t()]
  def discover_candidates, do: matching("[[Билды для новичков")

  defp matching(marker) do
    titles =
      for {title, %{file: file}} <- @index,
          @cache_dir |> Path.join(file) |> File.read!() |> String.contains?(marker),
          do: title

    Enum.sort(titles)
  end

  @doc "Reads and parses every discovered page."
  @spec load_all() :: [t()]
  def load_all, do: Enum.map(discover(), &load!/1)

  @doc "Reads one cached page by its wiki title."
  @spec load!(String.t()) :: t()
  def load!(title) do
    %{file: file, revid: revid} = Map.fetch!(@index, title)

    @cache_dir
    |> Path.join(file)
    |> File.read!()
    |> parse(title: title, revid: revid)
  end

  # ----------------------------------------------------------------- parse --

  @doc """
  Parses page wikitext.

  Never raises and never guesses: anything the tables above do not recognise lands
  in `problems` as `{:unknown_class, "…"}` / `{:missing, :race}` and so on, so a
  page that stops parsing says so instead of quietly producing a shorter build.
  """
  @spec parse(String.t(), keyword()) :: t()
  def parse(wikitext, opts \\ []) do
    lines = String.split(wikitext, ~r/\r?\n/)

    %__MODULE__{title: opts[:title], revid: opts[:revid]}
    |> put_race(wikitext)
    |> put_alignment(wikitext)
    |> put_abilities(lines)
    |> put_levels(lines)
    |> put_feats()
    |> put_skills(wikitext, lines)
    |> put_finished_numbers(lines)
    |> check_completeness()
  end

  defp put_race(page, wikitext) do
    case Regex.run(~r/'''Раса:?'''\s*([^(\n]+?)\s*\(([^)\n]+)\)/u, wikitext) do
      [_, ru, en] ->
        %{page | race_ru: ru, race_en: en, race: race_id(en)}

      _ ->
        add_problem(page, {:missing, :race})
    end
  end

  # The English name in the parentheses is matched against the ruleset's own race
  # names rather than a table here: the pages print «(Half-Elf)» and the data
  # prints "Half-elf", and case is the only difference across all seven.
  defp race_id(en) do
    ruleset = BuildCalculator.Data.ruleset!()
    wanted = String.downcase(en)

    Enum.find_value(ruleset.races, fn {id, race} ->
      String.downcase(race.name) == wanted && id
    end)
  end

  defp put_alignment(page, wikitext) do
    case Regex.run(~r/'''Характер:?'''\s*([^(\n]+?)\s*\(([^)\n]+)\)/u, wikitext) do
      [_, ru, en] ->
        %{page | alignment_ru: ru, alignment_en: Map.get(@alignment_labels, String.downcase(en))}

      _ ->
        add_problem(page, {:missing, :alignment})
    end
  end

  # «*Сила - 16 (+10 на прокачке)» — the score as the character sheet shows it,
  # then how much of the ten +1s from levelling went into it. Other parentheticals
  # exist («+2 от РДД», «+7 от умений») and must not be counted as level-ups, so
  # the increase is matched on the words «на прокачке» / «на апах» specifically.
  defp put_abilities(page, lines) do
    Enum.reduce(lines, page, fn line, acc ->
      with [_, label, score, tail] <-
             Regex.run(~r/^\*\s*([А-Яа-яЁё]+)\s*[-–—]\s*(\d+)\s*(.*)$/u, line),
           {:ok, ability} <- Map.fetch(@ability_labels, String.downcase(label)) do
        acc = %{acc | abilities: Map.put(acc.abilities, ability, String.to_integer(score))}

        case Regex.run(~r/\+(\d+)\s+на\s+(?:прокачке|апах)/u, tail) do
          [_, n] ->
            %{acc | ability_increases: Map.put(acc.ability_increases, ability, to_int(n))}

          _ ->
            acc
        end
      else
        _ -> acc
      end
    end)
  end

  # «:12. <span …>'''Мастер оружия'''</span></p> - Blind-Fight». The class is the
  # first bold run on the line; everything after it is a free-text note about
  # feats and skill dumps that no page writes the same way twice, so it is kept
  # raw rather than parsed.
  defp put_levels(page, lines) do
    entries =
      for line <- lines,
          [_, level, rest] <- [Regex.run(~r/^:\s*(\d+)\.\s*(.*)$/u, line)],
          do: {to_int(level), rest}

    {classes, notes, problems} =
      Enum.reduce(entries, {%{}, %{}, []}, fn {level, rest}, {classes, notes, problems} ->
        case Regex.run(~r/'''(.+?)'''/u, rest) do
          [_, name] ->
            note = rest |> String.replace(~r/'''.+?'''/u, "") |> clean_note()

            case class_id(name) do
              nil -> {classes, notes, [{:unknown_class, name} | problems]}
              id -> {Map.put(classes, level, id), Map.put(notes, level, note), problems}
            end

          _ ->
            {classes, notes, [{:no_class_on_level, level} | problems]}
        end
      end)

    levels =
      case Map.keys(classes) do
        [] -> []
        keys -> for level <- 1..Enum.max(keys), do: Map.get(classes, level)
      end

    %{
      page
      | levels: levels,
        level_notes: notes,
        problems: page.problems ++ Enum.reverse(problems)
    }
  end

  defp class_id(name) do
    key = normalise(name)

    Map.get(@class_aliases, key) || ruleset_class_id(key)
  end

  # Matched against `siala_41`'s own class list the same way races are, so the
  # alias table above only carries the spellings the build pages invented.
  # Оба имени равноправны как ключ поиска: английское — то, каким класс зовётся
  # в коде и в интерфейсе, русское (`ru`) — заголовок его страницы на вики,
  # каким его пишут авторы билдов.
  defp ruleset_class_id(key) do
    ruleset = BuildCalculator.Data.ruleset!()

    Enum.find_value(ruleset.classes, fn {id, class} ->
      (normalise(class.name) == key or (class.ru && normalise(class.ru) == key)) && id
    end)
  end

  defp normalise(name),
    do: name |> String.trim() |> String.downcase() |> String.replace("ё", "е")

  defp clean_note(rest) do
    rest
    |> String.replace(~r{</?(span|p|div)[^>]*>}u, "")
    |> String.trim()
    |> String.trim_leading("-")
    |> String.trim()
  end

  # ----------------------------------------------------------------- feats --

  # The tail of a ladder line, e.g. «- Great Fortitude; Favored Enemy (Gnomes)»
  # or «- Energy Resistance, Fire II, Epic Weapon Specialization (Katana)».
  #
  # Everything from `//` on is the author talking to the reader about skills
  # («// Заливаем 43 Spot») and is dropped: it is prose, and one of those
  # comments contains the word "Epic Skill Focus" inside a parenthetical about an
  # alternative, which a feat reader has no business believing.
  defp put_feats(page) do
    dictionary = feat_dictionary()

    declared =
      for {level, note} <- page.level_notes,
          entries = tokenise_feats(note, dictionary),
          entries != [],
          into: %{},
          do: {level, entries}

    %{page | declared_feats: declared}
  end

  # Feat name -> id, from the ruleset itself: the English `name` and — for the
  # six shard feats that have no English name at all (the custom weapon
  # proficiencies) — the shard's own page title, which is a name and not a fan
  # translation (CLAUDE.md §4). A name two feats share would make the table a
  # coin toss, so it raises instead.
  defp feat_dictionary do
    ruleset = BuildCalculator.Data.ruleset!()

    named =
      for {id, feat} <- ruleset.feats,
          name <- [feat.name, feat.ru],
          is_binary(name),
          reduce: %{} do
        acc ->
          key = normalise(name)

          case acc do
            %{^key => ^id} -> acc
            %{^key => other} -> raise "two feats answer to #{inspect(key)}: #{other}, #{id}"
            _ -> Map.put(acc, key, id)
          end
      end

    table = Map.merge(named, @feat_aliases)
    FeatListTokenizer.dictionary(table)
  end

  # One ladder line into feat entries, in the order the page writes them:
  # `%{feat: id | nil, raw: text, argument: text | nil, rank: text | nil}`.
  # `feat: nil` is a token the dictionary does not know — handed back rather than
  # dropped, so the reference test can declare it unreadable with a reason
  # instead of the page quietly losing a feat.
  #
  # The cutting-apart itself is `FeatListTokenizer.tokenize/2` (shared with
  # `BuildCalculator.GameLog` — see the moduledoc); this function only owns the
  # wiki-specific preface (drop the author's `//` commentary, normalise) and
  # renames the tokenizer's generic `value` back to this module's `feat`, so
  # every other function here keeps reading `entry.feat` unchanged.
  defp tokenise_feats(note, dictionary) do
    note
    |> String.split("//", parts: 2)
    |> hd()
    |> normalise()
    |> String.replace(~r/\s+/u, " ")
    |> FeatListTokenizer.tokenize(dictionary)
    |> Enum.map(fn %{value: feat} = entry ->
      entry |> Map.put(:feat, feat) |> Map.delete(:value)
    end)
  end

  @doc """
  Feat ids the page names at `level`, unreadable tokens dropped.
  """
  @spec feats_at(t(), pos_integer()) :: [atom()]
  def feats_at(%__MODULE__{declared_feats: feats}, level) do
    for entry <- Map.get(feats, level, []), entry.feat, do: entry.feat
  end

  @doc """
  The page's feats laid into the core's slot model, level by level.

  This is where the fixture stops describing a page and starts asking the rules a
  question, so what it returns is an account rather than a verdict:

    * `assigned` — `%{level => %{slot_id => feat_id}}`, ready to go on a `Build`;
    * `granted` — feats the page names that a **class already handed over**, so
      no slot is spent on them (CLAUDE.md §6: «получишь бесплатно — не трать
      слот»). Counting these as spends would accuse a legal build of overspending;
    * `unplaced` — feats no slot could take, each with **why every slot on that
      level refused**, or `:accepted` for a slot that would have taken it and was
      taken by another feat. "Nothing accepts this" and "two feats want one slot"
      are different findings and must not be summed;
    * `unreadable` — `{level, raw}` for tokens the dictionary does not know.

  Slots are filled by **maximum matching**, not greedily. A greedy pass that
  spends the general slot on a feat the class bonus would have taken reports a
  legal level as illegal, and the accusation would be the fixture's fault rather
  than the page's. The numbers are tiny (never more than two feats on a level),
  so an exhaustive search is affordable and obviously correct.

  Why a slot refused is *explained* here and never *decided* here:
  `BuildCalculator.Rules.FeatSlots.accepts?/3` decides, and `refusal/2` is only
  asked when it has already said no. A second implementation of the slot rules
  would eventually disagree with the first.
  """
  @spec feat_plan(t(), map()) :: %{
          assigned: %{pos_integer() => %{Build.slot_id() => atom()}},
          granted: [{pos_integer(), atom()}],
          unplaced: [%{level: pos_integer(), feat: atom(), slots: [{Build.slot_id(), term()}]}],
          unreadable: [{pos_integer(), String.t()}],
          declared: non_neg_integer(),
          slots: non_neg_integer(),
          filled: non_neg_integer()
        }
  def feat_plan(%__MODULE__{} = page, ruleset) do
    empty = %{
      assigned: %{},
      granted: [],
      unplaced: [],
      unreadable: [],
      declared: 0,
      slots: 0,
      filled: 0
    }

    build = to_build(page, ruleset)

    {_build, plan} =
      Enum.reduce(1..max(length(page.levels), 0)//1, {build, empty}, fn level, {acc, plan} ->
        plan_level(page, ruleset, acc, level, plan)
      end)

    plan
  end

  defp plan_level(page, ruleset, build, level, plan) do
    entries = Map.get(page.declared_feats, level, [])
    slots = FeatSlots.at(build, ruleset, level)
    owned = Build.granted_feats(build, ruleset, level)

    {granted, wanted} =
      entries
      |> Enum.filter(& &1.feat)
      |> Enum.map(& &1.feat)
      |> Enum.split_with(&MapSet.member?(owned, &1))

    {assigned, unplaced} = fill(ruleset, wanted, slots)

    plan = %{
      plan
      | assigned: Map.put(plan.assigned, level, Map.new(assigned)),
        granted: plan.granted ++ for(feat <- granted, do: {level, feat}),
        unplaced:
          plan.unplaced ++
            for feat <- unplaced do
              %{level: level, feat: feat, slots: refusals(ruleset, slots, feat)}
            end,
        unreadable: plan.unreadable ++ for(%{feat: nil, raw: raw} <- entries, do: {level, raw}),
        declared: plan.declared + length(entries),
        slots: plan.slots + length(slots),
        filled: plan.filled + length(assigned)
    }

    {%{build | feats: Map.put(build.feats, level, Map.new(assigned))}, plan}
  end

  # Maximum matching by exhaustive search: assign the head to every slot that
  # accepts it, or leave it unplaced, and keep whichever branch leaves the fewest
  # feats out. Pages never name more than two feats on a level, so the search
  # space is a handful of branches.
  defp fill(_ruleset, [], _slots), do: {[], []}

  defp fill(ruleset, [feat | rest], slots) do
    branches =
      for slot <- slots, FeatSlots.accepts?(ruleset, slot, feat) do
        {taken, out} = fill(ruleset, rest, List.delete(slots, slot))
        {[{slot.id, feat} | taken], out}
      end

    {taken, out} = fill(ruleset, rest, slots)
    Enum.min_by(branches ++ [{taken, [feat | out]}], fn {_taken, out} -> length(out) end)
  end

  defp refusals(ruleset, slots, feat) do
    for slot <- slots do
      if FeatSlots.accepts?(ruleset, slot, feat),
        do: {slot.id, :accepted},
        else: {slot.id, refusal(ruleset, slot, feat)}
    end
  end

  # Why `FeatSlots.accepts?/3` said no — a caption for a decision already made,
  # never the decision itself.
  defp refusal(ruleset, slot, feat_id) do
    feat = Map.get(ruleset.feats, feat_id)

    cond do
      is_nil(feat) ->
        :unknown_feat

      Map.get(feat, :disabled?) ->
        :disabled_on_the_shard

      slot.kind in [:general, :epic_general, :racial] and feat.type != "general" ->
        {:type_not_general, feat.type}

      slot.kind in [:general, :racial] and feat.epic? ->
        :epic_feat_before_epic_levels

      slot.kind == :class_bonus and not MapSet.member?(feat.bonus_for, slot.class) ->
        {:not_on_the_bonus_list, slot.class}

      slot.kind == :class_bonus and feat.epic? and not slot.epic? ->
        {:epic_feat_in_a_pre_epic_bonus_slot, slot.class}

      true ->
        :refused_for_a_reason_this_fixture_cannot_name
    end
  end

  # «Персонаж имеет в сумме 152 очка навыков к 40 уровню» and the leftover the page
  # claims («На ваше усмотрение остается 22 свободных очка навыка»). Both are the
  # page author's own arithmetic and are recorded, never assumed correct.
  defp put_skills(page, wikitext, lines) do
    declared = capture_int(wikitext, ~r/в\s+сумме\s+(\d+)\s+очк\w*\s+навык\w*/u)

    free =
      capture_int(wikitext, ~r/остается\s+(\d+)\s+свободных\s+очк\w*\s+навык\w*/u) ||
        capture_int(wikitext, ~r/остаётся\s+(\d+)\s+свободных\s+очк\w*\s+навык\w*/u) ||
        capture_int(wikitext, ~r/(\d+)\s+очк\w*\s+навык\w*\s+остаётся\s+у\s+вас\s+на\s+выбор/u)

    %{
      page
      | declared_skill_points: declared,
        declared_free_skill_points: free,
        declared_skills: declared_skills(lines)
    }
  end

  # Bullet lines inside the skills block: «*Discipline - 43», «*Search- 43»,
  # «*Use Magic Device - 33 (Доступен только на уровнях плута)».
  #
  # Each bullet carries the section it stands under, and the distinction is
  # load-bearing: `Мастер Ловушек` lists five more skills under «Очков хватит на
  # 4 из них» — a menu, not a plan. Summing those as if they were bought would
  # accuse the page of overspending 74 points it never claimed to spend.
  #
  # A list rather than a map because a skill legitimately appears twice: once in
  # «Обязательные навыки» with the rank a prestige class needs early, once in the
  # level-40 targets.
  defp declared_skills(lines) do
    {skills, _section} =
      Enum.reduce(lines, {[], :unknown}, fn line, {acc, section} ->
        case Regex.run(~r/^\*\s*([A-Za-z][A-Za-z ]*?)\s*[-–—]\s*(\d+)\s*(.*)$/u, line) do
          [_, name, ranks, tail] ->
            case Map.get(@skill_labels, name |> String.trim() |> String.downcase()) do
              nil -> {acc, section}
              skill -> {[{skill, to_int(ranks), section, String.trim(tail)} | acc], section}
            end

          _ ->
            {acc, section_of(line, section)}
        end
      end)

    Enum.reverse(skills)
  end

  # source: the three headings the build pages use above their skill bullets —
  #   «Обязательные навыки:»                                    (Мастер Вор revid 17941)
  #   «Остальные навыки, наиболее важные … к 40 уровню:»        (same)
  #   «… (Очков хватит на 4 из них)»                            (Мастер Ловушек revid 17928)
  # An unrecognised non-empty line resets the section to `:unknown` so a bullet
  # never inherits a heading from further up the page than its own paragraph.
  defp section_of(line, section) do
    cond do
      String.trim(line) == "" -> section
      String.starts_with?(String.trim(line), "*") -> section
      Regex.match?(~r/Обязательные\s+навыки/u, line) -> :required
      Regex.match?(~r/наиболее\s+важные/u, line) -> :target
      Regex.match?(~r/Очков\s+хватит|может\s+понадобиться/u, line) -> :optional
      true -> :unknown
    end
  end

  @doc """
  Ranks the page commits the build to, highest per skill.

  `:required` (needed early for a prestige class) and `:target` (the level-40
  goal) only — `:optional` menus are excluded, and the same skill listed in both
  sections collapses to the larger number, which is what the character ends with.
  """
  @spec committed_ranks(t()) :: %{atom() => pos_integer()}
  def committed_ranks(%__MODULE__{declared_skills: skills}) do
    for {skill, ranks, section, _note} <- skills,
        section in [:required, :target],
        reduce: %{} do
      acc -> Map.update(acc, skill, ranks, &max(&1, ranks))
    end
  end

  @doc """
  What the page's own skill plan costs, priced by `Rules.Skills`.

  This is the one place the wiki and the calculator can be compared on *spending*,
  and it exercises the rule community calculators get wrong: a rank costs 1 or 2
  depending on the class taken **on the level it was bought**, not on the build as
  a whole.

  Two prices are available and both are used:

    * the ranks a page pins to a level — «Intimidate - 4 (На 8 уровне, …)» — are
      charged at *that* level's price, which is the only honest reading;
    * everything else is charged at the cheapest price any level of the build
      offers, because no page states when the rest was bought. That makes the
      result a **lower bound**: if it already exceeds what the build earns, no
      schedule can rescue it.
  """
  @spec plan_cost(t(), Build.t(), map()) :: non_neg_integer()
  def plan_cost(%__MODULE__{} = page, %Build{} = build, ruleset) do
    levels = length(build.levels)
    pinned = pinned_ranks(page)

    Enum.reduce(committed_ranks(page), 0, fn {skill, ranks}, total ->
      cheapest =
        1..levels//1
        |> Enum.map(&Skills.rank_cost(build, ruleset, skill, &1))
        |> Enum.min(fn -> 2 end)

      case Map.get(pinned, skill) do
        nil ->
          total + ranks * cheapest

        {early_ranks, level} ->
          early = min(early_ranks, ranks)

          total + early * Skills.rank_cost(build, ruleset, skill, level) +
            (ranks - early) * cheapest
      end
    end)
  end

  # «Обязательные навыки» entries name the level they are bought on, because the
  # rank has to be there before a prestige class will take the character:
  # «*Hide - 10 (На 7 уровне, чтобы на 8 уровне персонажа можно было взять
  # Теневого Танцора)». The first number in the note is that level.
  defp pinned_ranks(%__MODULE__{declared_skills: skills}) do
    for {skill, ranks, :required, note} <- skills,
        [_, level] <- [Regex.run(~r/На\s+(\d+)\s+уровне/u, note)],
        into: %{},
        do: {skill, {ranks, to_int(level)}}
  end

  # The finished character's headline numbers. Read so that the reference test can
  # name them as explicitly *not comparable* — every one is a geared, buffed,
  # mini-set number (CLAUDE.md §3) and no page breaks it down far enough to take
  # the equipment back off. Read but never compared beats silently absent.
  #
  # ⚠ Спелл-резист — исключение, и единственное: он сверяется с моделью числом
  # в число (задача 3.45). Его дают только два фита, ни один предмет и ни один
  # бафф этих билдов в него не входит, и «63» на странице «Мастер Монах» — это
  # ровно `монах 35 + 10` плюс девять взятий по +2.
  defp put_finished_numbers(page, lines) do
    attack =
      Enum.find_value(lines, fn line ->
        capture_int(line, ~r/Бонус\s+атаки:\s*\+?(\d+)/u)
      end)

    saves =
      Enum.find_value(lines, fn line ->
        case Regex.run(~r/Спасброски:\s*(\d+)\D+(\d+)\D+(\d+)/u, line) do
          [_, fort, ref, will] -> %{fort: to_int(fort), ref: to_int(ref), will: to_int(will)}
          _ -> nil
        end
      end)

    # ⚠ Число стоит ПЕРЕД подписью — «*63 Защита от заклинаний, что делает
    # персонажа практически неуязвимым» — в отличие от всех остальных строк
    # раздела «Общее». Регулярка поэтому читается справа налево от лейбла,
    # а не слева направо от него.
    spell_resistance =
      Enum.find_value(lines, fn line ->
        capture_int(line, ~r/(\d+)\s+Защита\s+от\s+заклинаний/u)
      end)

    %{
      page
      | declared_attack_bonus: attack,
        declared_saves: saves,
        declared_spell_resistance: spell_resistance
    }
  end

  defp check_completeness(page) do
    holes =
      [
        page.levels == [] && {:missing, :levels},
        Enum.any?(page.levels, &is_nil/1) && {:missing, :level_gap},
        map_size(page.abilities) != 6 && {:missing, :abilities},
        is_nil(page.race) && page.race_en && {:unknown_race, page.race_en}
      ]
      |> Enum.filter(& &1)

    %{page | problems: page.problems ++ holes}
  end

  # ------------------------------------------------------------- to a build --

  @doc """
  The parsed page as a `BuildCalculator.Rules.Build`.

  `skills` are **not** filled in: no page states a complete per-level purchase
  schedule, and inventing one would put ranks on levels the author never named.
  What the pages do state — the final rank targets — is on the struct as
  `declared_skills` and is priced separately by the reference test.

  The ten `+1`s from levelling are placed on levels 4, 8 … 40 in the order the
  page lists the abilities. Where a page splits them across two abilities
  (`Бледный Призыватель`: +1 CON, +9 CHA) the split is real but *which* level got
  which is not stated, so the order here is an ordering assumption and nothing
  ability-dependent may be asserted against it.

  `feats: true` fills in the feats the page names, through `feat_plan/2`. It is
  **off by default** and that is deliberate: none of the numbers the reference
  test pins (base attack, saves, hit points, skill points) is touched by a feat,
  while the feat plan is itself one of the things under test — a build carrying
  it would make the plan both question and answer. Ask for it where the question
  *is* the feats: prerequisites, and the caveats they add to `stats.gaps`.
  """
  @spec to_build(t(), map(), keyword()) :: Build.t()
  def to_build(%__MODULE__{} = page, ruleset, opts \\ []) do
    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: page.race,
        alignment: page.alignment_en,
        base_abilities: base_abilities(page, ruleset),
        levels: page.levels,
        ability_increases: ability_increases(page)
      )

    if opts[:feats],
      do: %{build | feats: feat_plan(page, ruleset).assigned},
      else: build
  end

  @doc """
  Point-buy scores: what the page prints, minus the racial modifiers.

  See the module doc — the pages print the character sheet, and `Build` wants the
  scores before the race is applied.
  """
  @spec base_abilities(t(), map()) :: %{atom() => integer()}
  def base_abilities(%__MODULE__{} = page, ruleset) do
    modifiers =
      case Map.get(ruleset.races, page.race) do
        %{ability_modifiers: mods} when is_map(mods) -> mods
        _ -> %{}
      end

    Map.new(page.abilities, fn {ability, score} ->
      {ability, score - Map.get(modifiers, ability, 0)}
    end)
  end

  defp ability_increases(%__MODULE__{ability_increases: increases}) do
    increases
    |> Enum.flat_map(fn {ability, count} -> List.duplicate(ability, count) end)
    |> Enum.with_index(1)
    |> Map.new(fn {ability, nth} -> {nth * 4, ability} end)
  end

  # ----------------------------------------------------------------- utils --

  defp capture_int(text, regex) do
    case Regex.run(regex, text) do
      [_, n] -> to_int(n)
      _ -> nil
    end
  end

  defp to_int(string), do: String.to_integer(string)

  defp add_problem(page, problem), do: %{page | problems: page.problems ++ [problem]}
end
