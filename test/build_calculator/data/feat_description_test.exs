defmodule BuildCalculator.Data.FeatDescriptionTest do
  @moduledoc """
  Task 3.87 — a feat's `description` (Fandom's own "Specifics" prose), the
  field the "what this feat does" popover reads.

  Two layers get tested here: `Reading.strip_wiki_prose/1` itself, against
  the handful of markup shapes the 299-feat corpus actually contains (struck
  history, links, `<br />`, wiki emphasis, HTML entities — CLAUDE.md §3's
  reasoning for stripping presentation markup at load time rather than in
  `mix wiki.parse`), and the loader's wiring of it into every ruleset's
  `feats` dictionary.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader.Reading

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "Reading.strip_wiki_prose/1" do
    test "nil in, nil out — a page that states nothing has nothing to show" do
      assert Reading.strip_wiki_prose(nil) == nil
    end

    test "a string that strips down to nothing also answers nil" do
      assert Reading.strip_wiki_prose("<s>gone</s>") == nil
      assert Reading.strip_wiki_prose("   ") == nil
    end

    test "wiki links collapse to their display text" do
      assert Reading.strip_wiki_prose("a [[dragon]]") == "a dragon"

      assert Reading.strip_wiki_prose("[[polymorph|change into]] a shape") ==
               "change into a shape"
    end

    # `favored_enemy`'s real sentence (CLAUDE.md §3): the struck word is gone,
    # not "also true" — cutting it flips the sentence's meaning, and that flip
    # is the whole point of resolving patch history before anything else reads
    # the string.
    test "struck-through history is cut, not merely unwrapped" do
      assert Reading.strip_wiki_prose("they do <strike>not</strike> improve") ==
               "they do improve"

      assert Reading.strip_wiki_prose("a <del>character</del> ''caster''") == "a caster"
    end

    test "a fully-struck sentence leaves no orphan punctuation behind" do
      assert Reading.strip_wiki_prose("a dragon. <strike>details here</strike>.") ==
               "a dragon."
    end

    test "<br /> becomes a line break, remaining tags and emphasis are dropped" do
      assert Reading.strip_wiki_prose("one.<br />\n'''Note:''' two.") == "one.\nNote: two."
      assert Reading.strip_wiki_prose("a <code>value</code> stays") == "a value stays"
    end

    test "the handful of named HTML entities the corpus uses are decoded" do
      assert Reading.strip_wiki_prose("a &mdash; b") == "a — b"
      assert Reading.strip_wiki_prose("a&nbsp;b") == "a b"
    end
  end

  describe "wired into the ruleset" do
    test "every one of the 299 vanilla feats carries a description, on both rulesets", %{
      siala: siala,
      vanilla: vanilla
    } do
      vanilla_ids = for {id, feat} <- vanilla.feats, not is_nil(feat), do: id

      assert length(vanilla_ids) == 299

      for id <- vanilla_ids do
        assert is_binary(vanilla.feats[id].description),
               "#{id}: vanilla ruleset carries no description"

        assert is_binary(siala.feats[id].description),
               "#{id}: siala_41 ruleset carries no description"
      end
    end

    test "no description reaching either ruleset still carries wiki markup", %{
      siala: siala,
      vanilla: vanilla
    } do
      for ruleset <- [siala, vanilla], {id, feat} <- ruleset.feats, is_binary(feat.description) do
        refute feat.description =~ "[[", "#{id}: description still carries a wiki link"
        refute feat.description =~ "'''", "#{id}: description still carries wiki bold markup"
      end
    end

    # The five custom weapon proficiencies plus six more (CLAUDE.md §3) —
    # shard-only records with no Fandom page and so no Fandom prose. Dan
    # asked (task 3.87) for these to stay empty rather than translated from
    # `special_raw`, and the loader already answers that on its own: a
    # shard-only record simply never sets the field.
    test "all eleven shard-only feats carry no description at all", %{siala: siala} do
      only = for {id, feat} <- siala.feats, feat.siala_only?, do: id

      assert length(only) == 11
      assert Enum.all?(only, &is_nil(siala.feats[&1].description))
    end

    # Sourced together, real text: `alertness`'s page (CLAUDE.md §3) —
    # locking in the wiring end to end, not only the stripping helper alone.
    test "a concrete feat's description matches the page, cleanly stripped", %{vanilla: vanilla} do
      assert vanilla.feats[:alertness].description ==
               "+2 bonus to spot and listen checks due to finely tuned senses."
    end
  end
end
