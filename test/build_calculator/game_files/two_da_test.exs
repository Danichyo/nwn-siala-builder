defmodule BuildCalculator.GameFiles.TwoDATest do
  @moduledoc "Разбор текста `2DA V2.0` (задача 4.5) — на формах, которые встречаются в базовых таблицах."
  use ExUnit.Case, async: true

  alias BuildCalculator.GameFiles.TwoDA

  test "columns, rows by position, **** as nil, quoted values, CRLF" do
    text =
      "2DA V2.0\r\n\r\n    Label   Value   Note\r\n" <>
        "0   MULTICLASS_LIMIT   3   ****\r\n" <>
        ~s(1   ****   ****   "two words"\r\n)

    table = TwoDA.parse!(text)
    assert table.columns == ["Label", "Value", "Note"]
    assert TwoDA.count(table) == 2
    assert TwoDA.get(table, 0, "Label") == "MULTICLASS_LIMIT"
    assert TwoDA.int(table, 0, "Value") == 3
    assert TwoDA.get(table, 0, "Note") == nil
    assert TwoDA.get(table, 1, "Label") == nil
    assert TwoDA.get(table, 1, "Note") == "two words"
    assert TwoDA.row(table, 2) == nil
  end

  test "tabs, a DEFAULT line, and a header without a blank line before it" do
    table = TwoDA.parse!("2DA V2.0\nDEFAULT: 0\n\tBonus\t\n0\t1\n1\t0\n")
    assert table.default == "0"
    assert table.columns == ["Bonus"]

    assert Enum.map(TwoDA.rows(table), fn {i, row} -> {i, row["Bonus"]} end) == [
             {0, "1"},
             {1, "0"}
           ]
  end

  test "hex and negative integers; words are not integers" do
    table = TwoDA.parse!("2DA V2.0\n\nA B C D\n0 0x15 -2 CLS_ATK_1 0xFFFFFFFF\n")
    assert TwoDA.int(table, 0, "A") == 0x15
    assert TwoDA.int(table, 0, "B") == -2
    assert TwoDA.int(table, 0, "C") == nil
    assert TwoDA.int(table, 0, "D") == 0xFFFFFFFF
  end

  test "a column is found case-insensitively when the exact name is absent" do
    table = TwoDA.parse!("2DA V2.0\n\nSkillLabel SkillIndex ClassSkill\n0 Discipline 3 1\n")
    assert TwoDA.get(table, 0, "classskill") == "1"
  end

  test "short rows pad with nil; long rows keep the columns and leave a warning" do
    table = TwoDA.parse!("2DA V2.0\n\nA B\n0 1\n1 1 2 3\n")
    assert TwoDA.get(table, 0, "B") == nil
    assert TwoDA.get(table, 1, "B") == "2"
    assert table.warnings == [{:extra_values, 1, 1}]
  end

  test "rows are numbered by position; a printed label that disagrees is reported" do
    # `cls_feat_dradis.2da` в 37-17 пропускает метку 69 и продолжает с 70: ссылки
    # FeatIndex идут по номеру СТРОКИ, а метка — только подпись.
    table = TwoDA.parse!("2DA V2.0\n\nA\n0 x\n1 y\n3 z\n")
    assert TwoDA.get(table, 2, "A") == "z"
    assert TwoDA.label(table, 2) == "3"
    assert TwoDA.mislabeled(table) == [{2, "3"}]
  end

  test "a file that is not a 2DA V2.0 table is an error" do
    assert {:error, :not_a_2da_v2} = TwoDA.parse("2DA V1.0\n")
    assert {:error, :not_a_2da_v2} = TwoDA.parse("")
    assert {:error, :no_header} = TwoDA.parse("2DA V2.0\n\n")
  end
end
