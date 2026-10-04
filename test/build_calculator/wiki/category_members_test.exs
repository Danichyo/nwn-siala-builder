defmodule BuildCalculator.Wiki.CategoryMembersTest do
  @moduledoc """
  The rule that turns a category into a list: a sort key means "filed here", not
  "one of these".

  Worth its own tests because the whole size of `creature_types.json` rests on
  it. Counting `Category:Races` naively gives 26 and the wiki says 25 in words;
  the difference is one article about races, and the only thing that marks it as
  an article is the pipe in its category link.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.CategoryMembers

  describe "sort_key/2" do
    test "a bare link is a member" do
      assert CategoryMembers.sort_key("[[category:races]]", "Category:Races") == :bare
    end

    test "a piped link is a page filed under the category" do
      assert CategoryMembers.sort_key("[[Category: Races| Subrace]]", "Category:Races") ==
               {:key, "Subrace"}
    end

    # Both wikis mix the three spellings freely — `Ooze` writes `[[category:races]]`
    # while `Animal` writes `[[Category:Races]]` — so case and padding cannot be
    # allowed to decide whether a race exists.
    test "case and padding on the prefix and the name do not matter" do
      for text <- [
            "[[category:races]]",
            "[[Category:Races]]",
            "[[Category:races]]",
            "[[ category : Races ]]"
          ] do
        assert CategoryMembers.sort_key(text, "Category:Races") == :bare, text
      end
    end

    test "a page that never links the category at all" do
      assert CategoryMembers.sort_key("no categories here", "Category:Races") == :unlinked
    end

    test "an empty sort key still counts as one" do
      assert CategoryMembers.sort_key("[[Category:Races|]]", "Category:Races") == {:key, ""}
    end

    test "another category's link is not this category's" do
      assert CategoryMembers.sort_key("[[Category:Spells]]", "Category:Races") == :unlinked
    end
  end

  describe "split/2" do
    setup do
      pages = [
        {%{title: "Ooze", categories: ["Category:Races"]}, "[[category:races]]"},
        {%{title: "Aberration", categories: ["Category:Races"]}, "[[category:races]]"},
        {%{title: "Subrace", categories: ["Category:Races"]}, "[[Category: Races| Subrace]]"},
        {%{title: "Fireball", categories: ["Category:Spells"]}, "[[category:spells]]"}
      ]

      %{pages: pages}
    end

    test "keeps the members and sets the filed articles aside", %{pages: pages} do
      %{instances: instances, filed: filed} = CategoryMembers.split(pages, "Category:Races")

      assert Enum.map(instances, fn {entry, _text} -> entry.title end) == ["Aberration", "Ooze"]
      assert Enum.map(filed, fn {entry, _text} -> entry.title end) == ["Subrace"]
    end

    test "pages of other categories are not considered", %{pages: pages} do
      %{instances: instances, filed: filed} = CategoryMembers.split(pages, "Category:Races")

      refute "Fireball" in Enum.map(instances ++ filed, fn {entry, _text} -> entry.title end)
    end

    # The index is what says a page belongs; the wikitext only says *how*. A page
    # categorised by a template carries no link, and dropping it would silently
    # shrink a dictionary.
    test "a member whose wikitext carries no link is still a member" do
      pages = [{%{title: "Templated", categories: ["Category:Races"]}, "no link"}]

      assert %{instances: [{%{title: "Templated"}, _text}], filed: []} =
               CategoryMembers.split(pages, "Category:Races")
    end
  end
end
