defmodule BuildCalculator.Data do
  @moduledoc """
  Game reference data, compiled into the beam.

  Every ruleset is read and normalised **at compile time** (CLAUDE.md §5): broken
  JSON in `priv/rules/` fails `mix compile`, not a request, and looking a ruleset
  up at runtime is a literal lookup with no I/O and no parsing.

  Two rulesets are built:

    * `"vanilla"`  — `priv/rules/vanilla/*.json`, NWN1 as Fandom describes it.
    * `"siala_41"` — the same, with `priv/rules/siala_41/overrides.json` on top.
      This is the one the calculator uses.

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
  @default_version "siala_41"

  @type version :: String.t()

  @typedoc """
  Normalised game data for one ruleset.

  Notable members:

    * `:level_cap` / `:max_classes` — shard configuration, never literals in code
    * `:innate_hp_bonus` — «Дух Сиалы», `%{id:, ru:, amount:}` or `nil`: a flat
      hit-point bonus every character on Siala carries regardless of level or
      class, not tied to a feat (`Rules.Progression.hit_points/3`). `nil` for
      the vanilla ruleset always — NWN1 has no such mechanic
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
      shard fact can change (`changes[].affects` in `siala_41/classes.json`).
      Decides which facts count as a gap at all: a gap is a hole in the
      **answer**, so a fact whose every receiver is something the calculator
      never prints — damage, a buff, a summon — is not one (Dan, 10.08.2026).
      Two empty sets for vanilla, which switches the filter off rather than on.
      Read by `BuildCalculator.Rules.GapReceivers`
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
          epic_starts_at: pos_integer(),
          base_ac: pos_integer(),
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

  @doc "Version used by the calculator when a build does not name one."
  @spec default_version() :: version()
  def default_version, do: @default_version

  @doc "Every ruleset version compiled in."
  @spec versions() :: [version()]
  def versions, do: Map.keys(@rulesets)

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

  @doc "Like `ruleset/1`, but raises on an unknown version."
  @spec ruleset!(version()) :: t()
  def ruleset!(version \\ @default_version) when is_binary(version) do
    case ruleset(version) do
      {:ok, ruleset} ->
        ruleset

      {:error, {:unknown_ruleset, _}} ->
        raise ArgumentError, "unknown ruleset #{inspect(version)}"
    end
  end
end
