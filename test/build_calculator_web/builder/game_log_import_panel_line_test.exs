defmodule BuildCalculatorWeb.Builder.GameLogImportPanelLineTest do
  @moduledoc """
  `GameLogImportPanel.applied_line/2` — одна строка на зону отчёта «применено»
  (задача 3.215, репорт Dan 18.09.2026: пункты зон печатались без разделителя).

  Живые строки Хнюпиуса проверяет `builder_game_log_import_test.exs`; здесь —
  формы пункта, которых у Хнюпиуса нет: пометка `note` (проигравшая строка
  поглощения) и пустая зона.
  """
  use ExUnit.Case, async: true

  alias BuildCalculatorWeb.Builder.GameLogImportPanel

  test "пары «подпись значение» через запятую, пробел между подписью и значением" do
    rows = [%{label: "CON", value: "+15"}, %{label: "DEX", value: "+6"}]
    assert GameLogImportPanel.applied_line(rows) == "CON +15, DEX +6"
  end

  test "`between:` ставит двоеточие внутри пункта (руки), запятая между пунктами остаётся" do
    rows = [
      %{label: "В руке", value: "Bastard sword +6"},
      %{label: "Вторая рука", value: "Tower shield"}
    ]

    assert GameLogImportPanel.applied_line(rows, between: ": ") ==
             "В руке: Bastard sword +6, Вторая рука: Tower shield"
  end

  test "пометка `note` — в скобках у своего пункта, а не отдельным пунктом" do
    rows = [
      %{label: "Cold", value: "30", note: nil},
      %{label: "Cold", value: "15", note: "не вошла: на другом предмете больше"}
    ]

    assert GameLogImportPanel.applied_line(rows) ==
             "Cold 30, Cold 15 (не вошла: на другом предмете больше)"
  end

  test "голые строки (имена фитов) — как есть, повтор не схлопывается" do
    assert GameLogImportPanel.applied_line(["Cleave", "Epic toughness", "Epic toughness"]) ==
             "Cleave, Epic toughness, Epic toughness"
  end

  test "пустая зона — пустая строка" do
    assert GameLogImportPanel.applied_line([]) == ""
  end
end
