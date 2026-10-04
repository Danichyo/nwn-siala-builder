defmodule BuildCalculatorWeb.BuilderDroppedLinkTest do
  @moduledoc """
  Задача 4.35: флеш «Из ссылки выпало: …» называет потерю словами — у четырёх
  видов (`unknown_weapon`, `unknown_named_items`, `unknown_saves_specific`,
  `unknown_resistances`) он печатал сырой кортеж: «Из ссылки выпало:
  {:unknown_weapon, "scimitor"}».

  Откуда такая ссылка (проверено в 4.35): наш кодер для сегодняшних данных
  этих потерь не пишет — id оружия не менялись с появления справочника, стихии
  резистов тоже, а три числа пишутся числами, которые декодер читает. Их
  приносит ссылка, поправленная руками, или собранная на данных, из которых
  id потом ушёл, — от этого декодер и защищён. Поэтому ссылка здесь портится
  тем же приёмом, что в `encoding_test.exs`: подменой строки той же длины
  внутри payload'а.

  Редакция — умолчательная (Сиала), флеш по-русски; английские подписи —
  `labels_test.exs`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding}
  alias BuildCalculator.Rules.{Build, Gear}

  defp build(gear) do
    Build.new(
      ruleset_version: Data.default_version(),
      race: :human,
      alignment: :lawful_good,
      levels: List.duplicate(:fighter, 4),
      base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
      ability_increases: %{4 => :str},
      gear: Gear.new(gear)
    )
  end

  # Подмена строки внутри payload'а, длина та же — иначе поедет length-prefix
  # строки (тот же приём, что `tamper/3` в `encoding_test.exs`).
  defp tamper("2." <> body, from, to) do
    payload = body |> Base.url_decode64!(padding: false) |> :zlib.unzip()
    assert payload =~ from
    "2." <> Base.url_encode64(:zlib.zip(String.replace(payload, from, to)), padding: false)
  end

  defp code(gear, from, to), do: gear |> build() |> Encoding.encode() |> tamper(from, to)

  @cases [
    {"оружие", [weapon: :scimitar, weapon_attack: 5], "weapon|scimitar", "weapon|scimitor",
     "оружие scimitor"},
    {"оружие второй руки", [weapon: :scimitar, off_hand_weapon: :mace], "offweapon|mace",
     "offweapon|macx", "оружие macx"},
    {"крафтовые вещи", [named_items: 3], "nameditems|3", "nameditems|x",
     "крафтовые вещи nameditems|x"},
    {"раздельные спасы", [saves_specific: %{fort: 2, ref: 3, will: 4}], "savespec|2,3,4",
     "savespec|2,3,x", "спасы Fort / Ref / Will с экипировки savespec|2,3,x"},
    {"поглощение стихии", [resistances: %{fire: 15}], "resist|fire|15", "resist|fyre|15",
     "поглощение стихии resist|fyre|15"}
  ]

  for {name, gear, from, to, label} <- @cases do
    test "конструктор: #{name} — словами, а не кортежем", %{conn: conn} do
      code = code(unquote(Macro.escape(gear)), unquote(from), unquote(to))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      flash = view |> element("#flash-info") |> render()
      assert flash =~ "Из ссылки выпало: " <> unquote(label)
      refute flash =~ "{:unknown"

      # Билд открылся — без выпавшего, остальное на месте.
      assert has_element?(view, "#split-fighter")
    end
  end

  test "экран просмотра: все четыре вида — словами", %{conn: conn} do
    code =
      [
        weapon: :scimitar,
        named_items: 3,
        saves_specific: %{fort: 2, ref: 3, will: 4},
        resistances: %{fire: 15}
      ]
      |> build()
      |> Encoding.encode()
      |> tamper("weapon|scimitar", "weapon|scimitor")
      |> tamper("nameditems|3", "nameditems|x")
      |> tamper("savespec|2,3,4", "savespec|2,3,x")
      |> tamper("resist|fire|15", "resist|fyre|15")

    assert {:ok, %{dropped: dropped}} = Encoding.decode(code)
    assert length(dropped) == 4

    {:ok, view, _html} = live(conn, ~p"/b/#{code}")
    flash = view |> element("#flash-info") |> render()

    for label <- [
          "оружие scimitor",
          "крафтовые вещи nameditems|x",
          "спасы Fort / Ref / Will с экипировки savespec|2,3,x",
          "поглощение стихии resist|fyre|15"
        ],
        do: assert(flash =~ label)

    assert flash =~ "Из ссылки выпало: "
    refute flash =~ "{:unknown"
  end
end
