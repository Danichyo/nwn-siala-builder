defmodule BuildCalculatorWeb.ImportUiTest do
  @moduledoc """
  Импорт спрятан из интерфейса — задача 3.89, решение Dan 24.08.2026: «спрятать
  импорт, импортировать билды к нам никто не будет, а вот экспорт может
  пригодиться — сбилдил и сохранил в текстовом виде на всякий случай».

  ⚠️ **Спрятан ИНТЕРФЕЙС, а не код** — тот же приём, что у `LaunchUiTest`
  (`Layouts.accounts_ui?/0`). `BuildCalculatorWeb.Builder.Import` остаётся
  рабочим модулем: на нём стоит план проверки ванильных чисел через эталонные
  билды NWN-комьюнити (`docs/VANILLA_SPLIT.md` §4, §7.4). Его собственные тесты
  (`builder/import_test.exs`, `rules/illegal_levels_test.exs`) флага не касаются.

  Три вида проверок, как у `LaunchUiTest`:

  1. **кнопки и диалога нет** ни на одной странице, которая могла бы быть
     второй точкой входа — иначе однажды импорт вернётся молча вместе с чьей-то
     правкой шаблона;
  2. **экспорт рядом не задет** — его владелец просил сохранить целиком;
  3. **положительный контроль**: флаг включается, и кнопка с диалогом не просто
     появляются в DOM, а реально разбирают вставленный текст. Без этого «нет
     в DOM» ничего не доказывает — `refute` был бы зелёным и при опечатке в id.

  ⚠️ `async: false` — тест меняет глобальный `Application.put_env/3`, и
  параллельный сосед увидел бы чужую шапку (тот же довод, что у `LaunchUiTest`).
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculator.LibraryFixtures

  alias BuildCalculatorWeb.Layouts

  setup do
    # Сторож: если кто-то вернёт кнопку, поменяв флаг, а не разметку, тесты
    # ниже покраснеют осмысленно, а не «не нашли элемент».
    refute Layouts.import_ui?()
    :ok
  end

  describe "по умолчанию" do
    test "ни кнопки, ни диалога в конструкторе нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      refute has_element?(view, "#import-button")
      refute has_element?(view, "#import-dialog")
    end

    test "а экспорт рядом жив и работает", %{conn: conn} do
      # Положительный контроль к проверке выше: скрытие точечное, соседняя
      # кнопка не пострадала — ровно то, что владелец просил сохранить.
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code(levels: [:fighter])}")

      assert has_element?(view, "#build-io")
      assert has_element?(view, "#export-button")

      view |> element("#export-button") |> render_click()

      refute has_element?(view, "#export-dialog[hidden]")
      assert render(element(view, "#export-text")) =~ "Fighter"
    end

    test "экран просмотра не несёт второго входа в импорт", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/#{build_code()}")

      refute has_element?(view, "#import-button")
      refute has_element?(view, "#import-dialog")
      assert has_element?(view, "#build-view")
    end

    test "публичная библиотека тоже не несёт входа в импорт", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")

      refute has_element?(view, "#import-button")
      refute has_element?(view, "#import-dialog")
    end
  end

  describe "флаг возвращает импорт — положительный контроль скрытия" do
    setup do
      Application.put_env(:build_calculator, :import_ui, true)
      on_exit(fn -> Application.put_env(:build_calculator, :import_ui, false) end)
      :ok
    end

    test "кнопка и диалог снова в разметке, диалог открывается и закрывается", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#import-button")
      assert has_element?(view, "#import-dialog[hidden]")

      view |> element("#import-button") |> render_click()
      refute has_element?(view, "#import-dialog[hidden]")

      view |> element("#import-close") |> render_click()
      assert has_element?(view, "#import-dialog[hidden]")
    end

    test "и действительно разбирает вставленный текст, а не просто рисуется", %{conn: conn} do
      # Не «функция вернула true» — LiveView-тест на живой парсинг, чтобы
      # положительный контроль проверял работающую функциональность.
      pasted = """
      Каменный - Fighter(2)
      Гном (Dwarf), Lawful Good
      STR: 16 (16)
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      """

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()

      view
      |> form("#import-form", %{"import" => %{"text" => pasted}})
      |> render_submit()

      assert has_element?(view, "#import-report")
      assert render(element(view, "#import-read-levels")) =~ "2"

      view |> element("#import-apply") |> render_click()

      assert render(element(view, "#character-level")) =~ "2"
    end
  end
end
