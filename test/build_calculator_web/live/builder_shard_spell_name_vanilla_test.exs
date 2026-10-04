defmodule BuildCalculatorWeb.BuilderShardSpellNameVanillaTest do
  @moduledoc """
  Задача 4.58, ванильная половина: на ванили строка 50 `spells.2da` — по-прежнему
  Endure elements, и правка слоя Сиалы её не задела — ни имени, ни иконки, ни
  подписи «on the wiki». Сиальская половина и экспорт обеих —
  `builder_shard_spell_name_test.exs`.

  ⚠️ `async: false` — `use_edition/1` меняет редакцию ПРИЛОЖЕНИЯ через
  `Application.put_env/3`: ванильный билд на сайте рисуется только ванильной
  редакцией (сиальская встречает его мостиком), а параллельный сосед в той же
  VM увидел бы чужой сайт (CLAUDE.md §7).
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculatorWeb.EditionHelpers

  alias BuildCalculator.{Data, Encoding}
  alias BuildCalculator.Rules.Build

  setup do
    use_edition(:vanilla)
  end

  test "колдун 1: Endure elements под ванильным именем, без алиаса и без Reflection", %{
    conn: conn
  } do
    ruleset = Data.ruleset!("vanilla")

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: [:sorcerer],
        base_abilities: %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18}
      )

    {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}&l=1")

    row = view |> element("#spell-endure_elements") |> render()
    assert row =~ "Endure elements"
    refute row =~ "Reflection"
    refute row =~ "on the wiki"
    assert row =~ "Is_endelem.gif"

    view |> form("#spell-search-form", %{"q" => "refl"}) |> render_change()
    refute has_element?(view, "#spell-endure_elements")

    view |> form("#spell-search-form", %{"q" => "endure"}) |> render_change()
    assert has_element?(view, "#spell-endure_elements")
  end
end
