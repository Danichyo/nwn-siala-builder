defmodule BuildCalculatorWeb.ParamsShapeTest do
  @moduledoc """
  Параметры адреса и событий библиотеки, групп и аккаунтов — только строки
  (задача 4.76, `BuildCalculatorWeb.InputLimits.form/3`, `strings/2`).

  Браузер шлёт каждое поле формы строкой, но адрес и событие, собранные
  руками, кладут на место строки карту или список: `/library?q[a]=1`. До 4.76:

    * `/library` с картой в `q`, `class`, `race`, `author`, `lmin`, `lmax` —
      500 на мёртвом рендере обычной ссылкой (39 из 180 запросов перебора:
      `Library.Query.by_name/2`, `to_form/1`, `URI.encode_query/1`), библиотека
      спрятана, но маршрут жив; `q` уходил в ILIKE целиком — до 2 МБ сокетом;
    * события форм библиотеки, групп и аккаунта с картой в поле или строкой
      вместо формы роняли экран (`Protocol.UndefinedError` в отрисовке,
      `Ecto.CastError`, `FunctionClauseError`);
    * `POST /users/log-in` со строкой вместо формы, картой вместо почты,
      пароля или токена, без пароля — 500; токен не base64url — 500.

  Каждая проверка шлёт то, что ломало, и требует ответа не 5xx (страницы —
  200) и живого экрана после события.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Accounts.Scope
  alias BuildCalculatorWeb.InputLimits

  @long String.duplicate("x", 300_000)
  @shapes [map: %{"a" => "1"}, list: ["x", "y"], nested: %{"a" => %{"b" => "1"}}, long: @long]
  @library_keys ~w(q class lmin lmax race author cursor)

  # Код ответа — и для исключения, которое отдал бы эндпоинт.
  defp status(fun) do
    fun.().status
  rescue
    e in Plug.Conn.WrapperError -> Plug.Exception.status(e.reason)
    e -> Plug.Exception.status(e)
  end

  setup %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    group = group_fixture(scope)
    build = build_fixture(scope, %{name: "Probe", visibility: :public})

    %{
      signed: log_in_user(conn, user),
      user: user,
      scope: scope,
      group: group,
      build: build,
      code: build_code()
    }
  end

  describe "адрес библиотеки" do
    test "карта, список и длинная строка в любом фильтре — 200, во всех трёх разделах", ctx do
      sections = [
        {ctx.conn, "/library"},
        {ctx.signed, "/library/mine"},
        {ctx.signed, "/library/group/#{ctx.group.id}"}
      ]

      results =
        for {conn, path} <- sections, key <- @library_keys, {shape, value} <- @shapes do
          {path, key, shape, status(fn -> get(conn, path, %{key => value}) end)}
        end

      assert length(results) == 3 * length(@library_keys) * length(@shapes)
      assert Enum.reject(results, fn {_, _, _, status} -> status == 200 end) == []
    end

    test "карта в фильтре отбрасывается, строка рядом работает", %{conn: conn} do
      html =
        conn |> get("/library", %{"q" => %{"a" => "1"}, "race" => "dwarf"}) |> html_response(200)

      doc = LazyHTML.from_document(html)

      # Поле поиска пустое, раса выбрана.
      assert LazyHTML.attribute(LazyHTML.query(doc, "#library-filters input[name=q]"), "value") in [
               [],
               [""]
             ]

      assert LazyHTML.attribute(
               LazyHTML.query(doc, "#library-filters select[name=race] option[selected]"),
               "value"
             ) == ["dwarf"]
    end

    test "в ILIKE уходит не больше поля поиска (short_text/0 знаков)", ctx do
      name = String.duplicate("a", 120)
      found = build_fixture(ctx.scope, %{name: name, visibility: :public})

      {params, conn} =
        ilike_params(fn ->
          get(ctx.conn, "/library", %{"q" => name <> String.duplicate("z", 200_000)})
        end)

      # Положительный контроль: запрос с ILIKE был, и он один.
      assert [param] = params
      assert String.length(param) <= InputLimits.short_text() + 2

      # Обрезанный запрос — ровно имя: билд находится. Без обрезки
      # «%aaa…zzz…%» не нашёл бы ничего.
      assert html_response(conn, 200) =~ ~s(id="build-#{found.id}")
    end
  end

  describe "события библиотеки, групп, формы билда и аккаунта" do
    test "карта, список, строка вместо формы, нет формы — экран жив", ctx do
      cases = [
        {ctx.conn, "/library", "filter", nil, ~w(q class lmin lmax race author)},
        {ctx.signed, "/groups", "create", "group", ~w(name)},
        {ctx.signed, "/groups", "join", "join", ~w(invite_code)},
        {ctx.signed, "/groups/#{ctx.group.id}", "remove", nil, ~w(user)},
        {ctx.signed, "/builds/new?b=#{ctx.code}", "validate", "build",
         ~w(name visibility group_id)},
        {ctx.signed, "/builds/new?b=#{ctx.code}", "save", "build", ~w(name visibility)},
        {ctx.signed, "/builds/#{ctx.build.id}/edit", "validate", "build", ~w(name visibility)},
        {ctx.signed, "/builds/#{ctx.build.id}/edit", "save", "build", ~w(name description)},
        {ctx.conn, "/users/register", "validate", "user", ~w(email)},
        {ctx.conn, "/users/register", "save", "user", ~w(email)},
        {ctx.conn, "/users/log-in", "submit_magic", "user", ~w(email)},
        {ctx.signed, "/users/settings", "validate_email", "user", ~w(email)},
        {ctx.signed, "/users/settings", "update_email", "user", ~w(email)},
        {ctx.signed, "/users/settings", "validate_password", "user", ~w(password)},
        {ctx.signed, "/users/settings", "update_password", "user", ~w(password_confirmation)}
      ]

      Process.flag(:trap_exit, true)

      dead =
        for {conn, path, event, form, fields} <- cases,
            field <- fields,
            {label, payload} <- payloads(form, field),
            reduce: [] do
          acc ->
            {:ok, view, _html} = live(conn, path)

            # Живой экран отвечает на следующую отрисовку; упавший — выходом.
            # Переход после события (`push_navigate` у «сохранить», «ссылку
            # на вход») — ответ экрана, а не падение.
            alive? =
              try do
                case render_hook_quietly(view, event, payload) do
                  {:error, {kind, _to}} when kind in [:live_redirect, :redirect] -> true
                  _html -> is_binary(render(view))
                end
              catch
                :exit, _reason -> false
              end

            if alive?, do: acc, else: [{path, event, field, label} | acc]
        end

      assert dead == []
    end

    test "длинный код приглашения не ищется целиком и не роняет", %{signed: signed} do
      {:ok, view, _html} = live(signed, "/groups")
      render_hook(view, "join", %{"join" => %{"invite_code" => @long}})
      # «Такого кода нет» — флеш ошибки, экран на месте.
      assert has_element?(view, "#flash-error")
      assert has_element?(view, "#join-group-form")
    end
  end

  describe "POST входа и смены пароля" do
    test "собранное руками — 400, а не 500", ctx do
      for params <- [
            %{},
            %{"user" => "x"},
            %{"user" => %{"email" => %{"a" => "1"}, "password" => "p"}},
            %{"user" => %{"email" => "a@b.c", "password" => %{"a" => "1"}}},
            %{"user" => %{"token" => %{"a" => "1"}}},
            %{"user" => %{"email" => "a@b.c"}}
          ] do
        assert status(fn -> post(ctx.conn, ~p"/users/log-in", params) end) == 400,
               inspect(params)
      end

      for params <- [%{}, %{"user" => "x"}, %{"user" => %{"password" => %{"a" => "1"}}}] do
        assert status(fn -> post(ctx.signed, ~p"/users/update-password", params) end) == 400,
               inspect(params)
      end
    end

    test "токен, который не раскодируется, — «ссылка недействительна», а не 500", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => "%%%"}})
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "законный вход по-прежнему входит (контроль)", ctx do
      user = user_fixture() |> set_password()

      conn =
        post(ctx.conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end

  defp render_hook_quietly(view, event, payload) do
    test = self()
    ref = make_ref()
    capture_log(fn -> send(test, {ref, render_hook(view, event, payload)}) end)

    receive do
      {^ref, result} -> result
    end
  end

  defp payloads(nil, field) do
    [
      map: %{field => %{"a" => "1"}},
      list: %{field => ["a"]},
      long: %{field => @long},
      missing: %{}
    ]
  end

  defp payloads(form, field) do
    [
      missing_form: %{},
      form_string: %{form => "x"},
      form_list: %{form => ["x"]},
      map: %{form => %{field => %{"a" => "1"}}},
      list: %{form => %{field => ["a"]}},
      long: %{form => %{field => @long}}
    ]
  end

  # Параметры запросов с ILIKE, сделанных ЭТИМ процессом (мёртвый рендер
  # идёт в процессе теста).
  defp ilike_params(fun) do
    test = self()
    ref = make_ref()
    handler = {__MODULE__, ref}

    :telemetry.attach(
      handler,
      [:build_calculator, :repo, :query],
      fn _event, _measure, meta, _config ->
        if self() == test and meta.query =~ "ILIKE" do
          send(test, {ref, Enum.filter(meta.params, &(is_binary(&1) and &1 =~ "%"))})
        end
      end,
      nil
    )

    try do
      result = fun.()
      {drain(ref, []), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(ref, acc) do
    receive do
      {^ref, params} -> drain(ref, acc ++ params)
    after
      0 -> acc
    end
  end
end
