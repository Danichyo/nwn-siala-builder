defmodule BuildCalculatorWeb.UserLive.Settings do
  @moduledoc """
  Account settings: change the email address, set or change a password.

  Both are guarded by sudo mode (`:require_sudo_mode`) — a stolen open tab must
  not be enough to take the account over. The password form posts through
  `UserSessionController.update_password/2` so the session is reissued on a
  connection.
  """
  use BuildCalculatorWeb, :live_view

  on_mount {BuildCalculatorWeb.UserAuth, :require_sudo_mode}

  alias BuildCalculator.Accounts
  alias BuildCalculatorWeb.InputLimits

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="settings-page">
        <h1 class="page-title">{gettext("Account settings")}</h1>
        <p class="page-sub">{gettext("Email and password. There's nothing else in the account.")}</p>

        <.form
          for={@email_form}
          id="email-form"
          class="form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input
            field={@email_form[:email]}
            type="email"
            maxlength={BuildCalculatorWeb.InputLimits.email()}
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <button
            type="submit"
            class="btn btn-primary"
            id="email-submit"
            phx-disable-with={gettext("Changing…")}
          >
            {gettext("Change email")}
          </button>
        </.form>

        <hr class="form-sep" />

        <.form
          for={@password_form}
          id="password-form"
          class="form"
          action={~p"/users/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden-user-email"
            spellcheck="false"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            maxlength={BuildCalculatorWeb.InputLimits.password()}
            label={gettext("New password")}
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            maxlength={BuildCalculatorWeb.InputLimits.password()}
            label={gettext("Confirm new password")}
            autocomplete="new-password"
            spellcheck="false"
          />
          <button
            type="submit"
            class="btn btn-primary"
            id="password-submit"
            phx-disable-with={gettext("Saving…")}
          >
            {gettext("Save password")}
          </button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Email changed."))

        {:error, _} ->
          put_flash(socket, :error, gettext("The email change link is invalid or has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    {:ok,
     socket
     |> assign(:page_title, Edition.page_title(gettext("Settings")))
     |> assign(:current_email, user.email)
     |> assign(:email_form, to_form(email_changeset))
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:trigger_submit, false)}
  end

  # Задача 4.76: поля форм — только строки и только свои
  # (`InputLimits.form/3`): карта вместо почты или пароля роняла отрисовку
  # формы с ошибкой (`to_form/1`), строка вместо формы — `cast/4`.
  @email_fields ~w(email)
  @password_fields ~w(password password_confirmation)

  @impl true
  def handle_event("validate_email", params, socket) do
    user_params = InputLimits.form(params, "user", @email_fields)

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    user_params = InputLimits.form(params, "user", @email_fields)
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = gettext("A link to confirm the new email has been sent to it.")
        {:noreply, put_flash(socket, :info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    user_params = InputLimits.form(params, "user", @password_fields)

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    user_params = InputLimits.form(params, "user", @password_fields)
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
