defmodule BuildCalculator.Wiki.EpicRules do
  @moduledoc """
  Reads the epic (character level 21+) rules out of the cached Fandom pages.

  These rules are deliberately not class data. Every class page on Fandom carries
  an epic progression table and **not one of them has a BAB or a saving throw
  column** — past level 20 both stop depending on class at all and become a
  function of character level, written up on `Base attack`, `Base save` and
  `Level progression` instead. `BuildCalculator.Wiki.ClassPage` therefore cannot
  see them, and with the Siala cap at 41 levels that is half of every build.

  ## Where the values come from

  **Every number here is read out of a wikitable.** Three tables carry the whole
  numeric answer and they were written independently of one another, so they are
  cross-checked rather than trusted:

    * `Level progression` — one row per character level 21–40 carrying the epic
      attack bonus, epic save bonus, skill rank caps, general feat and ability
      increase for that level;
    * `Base attack` — the levels at which the epic attack bonus goes up;
    * `Base save` — the levels at which the epic save bonus goes up.

  A disagreement is not reconciled: the block gets `"status": "conflict"` and a
  `conflict_note`, exactly as `ClassPage` does for a class whose table and bold
  label differ.

  The rest of the epic rules (hit points, skill points per level, attacks per
  round, what counts as an epic class) exist only as prose. Those are kept as the
  **verbatim source line** that states them. Where such a line also pins down a
  single value, that value is emitted *gated on the line still being found*: if an
  editor rewrites the sentence the anchor stops matching, the value becomes `null`
  and the run reports it, instead of the parser quietly keeping a number nobody
  can trace back to the page any more.

  ## Level 41

  Fandom's cap is 40 and its tables stop there, so every "what does level 41 give"
  field is `null` with a note. Siala's own wiki (`41-ый уровень`, `Рост
  персонажа`) documents how the 41st level is *earned* and says nothing about what
  it grants. Continuing the tables by hand would be inventing game numbers, which
  CLAUDE.md §3 forbids, so the gap stays open and is listed in `open_questions`.
  """

  alias BuildCalculator.Wiki.Wikitable
  alias BuildCalculator.Wiki.Wikitext

  @wiki "fandom"

  @doc "Titles this parser needs in the cache; `mix wiki.fetch` fetches them."
  @spec pages() :: [binary]
  def pages do
    [
      "Ability score",
      "Attacks per round",
      "Base attack",
      "Base attack bonus",
      "Base save",
      "Bonus feat",
      "Character level",
      "Epic character",
      "Epic class",
      "General feat",
      "Hit point",
      "Level progression",
      "Prestige class",
      "Skill point",
      "Unarmed base attack bonus"
    ]
  end

  @doc """
  Builds the epic rules document out of the cached pages.

  `cached` is the `{index_entry, wikitext}` list `mix wiki.parse` already holds.
  Returns the JSON term plus `problems` — everything that did not parse or did
  not agree, for the caller to report rather than swallow.
  """
  @spec parse([{map, binary}]) :: %{json: term, problems: [binary]}
  def parse(cached) do
    context = context(cached)

    blocks = [
      {"epic_attack_bonus", epic_attack_bonus(context)},
      {"epic_save_bonus", epic_save_bonus(context)},
      {"attacks_per_round", attacks_per_round(context)},
      {"general_feats", general_feats(context)},
      {"ability_increases", ability_increases(context)},
      {"skill_ranks", skill_ranks(context)},
      {"skill_points", skill_points(context)},
      {"hit_points", hit_points(context)},
      {"epic_thresholds", epic_thresholds(context)},
      {"class_epic_bonus_feats", class_epic_bonus_feats(context)},
      {"level_table", level_table(context)}
    ]

    json =
      {:obj,
       [
         {"ruleset", "vanilla"},
         {"epic_starts_at_character_level", epic_starts_at(context)},
         {"character_level_cap", character_level_cap(context)},
         {"status", "parsed"}
       ] ++
         Enum.map(blocks, fn {name, block} -> {name, block.json} end) ++
         [{"open_questions", open_questions()}]}

    problems =
      context.missing ++
        Enum.flat_map(blocks, fn {name, block} ->
          Enum.map(block.problems, &"#{name}: #{&1}")
        end)

    %{json: json, problems: problems}
  end

  # ── the pages ─────────────────────────────────────────────────────────────

  defp context(cached) do
    by_title = Map.new(cached, fn {entry, wikitext} -> {entry.title, {entry, wikitext}} end)

    pages =
      for title <- pages(), Map.has_key?(by_title, title), into: %{} do
        {entry, wikitext} = Map.fetch!(by_title, title)
        {title, %{entry: entry, wikitext: wikitext, grids: grids(wikitext)}}
      end

    missing =
      for title <- pages(), not Map.has_key?(pages, title), do: "page not cached: #{title}"

    %{pages: pages, missing: missing}
  end

  defp page(context, title), do: Map.get(context.pages, title)

  defp grids(wikitext) do
    wikitext
    |> Wikitable.find_all()
    |> Enum.map(fn source ->
      source |> Wikitable.parse() |> Map.fetch!(:rows) |> Wikitable.expand()
    end)
  end

  # ── blocks ────────────────────────────────────────────────────────────────

  # The second flag here is the expensive one to get wrong: the epic bonus is
  # added to the base attack *as it stood at level 20*, so class levels taken
  # afterwards contribute nothing to it. Twenty fighter then twenty wizard is a
  # different character from twenty wizard then twenty fighter, and the wiki
  # spells that example out.
  defp epic_attack_bonus(context) do
    series = series(context, "Base attack", "character level", "epic attack bonus")
    rule = line(context, "Base attack", ~r/base attack increases at every odd character level/i)
    order = line(context, "Base attack", ~r/may depend on the order in which classes were taken/i)

    block(
      series_pairs(series) ++
        [
          {"added_to_base_attack_at_character_level", gated(rule, 20)},
          {"class_levels_after_20_add_base_attack", gated(rule, false)},
          {"at_character_level_41", nil},
          {"rule_raw", rule},
          {"class_order_raw", order},
          {"note",
           "Added to the base attack the character had at level 20; it is not a class " <>
             "progression. Fandom's table ends at level 39 because vanilla caps at 40, " <>
             "so what Siala's level 41 grants is unknown."}
        ],
      ["Base attack"],
      context,
      series_problems(series, "epic attack bonus", 21, 2)
    )
  end

  defp epic_save_bonus(context) do
    series = series(context, "Base save", "character level", "epic base save")
    rule = line(context, "Base save", ~r/all three base saves increase \+1 at each even/i)
    multiclass = line(context, "Base save", ~r/must be taken prior to character level 21/i)

    block(
      series_pairs(series) ++
        [
          {"applies_to", gated(rule, ["fortitude", "reflex", "will"])},
          {"added_to_base_saves_at_character_level", gated(rule, 20)},
          {"class_levels_after_20_add_base_saves", gated(rule, false)},
          {"at_character_level_41", nil},
          {"rule_raw", rule},
          {"multiclass_raw", multiclass},
          {"note",
           "Added to the base saves the character had at level 20, so an epic " <>
             "character's base saves depend on both character level and the class split " <>
             "at level 20 — including the +2 a class grants at its own first level, which " <>
             "is why a class picked up in the epics adds nothing. Fandom's table ends at " <>
             "level 40, so what Siala's level 41 grants is unknown."}
        ],
      ["Base save"],
      context,
      series_problems(series, "epic base save", 22, 2)
    )
  end

  # Three separate pages state this, which is why the flag is worth emitting at
  # all: the epic bonus raises every attack in the sequence but never adds one to
  # it. Read the other way round it would inflate every epic melee build by a
  # whole attack per round.
  defp attacks_per_round(context) do
    apr = line(context, "Attacks per round", ~r/maximum number of attacks is determined by/i)

    bab =
      line(context, "Base attack bonus", ~r/additional attacks are not gained after level 20/i)

    unarmed = line(context, "Unarmed base attack bonus", ~r/based upon the base attack achieved/i)

    block(
      [
        {"epic_bonus_adds_attacks", gated(apr && bab, false)},
        {"determined_by_bab_at_character_level", gated(apr, 20)},
        {"same_for_monk_unarmed", gated(unarmed, true)},
        {"attacks_per_round_raw", apr},
        {"base_attack_bonus_raw", bab},
        {"unarmed_raw", unarmed}
      ],
      ["Attacks per round", "Base attack bonus", "Unarmed base attack bonus"],
      context,
      []
    )
  end

  defp general_feats(context) do
    pre_epic = ordinal_levels(context, :pre_epic, :general_feats)
    epic = ordinal_levels(context, :epic, :general_feats)

    rule =
      line(context, "General feat", ~r/The first general feat is chosen at character creation/i)

    block(
      [
        {"pre_epic_levels", pre_epic},
        {"epic_levels", epic},
        {"every_n_levels", constant_step(epic)},
        {"continues_pre_epic_cadence", continues?(pre_epic, epic)},
        {"total_by_character_level_40", last_ordinal(context, :epic, :general_feats)},
        {"at_character_level_41", nil},
        {"rule_raw", rule},
        {"note",
         "General feats come from character level and are separate from class bonus " <>
           "feat slots; the one at level 1 comes from character creation, not from the " <>
           "every-three-levels cadence. The source enumerates them only up to level 39."}
      ],
      ["Level progression", "General feat"],
      context,
      ordinal_problems(pre_epic, epic, "general feat")
    )
  end

  defp ability_increases(context) do
    pre_epic = ordinal_levels(context, :pre_epic, :ability_increases)
    epic = ordinal_levels(context, :epic, :ability_increases)

    rule =
      line(context, "Ability score", ~r/every four \[\[character level\]\]s a single ability/i)

    block(
      [
        {"pre_epic_levels", pre_epic},
        {"epic_levels", epic},
        {"every_n_levels", constant_step(epic)},
        {"continues_pre_epic_cadence", continues?(pre_epic, epic)},
        {"total_by_character_level_40", last_ordinal(context, :epic, :ability_increases)},
        {"at_character_level_41", nil},
        {"rule_raw", rule},
        {"note", "The source enumerates ability increases only up to level 40."}
      ],
      ["Level progression", "Ability score"],
      context,
      ordinal_problems(pre_epic, epic, "ability increase")
    )
  end

  # Rank caps are the one part of the skill system the epic table states outright,
  # level by level — so the pre-epic formula is not assumed to carry over, it is
  # checked against all forty rows.
  defp skill_ranks(context) do
    rows = level_rows(context, :pre_epic) ++ level_rows(context, :epic)
    class_rule = line(context, "Skill point", ~r/maximum number of ranks a class skill/i)
    cross_rule = line(context, "Skill point", ~r/maximum for a cross-class skill is half/i)

    max? = rows != [] and Enum.all?(rows, &(&1.max_skill_rank == &1.level + 3))

    cross? =
      rows != [] and Enum.all?(rows, &(&1.cross_class_max_rank == div(&1.max_skill_rank, 2)))

    problems =
      failures([
        {max?, "max skill rank is not character level + 3 on every row"},
        {cross?, "cross-class max is not half the max rank on every row"}
      ])

    block(
      [
        {"max_rank_formula", if(max?, do: "character_level + 3")},
        {"cross_class_max_rank_formula", if(cross?, do: "floor(max_rank / 2)")},
        {"unchanged_in_epic", if(rows != [], do: max? and cross?)},
        {"verified_for_character_levels", if(rows != [], do: length(rows))},
        {"at_character_level_41", nil},
        {"class_skill_raw", class_rule},
        {"cross_class_skill_raw", cross_rule},
        {"note",
         "Per-level values are in `level_table`. The source tabulates rank caps only up " <>
           "to level 40."}
      ],
      ["Level progression", "Skill point"],
      context,
      problems
    )
  end

  # Nothing on Fandom says what happens to skill points per level in the epics,
  # which is not the same as saying nothing changes. The general rule is quoted
  # and the epic override stays null.
  defp skill_points(context) do
    block(
      [
        {"per_level_raw",
         line(context, "Skill point", ~r/Each class has a number of skill points/i)},
        {"epic_override", nil},
        {"note",
         "The page states the per-level formula (class value + intelligence modifier, " <>
           "minimum 1, quadrupled at character level 1) with no level bound and says " <>
           "nothing specific about the epics. No epic-specific statement was found on " <>
           "either wiki, which is not evidence that nothing changes."}
      ],
      ["Skill point"],
      context,
      []
    )
  end

  defp hit_points(context) do
    rule = line(context, "Hit point", ~r/At \[\[character level\]\]s 1 through 3/i)

    block(
      [
        {"hit_die_source", gated(rule, "class taken at that level")},
        {"epic_override", nil},
        {"rule_raw", rule},
        {"note",
         "The rule is written per character level with no epic clause, and the epic rows " <>
           "of every class page keep quoting the same hit die range " <>
           "(`epic_progression[].hp_raw` in classes.json), so epic levels appear to roll " <>
           "the ordinary class hit die. No page states that in so many words."}
      ],
      ["Hit point"],
      context,
      []
    )
  end

  defp epic_thresholds(context) do
    character = line(context, "Epic character", ~r/become epic characters once they have gained/i)
    class = line(context, "Epic class", ~r/To become epic with a specific/i)
    never = line(context, "Epic class", ~r/only able to attain five levels/i)
    prestige = line(context, "Prestige class", ~r/Prestige classes are limited to 10/i)

    block(
      [
        {"epic_character_from_character_level", gated(character, 21)},
        {"epic_base_class_from_class_level", gated(class, 21)},
        {"epic_prestige_class_from_class_level", gated(class, 11)},
        {"prestige_11th_level_requires_character_level", gated(class, 20)},
        {"prestige_max_class_level_through_character_level_20", gated(prestige, 10)},
        {"prestige_max_class_level_in_epics", nil},
        {"never_epic", gated(never, ["harper_scout", "purple_dragon_knight"])},
        {"never_epic_max_class_level", gated(never, 5)},
        {"epic_character_raw", character},
        {"epic_class_raw", class},
        {"never_epic_raw", never},
        {"prestige_class_raw", prestige},
        {"note",
         "Vanilla puts no cap on prestige levels past character level 20 beyond the " <>
           "character level cap itself, hence the null. Siala differs — `41-ый уровень` " <>
           "says a prestige class may be taken to level 31 — but that is the shard " <>
           "override layer's business, not this file's."}
      ],
      ["Epic character", "Epic class", "Prestige class"],
      context,
      []
    )
  end

  defp class_epic_bonus_feats(context) do
    block(
      [
        {"per_class", "priv/rules/vanilla/classes.json → epic_bonus_feat_levels"},
        {"rule_raw",
         line(context, "Bonus feat", ~r/An '''epic bonus feat''' is a bonus feat choice/i)},
        {"note",
         "Epic bonus feats are the one epic benefit that is class-based, and they are " <>
           "already parsed per class off the class pages, so they are not duplicated " <>
           "here. Mechanically they behave like any other bonus feat and draw on the " <>
           "same single per-class list."}
      ],
      ["Bonus feat"],
      context,
      []
    )
  end

  defp level_table(context) do
    rows = level_rows(context, :epic)
    attack = series(context, "Base attack", "character level", "epic attack bonus")
    save = series(context, "Base save", "character level", "epic base save")

    json =
      Enum.map(rows, fn row ->
        {:obj,
         [
           {"character_level", row.level},
           {"required_xp", row.required_xp},
           {"epic_attack_bonus", row.epic_attack_bonus},
           {"epic_save_bonus", row.epic_save_bonus},
           {"max_skill_rank", row.max_skill_rank},
           {"cross_class_max_rank", row.cross_class_max_rank},
           {"general_feat", row.general_feats},
           {"ability_increase", row.ability_increases}
         ]}
      end)

    problems =
      if(rows == [], do: ["no epic level table"], else: []) ++
        cross_check(rows, attack, :epic_attack_bonus, "epic attack bonus") ++
        cross_check(rows, save, :epic_save_bonus, "epic save bonus")

    block(
      [
        {"first_character_level", rows != [] && List.first(rows).level},
        {"last_character_level", rows != [] && List.last(rows).level},
        {"rows", json}
      ],
      ["Level progression"],
      context,
      problems
    )
  end

  # `Level progression` gives the running total at every level; `Base attack` and
  # `Base save` give the levels at which it steps. Two pages, two authors — same
  # numbers, or the block is a conflict.
  defp cross_check(_rows, nil, _field, label), do: ["no #{label} series to cross-check against"]

  defp cross_check(rows, series, field, label) do
    Enum.flat_map(rows, fn row ->
      expected = Enum.count(series, fn {level, _bonus} -> level <= row.level end)
      actual = Map.fetch!(row, field)

      if actual == expected do
        []
      else
        [
          "#{label} at level #{row.level}: Level progression says #{actual}, " <>
            "the per-level series implies #{expected}"
        ]
      end
    end)
  end

  defp epic_starts_at(context) do
    context
    |> line("Epic character", ~r/become epic characters once they have gained/i)
    |> gated(21)
  end

  defp character_level_cap(context) do
    context
    |> line("Character level", ~r/raises this limit to 40/i)
    |> gated(40)
  end

  defp open_questions do
    [
      "Character level 41 — Siala's cap — is outside every Fandom table: whether it " <>
        "grants +1 epic attack bonus, a general feat, an ability increase or a higher " <>
        "skill rank cap is unknown. Only the shard admins or an in-game character sheet " <>
        "can answer it.",
      "Whether skill points per level change in the epics is stated nowhere on either " <>
        "wiki.",
      "That epic hit points roll the ordinary class hit die is implied by the class " <>
        "tables but never stated outright.",
      "Siala's `41-ый уровень` raises the prestige class cap to 31 levels and defines a " <>
        "\"pure\" level-41 caster; those are shard overrides and belong in a siala_41 " <>
        "layer, which does not exist yet.",
      "Siala's wiki says nothing at all about epic attack, saves, feats, skill or " <>
        "ability progression, so everything in this file is assumed to hold there " <>
        "unchanged."
    ]
  end

  # ── reading the tables ────────────────────────────────────────────────────

  # A two-row transposed table: `! Character level | 21 || 23 || …` sitting over
  # `! Epic attack bonus | +1 || +2 || …`.
  defp series(context, title, level_label, value_label) do
    with %{grids: grids} <- page(context, title) do
      Enum.find_value(grids, fn grid ->
        levels = labelled_row(grid, level_label)
        values = labelled_row(grid, value_label)

        if levels && values && length(levels) == length(values) do
          Enum.zip(Enum.map(levels, &integer/1), Enum.map(values, &integer/1))
        end
      end)
    end
  end

  defp labelled_row(grid, label) do
    Enum.find_value(grid, fn
      [first | rest] ->
        if first.header? and normalize(first.text) == label, do: Enum.map(rest, & &1.text)

      [] ->
        nil
    end)
  end

  defp series_pairs(nil) do
    [
      {"table", nil},
      {"levels", nil},
      {"level_step", nil},
      {"bonus_step", nil},
      {"parity", nil},
      {"first_level", nil},
      {"last_level_in_source", nil},
      {"max_bonus_in_source", nil}
    ]
  end

  defp series_pairs(series) do
    levels = Enum.map(series, fn {level, _bonus} -> level end)
    bonuses = Enum.map(series, fn {_level, bonus} -> bonus end)

    [
      {"table",
       Enum.map(series, fn {level, bonus} ->
         {:obj, [{"character_level", level}, {"bonus", bonus}]}
       end)},
      {"levels", levels},
      {"level_step", constant_step(levels)},
      {"bonus_step", constant_step(bonuses)},
      {"parity", parity(levels)},
      {"first_level", List.first(levels)},
      {"last_level_in_source", List.last(levels)},
      {"max_bonus_in_source", List.last(bonuses)}
    ]
  end

  defp series_problems(nil, label, _first, _step), do: ["no #{label} table"]

  defp series_problems(series, label, first, step) do
    levels = Enum.map(series, fn {level, _bonus} -> level end)
    bonuses = Enum.map(series, fn {_level, bonus} -> bonus end)

    failures([
      {List.first(levels) == first,
       "#{label} starts at #{List.first(levels)}, expected #{first}"},
      {constant_step(levels) == step, "#{label} levels do not step by #{step}"},
      {bonuses == Enum.to_list(1..length(bonuses)//1),
       "#{label} does not go up by exactly 1 each time"}
    ])
  end

  # The two `Level progression` tables: only the epic one has epic columns.
  defp level_rows(context, which) do
    with %{grids: grids} <- page(context, "Level progression"),
         table when not is_nil(table) <- find_table(grids, which) do
      Enum.flat_map(table.body, fn cells ->
        case integer(cell(table, cells, "level")) do
          nil -> []
          level -> [row(table, cells, level)]
        end
      end)
    else
      _otherwise -> []
    end
  end

  defp find_table(grids, which) do
    Enum.find_value(grids, fn
      [header | body] ->
        columns = Enum.map(header, &normalize(&1.text))
        epic? = "epic attack bonus" in columns

        if Enum.all?(header, & &1.header?) and "level" in columns and epic? == (which == :epic) do
          %{columns: columns, body: body}
        end

      _grid ->
        nil
    end)
  end

  defp row(table, cells, level) do
    %{
      level: level,
      required_xp: integer(cell(table, cells, "required xp")),
      epic_attack_bonus: integer(cell(table, cells, "epic attack bonus")),
      epic_save_bonus: integer(cell(table, cells, "epic save bonus")),
      max_skill_rank: integer(cell(table, cells, "max skill rank")),
      cross_class_max_rank: integer(cell(table, cells, "cross-class max")),
      general_feats: ordinal(cell(table, cells, "general feats")),
      ability_increases:
        ordinal(cell(table, cells, "ability increase") || cell(table, cells, "ability increases"))
    }
  end

  defp cell(table, cells, column) do
    case Enum.find_index(table.columns, &(&1 == column)) do
      nil -> nil
      index -> cells |> Enum.at(index) |> then(&(&1 && &1.text))
    end
  end

  # The levels at which an ordinal column ("8th") carries a value.
  defp ordinal_levels(context, which, key) do
    case level_rows(context, which) do
      [] -> nil
      rows -> for row <- rows, Map.fetch!(row, key), do: row.level
    end
  end

  defp last_ordinal(context, which, key) do
    context
    |> level_rows(which)
    |> Enum.map(&Map.fetch!(&1, key))
    |> Enum.reject(&is_nil/1)
    |> List.last()
  end

  # "Continues" means two things and both are checked: the epic levels step evenly,
  # and the gap across the level-20 boundary is that same step. Comparing the whole
  # pre-epic run instead would be wrong — the first general feat comes from
  # character creation rather than from the every-three-levels cadence, so levels
  # 1 and 3 sit two apart and no rule is broken by it.
  defp continues?(pre_epic, epic) when pre_epic in [nil, []] or epic in [nil, []], do: nil

  defp continues?(pre_epic, epic) do
    case constant_step(epic) do
      nil -> nil
      step -> List.first(epic) - List.last(pre_epic) == step
    end
  end

  defp ordinal_problems(nil, _epic, label), do: ["no pre-epic #{label} column"]
  defp ordinal_problems(_pre_epic, nil, label), do: ["no epic #{label} column"]
  defp ordinal_problems(_pre_epic, [], label), do: ["no epic #{label} levels"]

  defp ordinal_problems(_pre_epic, epic, label) do
    failures([{constant_step(epic) != nil, "epic #{label} levels do not step evenly"}])
  end

  defp failures(checks), do: for({false, message} <- checks, do: message)

  defp constant_step(values) when length(values) < 2, do: nil

  defp constant_step(values) do
    steps =
      values
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)
      |> Enum.uniq()

    case steps do
      [step] -> step
      _mixed -> nil
    end
  end

  defp parity(levels) do
    cond do
      Enum.all?(levels, &(rem(&1, 2) == 1)) -> "odd"
      Enum.all?(levels, &(rem(&1, 2) == 0)) -> "even"
      true -> nil
    end
  end

  # ── reading the prose ─────────────────────────────────────────────────────

  defp line(context, title, anchor) do
    with %{wikitext: wikitext} <- page(context, title) do
      wikitext
      |> String.split("\n")
      |> Enum.find(&Regex.match?(anchor, &1))
      |> then(&(&1 && String.trim(&1)))
    end
  end

  # A value stated only in prose is emitted only while the sentence stating it is
  # still on the page.
  defp gated(nil, _value), do: nil
  defp gated(_line, value), do: value

  # ── assembling a block ────────────────────────────────────────────────────

  defp block(pairs, titles, context, problems) do
    json =
      {:obj,
       pairs ++
         [
           {"sources", Enum.map(titles, &source(context, &1))},
           {"status", if(problems == [], do: "parsed", else: "conflict")},
           {"conflict_note", if(problems != [], do: Enum.join(problems, "; "))}
         ]}

    %{json: json, problems: problems}
  end

  defp source(context, title) do
    entry = with %{entry: entry} <- page(context, title), do: entry

    {:obj,
     [
       {"wiki", @wiki},
       {"page", title},
       {"revid", entry && entry.revid},
       {"fetched", entry && entry.fetched}
     ]}
  end

  # ── scalars ───────────────────────────────────────────────────────────────

  defp normalize(text) do
    text
    |> Wikitext.strip_links()
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp integer(nil), do: nil

  defp integer(text) do
    case Regex.run(~r/^\s*([+-]?[\d,]+)\s*$/, Wikitext.strip_links(text)) do
      [_, digits] -> digits |> String.replace(",", "") |> String.to_integer()
      nil -> nil
    end
  end

  # "8th" is the eighth general feat, not level 8.
  defp ordinal(nil), do: nil

  defp ordinal(text) do
    case Regex.run(~r/^\s*(\d+)(?:st|nd|rd|th)\s*$/i, Wikitext.strip_links(text)) do
      [_, digits] -> String.to_integer(digits)
      nil -> nil
    end
  end
end
