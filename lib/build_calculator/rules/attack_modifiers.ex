defmodule BuildCalculator.Rules.AttackModifiers do
  @moduledoc """
  Attacks per round a **class** adds on top of the table lookup — the extension
  point vanilla says cannot exist.

  Vanilla is categorical: «a character's maximum number of attacks is determined
  by his or her BAB at character level 20», confirmed by three separate Fandom
  pages and transcribed in `priv/rules/vanilla/epic.json`. Siala's Arcane Archer
  contradicts it outright — «за каждые 10 уровней класс получает одну
  дополнительную атаку (максимум 3 за 30 уровней в классе)» — so the count is a
  base plus a layer, never one formula with a second term bolted on. The layer is
  empty for vanilla and reads off `ruleset.attack_modifiers`, which the class
  layer of the shard fills (`Data.Loader.Classes`).

  **Not one game number lives here.** How many class levels buy a step, how many
  attacks a step is worth, where the ceiling stands, which ability beats which,
  how many levels of which other class switch the rule off — all of it arrives as
  data. This module knows the *shapes*, and `Data.Loader` refuses to build a
  ruleset whose condition names a shape this module cannot read (see
  `condition_kinds/0`).

  ## Conditions come in three states, and only two of them are this module's

    * **readable** — `modelled?: true` with a `kind` from `condition_kinds/0`.
      Evaluated against the build; if it holds, the modifier grants nothing.
    * **declared not modelled** — `modelled?: false`. The data says out loud that
      the calculator does not answer this question, with who decided and why.
      Skipped, and **no gap**: «дырка в нашем ОТВЕТЕ, а не в наших знаниях»
      (CLAUDE.md §9). Today that is `mounted` — being on a horse is a state of
      combat, the same argument that closed buffs and the bard song.
    * **anything else** — the ruleset does not load. A disabling condition nobody
      can read is the dangerous direction: it would quietly grant attacks the
      player will not have, and up to three of them.

  ⚠ The middle state has a cost, and it is named rather than hidden: a character
  who really is mounted is shown one to three attacks too many. That is the shape
  of the decision, not a bug in it.

  ## What `read_modifiers` settles

  `ability_modifier_exceeds` has to compare two ability modifiers, and «naked or
  wearing gear» is a question no source in this project answers in general — feat
  prerequisites ignore gear (measurements S1/S2), bonus spell slots count it
  (task 3.70). So the record says which, the loader refuses a record that does not
  (`ability_modifier_sources/0`), and the reasoning sits in the data beside the
  quote it interprets rather than in this file.
  """

  alias BuildCalculator.Rules.{Abilities, Build}

  # The closed vocabulary of conditions, and the fields each one needs. The
  # loader reads it to refuse an unknown `when` at build time; `holds?/2` below
  # answers exactly these kinds, and `AttackModifiersTest` walks the map to prove
  # a kind cannot be listed here without a clause there.
  #
  # ⚠ Names describe the *comparison*, never the thing compared: `wis`, `dex`,
  # `shadowdancer` and `4` are the data's business, and a kind called
  # `wisdom_over_dexterity` would have smuggled two of them into the core.
  @conditions %{
    ability_modifier_exceeds: [:ability, :exceeds, :read_modifiers],
    class_levels_at_least: [:class, :levels]
  }

  # Which ability modifiers a condition may be measured against. Both are
  # computed by `Rules.compute/2` already — `abilities_naked` is a second pass
  # over the build with the gear taken off, not a subtraction (CLAUDE.md §6).
  @ability_sources [:naked, :with_gear]

  @typedoc "A condition as the loader hands it over, or one it was told to skip."
  @type condition :: %{
          required(:kind) => atom(),
          required(:modelled?) => boolean(),
          optional(atom()) => term()
        }

  @typedoc """
  One rule off a class page.

  `source` is what the modifier hangs on — `{:class, :arcane_archer}` — and it is
  what decides how many levels are counted. `max` is `nil` when the source states
  no ceiling.
  """
  @type modifier :: %{
          source: {:class, atom()},
          kind: :extra_attacks,
          per_class_levels: pos_integer(),
          attacks_per_step: pos_integer(),
          max: pos_integer() | nil,
          disabled_if: [condition()],
          status: String.t() | nil
        }

  @typedoc """
  One modifier's contribution, for the breakdown printed beside the number.
  """
  @type term_entry :: %{source: {:class, atom()}, kind: atom(), attacks: pos_integer()}

  @typedoc """
  Everything a condition may ask about the character.

  Both modifier maps are passed, never one: which of them a condition reads is
  the condition's own field, so the caller cannot decide it by accident.
  """
  @type context :: %{
          class_levels: %{atom() => pos_integer()},
          ability_modifiers: %{naked: %{atom() => integer()}, with_gear: %{atom() => integer()}}
        }

  @doc "Condition kinds this module can evaluate. The loader refuses any other."
  @spec condition_kinds() :: [atom()]
  def condition_kinds, do: Map.keys(@conditions)

  @doc "Fields a condition of this kind must carry, or `nil` for an unknown kind."
  @spec condition_fields(atom()) :: [atom()] | nil
  def condition_fields(kind), do: Map.get(@conditions, kind)

  @doc "Which ability modifiers a condition may be measured against."
  @spec ability_modifier_sources() :: [atom()]
  def ability_modifier_sources, do: @ability_sources

  @doc """
  The context a build offers its attack modifiers.

  `naked` and `with_gear` are the two modifier maps `Rules.compute/2` already has
  in hand; nothing here recomputes an ability score.
  """
  @spec context(Build.t(), %{atom() => integer()}, %{atom() => integer()}) :: context()
  def context(%Build{} = build, naked_modifiers, geared_modifiers) do
    %{
      class_levels: Build.class_levels(build),
      ability_modifiers: %{naked: naked_modifiers, with_gear: geared_modifiers}
    }
  end

  @doc """
  What the ruleset's modifiers add to the table lookup, term by term.

  Empty when the ruleset carries none (vanilla), when the build has no level of
  the granting class, or when a condition switches the rule off — a term that
  grants nothing is left out rather than carried as a zero, because the screen
  beside the number lists the terms it is made of and «Arcane Archer +0» explains
  nothing.
  """
  @spec terms(map(), context()) :: [term_entry()]
  def terms(ruleset, context) do
    for modifier <- Map.get(ruleset, :attack_modifiers, []),
        attacks = attacks_from(modifier, context),
        attacks > 0,
        do: %{source: modifier.source, kind: modifier.kind, attacks: attacks}
  end

  @doc "The sum of `terms/2`."
  @spec total([term_entry()]) :: non_neg_integer()
  def total(terms), do: Enum.sum_by(terms, & &1.attacks)

  # ⚠ `div/2` before the ceiling, and the ceiling after multiplying: the source
  # states both the step and the maximum, and applying them in the other order
  # would cap steps rather than attacks. Today `attacks_per_step` is 1 and the two
  # agree; the day a shard grants two attacks a step they would not.
  defp attacks_from(%{kind: :extra_attacks, source: {:class, class}} = modifier, context) do
    levels = Map.get(context.class_levels, class, 0)

    cond do
      levels == 0 -> 0
      disabled?(modifier.disabled_if, context) -> 0
      true -> capped(div(levels, modifier.per_class_levels) * modifier.attacks_per_step, modifier)
    end
  end

  defp attacks_from(_modifier, _context), do: 0

  defp capped(attacks, %{max: nil}), do: attacks
  defp capped(attacks, %{max: max}), do: min(attacks, max)

  defp disabled?(conditions, context), do: Enum.any?(conditions, &holds?(&1, context))

  # A condition the data declared unmodelled never fires — the calculator answers
  # for the character it does model (not mounted), and says so in the data rather
  # than in a gap.
  defp holds?(%{modelled?: false}, _context), do: false

  # «Персонаж, у которого модификатор мудрости выше, чем модификатор ловкости».
  # Strictly higher: equal modifiers leave the attacks alone.
  #
  # ⚠ `fetch!` twice, never `get/3` with a zero: a name that is not in the map is
  # a broken context, and defaulting it to zero would make the comparison hold
  # almost always — a rule silently switched **off** for builds that should have
  # the attacks. `Rules.compute/2` always passes all six modifiers, so this can
  # only fire on a caller that made a map up.
  defp holds?(%{kind: :ability_modifier_exceeds} = condition, context) do
    modifiers = Map.fetch!(context.ability_modifiers, condition.read_modifiers)

    Map.fetch!(modifiers, condition.ability) > Map.fetch!(modifiers, condition.exceeds)
  end

  # «Персонаж с классами ШД 4 и более». Not strict: four levels is already too
  # many, three are not.
  defp holds?(%{kind: :class_levels_at_least} = condition, context) do
    Map.get(context.class_levels, condition.class, 0) >= condition.levels
  end

  @doc """
  Whether an ability name is one the model carries. Asked by `Data.Loader`, so a
  typo in a condition (`"dexterity"` for `"dex"`) fails the build instead of
  comparing against a modifier of zero and switching the rule on almost always.
  """
  @spec ability?(atom()) :: boolean()
  def ability?(name), do: name in Abilities.keys()
end
