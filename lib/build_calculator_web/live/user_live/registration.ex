defmodule BuildCalculatorWeb.UserLive.Registration do
  @moduledoc """
  Sign-up: an email address and nothing else.

  This is `phx.gen.auth`'s generated flow with the daisyUI markup replaced by the
  project's own (CLAUDE.md §6) and the copy in Russian (§4). Registration mints
  no password — the account is confirmed by a link in the mail, and a password is
  optional and set later in settings.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts
  alias BuildCalculator.Accounts.{Scope, User}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="registration-page">
        <h1 class="page-title">Регистрация</h1>
        <p class="page-sub">
          Уже есть аккаунт? <.link navigate={~p"/users/log-in"} id="to-log-in">Войти</.link>. Аккаунт нужен только чтобы сохранять билды — конструктор и ссылки работают и без него.
        </p>

        <.form for={@form} id="registration-form" class="form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Почта"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <button
            type="submit"
            class="btn btn-primary"
            id="registration-submit"
            phx-disable-with="Создаём…"
          >
            Создать аккаунт
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
     |> assign(:page_title, "Регистрация · Калькулятор билдов Сиалы")
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
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
           "Письмо ушло на #{user.email} — откройте его, чтобы подтвердить почту."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
