defmodule BuildCalculator.Rules.Abilities do
  @moduledoc """
  Ability scores and their modifiers.

  Scores are assembled in four layers: point-buy base, racial modifiers from the
  ruleset, the +1 taken on every fourth character level, and what the build
  earns by itself — `Great strength` and its five siblings, a Red Dragon
  Disciple's own table (`BuildCalculator.Rules.AbilityBonuses`, task 3.1).
  Equipment is a fifth layer and is applied separately (`with_gear/3`), because
  the source keeps it separate: the first four make the **base score**, gear and
  spells are "magical means" with a ceiling of their own.
  """

  alias BuildCalculator.Rules.{AbilityBonuses, Build, Gear}

  @abilities [:str, :dex, :con, :int, :wis, :cha]

  @doc "The six ability keys, in canonical order."
  @spec keys() :: [Build.ability()]
  def keys, do: @abilities

  @doc """
  Ability modifier for a score.

  `floor((score - 10) / 2)` — floored, so a score of 9 is -1 and not 0.

  The 10 is the d20 baseline the wiki states outright ("a 'typical' human having
  a score of 10 in each ability", fandom "Ability score" revid 71148); no page
  spells the division out. This is the one game formula the core keeps rather
  than reads from the ruleset, and it is on the same register as the rest —
  `{:assumed, :ability_modifier_formula, ...}` in `ruleset.gaps`.
  """
  @spec modifier(integer()) :: integer()
  def modifier(score) when is_integer(score), do: Integer.floor_div(score - 10, 2)

  @doc """
  Ability scores at the end of `level` — the **base score**, gear excluded.

  Point buy, race, the every-fourth-level increases and the build's own bonuses,
  in that order. ⚠ All four are read *as of `level`*, which is what makes this
  function different from `scores/2` and what a caller asking about a past level
  is relying on: a `Great intelligence` taken at 27 must not change the skill
  points granted at 26 (`Rules.Skills.points_at/3`).
  """
  @spec scores_at(Build.t(), map(), non_neg_integer()) :: %{Build.ability() => integer()}
  def scores_at(%Build{} = build, ruleset, level) do
    racial = racial_modifiers(build, ruleset)
    own = AbilityBonuses.by_ability(build, ruleset, level)

    base =
      Map.new(@abilities, fn ability ->
        {ability,
         Map.get(build.base_abilities, ability, 0) + Map.get(racial, ability, 0) +
           Map.get(own, ability, 0)}
      end)

    Enum.reduce(build.ability_increases, base, fn {at, ability}, acc ->
      if at <= level and ability in @abilities,
        do: Map.update!(acc, ability, &(&1 + 1)),
        else: acc
    end)
  end

  @doc "Ability scores at the end of the build."
  @spec scores(Build.t(), map()) :: %{Build.ability() => integer()}
  def scores(%Build{} = build, ruleset) do
    scores_at(build, ruleset, Build.character_level(build))
  end

  @doc "Modifiers for every ability, from `scores/2`."
  @spec modifiers(%{Build.ability() => integer()}) :: %{Build.ability() => integer()}
  def modifiers(scores),
    do: Map.new(scores, fn {ability, score} -> {ability, modifier(score)} end)

  @doc """
  `scores` with the build's equipment applied.

  `{scores, bonuses, capped?}` — the totals, the per-ability bonus that was
  actually added (after the ruleset's ceiling) and whether a typed number was
  clipped. All three are wanted by `Rules.compute/2`, which shows the bonuses and
  has to say when one was clipped.

  Fourth layer of the same assembly `scores_at/3` starts, and the order is fixed
  (CLAUDE.md §6): `point buy + race -> the +1 every fourth level -> gear`.
  """
  @spec with_gear(%{Build.ability() => integer()}, Build.t(), map()) ::
          {%{Build.ability() => integer()}, %{atom() => integer()}, boolean()}
  def with_gear(scores, %Build{gear: gear}, ruleset) do
    {bonuses, capped?} = Gear.ability_bonuses(gear, ruleset)

    totals =
      Map.new(scores, fn {ability, score} -> {ability, score + Map.get(bonuses, ability, 0)} end)

    {totals, bonuses, capped?}
  end

  @doc """
  Ability modifiers at the end of `level`, equipment included.

  What a skill's value is computed off (`BuildCalculator.Rules.Skills.value/4`).
  Gear is a single final set with no history, so it is applied whatever the level
  — the same assumption `Rules.compute/2` makes, made in one place.
  """
  @spec modifiers_at(Build.t(), map(), non_neg_integer()) :: %{Build.ability() => integer()}
  def modifiers_at(%Build{} = build, ruleset, level) do
    {scores, _bonuses, _capped?} = build |> scores_at(ruleset, level) |> with_gear(build, ruleset)
    modifiers(scores)
  end

  @typedoc """
  The floor a build's key ability may not be bought below, and what put it there.

  `minimum` is the rule's number and applies to the **final** score; `base` is
  what point buy therefore has to buy, which is a different number for a race
  with a penalty. Both travel, because an interface that shows only `base`
  cannot explain why a half-orc's floor is 13 (CLAUDE.md §6: a budget that
  silently shrank reads as a broken calculator).
  """
  @type creation_floor :: %{
          ability: Build.ability(),
          class: Build.class_id(),
          minimum: integer(),
          racial: integer(),
          base: integer()
        }

  @doc """
  The caster floor the ruleset carries, or `nil` when it carries none.

  `%{value: 11, applies_to: :final_score, applies_when: :first_class_level}` —
  the rule itself, with no build in sight, so a caller can tell "this build has
  no floor" from "nobody wrote the rule down". The two look identical once
  collapsed to a `nil` floor and they are not the same claim (HANDOFF).

  ⚠ Not to be confused with `Rules.Spells.minimum_ability_score/2`, which is the
  *other* ability rule: that one is `10 + circle` and decides whether a caster
  can cast a given circle at all. This one is about character creation and
  decides what point buy will let the player set.
  """
  @spec creation_minimum(map()) ::
          %{value: integer(), applies_to: atom(), applies_when: atom()} | nil
  def creation_minimum(ruleset) do
    case Map.get(ruleset, :point_buy) do
      %{caster_minimum: %{} = rule} -> rule
      _ -> nil
    end
  end

  @doc """
  The floor this build's **first** class puts on its casting ability, or `nil`.

  «Минимум ключевой характеристики кастера — 11, и он ИТОГОВЫЙ, то есть после
  расовых модификаторов» — measured in game (Dan, тестовый сервер, 03.08.2026;
  `priv/rules/siala_41/overrides.json` → `_vanilla_constants_confirmed`). The
  game enforces it by buying the points for you, so a human sorcerer starts on
  CHA 11 with 27 points left and a half-orc one on a bought 13 with 25.

  Three things this deliberately does **not** do:

    * it does not name a class or an ability — which ability a class casts off is
      `casting_ability`, and "is a caster" is exactly "has one". The seven
      classes the measurement covers and the seven that carry the field are the
      same seven, so the list is derived and never written down twice;
    * it does not look past character level 1. Measured from the other side too:
      a fighter with WIS 8 who takes cleric second *gets the class* and simply
      does not cast, which is `Rules.Spells`' business and not this one;
    * it does not clamp to the point-buy floor. `base` is the rule's own
      arithmetic; whether a score that low can be bought at all is the price
      table's question, and whoever prices the purchase asks it.

  ⚠ `nil` covers three cases on purpose — no rule in the data, no class taken
  yet, and a class that does not cast. A caller that has to tell them apart asks
  `creation_minimum/1` and `Build.class_at/2` itself; folding "there is no floor"
  into "we do not know" here would make the interface unable to say which.
  """
  @spec creation_floor(Build.t(), map()) :: creation_floor() | nil
  def creation_floor(%Build{} = build, ruleset) do
    with %{value: minimum, applies_to: :final_score, applies_when: :first_class_level} <-
           creation_minimum(ruleset),
         class when not is_nil(class) <- Build.class_at(build, 1),
         ability when not is_nil(ability) <- casting_ability(ruleset, class) do
      racial = build |> racial_modifiers(ruleset) |> Map.get(ability, 0)

      %{
        ability: ability,
        class: class,
        minimum: minimum,
        racial: racial,
        base: minimum - racial
      }
    else
      _ -> nil
    end
  end

  defp casting_ability(ruleset, class) do
    ruleset.classes |> Map.get(class, %{}) |> Map.get(:casting_ability)
  end

  @doc "Racial ability modifiers for the build's race, `%{}` when the race is unknown."
  @spec racial_modifiers(Build.t(), map()) :: %{Build.ability() => integer()}
  def racial_modifiers(%Build{race: nil}, _ruleset), do: %{}

  def racial_modifiers(%Build{race: race}, ruleset) do
    case Map.fetch(ruleset.races, race) do
      {:ok, %{ability_modifiers: mods}} -> mods
      :error -> %{}
    end
  end

  @typedoc """
  One ability's final score, term by term (CLAUDE.md §6, task 3.2).

  `score` is what `scores/2` returns for this ability; the five other integer
  fields are what it was built from, kept apart instead of summed away —
  `point_buy + race_bonus + level_bonus + own_bonus + gear_bonus` always equals
  `score`. `gear_typed` is what the player entered *before* the ruleset's
  ceiling, so a caller can tell "nothing to add" from "added, then clipped"
  without a second lookup into `Build.t()`.

  `own_bonus` is what the build earns by itself (task 3.1) and `own_terms` says
  from what, source by source — `Great strength` taken three times and a Red
  Dragon Disciple's table are two different answers to "why is my strength 24"
  and the interface has to be able to print both.
  """
  @type breakdown :: %{
          ability: Build.ability(),
          score: integer(),
          modifier: integer(),
          point_buy: integer(),
          race_bonus: integer(),
          level_bonus: integer(),
          own_bonus: integer(),
          own_terms: [AbilityBonuses.term_entry()],
          gear_bonus: integer(),
          gear_typed: integer(),
          gear_capped?: boolean()
        }

  @doc """
  Every ability's final score, term by term — how `scores/2`'s number was
  assembled, not just what it came out to.

  This is `Skills.value/4`'s contract carried over to abilities: the totals
  panel is asked to name every addend the way a skill row already does
  (CLAUDE.md §6, task 3.2), and nothing here is a second computation of a game
  number — `point_buy`, `race_bonus` and `gear_bonus` are the same fields
  `scores_at/3` and `with_gear/2` already combine, just kept apart. Only
  `level_bonus` is new arithmetic, and it is a count of the build's own
  `ability_increases` entries, not a game rule.

  ⚠️ **The five terms always sum to `score`.** That equality is the whole
  honesty check task 3.2 exists to keep, and task 3.1 kept it the way it was
  meant to be kept: the fifth addend arrived as its **own field** rather than
  being folded into one of the four that were here, because "уровни +8" on a
  Red Dragon Disciple would have been a true total and a false explanation. A
  caller that finds the sum short of `score` has found a bug, not a build with
  an unusual feat.
  """
  @spec breakdown(Build.t(), map()) :: %{Build.ability() => breakdown()}
  def breakdown(%Build{} = build, ruleset) do
    level = Build.character_level(build)
    racial = racial_modifiers(build, ruleset)
    {gear_bonuses, _capped?} = Gear.ability_bonuses(build.gear, ruleset)
    own_terms = Enum.group_by(AbilityBonuses.terms(build, ruleset, level), & &1.ability)

    level_counts =
      for {at, ability} <- build.ability_increases, at <= level, reduce: %{} do
        acc -> Map.update(acc, ability, 1, &(&1 + 1))
      end

    Map.new(@abilities, fn ability ->
      point_buy = Map.get(build.base_abilities, ability, 0)
      race_bonus = Map.get(racial, ability, 0)
      level_bonus = Map.get(level_counts, ability, 0)
      terms = Map.get(own_terms, ability, [])
      own_bonus = Enum.reduce(terms, 0, &(&1.bonus + &2))
      gear_typed = Map.get(build.gear.abilities, ability, 0)
      gear_bonus = Map.get(gear_bonuses, ability, 0)
      score = point_buy + race_bonus + level_bonus + own_bonus + gear_bonus

      {ability,
       %{
         ability: ability,
         score: score,
         modifier: modifier(score),
         point_buy: point_buy,
         race_bonus: race_bonus,
         level_bonus: level_bonus,
         own_bonus: own_bonus,
         own_terms: terms,
         gear_bonus: gear_bonus,
         gear_typed: gear_typed,
         gear_capped?: gear_typed != gear_bonus
       }}
    end)
  end
end
