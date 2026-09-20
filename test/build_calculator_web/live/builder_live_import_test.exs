defmodule BuildCalculatorWeb.BuilderLiveImportTest do
  @moduledoc """
  Журнал диалога импорта конструктора — вынесен из `BuilderLiveTest` задачей
  3.194 (ускорение `mix test`), а не переписан: тот же текст, тот же порядок
  тестов, только отдельный файл.

  ⚠️ `async: false` — `setup` меняет глобальный `Application.put_env/3`
  (`:import_ui`), чтобы включить флагом спрятанный интерфейс на время блока
  (задача 3.89, решение Dan 24.08.2026: «спрятать импорт… а вот экспорт может
  пригодиться»). Параллельный сосед в общей VM увидел бы чужую шапку — тот же
  довод, что у `ImportUiTest` и `LaunchUiTest`. За тем, что кнопки и диалога
  нет по умолчанию, следит `ImportUiTest` — этот файл проверяет, что сам
  диалог, будучи включён, действительно разбирает вставленный текст.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "import" do
    # ⚠️ Спрятан флагом `Layouts.import_ui?()` под запуск (задача 3.89, решение
    # Dan 24.08.2026) — интерфейс, не код. Весь этот блок проверяет, что модуль
    # и диалог по-прежнему РАБОТАЮТ, поэтому флаг включён на время блока; за
    # тем, что кнопки и диалога нет по умолчанию, следит `ImportUiTest`.
    setup do
      Application.put_env(:build_calculator, :import_ui, true)
      on_exit(fn -> Application.put_env(:build_calculator, :import_ui, false) end)
      :ok
    end

    # Разбор показывается ДО применения: частично прочитанный билд лучше отказа,
    # но только если видно, что именно не прочиталось (CLAUDE.md §3).
    @pasted """
    Каменный - Fighter(2)
    Гном (Dwarf), Lawful Good
    STR: 16 (16)
    Hitpoints: 764
    LEVELING GUIDE
    01: Fighter(1): Power Attack, Неведомый Фит
    02: Fighter(2)
    """

    defp paste(view, text) do
      view
      |> form("#import-form", %{"import" => %{"text" => text}})
      |> render_submit()
    end

    test "the dialog is closed until it is asked for", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#import-dialog[hidden]")
      view |> element("#import-button") |> render_click()
      refute has_element?(view, "#import-dialog[hidden]")
    end

    test "nothing is applied until the report has been shown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()

      # Ничего не разобрано — применять нечего.
      assert has_element?(view, "#import-apply[disabled]")
      refute has_element?(view, "#import-report")

      paste(view, @pasted)

      assert has_element?(view, "#import-report")
      assert has_element?(view, "#import-summary")
      refute has_element?(view, "#import-apply[disabled]")
      # И билд всё ещё не тронут.
      assert render(element(view, "#character-level")) =~ "0"
    end

    test "the report names what was read and what was not", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)

      assert render(element(view, "#import-read-levels")) =~ "2"
      assert render(element(view, "#import-read-race")) =~ "Гном"
      assert has_element?(view, "#import-issues")
      assert render(element(view, "#import-issues")) =~ "Неведомый Фит"
    end

    test "the source's own numbers are shown beside ours, never imported", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)
      view |> element("#import-apply") |> render_click()

      # 764 HP пришли из чужого листа персонажа — у двух уровней воина их быть
      # не может, и калькулятор считает своё.
      assert render(element(view, "#import-compare")) =~ "764"
      refute render(element(view, "#stat-hp")) =~ "764"
    end

    test "accepting the report opens the build in the constructor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)
      view |> element("#import-apply") |> render_click()

      assert render(element(view, "#character-level")) =~ "2"
      assert has_element?(view, "#split-fighter")
      assert has_element?(view, "#import-dialog[hidden]")

      # ⚠️ Здесь стояла проверка `#save-build[href*='name=']` — «ссылка на
      # сохранение уносит имя из текста». Кнопка спрятана задачей 3.23, а имя
      # больше нигде на экране не появляется, поэтому проверка переехала в
      # `launch_ui_test.exs` (там флаг включается на время теста), а не исчезла.
      # Здесь остаётся то, что видно и без аккаунтов: билд действительно принят.
      refute has_element?(view, "#save-build")
    end

    test "editing the paste drops a report that no longer describes it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)
      assert has_element?(view, "#import-report")

      view
      |> form("#import-form", %{"import" => %{"text" => @pasted <> "\n11: Fighter(5)"}})
      |> render_change()

      refute has_element?(view, "#import-report")
    end

    test "a paste with nothing in it cannot be applied", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, "здесь нет никакого билда")

      assert has_element?(view, "#import-apply[disabled]")
    end

    # 🔴 Задача 3.221, часть C — ЖИВОЙ ТУПИК, воспроизведённый до правки.
    #
    # Импорт заменяет билд целиком и приземляет игрока на `taken + 1`. Панель
    # второго шага выбора фита сама закрывается только тогда, когда её уровень
    # разошёлся с активным (`assign_choice_panel/1` сверяет `level: ^active`),
    # а здесь он СОВПАДАЕТ: выбор открыт на 3-м уровне, `Fighter(2)` приземляет
    # ровно на 3-й. До правки на экране оставалась панель мёртвого выбора
    # («Шаг 2 · Spell focus», все восемь школ «недоступно: на уровне Fighter
    # этот фит не выбрать»), и вместе с ней ПРОПАДАЛ список фитов — уровень
    # нечем было заполнить, пока игрок не догадается нажать «отмена».
    test "применённый импорт закрывает второй шаг выбора фита", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()

      for level <- 1..3 do
        view |> element("#level-#{level}") |> render_click()
        view |> element("#class-card-wizard") |> render_click()
      end

      view |> element("#feat-ok-spell_focus") |> render_click()
      assert has_element?(view, "#feat-choice")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)
      view |> element("#import-apply") |> render_click()

      # Импорт приземлился ровно на тот уровень, где висел выбор...
      assert render(element(view, "#character-level")) =~ "2"
      assert has_element?(view, "#split-fighter")

      # ...и панели там больше нет, а список фитов вернулся на своё место.
      refute has_element?(view, "#feat-choice")
      assert has_element?(view, "#feat-lists")
    end
  end
end
