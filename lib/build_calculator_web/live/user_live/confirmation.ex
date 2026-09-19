defmodule BuildCalculatorWeb.UserLive.Confirmation do
  @moduledoc """
  Where the magic link lands: confirms the account and logs in.

  The form posts to `UserSessionController` for the same reason the log-in page
  does — a session cookie needs a connection.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="confirmation-page">
        <h1 class="page-title">Здравствуйте, {@user.email}</h1>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation-form"
          class="form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <div class="form-row">
            <button
              type="submit"
              class="btn btn-primary"
              id="confirm-and-stay"
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Подтверждаем…"
            >
              Подтвердить и запомнить меня
            </button>
            <button
              type="submit"
              class="btn"
              id="confirm-once"
              phx-disable-with="Подтверждаем…"
            >
              Подтвердить на один раз
            </button>
          </div>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login-form"
          class="form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope.user do %>
            <button
              type="submit"
              class="btn btn-primary"
              id="log-in-submit"
              phx-disable-with="Входим…"
            >
              Войти
            </button>
          <% else %>
            <div class="form-row">
              <button
                type="submit"
                class="btn btn-primary"
                id="log-in-and-stay"
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with="Входим…"
              >
                Войти и запомнить меня
              </button>
              <button type="submit" class="btn" id="log-in-once" phx-disable-with="Входим…">
                Войти на один раз
              </button>
            </div>
          <% end %>
        </.form>

        <p :if={!@user.confirmed_at} class="page-sub" id="password-hint">
          Если удобнее паролем — его можно завести в настройках.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok,
       socket
       |> assign(:page_title, "Вход · Калькулятор билдов Сиалы")
       |> assign(user: user, form: form, trigger_submit: false), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Ссылка недействительна или истекла.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
