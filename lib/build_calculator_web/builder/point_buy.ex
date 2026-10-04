defmodule BuildCalculatorWeb.Builder.PointBuy do
  @moduledoc """
  Character creation point buy, read from the ruleset.

  The table used to live here as a pair of literals, and it was **wrong**: the
  shortcut "one point per step up to 14, two above" prices an 18 at 14 points
  when it costs 16. The real steps are not uniform — fandom "Point buy"
  (revid 57460): *"it costs 2 points to increment a score to 15 or 16, and 3
  points to increment it to 17 or 18"*:

      score        8   9  10  11  12  13  14  15  16  17  18
      cumulative   0   1   2   3   4   5   6   8  10  13  16

  It now lives in `priv/rules/siala_41/overrides.json` under
  `_vanilla_constants_confirmed` — the section for universal vanilla rules that
  cannot live in `vanilla/`, because that layer is machine-generated and a hand
  written fact there is wiped by the next `mix wiki.parse`. Costs are stored
  cumulatively rather than as a formula precisely so there is nothing left to
  re-derive incorrectly.

  ## The floor is part of the table

  A caster's key ability cannot go below 11 **after racial modifiers**, and the
  game enforces it by buying the points for you: a human sorcerer starts on CHA
  11 with 27 points left, a half-orc one on a bought 13 with 25 (Dan, тестовый
  сервер, 03.08.2026). So every question here — what a score may be lowered to,
  what a fresh build starts on, how many points are actually free — is asked of
  a **build**, not of the ruleset alone: the answer depends on the race and on
  the class of character level 1.

  Which ability and which classes is not decided here. `Rules.Abilities`
  interprets the rule against `casting_ability`, and this module only prices the
  result, so no class name and no ability appears in this file.

  One thing the same fandom page states is still **not** applied: the +12 item
  ability ceiling ignores true racial modifiers and is lowered by penalties
  (fandom "Ability cap", revid 68173) — `{:not_modelled,
  :ability_cap_penalty_interaction}`.

  Every function takes the ruleset. A ruleset with no table (none ship that way)
  reports zero budget rather than falling back to numbers of its own.
  """

  alias BuildCalculator.Rules.Abilities
  alias BuildCalculator.Rules.Build

  @empty %{budget: 0, min_score: 0, max_score: 0, cost: %{}}

  @doc "Points available at character creation."
  @spec budget(map()) :: non_neg_integer()
  def budget(ruleset), do: table(ruleset).budget

  @doc """
  Lowest score the **table** allows — the floor before any rule raises it.

  `floor/3` is what a control should ask; this is the scale's own bottom, and it
  is what an imported sheet is judged against.
  """
  @spec min_score(map()) :: non_neg_integer()
  def min_score(ruleset), do: table(ruleset).min_score

  @doc "Highest score point buy allows."
  @spec max_score(map()) :: non_neg_integer()
  def max_score(ruleset), do: table(ruleset).max_score

  @doc """
  Lowest score `ability` may be bought at in this build.

  The table's floor, unless the build's first class is a caster and this is the
  ability it casts off — then it is whatever buys the rule's minimum after the
  race has been added (`Rules.Abilities.creation_floor/2`).

  ⚠ Never below the table's own floor. No NWN race gives a **bonus** to INT,
  WIS or CHA, so the clamp cannot bite today and the measurement says nothing
  about that case; it is here so a future race with one produces a legal score
  rather than a number off the bottom of the scale. Recorded in the data under
  `not_covered`.
  """
  @spec floor(map(), Build.t(), atom()) :: non_neg_integer()
  def floor(ruleset, %Build{} = build, ability) do
    case Abilities.creation_floor(build, ruleset) do
      %{ability: ^ability, base: base} -> max(base, min_score(ruleset))
      _ -> min_score(ruleset)
    end
  end

  @doc """
  Cost of raising one ability from the floor up to `score`.

  A straight lookup: the table is stored cumulatively, so nothing is summed and
  nothing can drift.
  """
  @spec cost(map(), integer()) :: non_neg_integer()
  def cost(ruleset, score), do: Map.get(table(ruleset).cost, score, 0)

  @doc "Cost of the single step that lands on `score`."
  @spec step_cost(map(), integer()) :: non_neg_integer()
  def step_cost(ruleset, score), do: cost(ruleset, score) - cost(ruleset, score - 1)

  @doc "Points spent by a whole set of base scores."
  @spec spent(map(), %{atom() => integer()}) :: non_neg_integer()
  def spent(ruleset, scores),
    do: Enum.reduce(scores, 0, fn {_ability, score}, sum -> sum + cost(ruleset, score) end)

  @doc "Points still unspent."
  @spec remaining(map(), %{atom() => integer()}) :: integer()
  def remaining(ruleset, scores), do: budget(ruleset) - spent(ruleset, scores)

  @doc """
  What the caster floor takes out of the budget before the player spends
  anything, or `nil` when this build has no floor.

  The floor's own fields plus `cost` — the points it eats — and `free`, what is
  left of the budget after it. These are the two numbers Dan measured (27 for a
  human caster, 25 for a half-orc one), and they are returned together because
  the interface has to print both: a budget that shrank without saying why reads
  as a bug in the calculator.
  """
  @spec forced(map(), Build.t()) :: map() | nil
  def forced(ruleset, %Build{} = build) do
    case Abilities.creation_floor(build, ruleset) do
      nil ->
        nil

      floor ->
        base = max(floor.base, min_score(ruleset))
        cost = cost(ruleset, base)

        floor
        |> Map.put(:base, base)
        |> Map.put(:cost, cost)
        |> Map.put(:free, budget(ruleset) - cost)
    end
  end

  @doc "Whether one more point can go into an ability currently at `score`."
  @spec can_raise?(map(), %{atom() => integer()}, integer()) :: boolean()
  def can_raise?(ruleset, scores, score) do
    score < max_score(ruleset) and remaining(ruleset, scores) >= step_cost(ruleset, score + 1)
  end

  @doc """
  Whether a point can come back out of `ability`, currently at `score`.

  The floor refuses it: *«очки списываются, опустить характеристику ниже
  нельзя»*. This is the half of the rule the player meets first, and it is why
  the control is disabled rather than merely warned about.
  """
  @spec can_lower?(map(), Build.t(), atom(), integer()) :: boolean()
  def can_lower?(ruleset, %Build{} = build, ability, score),
    do: score > floor(ruleset, build, ability)

  @doc """
  A fresh set of base scores: every ability at its floor, nothing else spent.

  With no build — a character that has not picked a race or a first class yet —
  that is the table's floor across the board.
  """
  @spec starting_scores(map(), Build.t()) :: %{atom() => integer()}
  def starting_scores(ruleset, build \\ %Build{}),
    do: Map.new(ruleset.abilities, &{&1, floor(ruleset, build, &1)})

  @doc """
  `build` with the caster floor bought, if it was not bought already.

  This is the game's own «принудительная покупка»: the score is raised and the
  points are gone. Only ever upwards — a class swapped away from a caster leaves
  the score where it is, because points the player may have meant to spend are
  not ours to take back.

  ⚠ Called alone, it can push the build over budget — this is what the unit
  tests below exercise directly, on purpose, as the honest fallback when there
  is nowhere left to take points from. In the constructor it never actually
  runs into that: `builder_live.ex`'s funnel asks `reset_needed?/2` first and,
  if the floor plainly does not fit, throws the whole distribution back to the
  table floor with `reset_to_floor/2` before calling this — see both below.
  Kept as two small functions plus this one rather than folded together
  because each answers one question on its own and each is worth testing on
  its own (AGENT_QUEUE.md §3.17, решение 3).
  """
  @spec enforce_floor(map(), Build.t()) :: Build.t()
  def enforce_floor(ruleset, %Build{} = build) do
    case forced(ruleset, build) do
      nil ->
        build

      %{ability: ability, base: base} ->
        current = Map.get(build.base_abilities, ability, min_score(ruleset))

        if current >= base,
          do: build,
          else: %Build{build | base_abilities: Map.put(build.base_abilities, ability, base)}
    end
  end

  @doc """
  Whether `enforce_floor/2`'s purchase no longer fits the free points — the
  trigger for AGENT_QUEUE.md §3.17's "смена класса первого уровня сбрасывает
  распределение", decided by Dan and refined with the coordinator into an
  exact threshold.

  «Нужно 3, свободно 5 → просто списываем, как сегодня (`enforce_floor/2`
  alone). Нужно 3, свободно 2 → сброс» — the boundary is a **shortfall**, so
  needing exactly what is free is still "как сегодня", not a reset.

  A pure predicate on purpose, asked of a build **before** anything is
  written: a caller has to tell "about to reset" from "already reset" without
  diffing `base_abilities` by hand, because a player's own manual −1 also
  lowers one score and must never read as this rule firing (`can_lower?/4`
  already keeps a manual step from doing that on its own — this is the other
  half, for a class or a race that just moved the floor out from under an
  already-legal purchase).

  `false` whenever there is no floor to enforce at all (`forced/2` is `nil`)
  or the current score already meets it — matching «Кастер → не-кастер: сброса
  нет никогда» exactly, because a class swap away from a caster makes
  `forced/2` `nil` and this returns `false` without looking at the budget.
  """
  @spec reset_needed?(map(), Build.t()) :: boolean()
  def reset_needed?(ruleset, %Build{} = build) do
    case forced(ruleset, build) do
      nil ->
        false

      %{ability: ability, base: base} ->
        current = Map.get(build.base_abilities, ability, min_score(ruleset))
        needed = cost(ruleset, base) - cost(ruleset, current)
        needed > 0 and needed > remaining(ruleset, build.base_abilities)
    end
  end

  @doc """
  `build` with every ability thrown back to the table floor — «сбрасывается
  распределение, а не бюджет: все шесть характеристик к табличному полу»
  (AGENT_QUEUE.md §3.17). Unconditional on purpose: the caller decides *when*
  with `reset_needed?/2` first, this only knows *how*.

  Always call `enforce_floor/2` right after — this step alone only clears the
  slate, it does not buy the new minimum back. Dan's measurement is what makes
  that second call safe: the floor's own cost (≤5 for the worst-cased race)
  never comes close to the full budget freed by this reset, so the pair never
  goes over budget the way `enforce_floor/2` can on its own.
  """
  @spec reset_to_floor(map(), Build.t()) :: Build.t()
  def reset_to_floor(ruleset, %Build{} = build) do
    floor = min_score(ruleset)
    %Build{build | base_abilities: Map.new(ruleset.abilities, &{&1, floor})}
  end

  defp table(%{point_buy: %{} = table}), do: table
  defp table(_ruleset), do: @empty
end
