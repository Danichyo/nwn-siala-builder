defmodule BuildCalculatorWeb.FeatInfoLabelsTest do
  @moduledoc """
  Подписи шарда у кружка фита (`.FeatInfo`) едут только с фитом, который шард
  изменил, — задача 4.4.

  Хук читает `data-label-changed`, `-changed-generic` и `-vanilla` лишь
  в ветке «фит изменён» (`featChanged === "true"` у одиночного кружка,
  `entry.changed` у стопки), и на любом другом кружке эти подписи были мёртвым
  текстом. На ванили, где шард не менял ни одного фита, мёртвый текст
  «Changed on Siala» стоял у каждого фита страницы — сторож «ни Сиалы, ни
  шарда» (`en_guard_test.exs`) видел его сотню раз.

  Разметка кружка проверяется разобранной (`LazyHTML`), а не сырой строкой.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculatorWeb.BuilderComponents

  @shard_labels ["data-label-changed", "data-label-changed-generic", "data-label-vanilla"]

  defp trigger(html, id), do: html |> LazyHTML.from_fragment() |> LazyHTML.query("##{id}")

  defp single(changed?) do
    html =
      render_component(&BuilderComponents.feat_info/1,
        id: "fi",
        name: "Evasion",
        description: "Fandom's prose",
        siala_changed?: changed?
      )

    trigger(html, "fi")
  end

  defp stack(changed) do
    entries =
      for {name, changed?} <- changed do
        %{
          name: name,
          description: "Fandom's prose",
          siala_changed?: changed?,
          siala_notes: [],
          siala_notes_more_text: nil,
          siala_specifics: [],
          siala_numbers_differ?: false,
          source_url: nil,
          source_link_text: nil
        }
      end

    html =
      render_component(&BuilderComponents.feats_info/1,
        id: "fs",
        label: "Level 1",
        entries: entries
      )

    trigger(html, "fs")
  end

  test "одиночный кружок: у фита без изменений шарда подписей шарда нет" do
    node = single(false)

    for label <- @shard_labels, do: assert(LazyHTML.attribute(node, label) == [])

    # Положительный контроль: кружок отрисован, его собственная подпись на месте.
    assert LazyHTML.attribute(node, "data-feat-changed") == ["false"]
    assert LazyHTML.attribute(node, "data-label-close") == ["Закрыть"]
  end

  test "одиночный кружок: у фита, изменённого шардом, подписи на месте — прежние" do
    node = single(true)

    assert LazyHTML.attribute(node, "data-feat-changed") == ["true"]
    assert LazyHTML.attribute(node, "data-label-changed") == ["Изменено на Сиале"]
    assert [_generic] = LazyHTML.attribute(node, "data-label-changed-generic")
    assert [_vanilla] = LazyHTML.attribute(node, "data-label-vanilla")
  end

  test "стопка: подписи есть, если изменён хоть один фит, и нет, если ни одного" do
    none = stack([{"Dodge", false}, {"Mobility", false}])
    for label <- @shard_labels, do: assert(LazyHTML.attribute(none, label) == [])

    some = stack([{"Dodge", false}, {"Evasion", true}])
    assert LazyHTML.attribute(some, "data-label-changed") == ["Изменено на Сиале"]
    assert [_generic] = LazyHTML.attribute(some, "data-label-changed-generic")
  end

  # Задача 4.67: текст «Особенностей» шарда (`siala_specifics`, у 33 страниц,
  # где числа шарда расходятся с Fandom) рисуется тем же блоком «Изменено на
  # Сиале», что цитаты `siala_note`, — первым, — и меняет подпись над описанием
  # Fandom. Хук рисует блок из `data-feat-notes` / `entry.notes` построчно, так
  # что проверка списка здесь — проверка того, что увидит игрок.
  describe "текст шарда (задача 4.67)" do
    @vanilla_numbers "Ванильное описание (Fandom) — числа ванильные; на Сиале верен текст шарда выше"

    defp single_with(specifics, notes, numbers_differ? \\ true) do
      html =
        render_component(&BuilderComponents.feat_info/1,
          id: "fi",
          name: "Point blank shot",
          description: "Fandom's prose",
          siala_changed?: true,
          siala_notes: notes,
          siala_specifics: specifics,
          siala_numbers_differ?: numbers_differ?
        )

      trigger(html, "fi")
    end

    defp notes(node), do: node |> LazyHTML.attribute("data-feat-notes") |> hd() |> Jason.decode!()

    test "одиночный кружок: текст шарда — первой строкой блока, подпись над Fandom — своя" do
      node = single_with(["+5 до 5 метров"], ["заметка шарда"])

      assert notes(node) == ["+5 до 5 метров", "заметка шарда"]
      assert LazyHTML.attribute(node, "data-label-vanilla") == [@vanilla_numbers]
      assert LazyHTML.attribute(node, "data-label-changed") == ["Изменено на Сиале"]
    end

    test "одиночный кружок без текста шарда — строки и подпись прежние" do
      node = single_with([], ["заметка шарда"])

      assert notes(node) == ["заметка шарда"]
      assert LazyHTML.attribute(node, "data-label-vanilla") == ["Ванильное описание (Fandom)"]
    end

    test "стопка: своя подпись едет в записи фита с текстом шарда и только в ней" do
      entries = [
        %{
          name: "Evasion",
          description: "Fandom's prose",
          siala_changed?: true,
          siala_notes: ["заметка шарда"],
          siala_notes_more_text: nil,
          siala_specifics: [],
          siala_numbers_differ?: false,
          source_url: nil,
          source_link_text: nil
        },
        %{
          name: "Imbue arrow",
          description: "Fandom's prose",
          siala_changed?: true,
          siala_notes: [],
          siala_notes_more_text: nil,
          siala_specifics: ["10д6 (Максимум 35д6)"],
          siala_numbers_differ?: true,
          source_url: nil,
          source_link_text: nil
        }
      ]

      node =
        render_component(&BuilderComponents.feats_info/1,
          id: "fs",
          label: "Level 2",
          entries: entries
        )
        |> trigger("fs")

      [evasion, imbue] =
        node |> LazyHTML.attribute("data-feat-entries") |> hd() |> Jason.decode!()

      assert evasion["notes"] == ["заметка шарда"]
      refute Map.has_key?(evasion, "vanillaLabel")
      assert imbue["notes"] == ["10д6 (Максимум 35д6)"]
      assert imbue["vanillaLabel"] == @vanilla_numbers

      # Общая подпись триггера — прежняя: её берут фиты без текста шарда.
      assert LazyHTML.attribute(node, "data-label-vanilla") == ["Ванильное описание (Fandom)"]
    end
  end

  # Задача 4.70: текст шарда есть и там, где парсер разницы чисел не увидел
  # (`numbers_differ: false` — Wholeness of body, Weapon finesse …). Строки
  # блока те же, а подпись над Fandom про числа молчит: совпавшие числа —
  # не повод называть числа Fandom «ванильными» в смысле «другими».
  describe "текст шарда без разницы чисел (задача 4.70)" do
    @no_numbers "Ванильное описание (Fandom) — на Сиале верен текст шарда выше"

    test "одиночный кружок: строки шарда первыми, подпись — без слова «числа»" do
      node = single_with(["исцеление + Heal", "Продолжительность: 1 час."], [], false)

      assert notes(node) == ["исцеление + Heal", "Продолжительность: 1 час."]
      assert LazyHTML.attribute(node, "data-label-vanilla") == [@no_numbers]
    end

    test "флаг без текста шарда подписи не меняет" do
      node = single_with([], ["заметка шарда"], true)
      assert LazyHTML.attribute(node, "data-label-vanilla") == ["Ванильное описание (Fandom)"]
    end

    test "стопка: подпись записи по её флагу" do
      entry = fn name, numbers_differ? ->
        %{
          name: name,
          description: "Fandom's prose",
          siala_changed?: true,
          siala_notes: [],
          siala_notes_more_text: nil,
          siala_specifics: ["текст шарда"],
          siala_numbers_differ?: numbers_differ?,
          source_url: nil,
          source_link_text: nil
        }
      end

      node =
        render_component(&BuilderComponents.feats_info/1,
          id: "fs",
          label: "Level 7",
          entries: [entry.("Wholeness of body", false), entry.("Imbue arrow", true)]
        )
        |> trigger("fs")

      [wholeness, imbue] =
        node |> LazyHTML.attribute("data-feat-entries") |> hd() |> Jason.decode!()

      assert wholeness["vanillaLabel"] == @no_numbers
      assert imbue["vanillaLabel"] == @vanilla_numbers
    end
  end
end
