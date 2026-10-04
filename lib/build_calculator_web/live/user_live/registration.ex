defmodule BuildCalculatorWeb.UserLive.Registration do
  @moduledoc """
  Sign-up: an email address and nothing else.

  This is `phx.gen.auth`'s generated flow with the daisyUI markup replaced by the
  project's own (CLAUDE.md §6) and the copy through gettext (§4; Russian on
  Siala, English on vanilla — task 4.48). Registration mints
  no password — the account is confirmed by a link in the mail, and a password is
  optional and set later in settings.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts
  alias BuildCalculator.Accounts.{Scope, User}
  alias BuildCalculatorWeb.InputLimits

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="registration-page">
        <h1 class="page-title">{gettext("Sign up")}</h1>
        <p class="page-sub">
          {gettext("Already have an account?")} <.link navigate={~p"/users/log-in"} id="to-log-in">{pgettext("account button", "Log in")}</.link>. {gettext(
            "You only need an account to save builds — the builder and links work without one."
          )}
        </p>

        <.form for={@form} id="registration-form" class="form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            maxlength={BuildCalculatorWeb.InputLimits.email()}
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <button
            type="submit"
            class="btn btn-primary"
            id="registration-submit"
            phx-disable-with={gettext("Creating…")}
          >
            {gettext("Create account")}
          </button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %Scope{user: %User{}}}} = socket) do
    {:ok, redirect(socket, to: BuildCalculatorWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(:page_title, Edition.page_title(gettext("Sign up")))
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  # Задача 4.76: поле формы — только строка (`InputLimits.form/3`): карта
  # вместо почты роняла отрисовку формы с ошибкой, строка вместо формы — `cast/4`.
  @impl true
  def handle_event("save", params, socket) do
    case Accounts.register_user(InputLimits.form(params, "user", ~w(email))) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("An email was sent to %{email} — open it to confirm your address.",
             email: user.email
           )
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", params, socket) do
    user_params = InputLimits.form(params, "user", ~w(email))
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
