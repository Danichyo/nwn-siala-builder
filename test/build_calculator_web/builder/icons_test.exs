defmodule BuildCalculatorWeb.Builder.IconsTest do
  @moduledoc """
  `BuildCalculatorWeb.Builder.Icons` against the two rulesets, not against the
  manifest in isolation — `test/build_calculator/data/icons_test.exs` already
  guards that `priv/rules/vanilla/icons.json` itself is complete and honest
  about what is on disk; this file guards the other half, that
  `ruleset.feats[id].icon` / `ruleset.spells[id].icon` actually resolve
  through it end to end (AGENT_QUEUE.md 3.50, part B).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Icons

  test "a feat's raw icon name resolves to a servable /icons/feats path" do
    ruleset = Data.ruleset!("vanilla")
    alertness = ruleset.feats[:alertness]

    assert alertness.icon == "Ife_alertness.gif"
    assert Icons.feat_path(alertness.icon) == "/icons/feats/Ife_alertness.gif"
  end

  test "a spell's raw icon name resolves to a servable /icons/spells path" do
    ruleset = Data.ruleset!("vanilla")
    acid_fog = ruleset.spells[:acid_fog]

    assert acid_fog.icon == "is_acidfog.gif"
    assert Icons.spell_path(acid_fog.icon) == "/icons/spells/Is_acidfog.gif"
  end

  test "nil icon resolves to nil path, not an error" do
    refute Icons.feat_path(nil)
    refute Icons.spell_path(nil)
  end

  test "an unknown spelling resolves to nil rather than raising" do
    refute Icons.feat_path("not a real icon.gif")
    refute Icons.spell_path("not a real icon.gif")
  end

  # AGENT_QUEUE.md 3.50, part A finding 1: two pairs of feats share one file
  # because MediaWiki folds their two spellings onto the same title. Both
  # spellings have to resolve, and to the *same* path — that is the whole
  # point of looking a raw name up against every spelling the manifest
  # recorded instead of renormalising it here (see the module's moduledoc).
  test "both feats behind each of the two name collisions resolve to the same file" do
    ruleset = Data.ruleset!("vanilla")

    ambidexterity = ruleset.feats[:ambidexterity]
    dual_wield = ruleset.feats[:dual_wield_feat]
    assert ambidexterity.icon == "Ife_ambidex.gif"
    assert dual_wield.icon == "ife ambidex.gif"
    assert Icons.feat_path(ambidexterity.icon) == Icons.feat_path(dual_wield.icon)
    assert Icons.feat_path(ambidexterity.icon) == "/icons/feats/Ife_ambidex.gif"

    draconic_armor = ruleset.feats[:draconic_armor]
    dragon_abilities = ruleset.feats[:dragon_abilities]
    assert draconic_armor.icon == "ife_x2ddarmor.gif"
    assert dragon_abilities.icon == "ife x2ddarmor.gif"
    assert Icons.feat_path(draconic_armor.icon) == Icons.feat_path(dragon_abilities.icon)
    assert Icons.feat_path(draconic_armor.icon) == "/icons/feats/Ife_x2ddarmor.gif"
  end

  # A feat/spell without an `icon` field is not a data gap (23 tiered feat
  # families, 9 vanilla spells — one Fandom page per whole family), and this
  # test is what would catch it becoming one: any id in either list has to
  # come back with a `nil` path, on both rulesets, never a raised error.
  for version <- Data.versions() do
    test "every icon-less feat/spell on #{version} resolves to a nil path, not an error" do
      ruleset = Data.ruleset!(unquote(version))

      for {id, feat} <- ruleset.feats, is_nil(feat.icon) do
        refute Icons.feat_path(feat.icon), "#{id} unexpectedly resolved a path from a nil icon"
      end

      for {id, spell} <- ruleset.spells, is_nil(spell.icon) do
        refute Icons.spell_path(spell.icon),
               "#{id} unexpectedly resolved a path from a nil icon"
      end
    end

    test "every feat/spell icon on #{version} that IS set resolves to a real path" do
      ruleset = Data.ruleset!(unquote(version))

      for {id, feat} <- ruleset.feats, feat.icon do
        assert Icons.feat_path(feat.icon), "#{id} names icon #{inspect(feat.icon)}, no match"
      end

      for {id, spell} <- ruleset.spells, spell.icon do
        assert Icons.spell_path(spell.icon), "#{id} names icon #{inspect(spell.icon)}, no match"
      end
    end
  end
end
