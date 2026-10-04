defmodule BuildCalculatorWeb.AnalyticsLiveTest do
  @moduledoc """
  Счётчик посещений и событий на живых экранах (задача 4.54): когда пишется
  посещение, что в нём лежит и когда пишется каждое событие калькулятора.

  Флаг — по умолчанию Сиалы (включён), поэтому файл асинхронный: он ничего
  не переключает. Выключенный флаг и отказы (базы, соли) —
  `analytics_flag_test.exs`, сторож утечки билдов по всем маршрутам —
  `analytics_leak_test.exs` (оба синхронные).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Analytics.{Event, Visit}
  alias BuildCalculator.Encoding
  alias BuildCalculator.Repo
  alias BuildCalculator.Rules.Build

  # Настоящий билд Dan: Сиала, 40 уровней, Fighter / Dwarven Defender / Weapon
  # Master — длинный код с эпиком.
  @dan_code "../../fixtures/dan_build_2026-09-13.code"
            |> Path.expand(__DIR__)
            |> File.read!()
            |> String.trim()

  defp visits, do: Repo.all(Visit) |> Enum.sort_by(& &1.id)
  defp events, do: Repo.all(Event) |> Enum.sort_by(& &1.id) |> Enum.map(& &1.name)

  defp truncated_code(levels) do
    {:ok, %{build: build}} = Encoding.decode(@dan_code)
    build |> Build.truncate(levels) |> Encoding.encode()
  end

  describe "посещение" do
    test "мёртвый рендер не пишет ничего — боты и превью ссылок не считаются", %{conn: conn} do
      for path <- ["/", "/b/#{@dan_code}", "/?b=#{@dan_code}", "/sources", "/library"] do
        assert conn |> get(path) |> html_response(200)
      end

      assert visits() == []
      assert events() == []
    end

    test "подключённое монтирование — одна строка: шаблон маршрута, а не путь", %{conn: conn} do
      {:ok, _view, _html} = live(conn, "/b/#{@dan_code}?utm_source=discord&fbclid=zzz&b=x")

      assert [visit] = visits()
      assert visit.page == "/b/:code"
      assert visit.edition == "siala"
      assert visit.utm_source == "discord"
      assert visit.utm_medium == nil
      assert visit.referrer_host == nil
      assert byte_size(visit.visitor) == 16
    end

    test "у каждого маршрута — свой шаблон", %{conn: conn} do
      for path <- ["/", "/?b=#{@dan_code}&l=3", "/sources", "/library", "/users/log-in"] do
        {:ok, _view, _html} = live(conn, path)
      end

      assert Enum.map(visits(), & &1.page) == ["/", "/", "/sources", "/library", "/users/log-in"]
    end

    test "источник — хост из параметров подключения, без пути; свой хост — не источник", %{
      conn: conn
    } do
      conn
      |> put_connect_params(%{"_analytics_ref" => "https://www.forum.example/t/5?b=#{@dan_code}"})
      |> live("/")

      # Хост страницы в тесте — `www.example.com` (`Plug.Test`), хост сайта —
      # `localhost` (`Endpoint.host/0`); `www.` срезается у обоих.
      conn
      |> put_connect_params(%{"_analytics_ref" => "example.com"})
      |> live("/")

      conn
      |> put_connect_params(%{"_analytics_ref" => "localhost"})
      |> live("/b/#{@dan_code}")

      assert Enum.map(visits(), & &1.referrer_host) == ["forum.example", nil, nil]
      # Со своего сайта — не «открыт по ссылке».
      assert events() == []
    end

    test "живая навигация — посещение без источника и без «открыт по ссылке»", %{conn: conn} do
      conn
      |> put_connect_params(%{
        "_live_referer" => "http://localhost/",
        "_analytics_ref" => "forum.example"
      })
      |> live("/b/#{@dan_code}")

      assert [%{page: "/b/:code", referrer_host: nil}] = visits()
      assert events() == []
    end

    test "перезагрузка и «Назад» — посещение, но не переход по ссылке", %{conn: conn} do
      for nav <- ["reload", "back_forward"] do
        conn |> put_connect_params(%{"_analytics_nav" => nav}) |> live("/?b=#{@dan_code}")
      end

      assert length(visits()) == 2
      assert events() == []

      # Положительный контроль: свежий переход тем же адресом — событие есть.
      conn |> put_connect_params(%{"_analytics_nav" => "navigate"}) |> live("/?b=#{@dan_code}")
      assert events() == ["link_opened"]
    end
  end

  describe "посетитель" do
    defp visitor_for(conn, peer, forwarded, agent) do
      conn
      |> Plug.Test.put_peer_data(%{address: peer, port: 50_000, ssl_cert: nil})
      |> put_req_header("x-forwarded-for", forwarded)
      |> put_req_header("user-agent", agent)
      |> live("/")

      List.last(visits()).visitor
    end

    test "за своим прокси — по X-Forwarded-For; публичный пир подделать заголовком нельзя", %{
      conn: conn
    } do
      proxy = {172, 18, 0, 1}
      public = {198, 51, 100, 9}

      a = visitor_for(conn, proxy, "203.0.113.7", "UA")
      b = visitor_for(conn, proxy, "203.0.113.8", "UA")
      c = visitor_for(conn, proxy, "203.0.113.7", "UA")
      d = visitor_for(conn, proxy, "203.0.113.7", "UA2")

      assert a != b
      assert a == c
      assert a != d

      # Публичный пир: заголовок написал сам клиент — уникальных не раздувает.
      e = visitor_for(conn, public, "1.1.1.1", "UA")
      f = visitor_for(conn, public, "2.2.2.2", "UA")
      assert e == f
    end
  end

  describe "события" do
    test "билд открыт по ссылке: просмотр, конструктор — по разу; битая ссылка — нет", %{
      conn: conn
    } do
      {:ok, _view, _html} = live(conn, "/b/#{@dan_code}")
      {:ok, _view, _html} = live(conn, "/?b=#{@dan_code}")
      {:ok, _view, _html} = live(conn, "/?b=2.not-a-real-code")
      {:ok, _view, _html} = live(conn, "/b/2.not-a-real-code")

      assert events() == ["link_opened", "link_opened"]
      assert Enum.all?(Repo.all(Event), &(&1.ruleset == "siala_41" and &1.edition == "siala"))
    end

    test "экспорт скачан — маяк рядом с кнопкой, на обоих экранах; не больше 20 за сессию", %{
      conn: conn
    } do
      {:ok, builder, _html} = live(conn, "/?b=#{@dan_code}")
      assert has_element?(builder, "#export-download-analytics[hidden]")

      builder
      |> element("#export-download-analytics")
      |> render_hook("analytics_export_downloaded")

      {:ok, view, _html} = live(conn, "/b/#{@dan_code}")

      for _ <- 1..25 do
        view |> element("#view-download-analytics") |> render_hook("analytics_export_downloaded")
      end

      downloads = Enum.count(events(), &(&1 == "export_downloaded"))
      assert downloads == 1 + 20
    end

    test "дошёл до последнего неэпического уровня — левелапом, один раз за сессию", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/?b=#{truncated_code(19)}")
      assert events() == ["link_opened"]

      view |> element("#class-card-fighter") |> render_click()
      assert events() == ["link_opened", "reached_last_pre_epic_level"]

      # Снять уровень и взять снова — порог уже пройден в этой сессии.
      view |> element("#drop-level") |> render_click()
      view |> element("#level-20") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      assert events() == ["link_opened", "reached_last_pre_epic_level"]
    end

    test "дошёл до капа — левелапом; ссылка на билд с капом сама по себе не «дошёл»", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/?b=#{@dan_code}")
      assert events() == ["link_opened"]

      view |> element("#class-card-fighter") |> render_click()
      assert events() == ["link_opened", "reached_level_cap"]
      assert [_, %{ruleset: "siala_41"}] = Repo.all(Event) |> Enum.sort_by(& &1.id)
    end

    test "лог .билд принят — событие с именем, без лога", %{conn: conn} do
      log = "../../fixtures/game_logs/hnyupius.log" |> Path.expand(__DIR__) |> File.read!()
      {:ok, view, _html} = live(conn, "/")

      view |> element("#game-log-import-button") |> render_click()

      view
      |> form("#game-log-import-form", %{"game_log_import" => %{"text" => log}})
      |> render_submit()

      assert events() == []
      view |> element("#game-log-import-apply") |> render_click()
      assert events() == ["game_log_imported"]
    end

    test "событие маяка не роняет экран без билда (просмотр битой ссылки)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/b/2.not-a-real-code")
      refute has_element?(view, "#view-download-analytics")

      # Событие, присланное руками, — гасится хуком, экран жив.
      assert render_hook(view, "analytics_export_downloaded", %{}) =~ "view-error"
      assert [%{name: "export_downloaded", ruleset: nil}] = Repo.all(Event)
    end
  end
end
