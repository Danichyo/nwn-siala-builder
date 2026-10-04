defmodule BuildCalculatorWeb.ModalFocusTest do
  @moduledoc """
  Задача 4.40, пункт 8: затемнение каждого модального окна веб-слоя рисует
  `BuilderComponents.modal_scrim/1` — с хуком `.ModalFocus`, который уводит
  фокус в окно, держит Tab внутри и возвращает фокус на кнопку-открывашку.

  `Phoenix.LiveViewTest` хуков не исполняет (CLAUDE.md §7), поведение хука
  держит `assets/test/modal_focus.test.mjs`, а живой Chrome — замер задачи.
  Здесь — половина контракта на стороне сервера: у окна есть хук, `data-opener`
  называет кнопку, которая в разметке действительно есть, и `hidden` по-прежнему
  открывает и закрывает окно сервер. Окно импорта текста (ваниль, флаг
  `import_ui`) — в `builder_live_import_test.exs`, где флаг уже включён.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.{Data, Encoding}
  alias BuildCalculator.Rules.Build

  @hook "BuildCalculatorWeb.BuilderComponents.ModalFocus"

  defp code do
    ruleset = Data.ruleset!(Data.default_version())

    Build.new(
      ruleset_version: ruleset.version,
      race: :human,
      alignment: :lawful_neutral,
      base_abilities: %{str: 16, dex: 13, con: 14, int: 10, wis: 10, cha: 10},
      levels: [:fighter, :fighter]
    )
    |> Encoding.encode()
  end

  defp assert_scrim(view, id, opener) do
    assert has_element?(view, "##{id}.scrim[phx-hook='#{@hook}'][data-opener='#{opener}']")
    assert has_element?(view, opener)
    assert has_element?(view, "##{id} [role='dialog']")
  end

  test "экспорт конструктора: хук, открывашка, сервер открывает и закрывает", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?b=#{code()}")

    assert_scrim(view, "export-dialog", "#export-button")
    assert has_element?(view, "#export-dialog[hidden]")

    view |> element("#export-button") |> render_click()
    refute has_element?(view, "#export-dialog[hidden]")

    view |> element("#export-close") |> render_click()
    assert has_element?(view, "#export-dialog[hidden]")
  end

  test "окно лога: хук и открывашка", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert_scrim(view, "game-log-import-dialog", "#game-log-import-button")
    assert has_element?(view, "#game-log-import-dialog[hidden]")

    view |> element("#game-log-import-button") |> render_click()
    refute has_element?(view, "#game-log-import-dialog[hidden]")
  end

  test "текст билда на экране просмотра: хук и открывашка", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/b/#{code()}")

    assert_scrim(view, "text-dialog", "#show-text")
    assert has_element?(view, "#text-dialog[hidden]")

    view |> element("#show-text") |> render_click()
    refute has_element?(view, "#text-dialog[hidden]")

    view |> element("#text-close") |> render_click()
    assert has_element?(view, "#text-dialog[hidden]")
  end
end
