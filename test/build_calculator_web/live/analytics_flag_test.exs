defmodule BuildCalculatorWeb.AnalyticsFlagTest do
  @moduledoc """
  Флаг счётчика выключен (задача 4.54): в таблицы не пишется ничего, а в браузер
  не уходит ничего лишнего — отрисовка та же, что с флагом, за вычетом ровно
  трёх вещей, которые флаг и включает: `<meta name="analytics">` в корневом
  макете, маяк у каждой кнопки «скачать .txt» и строка о счётчике на `/sources`.

  Положительный контроль — те же страницы с включённым флагом: метка, маяки
  и строка есть, строки в таблицах пишутся.

  Здесь же отказы счётчика внутри приложения: базы аналитики нет (`DROP TABLE`
  в песочнице), процесс соли остановлен — экран обязан жить.

  ⚠️ `async: false` — флаг меняется `Application.put_env/3` на всё приложение,
  параллельный сосед писал бы (или не писал) аналитику по чужому флагу
  (CLAUDE.md §7); `DROP TABLE` держит блокировку таблицы до конца теста,
  а остановка соли — общий процесс приложения. Редакция — Сиалы, через
  `use_edition/1`: он же возвращает флаги как были.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import BuildCalculatorWeb.EditionHelpers
  import Phoenix.LiveViewTest

  alias BuildCalculator.Analytics.{Event, Visit}
  alias BuildCalculator.Encoding
  alias BuildCalculator.Repo
  alias BuildCalculator.Rules.Build

  @dan_code "../../fixtures/dan_build_2026-09-13.code"
            |> Path.expand(__DIR__)
            |> File.read!()
            |> String.trim()

  setup do
    use_edition(:siala)
    :ok
  end

  defp flag(value), do: Application.put_env(:build_calculator, :analytics, value)

  defp pages, do: ["/", "/?b=#{@dan_code}", "/b/#{@dan_code}", "/sources", "/library"]

  defp code_before_cap do
    {:ok, %{build: build}} = Encoding.decode(@dan_code)
    build |> Build.truncate(40) |> Encoding.encode()
  end

  # Всё, что делает игрок: страницы, левелап до капа, лог, маяк скачивания.
  defp play(conn) do
    for path <- pages(), do: {:ok, _view, _html} = live(conn, path)

    {:ok, view, _html} = live(conn, "/?b=#{code_before_cap()}")
    view |> element("#class-card-fighter") |> render_click()

    # Маяка при выключенном флаге нет — событие приходит «руками».
    render_hook(view, "analytics_export_downloaded", %{})

    log = "../../fixtures/game_logs/hnyupius.log" |> Path.expand(__DIR__) |> File.read!()
    {:ok, importer, _html} = live(conn, "/")
    importer |> element("#game-log-import-button") |> render_click()

    importer
    |> form("#game-log-import-form", %{"game_log_import" => %{"text" => log}})
    |> render_submit()

    importer |> element("#game-log-import-apply") |> render_click()
  end

  describe "флаг выключен" do
    setup do
      flag(false)
      :ok
    end

    test "в таблицы не пишется ничего — ни посещений, ни событий", %{conn: conn} do
      play(conn)

      assert Repo.all(Visit) == []
      assert Repo.all(Event) == []
    end

    test "в разметке нет ни метки, ни маяков, ни строки о счётчике", %{conn: conn} do
      refute conn |> get("/") |> html_response(200) =~ ~s(name="analytics")

      {:ok, builder, _html} = live(conn, "/?b=#{@dan_code}")
      refute has_element?(builder, "#export-download-analytics")
      assert has_element?(builder, "#export-download")

      {:ok, view, _html} = live(conn, "/b/#{@dan_code}")
      refute has_element?(view, "#view-download-analytics")
      assert has_element?(view, "#view-download")

      {:ok, sources, _html} = live(conn, "/sources")
      refute has_element?(sources, "#sources-analytics")
      assert has_element?(sources, "#sources-disclaimer")
    end
  end

  describe "положительный контроль — флаг включён" do
    setup do
      flag(true)
      :ok
    end

    test "строки пишутся", %{conn: conn} do
      play(conn)

      assert length(Repo.all(Visit)) == length(pages()) + 2
      names = Repo.all(Event) |> Enum.map(& &1.name) |> Enum.sort()

      assert names ==
               Enum.sort(~w(link_opened link_opened link_opened reached_level_cap
                           export_downloaded game_log_imported))
    end

    test "метка, маяки и строка о счётчике есть", %{conn: conn} do
      assert conn |> get("/") |> html_response(200) =~
               ~s(<meta name="analytics" content="cookieless">)

      {:ok, builder, _html} = live(conn, "/?b=#{@dan_code}")
      assert has_element?(builder, "#export-download-analytics[hidden]")

      {:ok, view, _html} = live(conn, "/b/#{@dan_code}")
      assert has_element?(view, "#view-download-analytics[hidden]")

      {:ok, sources, _html} = live(conn, "/sources")
      assert render(element(sources, "#sources-analytics")) =~ "без cookie"
      assert render(element(sources, "#sources-analytics-heading")) =~ "Счётчик посещений"
    end
  end

  describe "отказ счётчика внутри приложения" do
    setup do
      flag(true)
      :ok
    end

    # `DROP TABLE` в песочнице держит блокировку таблицы до конца теста —
    # поэтому здесь, в синхронном файле, а не рядом с асинхронными соседями.
    test "базы аналитики нет — конструктор открывается и работает, отказ — строка в логе", %{
      conn: conn
    } do
      Repo.query!(
        "DROP VIEW analytics.daily_totals, analytics.daily_pages, analytics.daily_sources"
      )

      Repo.query!("DROP TABLE analytics.visits")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, view, _html} = live(conn, "/?b=#{code_before_cap()}")
          view |> element("#class-card-fighter") |> render_click()
          assert render(element(view, "#character-level")) =~ "41"
        end)

      assert log =~ "analytics: write dropped"
      # События пишутся в свою таблицу, она жива.
      assert Repo.all(Event) |> Enum.map(& &1.name) |> Enum.sort() ==
               ["link_opened", "reached_level_cap"]
    end

    test "соли нет (процесс остановлен) — экран открывается и работает, отказ в логе", %{
      conn: conn
    } do
      salt = BuildCalculator.Analytics.Salt
      :ok = Supervisor.terminate_child(BuildCalculator.Supervisor, salt)
      on_exit(fn -> Supervisor.restart_child(BuildCalculator.Supervisor, salt) end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, view, _html} = live(conn, "/?b=#{code_before_cap()}")
          view |> element("#class-card-fighter") |> render_click()
          assert render(element(view, "#character-level")) =~ "41"
        end)

      assert log =~ "analytics: skipped"
      assert Repo.all(Visit) == []
    end
  end

  describe "отрисовка с флагом и без" do
    test "разница — ровно метка, маяки и строка о счётчике; больше ничего", %{conn: conn} do
      for path <- pages() do
        flag(true)
        dead_on = conn |> get(path) |> html_response(200) |> normalize()
        {:ok, view, _html} = live(conn, path)
        live_on = view |> render() |> normalize()

        flag(false)
        dead_off = conn |> get(path) |> html_response(200) |> normalize()
        {:ok, view, _html} = live(conn, path)
        live_off = view |> render() |> normalize()

        # Положительный контроль: с флагом разметка действительно другая.
        assert dead_on != dead_off, "#{path}: флаг ничего не добавил в мёртвый рендер"

        assert strip_analytics(dead_on) == dead_off, "#{path}: мёртвый рендер"
        assert strip_analytics(live_on) == live_off, "#{path}: подключённый рендер"
      end
    end
  end

  # Случайное от запроса к запросу: токены LiveView и CSRF, id процесса.
  defp normalize(html) do
    html
    |> String.replace(~r/data-phx-session="[^"]*"/, ~s(data-phx-session=""))
    |> String.replace(~r/data-phx-static="[^"]*"/, ~s(data-phx-static=""))
    |> String.replace(~r/id="phx-[^"]*"/, ~s(id="phx-"))
    |> String.replace(~r/<meta name="csrf-token" content="[^"]*">/, ~s(<meta name="csrf-token">))
    |> String.replace(~r/name="_csrf_token" value="[^"]*"/, ~s(name="_csrf_token"))
    |> String.replace(~r/>\s+</, "><")
  end

  # Ровно то, что включает флаг, — и ничего сверх.
  defp strip_analytics(html) do
    html
    |> String.replace(~s(<meta name="analytics" content="cookieless">), "")
    |> String.replace(~r/<span[^>]* id="[a-z-]+-download-analytics"[^>]*><\/span>/, "")
    |> String.replace(~r/<h2[^>]* id="sources-analytics-heading"[^>]*>.*?<\/h2>/s, "")
    |> String.replace(~r/<p[^>]* id="sources-analytics"[^>]*>.*?<\/p>/s, "")
    |> String.replace(~r/>\s+</, "><")
  end
end
