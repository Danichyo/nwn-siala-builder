defmodule BuildCalculatorWeb.GroupsLive do
  @moduledoc """
  The groups you belong to, plus the two ways to get into one.

  There is no group directory and no browsing: `Accounts.list_groups/1` is
  scoped to membership and joining is by invite code, because "add a person by
  email" would be an email-enumeration oracle
  (`BuildCalculator.Accounts.Group`). This screen therefore has a *create* form
  and a *join by code* form, and nothing that looks other people up.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts
  alias BuildCalculatorWeb.InputLimits

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} active={:groups} />

      <div class="page page-narrow" id="groups-page">
        <h1 class="page-title">{gettext("Groups")}</h1>
        <p class="page-sub">
          {gettext(
            "A private circle: a build with “group” visibility is seen only by the group's members. There is no group directory — you join with an invite code."
          )}
        </p>

        <div class="glist" id="groups-list">
          <.link
            :for={group <- @groups}
            navigate={~p"/groups/#{group}"}
            class="grow-row"
            id={"group-#{group.id}"}
          >
            <span class="grow-name">{group.name}</span>
            <span class="grow-role">{role_label(group.caller_role)}</span>
          </.link>
          <p :if={@groups == []} class="empty-row" id="groups-empty">
            {gettext("You're not in any group yet.")}
          </p>
        </div>

        <h2 class="page-h2">{gettext("Create a group")}</h2>
        <.form for={@create_form} id="create-group-form" class="form" phx-submit="create">
          <.input
            field={@create_form[:name]}
            type="text"
            label={gettext("Name")}
            required
            maxlength="80"
          />
          <button type="submit" class="btn btn-primary" id="create-group-submit">{gettext("Create")}</button>
        </.form>

        <h2 class="page-h2">{gettext("Join with a code")}</h2>
        <.form for={@join_form} id="join-group-form" class="form" phx-submit="join">
          <.input
            field={@join_form[:invite_code]}
            type="text"
            maxlength={BuildCalculatorWeb.InputLimits.short_text()}
            label={gettext("Invite code")}
            required
          />
          <button type="submit" class="btn" id="join-group-submit">{gettext("Join")}</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, Edition.page_title(gettext("Groups")))
     |> assign(:create_form, to_form(%{"name" => ""}, as: "group"))
     |> assign(:join_form, to_form(%{"invite_code" => ""}, as: "join"))
     |> load_groups()}
  end

  # Задача 4.76: поля форм — только строки (`InputLimits.form/3`). Карта
  # вместо имени роняла отрисовку формы с ошибкой (`to_form/2`), строка вместо
  # формы — `cast/4` (`Ecto.CastError`), код приглашения картой — `String.trim/1`.
  @impl true
  def handle_event("create", params, socket) do
    attrs = InputLimits.form(params, "group", ~w(name))

    case Accounts.create_group(socket.assigns.current_scope, attrs) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Group created. The invite code is on its page."))
         |> push_navigate(to: ~p"/groups/#{group}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :create_form, to_form(changeset, as: "group"))}
    end
  end

  # Код приглашения ищется не длиннее своего поля: настоящий — 12 знаков
  # (`Group.generate_invite_code/0`), поле — `InputLimits.short_text/0`.
  def handle_event("join", params, socket) do
    code =
      params
      |> InputLimits.form("join", ~w(invite_code))
      |> Map.get("invite_code", "")
      |> InputLimits.query()
      |> String.trim()

    case Accounts.join_group(socket.assigns.current_scope, code) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("You're in the group “%{name}”.", name: group.name))
         |> push_navigate(to: ~p"/groups/#{group}")}

      {:error, :invalid_code} ->
        {:noreply, put_flash(socket, :error, gettext("That invite code doesn't exist."))}
    end
  end

  # Роль приезжает вместе с группой (`Group.caller_role`), тем же запросом.
  # Раньше здесь стоял `group_role/2` на каждую строку — один запрос к базе
  # на каждую группу списка при том, что join по членству в списке уже был.
  defp load_groups(socket) do
    assign(socket, :groups, Accounts.list_groups(socket.assigns.current_scope))
  end

  @doc false
  def role_label(:owner), do: pgettext("group role", "owner")
  def role_label(:member), do: pgettext("group role", "member")
  def role_label(_other), do: ""
end
