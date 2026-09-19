defmodule BuildCalculatorWeb.UserAuthFlowTest do
  @moduledoc """
  The web half of `phx.gen.auth`, end to end: register, log in, log out, settings.

  The context itself is covered in `test/build_calculator/accounts_test.exs` —
  what is checked here is the routing and the LiveViews around it, including the
  one property the product depends on: the site keeps working signed out.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures

  alias BuildCalculator.Accounts
  alias BuildCalculator.Accounts.Scope
  alias BuildCalculatorWeb.UserAuth

  describe "регистрация" do
    test "создаёт пользователя и шлёт письмо со ссылкой", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      {:error, {:live_redirect, %{to: "/users/log-in"}}} =
        view |> form("#registration-form", user: %{email: email}) |> render_submit()

      assert Accounts.get_user_by_email(email)
    end

    test "показывает ошибку на негодной почте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      html = view |> form("#registration-form", user: %{email: "без-собаки"}) |> render_change()
      assert html =~ "@"
    end

    test "вошедшего уводит с формы", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/register")
    end
  end

  describe "вход" do
    test "паролем", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      form =
        form(view, "#login-form-password",
          user: %{email: user.email, password: valid_user_password()}
        )

      conn = submit_form(form, conn)
      assert redirected_to(conn) == ~p"/"
    end

    test "по ссылке из письма", %{conn: conn} do
      user = unconfirmed_user_fixture()
      {token, _} = generate_user_magic_link_token(user)

      {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")
      assert has_element?(view, "#confirmation-form")

      form = form(view, "#confirmation-form", user: %{token: token})
      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_email(user.email).confirmed_at
    end

    test "просроченная ссылка не роняет страницу", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/users/log-in/#{"нет-такого-токена"}")
    end

    test "неверный пароль не выдаёт, зарегистрирована ли почта", %{conn: conn} do
      user = user_fixture() |> set_password()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "не тот пароль"}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Неверная почта или пароль"
    end
  end

  describe "выход" do
    test "чистит сессию", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> delete(~p"/users/log-out")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end

  describe "настройки" do
    setup :register_and_log_in_user

    test "меняют почту письмом подтверждения", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> form("#email-form", user: %{email: unique_user_email()})
      |> render_submit()

      # Почта не меняется до перехода по ссылке — старая на месте.
      assert Accounts.get_user_by_email(user.email)
    end

    test "заводят пароль", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      form =
        form(view, "#password-form",
          user: %{
            email: user.email,
            password: valid_user_password(),
            password_confirmation: valid_user_password()
          }
        )

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/users/settings"
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "без свежего входа настройки закрыты", %{conn: _conn} do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      offset_user_token(token, -11, :minute)

      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_token, token)

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/users/settings")
    end
  end

  describe "сайт без аккаунта" do
    test "конструктор, просмотр и публичная лента открыты", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/")
      assert {:ok, _view, _html} = live(conn, ~p"/library")
    end

    test "закрытые разделы уводят на вход и запоминают адрес", %{conn: _conn} do
      for path <- [~p"/library/mine", ~p"/groups", ~p"/users/settings"] do
        conn = get(build_conn(), path)
        assert redirected_to(conn) == ~p"/users/log-in"
        assert get_session(conn, :user_return_to) == path
      end
    end

    # ⚠️ Гость — обычный вызывающий, просто без пользователя. Раньше у него
    # и у «скоупа нет вовсе» было одно значение `nil`, и разбирался с этим
    # каждый вызывающий сам.
    test "у гостя скоуп есть, просто без пользователя", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert conn.assigns.current_scope == %Scope{user: nil}
    end

    test "у вошедшего в скоупе он сам", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> get(~p"/")

      assert conn.assigns.current_scope.user.id == user.id
    end

    # Раньше эта ветка на госте падала `nil.user` вместо того, чтобы отправить
    # на вход. Через роутер она недостижима — `:require_authenticated`
    # останавливает раньше, — поэтому проверяется напрямую: свойство должно
    # держаться на самой функции, а не на порядке `on_mount`.
    test "sudo-режим у гостя уводит на вход, а не падает" do
      # Структура собирается литералом: `flash` — зарезервированный assign,
      # и через `assign/3` его не поставить, а `on_mount` его читает.
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, current_scope: Scope.for_user(nil)}
      }

      assert {:halt, halted} = UserAuth.on_mount(:require_sudo_mode, %{}, %{}, socket)
      assert {:redirect, %{to: "/users/log-in"}} = halted.redirected
    end
  end
end
