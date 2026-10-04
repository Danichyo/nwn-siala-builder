defmodule BuildCalculatorWeb.Builder.ImportScoreInBracketTest do
  @moduledoc """
  Задача 4.40, пункт 3: число, снятое в конце скобки, не оставляет дыры.

  `LevelTail.drop_scores/1` снимает вписанный итог (`=17`, `(20)`) как арифметику
  источника и заменял его пробелом: `Whirlwind (Intimidate = 4)` (пост ECB
  186693, 12-й уровень) доходил до замечания как «Whirlwind (Intimidate )».
  Теперь итог, который закрывает скобку после слова, уходит вместе с пробелом
  перед ним. Чтение имени фита это не меняет — скобки при поиске имени и так
  заменяются пробелами (`FeatList`); меняется то, что игрок видит в отчёте.
  Скобка из одного итога (`(=25)`) остаётся по-старому — пустой скобкой `( )`;
  с захода 3 (пункт 22) читатель фитов читает пустую скобку одинаково с пробелом
  внутри и без (`import_empty_bracket_test.exs`).

  ⚠️ С захода 3 (пункт 23) голое «Whirlwind» — имя фита (Whirlwind attack),
  и незнакомое имя здесь — «Mystic Strike»: тесты про печать скобки, а не про
  имя. Строка поста 186693 читается фитом — тест ниже.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Import

  setup_all do
    %{ruleset: Data.ruleset!("vanilla")}
  end

  defp unknown(line, ruleset) do
    text = "Human, Lawful Good\nLEVELING GUIDE\n01: Fighter(1): #{line}\n"
    for {:unknown_feat, 1, raw} <- Import.parse(text, ruleset).issues, do: raw
  end

  test "`(Intimidate = 4)` — без пробела перед скобкой", %{ruleset: ruleset} do
    assert unknown("Mystic Strike (Intimidate = 4)", ruleset) == ["Mystic Strike (Intimidate)"]
    assert unknown("Mystic Strike (Intimidate =4 )", ruleset) == ["Mystic Strike (Intimidate)"]
    assert unknown("Mystic Strike [Intimidate= 4]", ruleset) == ["Mystic Strike [Intimidate]"]
  end

  # Итог не в конце скобки снимается, как прежде: пробелом.
  test "итог посреди скобки и вне скобки — как прежде", %{ruleset: ruleset} do
    assert unknown("Mystic Strike (Intimidate = 4 ranks)", ruleset) == [
             "Mystic Strike (Intimidate ranks)"
           ]

    assert unknown("Mystic Strike = 4", ruleset) == ["Mystic Strike"]
  end

  # Скобка, где итог один, — по-старому, пустой скобкой. Первая версия правки
  # 4.40 оставляла `()`, и это сдвинуло чтение двух постов корпуса (170330,
  # 281200) — поймал стенд `import_equivalence.exs`: читатель фитов читал `()`
  # не так, как `( )`. С захода 3 — одинаково (`import_empty_bracket_test.exs`).
  test "скобка из одного итога — чтение то же, что до 4.40", %{ruleset: ruleset} do
    assert unknown("Mystic Strike (=4)", ruleset) == ["Mystic Strike ( )"]

    ladder =
      for level <- 1..30 do
        if level == 30, do: "30 Fighter Graet CHA II (=25)", else: "#{level} Fighter"
      end

    result = Import.parse("Human, Lawful Good\n" <> Enum.join(ladder, "\n") <> "\n", ruleset)
    assert result.build.feats[30] == %{general: :great_charisma}
  end

  # Положительный контроль: скобка без итога не трогается.
  test "скобка без числа — как написана", %{ruleset: ruleset} do
    assert unknown("Mystic Strike (Intimidate )", ruleset) == ["Mystic Strike (Intimidate )"]
  end

  # Форма строки поста 186693 (текст постов корпуса в git не кладём —
  # `tools/vanilla_recon/README.md`): лестница «номер класс фиты прибавка».
  # С захода 3 (пункт 23) «Whirlwind» — Whirlwind attack, а «Intimidate» из
  # скобки — подробность, которую мы не храним, тоже без дыры от снятого числа.
  test "лестница в форме поста 186693", %{ruleset: ruleset} do
    ladder =
      for level <- 1..12 do
        tail = if level == 12, do: " Whirlwind (Intimidate = 4) CHA(19)", else: ""
        "#{level} Paladin#{tail}"
      end

    text = "Level Class Feat Ability Increase\n" <> Enum.join(ladder, "\n") <> "\n"

    result = Import.parse(text, ruleset)

    assert result.build.feats[12] == %{general: :whirlwind_attack}
    assert {:feat_qualifier_dropped, 12, :whirlwind_attack, "Intimidate"} in result.issues
    refute Enum.any?(result.issues, &match?({:unknown_feat, 12, _}, &1))
  end
end
