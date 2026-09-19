defmodule BuildCalculatorWeb.Builder.PaletteTest do
  @moduledoc """
  The class palette is a hand-assigned table, so it can drift from the data.

  These are the two failures that would otherwise be silent: a class the data
  gained and the table never learned about (which used to steal another class's
  colour, because the hue came from a hash), and two classes that ended up close
  enough to look the same in a 3px band.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Palette

  @min_gap 15

  test "каждый класс из данных есть в таблице оттенков" do
    missing = Map.keys(Data.ruleset!().classes) -- Palette.known()
    assert missing == [], "нет оттенка у классов: #{inspect(missing)}"
  end

  test "в таблице нет классов, которых нет в данных" do
    extra = Palette.known() -- Map.keys(Data.ruleset!().classes)
    assert extra == [], "оттенок назначен несуществующим классам: #{inspect(extra)}"
  end

  test "оттенки не повторяются и различимы на глаз" do
    hues = Palette.known() |> Enum.map(&Palette.hue/1) |> Enum.sort()

    assert length(Enum.uniq(hues)) == length(hues)

    # Круг замыкается, поэтому последний зазор считаем через 360.
    gaps =
      hues
      |> Enum.zip(tl(hues) ++ [hd(hues) + 360])
      |> Enum.map(fn {a, b} -> b - a end)

    assert Enum.min(gaps) >= @min_gap, "слишком близкие оттенки: #{inspect(Enum.min(gaps))}°"
  end

  test "неизвестный класс не получает чужой цвет, а остаётся серым" do
    refute Palette.hue(:definitely_not_a_class)
    refute Palette.hue(nil)

    assert Palette.style(nil) =~ "--cls-s: 0%"
    assert Palette.style(188) == "--h: 188"
  end

  test "престиж помечается только у престиж-классов" do
    ruleset = Data.ruleset!()

    assert Palette.prc(ruleset, :weapon_master) == "1"
    refute Palette.prc(ruleset, :fighter)
    refute Palette.prc(ruleset, nil)
    refute Palette.prc(ruleset, :definitely_not_a_class)
  end
end
