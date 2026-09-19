defmodule BuildCalculatorWeb.GameLogImportUiTest do
  @moduledoc """
  The game-log import button and dialog are visible by default — задача
  3.111, заход 2, запрос Dan 26.08.2026.

  ⚠️ **Другой сценарий, чем `ImportUiTest`, не его продолжение.** Тот флаг
  (`Layouts.import_ui?/0`) прячет вставку ЧУЖОГО билда в каноническом
  текстовом формате (задача 3.89 — «импортировать билды к нам никто не
  будет»); этот показывает вставку СВОЕГО персонажа из клиентского лога,
  которую Dan сам попросил. Оба флага независимы: этот тест держит
  `import_ui?` в его собственном умолчании (`false`) и проверяет, что
  соседняя кнопка от этого не зависит.

  Три вида проверок, как у `ImportUiTest`/`LaunchUiTest`:

    1. **кнопка и диалог есть** по умолчанию — иначе Dan не получит фичу,
       которую попросил;
    2. **старый текстовый импорт рядом не задет** — разные флаги, разное
       умолчание;
    3. **флаг может выключить эту кнопку отдельно**, и это положительный
       контроль на сам механизм скрытия — раз уж он заведён (симметрично
       двум соседним флагам, на случай если реальные логи игроков вскроют
       проблему и понадобится откат без деплоя).

  ⚠️ `async: false` — тест меняет глобальный `Application.put_env/3`.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculator.LibraryFixtures

  alias BuildCalculatorWeb.Layouts

  setup do
    refute Layouts.import_ui?()
    assert Layouts.game_log_import_ui?()
    :ok
  end

  describe "по умолчанию" do
    test "кнопка и диалог есть в конструкторе", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      assert has_element?(view, "#game-log-import-button")
      assert has_element?(view, "#game-log-import-dialog[hidden]")
    end

    test "старый текстовый импорт рядом остаётся спрятанным", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      assert has_element?(view, "#game-log-import-button")
      refute has_element?(view, "#import-button")
      refute has_element?(view, "#import-dialog")
    end

    test "экспорт рядом жив", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code(levels: [:fighter])}")

      assert has_element?(view, "#export-button")
    end

    test "экран просмотра не несёт кнопки вставки лога", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/#{build_code()}")

      refute has_element?(view, "#game-log-import-button")
      refute has_element?(view, "#game-log-import-dialog")
      assert has_element?(view, "#build-view")
    end
  end

  describe "флаг может выключить эту кнопку отдельно" do
    setup do
      Application.put_env(:build_calculator, :game_log_import_ui, false)
      on_exit(fn -> Application.put_env(:build_calculator, :game_log_import_ui, true) end)
      :ok
    end

    test "кнопки и диалога нет, когда флаг выключен", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      refute has_element?(view, "#game-log-import-button")
      refute has_element?(view, "#game-log-import-dialog")
      # Соседняя кнопка не пострадала.
      assert has_element?(view, "#export-button")
    end
  end
end
