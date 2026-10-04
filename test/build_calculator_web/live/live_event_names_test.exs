defmodule BuildCalculatorWeb.LiveEventNamesTest do
  @moduledoc """
  🔴 Сторож имён событий (задача 4.76): каждое имя, которое браузер может
  прислать экрану, взято из шаблона и есть в клаузах `handle_event/3` ЭТОГО
  экрана — и наоборот, у каждой клаузы есть шаблон, который её зовёт.

  С 4.76 у каждого LiveView веб-слоя последняя клауза `handle_event/3`
  отбрасывает событие, которое не берёт ни одна другая
  (`BuildCalculatorWeb.UnhandledEvent`): событие с чужим именем больше не роняет
  процесс и не пишет отчёт о падении в лог. Цена — опечатка в шаблоне
  (`phx-click="pick_fet"`) тоже молча отбрасывалась бы, а раньше роняла первый
  же тест, нажавший кнопку. Этот файл — то, что её ловит теперь: имена
  читает `BuildCalculatorWeb.LiveEventScan` (шаблоны, `JS.push/2`,
  `pushEvent` хуков, атрибуты-события компонентов, атрибуты, собранные
  в коде), клаузы — `__handled_events__/0` самого экрана.

  Обратное направление («клауза без шаблона») — проверка полноты самого
  сканера: путь, которым имя попадает в разметку и которого сканер не знает,
  выглядел бы мёртвой клаузой. Так нашёлся пятый путь — атрибуты, собранные
  в коде (`Builder.GearPanel`, `"phx-click": "pick_gear_weapon"`).

  Положительные контроли — подложенная опечатка в настоящем шаблоне, в
  компоненте, в атрибутах из кода, в хуке и в экране, собранном тут же, —
  находится; отрисовка экранов не несёт имени, которого сканер не видел.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Accounts.Scope
  alias BuildCalculatorWeb.LiveEventScan, as: Scan

  # Событие, которое LiveView обрабатывает сам, до клауз экрана
  # (`Phoenix.LiveView.Channel.view_handle_event/3`): крестик флеша.
  @live_view_own ["lv:clear-flash"]

  defp live_views do
    {:ok, modules} = :application.get_key(:build_calculator, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__live__, 0),
        do: module
  end

  # Хук счётчика (`BuildCalculatorWeb.Analytics`) гасит свои события до
  # клауз экрана — но только у экранов, все маршруты которых его ставят.
  defp hook_events(view) do
    routes =
      for %{metadata: %{phoenix_live_view: {^view, _action, _opts, session}}} <-
            BuildCalculatorWeb.Router.__routes__(),
          do: session.extra.on_mount

    analytics? =
      routes != [] and
        Enum.all?(routes, fn hooks ->
          Enum.any?(hooks, &(&1.id == {BuildCalculatorWeb.Analytics, :default}))
        end)

    if analytics?, do: BuildCalculatorWeb.Analytics.client_events(), else: []
  end

  defp handled(view), do: view.__handled_events__() ++ hook_events(view) ++ @live_view_own

  defp unhandled(units, view), do: Scan.unhandled(units, view, handled(view))

  defp names(found), do: Enum.map(found, &elem(&1, 0))

  describe "настоящий веб-слой" do
    setup do
      %{units: Scan.scan(Scan.read_sources())}
    end

    test "у каждого имени из шаблона есть своя клауза в экране, который его рисует", %{
      units: units
    } do
      views = live_views()

      # Положительный контроль обхода: экраны нашлись все, а не ноль.
      assert length(views) >= 11
      assert BuildCalculatorWeb.BuilderLive in views
      assert BuildCalculatorWeb.SourcesLive in views

      for view <- views do
        assert unhandled(units, view) == [],
               "#{inspect(view)}: имена без клаузы — #{inspect(unhandled(units, view))}"
      end
    end

    test "у каждой клаузы есть шаблон, который её зовёт (полнота сканера)", %{units: units} do
      for view <- live_views() do
        emitted = units |> Scan.emitted(view) |> Map.keys()
        dead = view.__handled_events__() -- emitted

        assert dead == [],
               "#{inspect(view)}: клаузы, которых не зовёт ни один шаблон — #{inspect(dead)}"
      end
    end

    test "каждый путь имени виден сканеру (контроль: настоящие места)", %{units: units} do
      builder = Scan.emitted(units, BuildCalculatorWeb.BuilderLive)
      view = Scan.emitted(units, BuildCalculatorWeb.BuildViewLive)

      # литерал `phx-click` в своём шаблоне
      assert {BuildCalculatorWeb.BuilderLive, :render} in builder["pick_feat"]
      # литерал в компоненте другого модуля
      assert builder["toggle_section"] == [{BuildCalculatorWeb.BuilderComponents, :section}]
      # выражение `{@next.ready? && "select_level"}` в компоненте
      assert {BuildCalculatorWeb.BuilderComponents, :next_level} in builder["select_level"]
      # `JS.push/2` в помощнике экрана
      assert builder["jump_to_gear_issue"] == [{BuildCalculatorWeb.BuilderLive, :gear_issue_jump}]
      # `pushEvent` колокированного хука
      assert {BuildCalculatorWeb.BuilderLive, :render} in builder["set_guided_mode"]

      # атрибут-событие компонента на месте вызова (через передачу дальше)
      assert {BuildCalculatorWeb.BuilderLive, :render} in builder["gear_weapon_search"]
      assert {BuildCalculatorWeb.BuilderLive, :render} in builder["drop_gear_weapon"]
      # атрибуты, собранные в коде другого модуля
      assert [{BuildCalculatorWeb.Builder.GearPanel, _fun}] = builder["pick_gear_weapon"]

      # маяк счётчика — хук компонента, у обоих экранов, его рисующих
      assert builder["analytics_export_downloaded"] ==
               [{BuildCalculatorWeb.BuilderComponents, :download_text}]

      assert view["analytics_export_downloaded"] ==
               [{BuildCalculatorWeb.BuilderComponents, :download_text}]

      # крестик флеша — у всех экранов через `<Layouts.app>`
      for live_view <- live_views() do
        assert Map.has_key?(Scan.emitted(units, live_view), "lv:clear-flash"), inspect(live_view)
      end
    end

    test "хуков вне шаблонов, шлющих события, нет" do
      assert Scan.asset_push_events() == []
    end
  end

  describe "положительный контроль: подложенная опечатка находится" do
    test "в шаблоне экрана — у этого экрана и только у него" do
      path = "lib/build_calculator_web/live/builder_live.html.heex"
      planted = File.read!(path) <> ~s(\n<button id="typo-476" phx-click="pick_fet">x</button>\n)
      units = Scan.scan(Scan.read_sources(%{path => planted}))

      assert names(unhandled(units, BuildCalculatorWeb.BuilderLive)) == ["pick_fet"]
      assert unhandled(units, BuildCalculatorWeb.BuildViewLive) == []
    end

    test "в общем компоненте — у каждого экрана, который его вызывает" do
      path = "lib/build_calculator_web/components/builder_components.ex"
      source = File.read!(path)
      assert source =~ ~s(phx-click="toggle_section")

      planted =
        String.replace(source, ~s(phx-click="toggle_section"), ~s(phx-click="toggle_sectoin"))

      units = Scan.scan(Scan.read_sources(%{path => planted}))

      assert [{"toggle_sectoin", [{BuildCalculatorWeb.BuilderComponents, :section}]}] =
               unhandled(units, BuildCalculatorWeb.BuilderLive)

      # и обратное направление видит осиротевшую клаузу
      emitted = units |> Scan.emitted(BuildCalculatorWeb.BuilderLive) |> Map.keys()
      assert "toggle_section" in (BuildCalculatorWeb.BuilderLive.__handled_events__() -- emitted)

      # экран без этого компонента не задет
      assert unhandled(units, BuildCalculatorWeb.LibraryLive) == []
    end

    test "в атрибутах, собранных в коде другого модуля" do
      path = "lib/build_calculator_web/builder/gear_panel.ex"
      source = File.read!(path)

      planted =
        String.replace(
          source,
          ~s("phx-click": "pick_gear_weapon"),
          ~s("phx-click": "pick_gear_waepon")
        )

      refute planted == source

      units = Scan.scan(Scan.read_sources(%{path => planted}))
      assert names(unhandled(units, BuildCalculatorWeb.BuilderLive)) == ["pick_gear_waepon"]
    end

    test "в pushEvent колокированного хука" do
      path = "lib/build_calculator_web/live/builder_live.html.heex"
      source = File.read!(path)

      planted =
        String.replace(source, ~s|pushEvent("set_guided_mode"|, ~s|pushEvent("set_guided_mod"|)

      refute planted == source

      units = Scan.scan(Scan.read_sources(%{path => planted}))
      assert names(unhandled(units, BuildCalculatorWeb.BuilderLive)) == ["set_guided_mod"]
    end

    test "в экране, собранном тут же: клаузы читает сам экран, опечатку — сканер", %{conn: conn} do
      module = Module.concat(__MODULE__, "TypoLive#{System.unique_integer([:positive])}")

      source = """
      defmodule #{inspect(module)} do
        use BuildCalculatorWeb, :live_view

        @impl true
        def mount(_params, _session, socket), do: {:ok, assign(socket, :count, 0)}

        @impl true
        def render(assigns) do
          ~H\"\"\"
          <button id="real" phx-click="real_event">{@count}</button>
          <button id="typo" phx-click="real_evnet">typo</button>
          \"\"\"
        end

        @impl true
        def handle_event("real_event", _params, socket),
          do: {:noreply, update(socket, :count, &(&1 + 1))}
      end
      """

      [{^module, _binary}] = Code.compile_string(source, "typo_live.ex")

      assert module.__handled_events__() == ["real_event"]

      units = Scan.scan([{"typo_live.ex", source}])

      assert Scan.unhandled(units, module, handled(module) ++ @live_view_own) |> names() == [
               "real_evnet"
             ]

      # И экран её переживает: опечатка отбрасывается, а не роняет процесс.
      {:ok, view, _html} = live_isolated(conn, module)

      log =
        capture_log(fn ->
          view |> element("#typo") |> render_click()
          view |> element("#real") |> render_click()
        end)

      assert has_element?(view, "#real", "1")
      assert log =~ "#{inspect(module)}: an event no clause of handle_event/3 takes"
    end
  end

  describe "отрисовка не несёт имени, которого сканер не видел" do
    # Имя, собранное во время работы («pick_» <> вид), сканер не прочёл бы
    # из исходников. Отрисовка нескольких состояний — сверка снаружи.
    setup %{conn: conn} do
      user = user_fixture()
      scope = Scope.for_user(user)
      group = group_fixture(scope)
      build = build_fixture(scope, %{name: "Probe", visibility: :public})
      %{signed: log_in_user(conn, user), group: group, build: build, code: build_code()}
    end

    test "конструктор, просмотр, библиотека, группы, аккаунт", ctx do
      units = Scan.scan(Scan.read_sources())

      pages = [
        {BuildCalculatorWeb.BuilderLive, ctx.conn, "/", &open_builder_panels/1},
        {BuildCalculatorWeb.BuilderLive, ctx.conn, "/?b=#{ctx.code}&l=3", &open_builder_panels/1},
        {BuildCalculatorWeb.BuildViewLive, ctx.conn, "/b/#{ctx.code}", & &1},
        {BuildCalculatorWeb.LibraryLive, ctx.conn, "/library", & &1},
        {BuildCalculatorWeb.SourcesLive, ctx.conn, "/sources", & &1},
        {BuildCalculatorWeb.UserLive.Login, ctx.conn, "/users/log-in", & &1},
        {BuildCalculatorWeb.UserLive.Registration, ctx.conn, "/users/register", & &1},
        {BuildCalculatorWeb.UserLive.Settings, ctx.signed, "/users/settings", & &1},
        {BuildCalculatorWeb.GroupsLive, ctx.signed, "/groups", & &1},
        {BuildCalculatorWeb.GroupLive, ctx.signed, "/groups/#{ctx.group.id}", & &1},
        {BuildCalculatorWeb.BuildFormLive, ctx.signed, "/builds/new?b=#{ctx.code}", & &1},
        {BuildCalculatorWeb.BuildFormLive, ctx.signed, "/builds/#{ctx.build.id}/edit", & &1}
      ]

      # Флеш (неизвестная короткая ссылка уводит на конструктор с ним) — его
      # крестик несёт команду JS `push`, а не имя: контроль второй формы.
      flashed = get(ctx.conn, "/s/ZZZZZZ")
      assert redirected_to(flashed) == "/"
      pages = [{BuildCalculatorWeb.BuilderLive, recycle(flashed), "/", & &1} | pages]

      seen =
        for {module, conn, path, step} <- pages, reduce: %{} do
          acc ->
            {:ok, view, _html} = live(conn, path)
            html = view |> step.() |> render()
            Map.update(acc, module, dom_events(html), &(&1 ++ dom_events(html)))
        end

      # Положительный контроль: отрисовка несёт имена, а не пустоту, — обе
      # формы атрибута (имя и команда JS).
      assert "pick_class" in seen[BuildCalculatorWeb.BuilderLive]
      assert "toggle_section" in seen[BuildCalculatorWeb.BuilderLive]
      assert "toggle_gear_weapon_add" in seen[BuildCalculatorWeb.BuilderLive]
      assert "lv:clear-flash" in seen[BuildCalculatorWeb.BuilderLive]
      assert "filter" in seen[BuildCalculatorWeb.LibraryLive]

      for {module, events} <- seen do
        emitted = units |> Scan.emitted(module) |> Map.keys()
        missing = Enum.uniq(events) -- emitted

        assert missing == [],
               "#{inspect(module)}: в отрисовке, но не в сканере — #{inspect(missing)}"
      end
    end
  end

  # Открыть то, что открывается кликом: «Вещи» (там JS.push и атрибуты из кода).
  defp open_builder_panels(view) do
    if has_element?(view, "#gear-toggle") do
      view |> element("#gear-toggle") |> render_click()
    end

    view
  end

  @bindings ~w(click change submit blur focus keydown keyup window-keydown window-keyup
               window-blur window-focus click-away capture-click)

  # Имена событий из разметки: значение атрибута или `push` команды JS.
  defp dom_events(html) do
    doc = LazyHTML.from_document(html)

    for binding <- @bindings,
        attr = "phx-" <> binding,
        value <- LazyHTML.attribute(LazyHTML.query(doc, "[#{attr}]"), attr),
        event <- value_events(value),
        do: event
  end

  defp value_events("[" <> _ = json) do
    for ["push", %{"event" => event}] <- Jason.decode!(json), do: event
  end

  defp value_events(""), do: []
  defp value_events(name), do: [name]
end
