defmodule BuildCalculatorWeb.UnhandledEventTest do
  @moduledoc """
  Последняя клауза `handle_event/3` каждого экрана (задача 4.76,
  `BuildCalculatorWeb.UnhandledEvent`): событие, которого не берёт ни одна
  клауза, отбрасывается — процесс жив, отчёта о падении нет, в лог — одна
  строка `warning` без значений клиента, не чаще раза в минуту на экран.

  ⚠️ `async: false` — строки идут в общий лог (`capture_log/1` видит и чужие
  процессы), а потолок частоты — общий счётчик узла (`BuildCalculator.RateLimit`),
  который тест сбрасывает.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias BuildCalculatorWeb.UnhandledEvent

  @code "../fixtures/dan_build_2026-09-13.code"
        |> Path.expand(__DIR__)
        |> File.read!()
        |> String.trim()

  # Строки этого модуля в счётчике частоты — снять, чтобы первая строка
  # минуты была нашей (её могли съесть другие тесты в ту же минуту).
  defp reset_rate do
    :ets.match_delete(BuildCalculator.RateLimit, {{UnhandledEvent, :_, :_}, :_, :_})
    :ok
  end

  defp crashes?(view) do
    Process.flag(:trap_exit, true)
    ref = Process.monitor(view.pid)

    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> true
    after
      100 -> false
    end
  end

  describe "экраны веб-слоя" do
    setup do
      reset_rate()
    end

    test "конструктор: неизвестное имя и известное с чужой нагрузкой — экран жив, отчёта нет",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?b=#{@code}")

      log =
        capture_log([level: :warning], fn ->
          render_hook(view, "no_such_event", %{"b" => @code})
          # Чужая нагрузка у своего имени: `pick_race` без `race`.
          render_hook(view, "pick_race", %{"b" => @code})
          render_hook(view, @code, %{})
        end)

      refute crashes?(view)

      # Экран отвечает на законное событие после трёх отброшенных.
      view |> element("#level-3") |> render_click()
      assert has_element?(view, ~s(#level-3[aria-current="true"]))

      # Одна строка на минуту: три события — одна строка, первая.
      assert [line] =
               String.split(log, "\n", trim: true) |> Enum.filter(&(&1 =~ "handle_event/3"))

      assert line =~ "BuildCalculatorWeb.BuilderLive: an event no clause of handle_event/3 takes"
      refute log =~ "terminating"
      refute log =~ String.slice(@code, 2, 16)
      refute log =~ "no_such_event"
    end

    test "у своего имени строка называет имя — оно наше, а не клиента", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/b/#{@code}")

      log =
        capture_log([level: :warning], fn ->
          render_hook(view, "toggle_view_filter", %{"b" => @code})
        end)

      refute crashes?(view)

      assert log =~
               ~s(BuildCalculatorWeb.BuildViewLive: event "toggle_view_filter" came with a payload)

      refute log =~ String.slice(@code, 2, 16)
    end

    test "экран без своих клауз (источники) тоже не падает", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sources")
      assert BuildCalculatorWeb.SourcesLive.__handled_events__() == []

      capture_log(fn -> render_hook(view, "anything", %{}) end)
      refute crashes?(view)
    end

    test "потолок частоты — свой у каждого экрана", %{conn: conn} do
      {:ok, builder, _html} = live(conn, "/")
      {:ok, library, _html} = live(conn, "/library")

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..5, do: render_hook(builder, "x", %{})
          for _ <- 1..5, do: render_hook(library, "x", %{})
        end)

      lines = log |> String.split("\n", trim: true) |> Enum.filter(&(&1 =~ "handle_event/3"))
      assert length(lines) == 2
      assert Enum.any?(lines, &(&1 =~ "BuilderLive"))
      assert Enum.any?(lines, &(&1 =~ "LibraryLive"))
    end
  end

  describe "клаузы экрана" do
    test "имена из охранника `in` читаются так же, как литералы" do
      handled = BuildCalculatorWeb.BuilderLive.__handled_events__()

      # литерал
      assert "pick_feat" in handled
      # из `when event in @text_import_events`
      assert "import_parse" in handled
      # из `when event in @game_log_import_events`
      assert "game_log_import_apply" in handled
      # последняя клауза сама в список не входит
      assert Enum.all?(handled, &is_binary/1)
    end

    test "клауза, берущая любое имя, не компилируется: последняя клауза — общая" do
      source = """
      defmodule #{inspect(Module.concat(__MODULE__, "AnyLive"))} do
        use BuildCalculatorWeb, :live_view

        @impl true
        def render(assigns), do: ~H"<div></div>"

        @impl true
        def handle_event(event, _params, socket) when is_binary(event), do: {:noreply, socket}
      end
      """

      assert_raise ArgumentError, ~r/takes any event name/, fn ->
        Code.compile_string(source, "any_live.ex")
      end
    end

    test "без значений клиента: строка не берёт имя, которого у экрана нет" do
      line = UnhandledEvent.line(BuildCalculatorWeb.BuilderLive, @code)
      refute line =~ @code
      assert line =~ "an event no clause"

      line = UnhandledEvent.line(BuildCalculatorWeb.BuilderLive, %{"b" => @code})
      refute line =~ "%{"
      refute line =~ @code

      # Положительный контроль: своё имя — называется.
      assert UnhandledEvent.line(BuildCalculatorWeb.BuilderLive, "pick_feat") =~ ~s("pick_feat")
    end
  end
end
