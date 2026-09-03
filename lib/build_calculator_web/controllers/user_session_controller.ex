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
  alias BuildCalculatorWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Почта подтверждена.")
  end

  def create(conn, params) do
    create(conn, params, "С возвращением!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "Ссылка недействительна или истекла.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Неверная почта или пароль")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Пароль обновлён.")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Вы вышли.")
    |> UserAuth.log_out_user()
  end
end
