defmodule BuildCalculatorWeb.BuilderShardSpellNameTest do
  @moduledoc """
  Задача 4.58: заклинание шарда на ванильной строке — «Отражение (Reflection)»
  вместо Endure elements (строка 50 `spells.2da` хака, страница Сиалы
  «Отражение», слой `siala_41/spells.json`).

  На Сиале интерфейс называет его `Reflection` — английской половиной игрового
  имени, как называет по-английски все заклинания (CLAUDE.md §4), — а заглавие
  страницы вики «Отражение» служит поисковым алиасом и подписью «на вики —
  «Отражение»» под именем в списке. Ванильное имя на Сиале не печатается нигде:
  ни в списке выбора, ни в чипе слота, ни на лестнице, ни в гиде просмотра,
  ни в экспорте. id прежний (`endure_elements`) — ссылка, собранная до правки,
  открывается с тем же заклинанием под новым именем.

  Ванильная половина — `builder_shard_spell_name_vanilla_test.exs` (синхронный:
  ванильный билд на сайте рисуется только ванильной редакцией, CLAUDE.md §7);
  ванильный экспорт — здесь, это чистая функция без редакции.

  Редакция — умолчательная (Сиала), тексты по-русски.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding, Rules}
  alias BuildCalculator.Rules.{Build, Spells}
  alias BuildCalculatorWeb.Builder.Export

  @abilities %{str: 8, dex: 14, con: 14, int: 10, wis: 10, cha: 18}

  setup do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  # Колдун 1; `spells` — заклинания 1-го круга по слотам, начиная с первого.
  defp sorcerer(ruleset, first_circle \\ []) do
    b =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: [:sorcerer],
        base_abilities: @abilities
      )

    slots = for slot <- Spells.slots_at(b, ruleset, 1), slot.circle == 1, do: slot.id
    %Build{b | spells: %{1 => Map.new(Enum.zip(slots, first_circle))}}
  end

  defp open(conn, build), do: live(conn, ~p"/?b=#{Encoding.encode(build)}&l=1")

  defp text(view, selector), do: view |> element(selector) |> render()

  describe "список выбора колдуна 1" do
    test "строка 50 — Reflection с подписью вики «Отражение», без Endure elements", %{
      conn: conn,
      siala: siala
    } do
      {:ok, view, _html} = open(conn, sorcerer(siala))

      row = text(view, "#spell-endure_elements")
      assert row =~ "Reflection"
      assert row =~ "на вики — «Отражение»"
      refute row =~ "Endure"

      # Иконка ванильного Endure elements — картинка другого заклинания; арта
      # шарда (`is_antimag`) у нас нет, бокс пустой.
      refute row =~ "Is_endelem"

      # Положительный контроль: список правда открыт и несёт соседей по кругу.
      assert has_element?(view, "#spell-magic_missile")
      refute render(element(view, "#spell-list")) =~ "Endure elements"
    end

    # Поиск находит по обоим написаниям: по имени — с подсветкой, по алиасу —
    # без неё (позиции принадлежат алиасу, а не печатаемому имени).
    test "поиск находит по «Reflection» и по «Отражение», а по «Endure» — нет", %{
      conn: conn,
      siala: siala
    } do
      {:ok, view, _html} = open(conn, sorcerer(siala))

      for query <- ["refl", "Reflection", "отраж", "Отражение"] do
        view |> form("#spell-search-form", %{"q" => query}) |> render_change()
        assert has_element?(view, "#spell-endure_elements"), "не нашлось по #{inspect(query)}"
      end

      view |> form("#spell-search-form", %{"q" => "endure"}) |> render_change()
      refute has_element?(view, "#spell-endure_elements")

      # Положительный контроль самого поиска: другое заклинание по своему имени.
      view |> form("#spell-search-form", %{"q" => "magic missile"}) |> render_change()
      assert has_element?(view, "#spell-magic_missile")
      refute has_element?(view, "#spell-endure_elements")
    end

    test "клик кладёт его в слот, и чип называет Reflection", %{conn: conn, siala: siala} do
      {:ok, view, _html} = open(conn, sorcerer(siala))

      view |> element("#spell-endure_elements") |> render_click()

      chips = text(view, "#spell-slot-chips")
      assert chips =~ "Reflection"
      refute chips =~ "Endure"
    end
  end

  describe "ссылка, собранная до правки" do
    # Код билда несёт id, а не имя: та же ссылка открывает то же заклинание,
    # просто под именем шарда. Пик не выпадает и нелегальным не становится.
    test "открывается с тем же заклинанием: лестница и гид просмотра — Reflection", %{
      conn: conn,
      siala: siala
    } do
      build = sorcerer(siala, [:endure_elements])
      code = Encoding.encode(build)

      assert {:ok, %{build: decoded, dropped: []}} = Encoding.decode(code)
      assert decoded.spells == build.spells
      assert Rules.illegal_spells(decoded, siala) == []

      {:ok, view, _html} = open(conn, build)
      ladder = text(view, "#level-ladder")
      assert ladder =~ "Reflection"
      refute ladder =~ "Endure"

      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      assert render(view) =~ "Reflection"
      refute render(view) =~ "Endure elements"
    end
  end

  describe "экспорт" do
    defp export_text(ruleset) do
      build = sorcerer(ruleset, [:endure_elements])
      Export.text(build, ruleset, Rules.compute(build, ruleset))
    end

    defp level_line(text),
      do: text |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "01:"))

    # Как у расы: экспорт печатает то имя, которым сущность называет интерфейс.
    # У расы это «Гном (Dwarf)» — имя шарда и движковое, механика у них одна;
    # у этого заклинания движковое имя — другое заклинание, и в скобки не идёт.
    test "Сиала печатает [1] Reflection — без Endure elements и без скобок", %{siala: siala} do
      text = export_text(siala)
      assert level_line(text) =~ "[1] Reflection,"
      refute text =~ "Endure"
      refute text =~ "Отражение"
    end

    # Форма гильдии ECB (`Edition.export_guide/1` → `:ecb`, `leveling_guide/2`
    # экспорта) известных заклинаний в гиде не печатает вовсе: имени там нет ни
    # старого, ни нового. Положительный контроль — строка уровня на месте.
    test "ваниль: в экспорте нет ни Reflection, ни строки заклинания", %{vanilla: vanilla} do
      text = export_text(vanilla)
      assert level_line(text) == "01: Sorcerer(1):"
      refute text =~ "Reflection"
      refute text =~ "Endure"
    end
  end
end
