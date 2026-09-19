defmodule BuildCalculator.FeatListTokenizerTest do
  @moduledoc """
  Direct unit coverage for the tokenizer extracted out of `WikiBuildPage`
  (task 3.111). `wiki_builds_test.exs` and `import_test.exs` already exercise
  it end to end through `WikiBuildPage`'s own feat parsing — unchanged by the
  extraction, per `mix test` before and after — but neither pins the
  algorithm's *rules* on their own, small, controllable dictionaries. This
  file does, so a future edit to the tokenizer breaks a test that names
  exactly what broke, not a 182-test regression suite somewhere else.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.FeatListTokenizer

  defp dict(table), do: FeatListTokenizer.dictionary(table)

  describe "plain names" do
    test "a single known name resolves, with no argument or rank" do
      dictionary = dict(%{"dodge" => :dodge})

      assert [%{value: :dodge, raw: "dodge", argument: nil, rank: nil}] =
               FeatListTokenizer.tokenize("dodge", dictionary)
    end

    test "several names separated by commas all resolve, in order" do
      dictionary = dict(%{"dodge" => :dodge, "mobility" => :mobility, "cleave" => :cleave})

      assert [%{value: :dodge}, %{value: :mobility}, %{value: :cleave}] =
               FeatListTokenizer.tokenize("dodge, mobility, cleave", dictionary)
    end

    test "separators include semicolons and stray punctuation, not only commas" do
      dictionary = dict(%{"dodge" => :dodge, "mobility" => :mobility})

      assert [%{value: :dodge}, %{value: :mobility}] =
               FeatListTokenizer.tokenize("dodge; - mobility", dictionary)
    end

    test "empty text tokenizes to no entries" do
      assert [] = FeatListTokenizer.tokenize("", dict(%{"dodge" => :dodge}))
    end
  end

  describe "the comma-in-a-name trap" do
    test "a dictionary entry containing its own comma is read whole, not split" do
      # `Energy Resistance, Fire I` (CLAUDE.md §9) is the real-world case this
      # guards: a comma inside a feat's own name must not be mistaken for the
      # separator between two feats.
      dictionary =
        dict(%{
          "energy resistance, fire" => :epic_energy_resistance,
          "epic prowess" => :epic_prowess
        })

      assert [
               %{value: :epic_energy_resistance, raw: "energy resistance, fire", rank: "i"},
               %{value: :epic_prowess}
             ] = FeatListTokenizer.tokenize("energy resistance, fire i, epic prowess", dictionary)
    end
  end

  describe "longest match" do
    test "a longer entry wins over a shorter one that is its own prefix" do
      dictionary =
        dict(%{"weapon focus" => :weapon_focus, "epic weapon focus" => :epic_weapon_focus})

      assert [%{value: :epic_weapon_focus, raw: "epic weapon focus"}] =
               FeatListTokenizer.tokenize("epic weapon focus", dictionary)
    end

    test "the shorter entry still resolves on its own, unharmed by the longer one existing" do
      dictionary =
        dict(%{"weapon focus" => :weapon_focus, "epic weapon focus" => :epic_weapon_focus})

      assert [%{value: :weapon_focus, raw: "weapon focus"}] =
               FeatListTokenizer.tokenize("weapon focus (bastard sword)", dictionary)
    end
  end

  describe "arguments and ranks" do
    test "a parenthesised argument is captured and stripped from the name" do
      dictionary = dict(%{"weapon focus" => :weapon_focus})

      assert [%{value: :weapon_focus, argument: "bastard sword", rank: nil}] =
               FeatListTokenizer.tokenize("weapon focus (bastard sword)", dictionary)
    end

    test "a missing closing bracket still yields the argument" do
      dictionary = dict(%{"improved critical" => :improved_critical})

      assert [%{value: :improved_critical, argument: "shuriken"}] =
               FeatListTokenizer.tokenize("improved critical (shuriken", dictionary)
    end

    test "a trailing roman numeral is read as a rank, not swallowed into the name" do
      dictionary = dict(%{"great strength" => :great_strength})

      assert [%{value: :great_strength, argument: nil, rank: "iii"}] =
               FeatListTokenizer.tokenize("great strength iii", dictionary)
    end

    test "a word that merely starts with a roman letter is not misread as a rank" do
      dictionary = dict(%{"improved expertise" => :improved_expertise})

      assert [%{value: :improved_expertise, rank: nil}] =
               FeatListTokenizer.tokenize("improved expertise", dictionary)
    end
  end

  describe "unresolved text" do
    test "a name the dictionary does not know is handed back verbatim, not dropped" do
      dictionary = dict(%{"dodge" => :dodge})

      assert [%{value: nil, raw: "mystery feat", argument: nil, rank: nil}] =
               FeatListTokenizer.tokenize("mystery feat", dictionary)
    end

    test "an unresolved run stops at the next comma, and reading continues after it" do
      dictionary = dict(%{"dodge" => :dodge})

      assert [%{value: nil, raw: "mystery feat"}, %{value: :dodge}] =
               FeatListTokenizer.tokenize("mystery feat, dodge", dictionary)
    end
  end

  describe "dictionary/1" do
    test "sorts keys longest-first regardless of insertion order" do
      {_table, keys} = FeatListTokenizer.dictionary(%{"a" => 1, "aaa" => 2, "aa" => 3})
      assert keys == ["aaa", "aa", "a"]
    end
  end
end
