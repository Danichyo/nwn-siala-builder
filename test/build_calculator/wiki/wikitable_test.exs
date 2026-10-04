defmodule BuildCalculator.Wiki.WikitableTest do
  use ExUnit.Case, async: true

  alias BuildCalculator.Wiki.Wikitable

  defp grid(source) do
    source
    |> Wikitable.parse()
    |> Map.fetch!(:rows)
    |> Wikitable.expand()
    |> Enum.map(fn row -> Enum.map(row, & &1.text) end)
  end

  describe "expand/1 with spans" do
    test "a two-row header stitched with rowspan and colspan lines up" do
      # The shape every class page uses: "Saves" spans three columns on the first
      # header row, everything beside it spans down into the second.
      source = """
      {| border="2"
      |- style="background:#c0c0c0"
      !rowspan=2|Lvl
      !rowspan=2|BAB
      !colspan="3"|Saves
      !rowspan=2|Feats
      |- style="background:#c0c0c0"
      !Fort
      !Ref
      !Will
      |- align=center
      |1st || +1 || +2 || +0 || +0 ||align=left|bonus feat
      |}
      """

      assert grid(source) == [
               ["Lvl", "BAB", "Saves", "Saves", "Saves", "Feats"],
               ["Lvl", "BAB", "Fort", "Ref", "Will", "Feats"],
               ["1st", "+1", "+2", "+0", "+0", "bonus feat"]
             ]
    end

    test "a spacer column declared once keeps every body row aligned" do
      # `!rowspan="4"|&nbsp;` occupies a column in all four rows but appears in
      # only one of them. Zipping body cells against the header without expanding
      # it would shift every spell count one column to the left.
      source = """
      {|
      |-
      !rowspan=2|Lvl
      !rowspan="4" style="background:#ffffff"|&nbsp;
      !colspan=2|Spells per day
      |-
      !1st
      !2nd
      |-
      |1st ||3 ||1
      |-
      |2nd ||4 ||2
      |}
      """

      assert grid(source) == [
               ["Lvl", "", "Spells per day", "Spells per day"],
               ["Lvl", "", "1st", "2nd"],
               ["1st", "", "3", "1"],
               ["2nd", "", "4", "2"]
             ]
    end

    test "marks copies of a spanned cell so a caller can tell them from the original" do
      source = """
      {|
      |-
      !rowspan=2 colspan=2|Corner
      !Right
      |-
      !Other
      |}
      """

      [[first, across, _right], [down, _down_across, _other]] =
        source |> Wikitable.parse() |> Map.fetch!(:rows) |> Wikitable.expand()

      refute first.spanned?
      assert across.spanned?
      assert down.spanned?
      assert first.rowspan == 2
      assert first.colspan == 2
    end

    test "a rowspan that outlives the table does not affect earlier rows" do
      source = """
      {|
      |-
      !Lvl
      !rowspan=9|&nbsp;
      !HP
      |-
      |1st ||5-10
      |}
      """

      assert grid(source) == [["Lvl", "", "HP"], ["1st", "", "5-10"]]
    end
  end

  describe "parse/1 cell syntax" do
    test "splits attributes off the cell but leaves a wiki link's pipe alone" do
      source = """
      {|
      |-
      |align=left|[[Dual-wield (feat)|dual-wield]] ||style="x"|b
      |}
      """

      assert [%{cells: [left, right]}] = Wikitable.parse(source).rows
      assert left.attrs == "align=left"
      assert left.text == "[[Dual-wield (feat)|dual-wield]]"
      assert right.attrs == "style=\"x\""
      assert right.text == "b"
    end

    test "reads a row that opens with an empty attribute part" do
      # The arcane archer's epic table writes its rows as `||11th ||…`.
      source = """
      {|
      |-
      ||11th ||align=left| ||44-88
      |}
      """

      assert grid(source) == [["11th", "", "44-88"]]
    end

    test "takes cells that arrive before the first row separator" do
      # The purple dragon knight's table opens straight into header cells, and
      # indents every line.
      source = """
      {| class="compacttable"
         !Level
         !BAB
       |-
         |1 ||+1
       |}
      """

      assert grid(source) == [["Level", "BAB"], ["1", "+1"]]
    end

    test "treats a header row containing a blank data cell as a header row" do
      # The champion of Torm's epic table declares its spacer with `|` in the
      # middle of a row of `!` cells.
      source = """
      {|
      |-
      !Lvl
      |rowspan=3 style="background:#ffffff"|&nbsp;
      !Save bonus
      |-
      |11th || +5
      |}
      """

      assert [header, body] = Wikitable.parse(source).rows |> Wikitable.expand()
      assert Enum.map(header, & &1.text) == ["Lvl", "", "Save bonus"]
      assert Enum.map(body, & &1.text) == ["11th", "", "+5"]
      assert Enum.all?(header, &(&1.header? or &1.text == ""))
    end

    test "continues a cell onto the following lines" do
      source = """
      {|
      |-
      |align=left|first line
      second line
      |}
      """

      assert grid(source) == [["first line\nsecond line"]]
    end

    test "skips blank lines and the caption" do
      source = """
      {|
      |+ Level progression

      |-

      !Lvl

      |-
      |1st
      |}
      """

      assert grid(source) == [["Lvl"], ["1st"]]
    end

    test "splits a header row that uses || instead of !! between cells" do
      # Siala's `Система оружия` writes its eight-column header this way —
      # `!a ||b ||c` with no `!!` anywhere — and MediaWiki renders it as eight
      # separate `<th>` cells (checked against `action=parse`), not one. A data
      # row already splits on `||`; a header row must accept it too.
      source = """
      {|
      |-
      !style="x"|Lvl ||style="x"|BAB
      |-
      |1st ||+1
      |}
      """

      assert grid(source) == [["Lvl", "BAB"], ["1st", "+1"]]
    end

    test "still splits a header row on !! when there is no || at all" do
      source = """
      {|
      |-
      !Lvl!!BAB
      |}
      """

      assert grid(source) == [["Lvl", "BAB"]]
    end

    test "a header row may mix !! and || on the same line" do
      # `fandom:Attacks per round`'s table header, verbatim: three cells joined
      # by `!!`, then two more joined by `||` off the last of them.
      source = """
      {|
      |-
      ! BAB !! Attack bonuses !! Attacks per round || Unarmed progression (monk) || Unarmed APR (monk)
      |}
      """

      assert grid(source) == [
               [
                 "BAB",
                 "Attack bonuses",
                 "Attacks per round",
                 "Unarmed progression (monk)",
                 "Unarmed APR (monk)"
               ]
             ]
    end
  end

  describe "find_all/1" do
    test "returns top-level tables and keeps a nested one inside its cell" do
      wikitext = """
      Intro.

      {| border=1
      |-
      |outer
      {| border=2
      |-
      |inner
      |}
      |}

      {| border=3
      |-
      |second
      |}
      """

      assert [first, second] = Wikitable.find_all(wikitext)
      assert first =~ "border=1"
      assert first =~ "|inner"
      assert second =~ "border=3"
      refute second =~ "border=1"
    end

    test "ignores prose outside tables" do
      assert Wikitable.find_all("'''Hit die:''' d10\n\nno tables here") == []
    end
  end

  describe "split_top/2" do
    test "does not split inside links, templates or a nested table" do
      assert Wikitable.split_top("a||[[b||c]]||{{d||e}}", "||") == ["a", "[[b||c]]", "{{d||e}}"]
      assert Wikitable.split_top("a|{| x | y |}|b", "|") == ["a", "{| x | y |}", "b"]
    end
  end
end
