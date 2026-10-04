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
  alias BuildCalculatorWeb.InputLimits

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="login-page">
        <h1 class="page-title">{gettext("Log in")}</h1>
        <p class="page-sub">
          <%= if @current_scope.user do %>
            {gettext("Confirm it's you — this action needs a fresh log-in.")}
          <% else %>
            {gettext("No account?")} <.link navigate={~p"/users/register"} id="to-register">{pgettext("call to action", "Sign up")}</.link>. {gettext(
              "You only need one to save builds."
            )}
          <% end %>
        </p>

        <p :if={local_mail_adapter?()} class="notice-soft" id="local-mail-note">
          {gettext("Mail goes to a local mailbox:")} <.link href="/dev/mailbox">{gettext("view the mail")}</.link>.
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
            maxlength={BuildCalculatorWeb.InputLimits.email()}
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <button type="submit" class="btn btn-primary" id="login-magic-submit">
            {gettext("Email me a log-in link")}
          </button>
        </.form>

        <p class="form-or">{gettext("or with a password, if you've set one")}</p>

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
            maxlength={BuildCalculatorWeb.InputLimits.email()}
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            maxlength={BuildCalculatorWeb.InputLimits.password()}
            label={gettext("Password")}
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
              {gettext("Log in and stay logged in")}
            </button>
            <button type="submit" class="btn" id="login-password-once">{gettext(
              "Log in only this time"
            )}</button>
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
     |> assign(:page_title, Edition.page_title(gettext("Log in")))
     |> assign(form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  # Задача 4.76: почта — только строка, и ищется, только если такая может
  # быть у аккаунта (`InputLimits.within?/2`, предел — тот же, что у
  # `Accounts.User`). Карта роняла `get_user_by_email/1` (охранник `is_binary`),
  # нет поля — клаузу. Ответ тот же при любом вводе.
  def handle_event("submit_magic", params, socket) do
    email = InputLimits.form(params, "user", ~w(email))["email"]

    if InputLimits.within?(email, InputLimits.email()) do
      if user = Accounts.get_user_by_email(email) do
        Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
      end
    end

    # Deliberately the same answer either way — otherwise this page tells anyone
    # who asks whether an address is registered.
    info = gettext("If we have that email, a log-in link is on its way.")

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
