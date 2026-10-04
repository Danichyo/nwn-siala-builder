defmodule BuildCalculatorWeb.FeatInfoShardPageComponentTest do
  @moduledoc """
  Кружок `ⓘ` у фита шарда без страницы на Fandom (задача 4.71): страница шарда
  едет в `data-feat-page` (JSON блоков), подпись над ней — в `data-label-page`.

  🔴 Безопасность: текст страницы — цитата с вики, и ни строка из неё, ни её
  кусок не становится разметкой. Сервер кладёт её только в значение атрибута
  (HEEx экранирует), хук рисует её через `textContent` из закрытого набора
  тегов (`assets/test/feat_info.test.mjs`). Здесь — серверная половина:
  враждебная строка в блоках остаётся строкой в атрибуте и не порождает
  ни одного элемента разметки.

  Разметка проверяется разобранной (`LazyHTML`), а не сырой строкой.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculatorWeb.BuilderComponents
  alias BuildCalculatorWeb.Builder.WikiBlocks

  @label "Текст шарда — ванильного описания (Fandom) нет"

  @hostile [
    "<script>alert(1)</script>",
    "<img src=x onerror=alert(2)>",
    "[javascript:alert(3) click me]",
    "\" onmouseover=\"alert(4)",
    "</span><script>alert(5)</script>"
  ]

  setup do
    Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
    :ok
  end

  defp parsed(html), do: LazyHTML.from_fragment(html)
  defp trigger(doc, id), do: LazyHTML.query(doc, "##{id}")

  defp single(page, extra \\ []) do
    render_component(
      &BuilderComponents.feat_info/1,
      [id: "fi", name: "Instinctive Throw", shard_page: page] ++ extra
    )
  end

  test "страница шарда — в data-feat-page, подпись — своя, описания Fandom нет" do
    page = [%{kind: "p", text: "Монах может совершить бросок."}, %{kind: "h", text: "Общие"}]
    node = page |> single() |> parsed() |> trigger("fi")

    assert [json] = LazyHTML.attribute(node, "data-feat-page")

    assert Jason.decode!(json) == [
             %{"kind" => "p", "text" => "Монах может совершить бросок."},
             %{"kind" => "h", "text" => "Общие"}
           ]

    assert LazyHTML.attribute(node, "data-label-page") == [@label]
    assert LazyHTML.attribute(node, "data-feat-description") == []
    # Не «изменено на Сиале»: подписей шарда нет вовсе.
    assert LazyHTML.attribute(node, "data-feat-changed") == ["false"]
    assert LazyHTML.attribute(node, "data-label-changed") == []
    assert LazyHTML.attribute(node, "data-label-vanilla") == []
  end

  test "у фита с описанием Fandom и без страницы — ни атрибута страницы, ни подписи" do
    node =
      render_component(&BuilderComponents.feat_info/1,
        id: "fi",
        name: "Iron will",
        description: "Fandom's prose"
      )
      |> parsed()
      |> trigger("fi")

    assert LazyHTML.attribute(node, "data-feat-page") == []
    assert LazyHTML.attribute(node, "data-label-page") == []
    # Положительный контроль: кружок отрисован.
    assert LazyHTML.attribute(node, "data-feat-description") == ["Fandom's prose"]
  end

  # 🔴 Враждебная строка прямо в блоках, мимо `WikiBlocks` (худший случай:
  # чтение вики ошиблось): на странице — ни одного элемента из неё, в атрибуте
  # — она же, буква в букву.
  test "враждебный текст в блоках — строка в атрибуте, а не разметка" do
    page = [
      %{kind: "p", text: Enum.at(@hostile, 0)},
      %{kind: "ul", items: Enum.slice(@hostile, 1, 2)},
      %{kind: "<img src=x onerror=alert(6)>", text: Enum.at(@hostile, 3)},
      %{kind: "pre", text: Enum.at(@hostile, 4)}
    ]

    doc = page |> single() |> parsed()

    assert LazyHTML.query(doc, "script") |> Enum.count() == 0
    assert LazyHTML.query(doc, "img") |> Enum.count() == 0
    assert LazyHTML.query(doc, "[onerror]") |> Enum.count() == 0
    assert LazyHTML.query(doc, "[onmouseover]") |> Enum.count() == 0
    assert LazyHTML.query(doc, "a") |> Enum.count() == 0

    # Положительный контроль измерителя: те же строки, вставленные разметкой
    # без экранирования, запрос нашёл бы.
    raw = parsed("<div>" <> Enum.join(@hostile) <> "</div>")
    assert LazyHTML.query(raw, "script") |> Enum.count() == 2
    assert LazyHTML.query(raw, "img[onerror]") |> Enum.count() == 1

    # Положительный контроль: кружок один и несёт строки целиком.
    node = trigger(doc, "fi")
    assert Enum.count(node) == 1
    assert [json] = LazyHTML.attribute(node, "data-feat-page")
    assert Jason.decode!(json) == Jason.decode!(Jason.encode!(page))
  end

  # Та же проверка по всей дороге: враждебная разметка в теле раздела страницы
  # → `WikiBlocks.blocks/1` → кружок.
  test "враждебная разметка в тексте раздела — до кружка доходит только текст" do
    body =
      "*<script>alert(1)</script> пункт\n" <>
        "<img src=x onerror=alert(2)>текст [javascript:alert(3) click me]"

    doc = body |> WikiBlocks.blocks() |> single() |> parsed()

    assert LazyHTML.query(doc, "script") |> Enum.count() == 0
    assert LazyHTML.query(doc, "img") |> Enum.count() == 0

    [json] = doc |> trigger("fi") |> LazyHTML.attribute("data-feat-page")

    assert Jason.decode!(json) == [
             %{"kind" => "ul", "items" => ["alert(1) пункт"]},
             %{"kind" => "p", "text" => "текст [javascript:alert(3) click me]"}
           ]
  end

  describe "стопка выданных (feats_info/1)" do
    defp entry(name, opts) do
      Map.merge(
        %{
          name: name,
          description: nil,
          siala_changed?: false,
          siala_notes: [],
          siala_notes_more_text: nil,
          siala_specifics: [],
          siala_numbers_differ?: false,
          shard_page: [],
          source_url: nil,
          source_link_text: nil
        },
        Map.new(opts)
      )
    end

    defp stack(entries) do
      render_component(&BuilderComponents.feats_info/1,
        id: "fs",
        label: "Level 5",
        entries: entries
      )
      |> parsed()
      |> trigger("fs")
    end

    test "страница едет в записи фита шарда и только в ней; подпись — у триггера" do
      node =
        stack([
          entry("Instinctive Throw", shard_page: [%{kind: "p", text: "бросок"}]),
          entry("Deflect arrows", description: "Fandom's prose")
        ])

      [throw, deflect] =
        node |> LazyHTML.attribute("data-feat-entries") |> hd() |> Jason.decode!()

      assert throw["page"] == [%{"kind" => "p", "text" => "бросок"}]
      assert throw["description"] == nil
      refute Map.has_key?(deflect, "page")
      assert deflect["description"] == "Fandom's prose"
      assert LazyHTML.attribute(node, "data-label-page") == [@label]
    end

    test "без фитов шарда — ни ключа page, ни подписи: JSON прежний" do
      node = stack([entry("Deflect arrows", description: "Fandom's prose")])

      [deflect] = node |> LazyHTML.attribute("data-feat-entries") |> hd() |> Jason.decode!()

      assert Map.keys(deflect) |> Enum.sort() ==
               ~w(changed description name notes notesMore sourceText sourceUrl)

      assert LazyHTML.attribute(node, "data-label-page") == []
    end
  end
end
