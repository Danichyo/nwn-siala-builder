defmodule BuildCalculatorWeb.Builder.FuzzyTest do
  use ExUnit.Case, async: true

  alias BuildCalculatorWeb.Builder.Fuzzy

  defp best(query, names) do
    names
    |> Enum.map(&{&1, Fuzzy.match(query, &1)})
    |> Enum.reject(fn {_name, match} -> is_nil(match) end)
    |> Enum.max_by(fn {_name, match} -> match.score end, fn -> nil end)
    |> case do
      nil -> nil
      {name, _match} -> name
    end
  end

  @feats [
    "Power attack",
    "Improved knockdown",
    "Improved two-weapon fighting",
    "Two-weapon fighting",
    "Toughness",
    "Blind fight",
    "Weapon focus"
  ]

  describe "abbreviations the community actually types" do
    test "pwatk finds Power attack" do
      assert best("pwatk", @feats) == "Power attack"
    end

    test "ikd finds Improved knockdown" do
      assert best("ikd", @feats) == "Improved knockdown"
    end

    test "itwf finds Improved two-weapon fighting" do
      assert best("itwf", @feats) == "Improved two-weapon fighting"
    end
  end

  test "a dropped letter still matches" do
    assert Fuzzy.match("toughnes", "Toughness")
  end

  test "letters that are not there in order do not match" do
    refute Fuzzy.match("zzz", "Toughness")
    refute Fuzzy.match("kcatta", "Power attack")
  end

  test "an empty query matches everything with no highlights" do
    assert %{score: 0, positions: []} = Fuzzy.match("", "Toughness")
    assert %{score: 0, positions: []} = Fuzzy.match("   ", "Toughness")
  end

  test "a shorter name wins when everything else is equal" do
    short = Fuzzy.match("twf", "Two-weapon fighting")
    long = Fuzzy.match("twf", "Improved two-weapon fighting")

    assert short.score > long.score
  end

  test "a prefix beats a scattered subsequence" do
    prefix = Fuzzy.match("tough", "Toughness")
    scattered = Fuzzy.match("tough", "Two-weapon fighting is rough")

    assert prefix.score > scattered.score
  end

  test "cyrillic queries work — the wiki aliases are searched too" do
    assert Fuzzy.match("живуч", "Живучесть")
    refute Fuzzy.match("живучх", "Живучесть")
  end

  describe "segments" do
    test "runs of matched and unmatched characters are merged" do
      assert Fuzzy.segments("Power attack", [0, 1, 6, 7, 8]) == [
               {:hit, "Po"},
               {:miss, "wer "},
               {:hit, "att"},
               {:miss, "ack"}
             ]
    end

    test "no positions means one plain run" do
      assert Fuzzy.segments("Toughness", []) == [{:miss, "Toughness"}]
    end

    test "positions line up with the original casing" do
      match = Fuzzy.match("pa", "Power attack")

      assert [{:hit, "P"} | _] = Fuzzy.segments("Power attack", match.positions)
    end
  end
end
