defmodule BuildCalculator.Rules.Spells do
  @moduledoc """
  Two different mechanics that must never be confused (CLAUDE.md §6).

    * **Spells known** (Sorcerer, Bard) — a choice made *for good* at level-up.
      It is a decision of the level, so it belongs beside the feats and in the
      progression column. "New spells this level" is the difference between the
      `spells_known` row for this class level and the row before it: on Sorcerer
      7 that is one of circle 1, one of circle 2 and one of circle 3 — exactly
      the slot model the feats already use, which is why the interface reuses
      the same chips.
    * **Slots per day** (every caster) — not a choice but a derived statistic.
      It belongs in the totals panel next to BAB and the saves.

  ## The level-20 wall

  ⚠ **No caster has an epic spell progression.** Both tables stop at **class**
  level 20: Sorcerer 20 and Sorcerer 41 know the same 41 spells and have the
  same slots. Class levels past the twentieth give hit points, saves and feats
  and nothing else.

  This is not a footnote to handle quietly — it is the mistake on which a player
  loses half a build, so `per_day/2` returns `past_table?` and the level scene
  says it out loud instead of showing an empty list.

  ## The 41st level

  Siala's own top level grants no choice of spells at all
  (`epic.spell_selection_at_41`), which is a separate thing from the wall above:
  the wall is a table running out, this is the shard forbidding the choice on a
  level whose table may still be running. Read from the ruleset, so vanilla —
  which states no such rule — is unaffected.

  ## A prestige class that pushes somebody else's table

  Pale Master hands its host caster extra **slots** and nothing else: «Pale master
  levels augment spell slots, but otherwise do not affect spellcasting. Thus, a
  level 10 sorcerer / 19 pale master has the same spells per day as a level 20
  sorcerer, but has a caster level of only 10 and only knows as many spells as a
  level 10 sorcerer» (Fandom «Pale master», revid 71581).

  Three things about it are easy to get wrong and all three are in the data
  (`priv/rules/vanilla/spellcasting.json`), never here:

    * it is **odd class levels only** — the page lists 1, 3, 5, 7, 9 and then
      «at every odd pale master level». The page's own example does not
      discriminate (both readings cap at 20 there), so it is the sentence that
      decides and not the arithmetic;
    * it moves `spells_per_day` and **not** `spells_known` — a Bard 4 / Pale
      Master 30 has the slots of a bard 19 and the known spells of a bard 4;
    * the host is «his highest caster class (bard, sorcerer or wizard)», arcane
      only, so a Cleric gets nothing from it.

  No class is named in this module. `ruleset.casting.advancement` is keyed by the
  prestige class, and everything above is a field of the record.

  ⚠ Two hosts tied for highest is a case no source settles, so `advancement/2`
  advances **neither** and names the prestige class in `undecided`. Understating
  is the safe direction — it refuses rather than grants — but it is still an
  answer we do not have, so `Rules.Prereqs` says so out loud where it changes a
  verdict.

  ## A class that bends its own table (AGENT_QUEUE.md §3.10)

  A Wizard may name a spell school as a one-time choice on the class's own
  first level (`Rules.ClassChoices`, the same mechanism a Cleric's two domains
  use) and gain a flat bonus to every circle of daily slots it already has —
  «gaining one additional prepared spell per spell level» (Fandom «Wizard»).
  The choice itself is `ClassChoices`' business; the bonus it produces is a
  number, so it lives here, read out of `ruleset.casting.school_specialization`
  (keyed by class, same shape as `advancement` above — no class id named in this
  module either).

  ⚠ Only circles the row **already lists** gain the bonus. A circle the
  character cannot yet cast is simply absent from `slots` (`last_row_at/2`),
  and specialization does not invent one — it makes an existing slot bigger,
  never a new one.

  ⚠ Whether circle 0 (cantrips) shares in the bonus is genuinely unsettled by
  the source — neither Fandom quote says «per spell level» does or does not
  include it — so the data states a decision (`min_circle: 1`, cantrips
  excluded) rather than the code assuming one. ⚠ Until 09.08.2026 this travelled
  as `{:assumed, :wizard_specialization_excludes_cantrips}`; Dan measured it in
  game (wizard 1, INT 11, Conjuration: circle 0 shows 3, circle 1 shows 2), the
  decision became a fact, and the gap was removed rather than left to frighten
  the reader about something now settled.

  What specialization also does — forbid casting the opposed school, scrolls
  included — has nothing here to **check**: no class in the data models which
  spells a Wizard prepares or can cast, so no number of ours moves with it. Its
  **size** is a different question and it is answered: `specialization_costs/2`
  pairs every school with how many spells of the class's own list the opposed
  one takes away, so the choice can name what it gives and what it takes in one
  breath (task 3.86). ⚠ Until 24.08.2026 this travelled as `{:not_modelled,
  :wizard_opposed_school}` — «мы показываем игроку одну выгоду». The gap is gone
  because the answer grew, not because the restriction became checkable.

  ⚠ The count is over the class's **whole** list, not over the circles the
  character has reached: the school is named once and kept for the rest of the
  build, so what it costs is a lifetime figure (решение Dan). And it is counted
  off `spell.school` in the loaded ruleset, which is the shard's school where
  the shard moved it — Siala takes five of the Bigby spells out of evocation
  and into enchantment, so counting off vanilla's column would understate what
  Illusion costs by four spells out of twenty.

  ## Bonus slots for a high casting ability (task 3.70)

  «Spellcasters receive bonus spell slots for high casting abilities … these
  bonuses are determined by the modifier for the relevant ability … In order to
  receive a bonus spell slot of a given level, the caster must have spell slots
  of that level by virtue of class level. For this purpose, having "0" spell
  slots counts (but having "-" spell slots does not)» (Fandom «Ability modifier»
  §Spellcasting, revid 71035 — `Bonus spells` redirects onto it).

  Four conditions, and every one of them is a line of `ruleset.casting.
  bonus_slots` rather than a decision made here:

    * the circle must already be **in the class row** — a printed `0` is a key
      of that row and an empty cell is an absent key, which is the distinction
      `spells_per_day` carries all the way from the parser. This is what lets a
      Paladin 4 with wisdom 12 cast at all, three class levels before a Paladin
      with wisdom 10;
    * **cantrips never** (`min_circle`), and this one the source states outright
      — unlike the Wizard's school bonus above, where the same question had to
      be decided and then measured;
    * the ability is the class's own (`casting_ability`), so no ability is named
      here either;
    * the modifier is the **modified** one, gear included. Not a reading of ours:
      one sentence of every caster's page opposes the two — «a base charisma
      score of 10 + the spell's level is required to cast a spell, bonus spells
      are based on modified charisma». ⚠ Not to be confused with a **feat's**
      prerequisite, where gear does not count (S1/S2): different rule, different
      question.

  ⚠ The bonus can turn a `0` into a `1`, so `casters_for_circle/3` — and through
  it `casts_spell_level` — depends on the character's abilities now, which it did
  not before. That is the rule, not a leak: a Bard 2 with charisma 12 really
  does cast first-circle spells and one with charisma 10 really does not.

  ## Relearning

  In game a Sorcerer may drop one known spell for another at any level-up
  (`source: user`). It is deliberately **not** in the constructor — Dan's call:
  a rare move whose support would turn "spells known" from an accumulation of
  choices into the result of replaying a history of swaps, an extra mode
  everybody pays attention for. So known spells are a plain accumulation.
  """

  alias BuildCalculator.Rules.{Abilities, Build}

  @type slot :: %{id: {:circle, pos_integer(), non_neg_integer()}, circle: non_neg_integer()}

  @typedoc """
  Why a circle the class row names is out of reach: the score the caster's own
  ability has to make and does not.

  The same tuple `BuildCalculator.Rules.Prereqs` refuses a feat with, because it
  is the same fact — a score of 10 + the circle, off the same rule and the same
  citation. One form, one Russian caption in the web layer.
  """
  @type unmet_circle :: {:requires_ability, atom(), pos_integer()}

  @doc """
  New spells the class taken at character `level` grants a choice of.

  The difference between two rows of `spells_known`, one slot per new spell,
  sorted by circle. Empty for a class that knows no spells, and empty past the
  end of the table — which is a fact about the build, not a missing row.
  """
  @spec slots_at(Build.t(), map(), pos_integer()) :: [slot()]
  def slots_at(%Build{} = build, ruleset, level) when level >= 1 do
    with true <- selectable_level?(ruleset, level),
         class when not is_nil(class) <- Build.class_at(build, level),
         {:ok, %{spells_known: known}} when map_size(known) > 0 <-
           Map.fetch(ruleset.classes, class),
         class_level = Build.class_level_at(build, level),
         {:ok, now} <- Map.fetch(known, class_level) do
      before = Map.get(known, class_level - 1, %{})

      for {circle, count} <- Enum.sort(now),
          index <- 0..(count - Map.get(before, circle, 0) - 1)//1 do
        %{id: {:circle, circle, index}, circle: circle}
      end
    else
      _ -> []
    end
  end

  def slots_at(%Build{}, _ruleset, _level), do: []

  @doc """
  Every known-spell slot in the build, as `%{character_level => [slot]}`.

  Levels that grant none are absent rather than mapped to `[]` — the same shape
  `BuildCalculator.Rules.FeatSlots.all/2` returns.
  """
  @spec slots(Build.t(), map()) :: %{pos_integer() => [slot()]}
  def slots(%Build{} = build, ruleset) do
    for level <- 1..max(Build.character_level(build), 0)//1,
        slots = slots_at(build, ruleset, level),
        slots != [],
        into: %{},
        do: {level, slots}
  end

  @doc "Spell ids known by the end of `level`."
  @spec known(Build.t(), non_neg_integer()) :: MapSet.t(atom())
  def known(%Build{spells: spells}, level) do
    for {lv, at} <- spells, lv <= level, {_slot, id} <- at, into: MapSet.new(), do: id
  end

  @doc """
  Slots per day, one entry per casting class in the build.

  `class_level` is what the character actually has; `table_level` is the row
  actually read, capped at the last row the table has. When the two differ,
  `past_table?` is true and the player must be told — that is the level-20 wall.

  ## Two readings of the row, and which is which (task 3.125)

  `slots` is what the character **has**: the row after the casting floor, the
  spellbook reading. `offered_slots` is the row before it — the class table plus
  specialization plus the ability bonus — and `unmet_circles` says which circles
  the two differ by and why.

  🔴 **Measured.** Dan on a Wizard 8 with intelligence 11 (`GAME_CHECKS.md`
  AE2): «2 круг так и не появился». His class row prints three second-circle
  slots and the game shows him none, because casting a circle needs a score of
  10 + the circle (`minimum_ability_score/2`). Until this task `slots` was the
  row, so the panel printed the three.

  ⚠ **The floor is applied AFTER the ability bonus, not before**, and that
  ordering is the whole of Dan's second decision: a Paladin 4 with wisdom 12
  has a printed `0` at the first circle, which the bonus turns into a real slot
  — cut first and he would lose the very slot he raised wisdom for.

  ⚠ **`offered_slots` is what a feat prerequisite asks about**, and it must
  stay the row: a Bard 4 with charisma 11 is refused the circle here and still
  offered `Empower Spell` (task 3.124, measured). `casters_for_circle/3` and
  `casters_offered_circle/3` therefore read `offered_slots`, never `slots` —
  they answer "what does the table say", and this key answers "what can he
  cast".
  """
  @spec per_day(Build.t(), map()) :: [
          %{
            class: atom(),
            class_level: pos_integer(),
            table_level: pos_integer(),
            past_table?: boolean(),
            slots: %{non_neg_integer() => non_neg_integer()},
            offered_slots: %{non_neg_integer() => non_neg_integer()},
            unmet_circles: %{non_neg_integer() => unmet_circle()},
            knows_spells?: boolean(),
            advanced_levels: non_neg_integer(),
            advanced_by: [atom()],
            specialized_school: atom() | nil,
            ability: atom() | nil,
            ability_modifier: integer() | nil,
            ability_bonus: %{non_neg_integer() => pos_integer()}
          }
        ]
  def per_day(%Build{} = build, ruleset) do
    advanced = advancement(build, ruleset).hosts

    # One assembly of the ability scores for the whole call rather than one per
    # casting class: `Abilities.scores_at/3` walks the build's feats, and a
    # four-class build would otherwise walk them four times for one answer.
    #
    # ⚠ Both readings are assembled because the source opposes them inside one
    # sentence — «a base charisma score of 10 + the spell's level is required to
    # cast a spell, bonus spells are based on modified charisma». The bonus
    # below reads the **modified** modifier; the floor reads the **smaller** of
    # the two scores, which is the base one for as long as gear only ever adds.
    base_scores = Abilities.scores_at(build, ruleset, Build.character_level(build))
    {geared_scores, _bonuses, _capped?} = Abilities.with_gear(base_scores, build, ruleset)
    modifiers = Abilities.modifiers(geared_scores)
    casting_scores = casting_scores(base_scores, geared_scores)

    for {class, class_level} <- Enum.sort(Build.class_levels(build)),
        definition = Map.get(ruleset.classes, class),
        definition != nil,
        map_size(definition.spells_per_day) > 0,
        lent = Map.get(advanced, class, %{levels: 0, from: []}),
        # The row read is the class's own level plus what a prestige class lent
        # it, and the class's own level is what the character actually has. Both
        # travel, because the interface has to be able to say why a sorcerer 10
        # reads off row 20 — a number that grew for a reason nobody typed looks
        # like a bug.
        reached = class_level + lent.levels,
        table_level = min(reached, definition.spell_table_max_class_level || reached),
        base_slots = last_row_at(definition.spells_per_day, table_level),
        base_slots != %{} do
      # A class's own choice may bend this same row — a Wizard's school
      # (`ruleset.casting.school_specialization`, see the moduledoc). `chosen`
      # is `[]` for every class without the choice at all and for a Wizard who
      # stayed general, so both read as "no bonus" through the same path.
      chosen = Build.class_choice(build, class)

      # ⚠ Both bonuses are read off `base_slots` — the row the class table
      # itself gives — and not off each other's output. That is what the source
      # means by «by virtue of class level», and it also makes the two
      # independent: neither can lift the other over a threshold, and the order
      # they are summed in cannot matter.
      ability = definition.casting_ability
      modifier = ability && Map.get(modifiers, ability)
      ability_bonus = ability_bonus(ruleset, base_slots, modifier)

      offered =
        base_slots
        |> specialization_bonus(ruleset, class, chosen)
        |> add_bonus(ability_bonus)

      # ⚠ Last, and that is the rule rather than the order the code came out
      # in: the bonus above turns a printed `0` into a real slot, so a floor
      # applied to `base_slots` would take away the first circle from the very
      # Paladin whose wisdom just bought it (Dan's decision, task 3.125).
      unmet = unmet(ruleset, ability, Map.get(casting_scores, ability), Map.keys(offered))

      %{
        class: class,
        class_level: class_level,
        table_level: table_level,
        past_table?: reached > table_level,
        slots: Map.drop(offered, Map.keys(unmet)),
        offered_slots: offered,
        unmet_circles: unmet,
        knows_spells?: map_size(definition.spells_known) > 0,
        advanced_levels: lent.levels,
        advanced_by: lent.from,
        specialized_school: if(chosen != [] and specialization(ruleset, class), do: hd(chosen)),
        # The three travel so the panel can say *why* the row grew. A number
        # that moved for a reason nobody typed reads as a bug — the same
        # argument `table_level` and `specialized_school` are here for.
        ability: ability,
        ability_modifier: modifier,
        ability_bonus: ability_bonus
      }
    end
  end

  @doc """
  Bonus slots a casting ability `modifier` adds to a class row, per circle.

  `%{}` for a modifier of nil (no source names the class's ability), for a
  ruleset carrying no table, and for every modifier the table gives nothing for
  — a build with charisma 10 is not a build we failed to compute.

  Only circles the row **already lists** appear, and a listed `0` is a circle:
  «the caster must have spell slots of that level by virtue of class level. For
  this purpose, having "0" spell slots counts (but having "-" spell slots does
  not)».
  """
  @spec ability_bonus(map(), %{non_neg_integer() => non_neg_integer()}, integer() | nil) ::
          %{non_neg_integer() => pos_integer()}
  def ability_bonus(_ruleset, _row, nil), do: %{}

  def ability_bonus(ruleset, row, modifier) when is_integer(modifier) do
    case bonus_slot_rule(ruleset) do
      nil ->
        %{}

      rule ->
        for {circle, _count} <- row,
            circle >= rule.min_circle,
            bonus = bonus_slots(rule, modifier, circle),
            bonus > 0,
            into: %{},
            do: {circle, bonus}
    end
  end

  @doc """
  The source's own general rule for a bonus slot count, off a loaded formula.

  «As a general rule, the number of bonus spell slots of a given level is
  (modifier − spell level)/4 + 1, rounded down, with a minimum of zero» — and
  every one of those three numbers arrives in `formula`
  (`priv/rules/vanilla/spellcasting.json`), so none of them is written here.

  Public because `BuildCalculator.Data.Loader.Spells` runs it against all 234
  cells of the transcribed table at load time and refuses to build a ruleset
  where the two disagree. One implementation, checked from the other side —
  the same shape as `Rules.Attack.weapon_property_field/1`.
  """
  @spec bonus_slots_by_formula(map(), integer(), integer()) :: non_neg_integer()
  def bonus_slots_by_formula(%{divisor: divisor, plus: plus, minimum: minimum}, modifier, circle) do
    max(Integer.floor_div(modifier - circle, divisor) + plus, minimum)
  end

  defp bonus_slot_rule(ruleset) do
    ruleset |> Map.get(:casting, %{}) |> Map.get(:bonus_slots)
  end

  # The table decides wherever it speaks. Outside it — a modifier past its last
  # row, or a circle past its last column — the answer is the general rule the
  # same paragraph states, which the loader has just verified cell for cell
  # against the whole table. Clamping to the last row instead would understate
  # silently, and understating silently is the failure mode this project is
  # arranged against.
  #
  # ⚠ Unreachable today and kept anyway: point buy 18 + race 2 + ten increases +
  # ten `Great …` + two from a Red Dragon Disciple is 40, and the +12 gear
  # ceiling makes 52 — exactly the score of the table's last row.
  defp bonus_slots(rule, modifier, circle) do
    with {:ok, row} <- Map.fetch(rule.by_modifier, modifier),
         {:ok, count} <- Map.fetch(row, circle) do
      count
    else
      :error -> bonus_slots_by_formula(rule.formula, modifier, circle)
    end
  end

  defp add_bonus(slots, bonus) do
    Map.merge(slots, bonus, fn _circle, count, extra -> count + extra end)
  end

  @doc """
  The one-time school choice `class` may make, or `nil` when it has none.

  `ruleset.casting.school_specialization` keyed by class — empty for every class
  but a Wizard today, so this answers `nil` for the other six casters. No class
  id is written here; see the moduledoc.
  """
  @spec specialization(map(), atom()) :: map() | nil
  def specialization(ruleset, class) do
    ruleset |> Map.get(:casting, %{}) |> Map.get(:school_specialization, %{}) |> Map.get(class)
  end

  @doc """
  How many spells of each school `class`'s own list holds.

      %{evocation: 31, conjuration: 27, transmutation: 28, ...}

  The list is the same one `list_for/2` offers (`ruleset.spell_lists` decides
  which column of a spell names its circle for this class), so a spell whose
  circle is patch history rather than a number is out of both — it is out of the
  picker, so it is out of the count.

  ⚠ A spell whose **school** could not be read is absent too, not bucketed
  anywhere. The loader lifts the field the way it lifts a circle — the reading
  when it is unambiguous, the source string in `school_raw` when it is not — and
  no spell of any list is in that state today. `SpellSchoolTest` is what keeps
  it that way: it asserts these counts add back up to the size of the list, so a
  school that stops being readable upstream shows as a failing test rather than
  as a number quietly four short.
  """
  @spec school_counts(map(), atom()) :: %{atom() => pos_integer()}
  def school_counts(ruleset, class), do: ruleset |> list_for(class) |> counts_by_school()

  defp counts_by_school(list) do
    for %{spell: spell} <- list,
        school = Map.get(spell, :school),
        school != nil,
        reduce: %{} do
      counts -> Map.update(counts, school, 1, &(&1 + 1))
    end
  end

  @doc """
  What naming each school as `class`'s specialization takes away.

      %{illusion: %{school: :enchantment, spells: 20, list_size: 179}, ...}

  Keyed by the school the character would **name**; the value is the school that
  closes, how many spells of `class`'s own list go with it, and how big that
  list is. `%{}` for a class with no specialization record and for a school the
  record names no opposite for — an answer we do not have is left out rather
  than reported as zero, which is the one number that would read as "costs
  nothing".

  ⚠ `list_size` travels with the count rather than being left to the caller: a
  loss of 27 means nothing without what it is 27 **of**, and a denominator
  fetched separately is a denominator that can be fetched from somewhere else.

  The gain half of the same choice is `specialization/2`'s `bonus_per_circle`
  and `min_circle`; the two are deliberately separate functions, because the
  gain is one sentence for every school and the cost is a different number for
  each.
  """
  @spec specialization_costs(map(), atom()) :: %{
          atom() => %{school: atom(), spells: non_neg_integer(), list_size: non_neg_integer()}
        }
  def specialization_costs(ruleset, class) do
    case specialization(ruleset, class) do
      %{opposed_schools: opposed} when opposed != %{} ->
        list = list_for(ruleset, class)
        counts = counts_by_school(list)

        for {school, forbidden} <- opposed, into: %{} do
          {school,
           %{
             school: forbidden,
             spells: Map.get(counts, forbidden, 0),
             list_size: length(list)
           }}
        end

      _no_specialization ->
        %{}
    end
  end

  defp specialization_bonus(slots, _ruleset, _class, []), do: slots

  defp specialization_bonus(slots, ruleset, class, _chosen) do
    case specialization(ruleset, class) do
      nil ->
        slots

      %{bonus_per_circle: bonus, min_circle: min_circle} ->
        for {circle, count} <- slots, into: %{} do
          if circle >= min_circle, do: {circle, count + bonus}, else: {circle, count}
        end
    end
  end

  @doc """
  Slot-table levels a prestige class lends, per host class.

      %{hosts: %{sorcerer: %{levels: 10, from: [:pale_master]}}, undecided: []}

  `undecided` names a prestige class whose host could not be picked because two
  of its hosts are tied for highest — the page says «his highest caster class»
  and nothing settles a tie, so nothing is advanced. It is listed rather than
  dropped so a caller can refuse to answer instead of answering short.
  """
  @spec advancement(Build.t(), map()) :: %{
          hosts: %{atom() => %{levels: non_neg_integer(), from: [atom()]}},
          undecided: [atom()]
        }
  def advancement(%Build{} = build, ruleset) do
    taken = Build.class_levels(build)

    for {class, rule} <- Enum.sort(advancement_rules(ruleset)),
        class_level = Map.get(taken, class, 0),
        class_level > 0,
        reduce: %{hosts: %{}, undecided: []} do
      acc ->
        case host_for(rule, taken) do
          {:ok, host} ->
            lent = lent_levels(rule, class_level)

            update_in(acc.hosts, fn hosts ->
              Map.update(
                hosts,
                host,
                %{levels: lent, from: [class]},
                &%{levels: &1.levels + lent, from: Enum.sort([class | &1.from])}
              )
            end)

          :undecided ->
            update_in(acc.undecided, &Enum.sort([class | &1]))

          :none ->
            acc
        end
    end
  end

  @doc """
  Casting classes in the build whose slot table reaches `circle`.

  One entry per class, with the ability that class casts off — `nil` when no
  source names it, which is a fact the caller must handle rather than round down
  to "fine".

  ⚠ This is the **casting** reading: a cell of `0` is not a slot, so it does not
  reach. What a *feat prerequisite* asks is one Bard level wider and lives in
  `casters_offered_circle/3` — see its own note. The two were one function until
  27.08.2026 and the split is a measurement, not a tidy-up.

  ⚠ Read off `offered_slots` and **not** `slots`: this is one half of "able to
  cast", and the other half — the score of 10 + the circle — is asked next, by
  `Rules.Prereqs`, which needs to name it separately («нужен INT 12» is the
  useful refusal, «нужен 2-й круг» is not). Reading the floored `slots` here
  would fold the two halves into one and silently coarsen the reason (task
  3.125).
  """
  @spec casters_for_circle(Build.t(), map(), non_neg_integer()) ::
          [%{class: atom(), ability: atom() | nil}]
  def casters_for_circle(%Build{} = build, ruleset, circle) do
    for entry <- per_day(build, ruleset),
        max_circle(entry.offered_slots) >= circle do
      %{
        class: entry.class,
        ability: Map.get(Map.get(ruleset.classes, entry.class, %{}), :casting_ability)
      }
    end
  end

  @doc """
  Casting classes whose slot table **names** `circle` at all, by class level.

  A printed `0` is a circle and an empty cell is not — the very distinction the
  bonus-slot rule turns on: «the caster must have spell slots of that level by
  virtue of class level. For this purpose, having "0" spell slots counts (but
  having "-" spell slots does not)» (Fandom «Ability modifier» §Spellcasting,
  revid 71035). Both readings of the table were already in this module; only one
  of them had a name.

  🔴 **This is the question a feat prerequisite asks of a SPONTANEOUS caster,
  and it is measured.** Dan, 27.08.2026 (`GAME_CHECKS.md`, case AE1): a Bard 4
  with charisma **11** is offered `Empower Spell` and a Bard 3 is not. Bard 4 is
  the first row printing a second-circle cell and it prints `0`; Bard 3 has no
  second-circle cell at all. Charisma 11 is below the 12 that casting a
  second-circle spell needs, so the engine plainly did not ask about the ability
  — it asked about the cell.

  ⚠ **For a prepared caster it is not the whole question**, and that too is
  measured (case AE2, the same day): a Wizard 8 with intelligence 11 has a cell
  of **3** at the second circle and is offered neither the circle nor the feat.
  So this function is not the prerequisite's answer by itself — see
  `spontaneous_casters_offered_circle/3`, which is the half that is, and
  `BuildCalculator.Rules.Prereqs` for how the two halves are put together.

  ⚠ Only class ids come back, with no ability beside them, and that is the
  point rather than an omission: which ability a class casts off decides
  whether the character can **cast** the circle, and that is the other question
  (`casters_for_circle/3` plus `minimum_ability_score/2`). A caller that wants
  the ability is asking the wrong function.

  ⚠ Read off `offered_slots`, which is the row *before* the casting floor, and
  that is load-bearing rather than incidental: a Bard 4 with charisma 11 is the
  measurement this whole function exists for, and since task 3.125 he no longer
  has a second circle in `slots` at all. Reading `slots` here would take the
  measured exception away from exactly the build that proved it.

  ⚠ Safe to read a row two bonuses have already touched: neither can introduce a
  circle. The ability bonus is computed «for circles the row already lists» and
  specialization «makes an existing slot bigger, never a new one» — so the set of
  keys is the class table's own, before either.
  """
  @spec casters_offered_circle(Build.t(), map(), non_neg_integer()) :: [atom()]
  def casters_offered_circle(%Build{} = build, ruleset, circle) do
    for entry <- per_day(build, ruleset),
        Map.has_key?(entry.offered_slots, circle),
        do: entry.class
  end

  @doc """
  Spontaneous casting classes in the build whose slot table **names** `circle`.

  `casters_offered_circle/3` narrowed to the classes one sentence of the source
  grants the weaker reading of «ability to cast Nth level spells» to:

  > «Spontaneous casters ([[bard]]s and [[sorcerer]]s) can take this feat without
  > being able to cast first level spells as long as their [[class level]]
  > qualifies for at least 0 level one spell slots (that is, even if their
  > casting ability is too low to actually cast a level one spell)» —
  > `fandom:Spell focus`, Notes, revid 69073.

  🔴 **The first two words are the rule** (task 3.124). Task 3.122 applied the
  sentence to all seven casters, and Dan measured the difference the next hour:
  a Wizard 8 with intelligence 11 is offered neither the second circle nor
  `Empower Spell`, while a Bard 4 with charisma 11 is offered the feat.

  ⚠ «at least 0» is not «exactly 0», and the distinction is measured rather than
  argued: the engine's own `.билд` print (`aley.log`) carries a Bard **9** with
  charisma 11 holding `Empower Spell`, and his second-circle cell is **3**. So
  the exception is about being spontaneous, not about the cell being zero — the
  reading `GAME_CHECKS.md` AE2 offered as the alternative is false on that build.

  ⚠ Which classes those are comes from the ruleset (`casting.spontaneous`), never
  from a name in this file. A ruleset that does not say returns `[]` here — the
  exception applies to nobody, which is the strict direction, and the loader
  announces `{:missing_data, :spontaneous_casters}`.
  """
  @spec spontaneous_casters_offered_circle(Build.t(), map(), non_neg_integer()) :: [atom()]
  def spontaneous_casters_offered_circle(%Build{} = build, ruleset, circle) do
    spontaneous = spontaneous_casters(ruleset)

    for class <- casters_offered_circle(build, ruleset, circle),
        MapSet.member?(spontaneous, class),
        do: class
  end

  @doc """
  The ruleset's set of spontaneous casting classes, empty when it names none.
  """
  @spec spontaneous_casters(map()) :: MapSet.t(atom())
  def spontaneous_casters(ruleset) do
    case ruleset |> Map.get(:casting, %{}) |> Map.get(:spontaneous) do
      %MapSet{} = classes -> classes
      _no_record -> MapSet.new()
    end
  end

  @doc """
  The score a caster's own ability must reach to cast `circle`, or `nil`.

  «In order to prepare or cast a known spell, the caster must have both a *base*
  casting ability score and a modified casting ability score of at least 10 +
  spell level» (Fandom «Ability score», revid 71148). The 10 and the 1-per-circle
  come from `priv/rules/vanilla/spellcasting.json`, so a shard that moves them
  moves them in data; `nil` is "the file does not say", and then the rule is not
  checked rather than guessed.

  ⚠ «Both a base … and a modified … score» means the score to compare against
  this is the **smaller** of the two. Gear only adds today, which makes the base
  the binding one — but the day a penalty arrives from an item, the two part
  company and the modified one binds instead.

  🔴 **Asked by `casts_spell_level` for a caster who PREPARES spells, and by
  nothing else** (task 3.124). The two neighbouring tasks of 27.08.2026 moved it
  twice: 3.122 took it out of the prerequisite for all seven casters on a
  measurement of a Bard, and 3.124 put it back for the five who are not
  spontaneous, on a measurement of a Wizard. Both measurements stand; what was
  wrong in between was the scope, not either number.

  ⚠ **One thing it is still NOT wired to, and the same measurement says it
  should be.** Dan on the Wizard 8 with intelligence 11: «2 круг так и не
  появился» — the game does not show him the circle at all, and our panel prints
  the three slots his class table gives. That is a question about the number we
  print rather than about a feat, it has its own cost and its own decision, and
  it is filed rather than folded in here (`AGENT_QUEUE.md` §3.125). Until then
  the panel is knowingly generous to a caster below the floor.
  """
  @spec minimum_ability_score(map(), non_neg_integer()) :: pos_integer() | nil
  def minimum_ability_score(ruleset, circle) when is_integer(circle) do
    case ruleset |> Map.get(:casting, %{}) |> Map.get(:ability_minimum) do
      %{base: base, per_circle: per_circle} -> base + per_circle * circle
      _no_rule -> nil
    end
  end

  @doc """
  Which of `circles` `class` cannot cast **as of `level`**, and why.

  `%{circle => {:requires_ability, ability, minimum}}`, empty when every circle
  asked about is within reach — and empty, too, whenever the question cannot be
  answered: a ruleset stating no floor (`minimum_ability_score/2` is `nil`) and a
  class whose casting ability no source names. Both already travel as gaps of
  their own (`{:missing_data, :casting_ability_minimum}` and `{:missing_data,
  {:casting_ability, class}}`), and hiding a circle on a rule we do not have
  would be the one failure a player cannot see from inside the tool.

  🔴 **As of `level`, and that is the point of the argument.** `per_day/2` asks
  the same question of the finished character, because slots per day are what
  he has *now*. A known spell is the opposite: it is a decision of its own level
  and cannot be taken back (see the moduledoc on relearning), so what may be
  chosen at level 8 is decided by the scores at level 8 — the same reading
  `Rules.Skills.points_at/3` makes for skill points, and for the same reason.

  ⚠ The circles come from the caller rather than being derived here: the level
  scene asks about the slots that level actually grants, and inventing the range
  `0..9` would answer about circles no table names.
  """
  @spec unmet_circles(Build.t(), map(), atom(), [non_neg_integer()], non_neg_integer()) ::
          %{non_neg_integer() => unmet_circle()}
  def unmet_circles(%Build{} = build, ruleset, class, circles, level) do
    ability = ruleset.classes |> Map.get(class, %{}) |> Map.get(:casting_ability)

    base = Abilities.scores_at(build, ruleset, level)
    {geared, _bonuses, _capped?} = Abilities.with_gear(base, build, ruleset)

    unmet(ruleset, ability, base |> casting_scores(geared) |> Map.get(ability), circles)
  end

  # «In order to prepare or cast a known spell, the caster must have **both** a
  # base casting ability score **and** a modified casting ability score of at
  # least 10 + spell level» — so what the floor is compared against is the
  # smaller of the two. Gear only ever adds today, which makes the base the
  # binding one; the day a penalty arrives from an item the two part company and
  # the modified one binds instead, without this line changing.
  defp casting_scores(base, geared) do
    Map.new(base, fn {ability, score} ->
      {ability, min(score, Map.get(geared, ability, score))}
    end)
  end

  defp unmet(ruleset, ability, score, circles) do
    for circle <- circles,
        reason = circle_refusal(ruleset, ability, score, circle),
        into: %{},
        do: {circle, reason}
  end

  # Nothing to compare with is not "fine": both of these are announced as gaps
  # by the data layer, and the answer here is "no refusal", which leaves the
  # circle visible rather than hiding it on a rule we do not have.
  defp circle_refusal(_ruleset, nil, _score, _circle), do: nil
  defp circle_refusal(_ruleset, _ability, nil, _circle), do: nil

  defp circle_refusal(ruleset, ability, score, circle) do
    case minimum_ability_score(ruleset, circle) do
      minimum when is_integer(minimum) and score < minimum ->
        {:requires_ability, ability, minimum}

      _within_reach_or_no_rule ->
        nil
    end
  end

  @doc """
  The highest spell circle the build has slots for, `0` for a non-caster.

  Read straight off the class tables through `per_day/2` (`offered_slots`, the
  row before the casting floor — see the note below), so the level-20 wall
  applies here too: a Sorcerer 41 reaches exactly what a Sorcerer 20 reaches.
  Circle 0 (cantrips) counts as 0, which is also what a character with no
  casting class gets — the two are indistinguishable here on purpose, since no
  prerequisite in the data asks for cantrips.

  ⚠ This answers "does a class table give this character slots of circle N",
  which is **one** half of "ability to cast Nth level spells". The other half is a
  score of 10 + the circle in the class's own casting ability, and that one needs
  the character's abilities, so it cannot live in a function of the build alone —
  see `casters_for_circle/3` and `BuildCalculator.Rules.Prereqs`. A build that
  clears this and fails that cannot cast the circle.
  """
  @spec highest_circle(Build.t(), map()) :: non_neg_integer()
  def highest_circle(%Build{} = build, ruleset) do
    for %{offered_slots: slots} <- per_day(build, ruleset), reduce: 0 do
      highest -> max(highest, max_circle(slots))
    end
  end

  @doc """
  Which spells `class` may choose from, and at which circle.

  `ruleset.spell_lists` says which column of a spell entry names the circle for a
  class. A spell whose circle is written as patch history rather than a number
  (`"epic"`, `"<s>2</s> 3"`) has no circle here and is simply absent — turning
  that string into a number would be inventing one (CLAUDE.md §3).
  """
  @spec list_for(map(), atom()) :: [%{id: atom(), circle: non_neg_integer(), spell: map()}]
  def list_for(ruleset, class) do
    case Map.fetch(ruleset.spell_lists, class) do
      {:ok, key} ->
        for {id, spell} <- ruleset.spells,
            circle = Map.get(spell.levels, key),
            circle != nil,
            do: %{id: id, circle: circle, spell: spell}

      :error ->
        []
    end
  end

  # ⚠ The shard's own top level grants no *choice* of spells: «На 41-м уровне
  # нельзя выбирать заклинания» (`siala_41/overrides.json`
  # `epic.spell_selection_at_41`, wiki «41-ый уровень» revid 20387, `verified`).
  # A Bard whose table is still running there would otherwise be offered a slot
  # on the one level the shard says grants none.
  #
  # Slots per day are deliberately untouched: they are a derived statistic, not
  # a choice, and the page forbids choosing (CLAUDE.md §6). The flag comes from
  # the ruleset and vanilla's is `true`, so vanilla level 40 still chooses.
  defp selectable_level?(ruleset, level) do
    ruleset.epic.spell_selection_at_level_cap? or level < ruleset.level_cap
  end

  defp advancement_rules(ruleset) do
    ruleset |> Map.get(:casting, %{}) |> Map.get(:advancement, %{})
  end

  # Which of the rule's host classes the build advances. «His highest caster
  # class» — so the one with the most levels, and a tie is not decided here
  # because nothing decides it anywhere.
  defp host_for(rule, taken) do
    present =
      for host <- rule.hosts, level = Map.get(taken, host, 0), level > 0, do: {host, level}

    case present do
      [] ->
        :none

      present ->
        best = present |> Enum.map(&elem(&1, 1)) |> Enum.max()

        case for {host, level} <- present, level == best, do: host do
          [host] -> {:ok, host}
          _tied -> :undecided
        end
    end
  end

  # How many table levels `class_level` levels of the prestige class are worth.
  # `:odd` counts 1, 3, 5 … — ten of them by class level 19, which is exactly the
  # «level 10 sorcerer / 19 pale master ≡ level 20 sorcerer» the page states.
  defp lent_levels(%{at_class_levels: :odd, levels_per_grant: per}, class_level) do
    div(class_level + 1, 2) * per
  end

  defp lent_levels(%{at_class_levels: :every, levels_per_grant: per}, class_level) do
    class_level * per
  end

  defp max_circle(slots) do
    for {circle, count} <- slots, count > 0, reduce: 0 do
      highest -> max(highest, circle)
    end
  end

  # A caster keeps the last row it reached: a Paladin at class level 3 has no
  # row of its own (the table starts at 4), and reading "the row at or below" is
  # what the wiki table means by leaving the cell empty.
  defp last_row_at(table, level) do
    table
    |> Enum.filter(fn {row_level, _slots} -> row_level <= level end)
    |> Enum.max_by(&elem(&1, 0), fn -> {0, %{}} end)
    |> elem(1)
  end
end
