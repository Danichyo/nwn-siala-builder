defmodule BuildCalculatorWeb.AnalyticsSwitchTest do
  @moduledoc """
  Выключатель счётчика без пересборки — `ANALYTICS=off` в окружении
  (задача 4.75, `config/runtime.exs`).

  Конфиг читается тем же `Config.Reader`, что и релиз при запуске, — с
  переменной и без, в `:dev` и в `:prod` (подставные `DATABASE_URL`
  и `SECRET_KEY_BASE`). Затем значение, которое прочитал релиз, кладётся
  в приложение, и сайт проверяется так же, как в `analytics_flag_test.exs`:
  при выключенном — ни строки в таблицах, ни метки, ни маяка; положительный
  контроль — без переменной всё это есть.

  ⚠️ `async: false` — тест меняет переменные окружения ОС (`System.put_env/2`)
  и флаг приложения `:analytics` (`Application.put_env/3`): параллельный
  сосед прочитал бы чужое окружение и писал бы (или не писал) аналитику
  по чужому флагу.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import BuildCalculatorWeb.EditionHelpers
  import Phoenix.LiveViewTest

  alias BuildCalculator.Analytics.{Event, Visit}
  alias BuildCalculator.Repo

  @dan_code "../fixtures/dan_build_2026-09-13.code"
            |> Path.expand(__DIR__)
            |> File.read!()
            |> String.trim()

  @vars ~w(ANALYTICS EDITION DATABASE_URL SECRET_KEY_BASE PHX_SERVER)

  setup do
    previous = for var <- @vars, do: {var, System.get_env(var)}

    on_exit(fn ->
      for {var, value} <- previous do
        if value, do: System.put_env(var, value), else: System.delete_env(var)
      end
    end)

    Enum.each(@vars, &System.delete_env/1)
    System.put_env("DATABASE_URL", "ecto://u:p@localhost/db")
    System.put_env("SECRET_KEY_BASE", String.duplicate("k", 64))
    use_edition(:siala)
  end

  # Что прочитает релиз: `:missing` — ключа нет, работает пресет редакции.
  defp runtime_analytics(value, env) do
    if value, do: System.put_env("ANALYTICS", value), else: System.delete_env("ANALYTICS")

    "config/runtime.exs"
    |> Config.Reader.read!(env: env)
    |> Keyword.get(:build_calculator, [])
    |> Keyword.get(:analytics, :missing)
  end

  describe "config/runtime.exs" do
    test "off выключает, пусто и без переменной — пресет редакции" do
      for env <- [:dev, :prod] do
        assert runtime_analytics("off", env) == false
        assert runtime_analytics(nil, env) == :missing
        assert runtime_analytics("", env) == :missing
      end
    end

    test "переменная только выключает: другое значение роняет запуск словами" do
      for value <- ["on", "true", "OFF", "0", "of"] do
        assert_raise RuntimeError, ~r/ANALYTICS=#{inspect(value)} is not understood/, fn ->
          runtime_analytics(value, :prod)
        end
      end
    end

    test "под mix test переменная не читается" do
      assert runtime_analytics("off", :test) == :missing
    end

    test "с ванильной редакцией выключает так же" do
      System.put_env("EDITION", "vanilla")
      assert runtime_analytics("off", :prod) == false
    end
  end

  describe "сайт с тем, что прочитал релиз" do
    # Как релиз: прочитанное `runtime.exs` значение — в окружение приложения.
    defp boot_with(value) do
      case runtime_analytics(value, :prod) do
        :missing -> Application.delete_env(:build_calculator, :analytics)
        flag -> Application.put_env(:build_calculator, :analytics, flag)
      end
    end

    defp visit_everything(conn) do
      html = conn |> get("/") |> html_response(200)
      {:ok, builder, _html} = live(conn, "/?b=#{@dan_code}")
      {:ok, view, _html} = live(conn, "/b/#{@dan_code}")
      render_hook(builder, "analytics_export_downloaded", %{})
      %{html: html, builder: builder, view: view}
    end

    test "ANALYTICS=off — ни строки, ни метки, ни маяка", %{conn: conn} do
      boot_with("off")
      %{html: html, builder: builder, view: view} = visit_everything(conn)

      assert Repo.all(Visit) == []
      assert Repo.all(Event) == []
      refute html =~ ~s(name="analytics")
      refute has_element?(builder, "#export-download-analytics")
      refute has_element?(view, "#view-download-analytics")
    end

    test "положительный контроль: без переменной — пресет, всё на месте", %{conn: conn} do
      boot_with(nil)
      %{html: html, builder: builder, view: view} = visit_everything(conn)

      assert length(Repo.all(Visit)) == 2
      assert [_ | _] = Repo.all(Event)
      assert html =~ ~s(<meta name="analytics" content="cookieless">)
      assert has_element?(builder, "#export-download-analytics")
      assert has_element?(view, "#view-download-analytics")
    end
  end
end
