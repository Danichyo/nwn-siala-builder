defmodule BuildCalculatorWeb.UserSessionController do
  @moduledoc """
  Creating and destroying the session cookie.

  Log in has to be a real form POST rather than a LiveView event: the session
  cookie is written on the connection, which a socket does not have. The log-in
  and confirmation LiveViews therefore submit into this controller with
  `phx-trigger-action` — that is the generated shape and it is kept.
  """
  use BuildCalculatorWeb, :controller

  alias BuildCalculator.Accounts
  alias BuildCalculatorWeb.InputLimits
  alias BuildCalculatorWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, gettext("Email confirmed."))
  end

  def create(conn, params) do
    create(conn, params, gettext("Welcome back."))
  end

  # Задача 4.76: поля входа — только строки и только эти четыре
  # (`InputLimits.form/3`). Карта вместо почты, пароля или токена роняла
  # контекст (охранники `is_binary`, `Base.url_decode64/2`), строка вместо
  # формы и форма без пароля — сопоставление: 500. Законная форма шлёт либо
  # токен (вход по ссылке), либо почту с паролем, хоть пустыми; остальное
  # собрано руками и получает 400, как запрос без формы вовсе.
  @user_fields ~w(email password token remember_me)

  defp create(conn, params, info) do
    case InputLimits.form(params, "user", @user_fields) do
      %{"token" => token} = user_params -> magic_link(conn, token, user_params, info)
      %{"email" => _, "password" => _} = user_params -> password(conn, user_params, info)
      _malformed -> raise Plug.BadRequestError
    end
  end

  # magic link login
  defp magic_link(conn, token, user_params, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, gettext("The link is invalid or has expired."))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp password(conn, %{"email" => email, "password" => password} = user_params, info) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, gettext("Invalid email or password"))
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  # Форма настроек шлёт сюда пароль, который уже проверила (`UserLive.Settings`);
  # поля — только строки (задача 4.76), а пароль, который проверку не прошёл,
  # пришёл не из формы — 400, а не падение сопоставления.
  def update_password(conn, params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    user_params = InputLimits.form(params, "user", ~w(email password password_confirmation))

    case Accounts.update_user_password(user, user_params) do
      {:ok, {_user, expired_tokens}} ->
        # disconnect all existing LiveViews with old sessions
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_session(:user_return_to, ~p"/users/settings")
        |> create(%{"user" => user_params}, gettext("Password updated."))

      {:error, _changeset} ->
        raise Plug.BadRequestError
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("You've logged out."))
    |> UserAuth.log_out_user()
  end
end
