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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="settings-page">
        <h1 class="page-title">Настройки аккаунта</h1>
        <p class="page-sub">Почта и пароль. Больше в аккаунте ничего нет.</p>

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
            label="Почта"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <button
            type="submit"
            class="btn btn-primary"
            id="email-submit"
            phx-disable-with="Меняем…"
          >
            Сменить почту
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
            label="Новый пароль"
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Ещё раз"
            autocomplete="new-password"
            spellcheck="false"
          />
          <button
            type="submit"
            class="btn btn-primary"
            id="password-submit"
            phx-disable-with="Сохраняем…"
          >
            Сохранить пароль
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
          put_flash(socket, :info, "Почта изменена.")

        {:error, _} ->
          put_flash(socket, :error, "Ссылка для смены почты недействительна или истекла.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    {:ok,
     socket
     |> assign(:page_title, "Настройки · Калькулятор билдов Сиалы")
     |> assign(:current_email, user.email)
     |> assign(:email_form, to_form(email_changeset))
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "Ссылка для подтверждения новой почты ушла на неё."
        {:noreply, put_flash(socket, :info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"user" => user_params}, socket) do
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
