defmodule BuildCalculator.Data do
  @moduledoc """
  Game reference data, compiled into the beam.

  Every ruleset is read and normalised **at compile time** (CLAUDE.md §5): broken
  JSON in `priv/rules/` fails `mix compile`, not a request, and looking a ruleset
  up at runtime is a literal lookup with no I/O and no parsing.

  Two rulesets are built:

    * `"vanilla"`  — `priv/rules/vanilla/*.json`, NWN1 as Fandom describes it,
      and nothing else: it reads no file of the shard (task 4.1). Its
      hand-written rules no entity owns — the class limit, stat ceilings, the
      manual gear layer, attack formulas, vanilla constants, the receivers
      vocabulary — live in `vanilla/rules.json`.
    * `"siala_41"` — the same, with the shard's files on top: its class, race,
      feat, skill and spell layers, and `priv/rules/siala_41/overrides.json`
      laid over `vanilla/rules.json` by the same keys
      (`BuildCalculator.Data.Loader.Layers`). This is the one the calculator
      uses.

  A ruleset is a plain map (see `t:t/0`). Everything configurable — the level cap,
  the class limit, what a level past the vanilla cap grants — comes from the data,
  so none of it is a literal in the rules core.

  ## Missing data is data

  Files that do not exist yet (`vanilla/skills.json`) degrade to an empty
  dictionary; assumptions that had to be made (base AC, the attacks-per-round
  table) are listed in `ruleset.gaps` as machine-readable entries. Nothing is
  silently invented.
  """

  alias BuildCalculator.Data.Loader

  @rules_dir Path.expand("../../priv/rules", __DIR__)

  for rel <- Loader.source_files() do
    # Registered whether or not the file exists: `Mix.Utils.last_modified/1`
    # reports 0 for a missing path, so creating `skills.json` later marks this
    # module stale and it recompiles by itself.
    @external_resource Path.join(@rules_dir, rel)
  end

  @rulesets Loader.load!(@rules_dir)
  @versions Map.keys(@rulesets)

  @type version :: String.t()

  @typedoc """
  Normalised game data for one ruleset.

  Notable members:

    * `:level_cap` / `:max_classes` — ruleset configuration, never literals in code
      (vanilla 40 / 3, Siala 41 / 4)
    * `:innate_hp_bonus` — «Дух Сиалы», `%{id:, ru:, amount:}` or `nil`: a flat
      hit-point bonus every character on Siala carries regardless of level or
      class, not tied to a feat (`Rules.Progression.hit_points/3`). `nil` for
      the vanilla ruleset always — NWN1 has no such mechanic
    * `:hp_floor_per_level` — the fewest hit points one character level gives
      after its die, CON and per-level feat bonuses (1 on both rulesets,
      `fandom:Hit point`, task 4.56). `nil` only when no layer states it, and
      then hit points are refused with `{:missing_data, :hp_floor_per_level}`
      rather than floored at a number nobody stated
    * `:skill_points_floor_per_level` / `:skill_points_first_level_multiplier` —
      the fewest skill points one level gives after the class's points and the
      intelligence modifier, and what character level 1 multiplies its sum by
      (1 and 4 on both rulesets, `fandom:Skill point`, task 4.65). `nil` only
      when no layer states them, and then skill points are not granted at all
      (`skill_points.earned`/`free` `nil`) with `{:missing_data, …}` of the
      missing one, rather than at a number nobody stated
    * `:base_ac` — armour class before any modifier (10 on both rulesets,
      `_vanilla_constants_confirmed.base_ac`, `fandom:Armor class`, task 4.65).
      `nil` only when no layer states it, and then `ac_naked`/`ac_geared` are
      `nil` with `{:missing_data, :base_ac}`
    * `:classes` — `%{class_id => class}`; `class.progression` maps a *class* level
      to the BAB and save numbers off the wiki table
    * `:epic` — `attack_bonus` / `save_bonus` map a *character* level to the
      cumulative epic bonus, already extended past the vanilla cap by the shard's
      rule for level 41
    * `:skill_rank_caps` — `%{character_level => %{class:, cross_class:}}`
    * `:attacks_per_round` — `%{bab => attacks}`
    * `:skill_rules` — the two skill rules that are not properties of one skill:
      the Spellcraft contribution to every saving throw and the stealth penalty a
      build of four classes takes
    * `:systems` — the shard's ten custom systems with the verdict on each. Nine
      do not reach a build's numbers (CLAUDE.md §3, closed); carried so the
      interface can show what is knowingly left out
    * `:stat_caps` — ceilings on **bonuses**, never on the base. Only what the
      data marks `verified`; the rest stays a gap
    * `:stat_cap_sources` — and **which** bonuses a ceiling covers, per source
      kind (`%{stat => %{source => %{inside?:, assumed?:}}}`). "Applies to
      bonuses" is not the same as "applies to every bonus": since 09.08.2026 a
      feat's attack bonus sits on top of the +20 rather than under it (Dan),
      while gear and the shard's racial bonus stay under it. Read by
      `BuildCalculator.Rules.Caps.covers_source?/3`
    * `:gap_receivers` — `%{our:, not_our:}`, the closed vocabulary of what a
      fact can change (`changes[].affects` in `siala_41/classes.json`, `affects`
      in the vanilla markup files). Decides which facts count as a gap at all:
      a gap is a hole in the **answer**, so a fact whose every receiver is
      something the calculator never prints — damage, a buff, a summon — is not
      one (Dan, 10.08.2026). The same for both rulesets since task 4.1
      (`vanilla/rules.json` → `_receivers`); two empty sets only where no layer
      declares one, which switches the filter off rather than on. Read by
      `BuildCalculator.Rules.GapReceivers`
    * `:gear` — what the manual equipment layer accepts and how far
    * `:point_buy` — character creation costs, cumulative
    * `:gaps` — everything unknown, derived or assumed, machine-readable
  """
  @type t :: %{
          version: version(),
          layers: [String.t()],
          level_cap: pos_integer(),
          max_classes: pos_integer() | nil,
          innate_hp_bonus: %{id: atom(), ru: String.t(), amount: pos_integer()} | nil,
          hp_floor_per_level: pos_integer() | nil,
          skill_points_floor_per_level: pos_integer() | nil,
          skill_points_first_level_multiplier: pos_integer() | nil,
          epic_starts_at: pos_integer(),
          base_ac: pos_integer() | nil,
          abilities: [atom()],
          classes: %{optional(atom()) => map()},
          races: %{optional(atom()) => map()},
          feats: %{optional(atom()) => map()},
          skills: %{optional(atom()) => map()},
          skill_rules: %{save_bonus: [map()], stealth_multiclass_penalty: map() | nil},
          systems: [map()],
          spells: %{optional(atom()) => map()},
          spell_lists: %{optional(atom()) => atom()},
          name_map: %{optional(String.t()) => String.t()},
          epic: map(),
          skill_rank_caps: %{
            optional(pos_integer()) => %{class: pos_integer(), cross_class: pos_integer()}
          },
          attacks_per_round: %{optional(non_neg_integer()) => pos_integer()},
          attack_modifiers: [map()],
          attack_ability: %{
            default: atom() | nil,
            weapon_defaults: [map()],
            rules: [map()]
          },
          stat_caps: %{optional(atom()) => integer()},
          stat_cap_sources: %{
            optional(atom()) => %{optional(atom()) => %{inside?: boolean(), assumed?: boolean()}}
          },
          gap_receivers: %{our: MapSet.t(String.t()), not_our: MapSet.t(String.t())},
          gear: %{
            ability_bonus_cap: integer() | nil,
            ac_types: [atom()],
            ac_type_names: %{optional(String.t()) => String.t()},
            ac_cap: integer() | nil,
            worn: [
              %{
                id: atom(),
                ru: String.t() | nil,
                ac_type: atom(),
                caps_dexterity?: boolean(),
                items: [
                  %{
                    id: atom(),
                    category: atom(),
                    name: String.t() | nil,
                    base_ac: integer(),
                    max_dex: integer() | nil,
                    weight_class: BuildCalculator.Rules.Worn.weight_class()
                  }
                ]
              }
            ]
          },
          point_buy: map() | nil,
          prestige: map(),
          gaps: [tuple()]
        }

  @doc """
  Version used when a build does not name one — the deployment's, not the code's.

  Read at call time from `config :build_calculator, :default_ruleset`. Until
  task 4.2 this was a module attribute naming the shard's ruleset, so every
  deployment computed Siala by default. Now two sites run from one code base
  (VANILLA.md §2), and which ruleset a site computes is part of its edition —
  a web concern this module knows nothing about: the edition writes the key
  once, at boot (`BuildCalculatorWeb.Edition.configure!/0`, called from
  `BuildCalculator.Application.start/2`). The core only reads it.

  Raises when the key is unset or names no compiled ruleset — a build silently
  encoded under the wrong ruleset would be worse than a crash at the call.
  """
  @spec default_version() :: version()
  def default_version do
    case Application.fetch_env(:build_calculator, :default_ruleset) do
      {:ok, version} when version in @versions ->
        version

      {:ok, other} ->
        raise ArgumentError,
              "config :build_calculator, :default_ruleset names no compiled ruleset: " <>
                inspect(other)

      :error ->
        raise ArgumentError,
              "config :build_calculator, :default_ruleset is not set — it is written at " <>
                "boot by BuildCalculatorWeb.Edition.configure!/0"
    end
  end

  @doc "Every ruleset version compiled in."
  @spec versions() :: [version()]
  def versions, do: @versions

  @doc """
  Fetches a ruleset by version.

  Builds store their `ruleset_version` and must always be recomputed with it —
  never "with the latest" (CLAUDE.md §5).
  """
  @spec ruleset(version()) :: {:ok, t()} | {:error, {:unknown_ruleset, version()}}
  def ruleset(version) when is_binary(version) do
    case Map.fetch(@rulesets, version) do
      {:ok, ruleset} -> {:ok, ruleset}
      :error -> {:error, {:unknown_ruleset, version}}
    end
  end

  @doc """
  Like `ruleset/1`, but raises on an unknown version.

  ⚠️ The version is required. Until task 4.2 it defaulted to the shard's
  ruleset, and a caller that forgot to name one silently computed Siala on
  any site. A site asks its edition (`BuildCalculatorWeb.Edition.ruleset/0`);
  a test names the ruleset it means.
  """
  @spec ruleset!(version()) :: t()
  def ruleset!(version) when is_binary(version) do
    case ruleset(version) do
      {:ok, ruleset} ->
        ruleset

      {:error, {:unknown_ruleset, _}} ->
        raise ArgumentError, "unknown ruleset #{inspect(version)}"
    end
  end
end
