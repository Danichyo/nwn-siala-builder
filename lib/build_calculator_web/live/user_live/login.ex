defmodule BuildCalculatorWeb.UserLive.Login do
  @moduledoc """
  Log in, by magic link or by password.

  Both forms `action=` into `UserSessionController`: the session cookie is
  written on the connection, not on the socket, so the password form submits for
  real with `phx-trigger-action`. That is the generated shape and it is kept —
  only the markup and the copy changed.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="login-page">
        <h1 class="page-title">Вход</h1>
        <p class="page-sub">
          <%= if @current_scope.user do %>
            Нужно подтвердить, что это вы, — действие требует свежего входа.
          <% else %>
            Нет аккаунта? <.link navigate={~p"/users/register"} id="to-register">Зарегистрируйтесь</.link>. Он нужен только чтобы сохранять билды.
          <% end %>
        </p>

        <p :if={local_mail_adapter?()} class="notice-soft" id="local-mail-note">
          Почта уходит в локальный ящик: <.link href="/dev/mailbox">посмотреть письма</.link>.
        </p>

        <.form
          :let={f}
          for={@form}
          id="login-form-magic"
          class="form"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope.user}
            field={f[:email]}
            type="email"
            label="Почта"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <button type="submit" class="btn btn-primary" id="login-magic-submit">
            Прислать ссылку для входа
          </button>
        </.form>

        <p class="form-or">или паролем, если вы его завели</p>

        <.form
          :let={f}
          for={@form}
          id="login-form-password"
          class="form"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope.user}
            field={f[:email]}
            type="email"
            label="Почта"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Пароль"
            autocomplete="current-password"
            spellcheck="false"
          />
          <div class="form-row">
            <button
              type="submit"
              class="btn btn-primary"
              id="login-password-submit"
              name={@form[:remember_me].name}
              value="true"
            >
              Войти и запомнить
            </button>
            <button type="submit" class="btn" id="login-password-once">Войти на один раз</button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # Скоуп есть всегда, так что вся неизвестность здесь — вошёл или нет;
    # `get_in` с `Access.key/1` разбирал ещё и «скоупа нет вовсе», которого
    # больше не бывает (`BuildCalculator.Accounts.Scope`).
    user = socket.assigns.current_scope.user

    email = Phoenix.Flash.get(socket.assigns.flash, :email) || (user && user.email)

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     socket
     |> assign(:page_title, "Вход · Калькулятор билдов Сиалы")
     |> assign(form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
    end

    # Deliberately the same answer either way — otherwise this page tells anyone
    # who asks whether an address is registered.
    info = "Если такая почта у нас есть, ссылка для входа уже в пути."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:build_calculator, BuildCalculator.Mailer)[:adapter] ==
      Swoosh.Adapters.Local
  end
end
