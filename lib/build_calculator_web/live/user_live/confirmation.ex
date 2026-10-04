defmodule BuildCalculatorWeb.UserLive.Confirmation do
  @moduledoc """
  Where the magic link lands: confirms the account and logs in.

  The form posts to `UserSessionController` for the same reason the log-in page
  does — a session cookie needs a connection.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts
  alias BuildCalculatorWeb.InputLimits

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="confirmation-page">
        <h1 class="page-title">{gettext("Hello, %{email}", email: @user.email)}</h1>

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
              phx-disable-with={gettext("Confirming…")}
            >
              {gettext("Confirm and remember me")}
            </button>
            <button
              type="submit"
              class="btn"
              id="confirm-once"
              phx-disable-with={gettext("Confirming…")}
            >
              {gettext("Confirm only this time")}
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
              phx-disable-with={gettext("Logging in…")}
            >
              {pgettext("account button", "Log in")}
            </button>
          <% else %>
            <div class="form-row">
              <button
                type="submit"
                class="btn btn-primary"
                id="log-in-and-stay"
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with={gettext("Logging in…")}
              >
                {gettext("Log in and remember me")}
              </button>
              <button
                type="submit"
                class="btn"
                id="log-in-once"
                phx-disable-with={gettext("Logging in…")}
              >
                {gettext("Log in only this time")}
              </button>
            </div>
          <% end %>
        </.form>

        <p :if={!@user.confirmed_at} class="page-sub" id="password-hint">
          {gettext("If you prefer a password, you can set one in settings.")}
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
       |> assign(:page_title, Edition.page_title(gettext("Log in")))
       |> assign(user: user, form: form, trigger_submit: false), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("The link is invalid or has expired."))
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  # Задача 4.76: поля — только строки и только эти два (`InputLimits.form/3`):
  # карта в скрытом поле роняла отрисовку формы.
  @impl true
  def handle_event("submit", params, socket) do
    params = InputLimits.form(params, "user", ~w(token remember_me))
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
