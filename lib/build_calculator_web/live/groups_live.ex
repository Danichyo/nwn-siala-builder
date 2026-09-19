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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} active={:groups} />

      <div class="page page-narrow" id="groups-page">
        <h1 class="page-title">Группы</h1>
        <p class="page-sub">
          Приватный круг: билд с видимостью «группа» виден только её участникам. Каталога групп нет — вступают по коду приглашения.
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
            Вы пока ни в одной группе.
          </p>
        </div>

        <h2 class="page-h2">Создать группу</h2>
        <.form for={@create_form} id="create-group-form" class="form" phx-submit="create">
          <.input
            field={@create_form[:name]}
            type="text"
            label="Название"
            required
            maxlength="80"
          />
          <button type="submit" class="btn btn-primary" id="create-group-submit">Создать</button>
        </.form>

        <h2 class="page-h2">Вступить по коду</h2>
        <.form for={@join_form} id="join-group-form" class="form" phx-submit="join">
          <.input
            field={@join_form[:invite_code]}
            type="text"
            label="Код приглашения"
            required
          />
          <button type="submit" class="btn" id="join-group-submit">Вступить</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Группы · Калькулятор билдов Сиалы")
     |> assign(:create_form, to_form(%{"name" => ""}, as: "group"))
     |> assign(:join_form, to_form(%{"invite_code" => ""}, as: "join"))
     |> load_groups()}
  end

  @impl true
  def handle_event("create", %{"group" => params}, socket) do
    case Accounts.create_group(socket.assigns.current_scope, params) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Группа создана. Код приглашения — на её странице.")
         |> push_navigate(to: ~p"/groups/#{group}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :create_form, to_form(changeset, as: "group"))}
    end
  end

  def handle_event("join", %{"join" => %{"invite_code" => code}}, socket) do
    case Accounts.join_group(socket.assigns.current_scope, String.trim(code)) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы в группе «#{group.name}».")
         |> push_navigate(to: ~p"/groups/#{group}")}

      {:error, :invalid_code} ->
        {:noreply, put_flash(socket, :error, "Такого кода приглашения нет.")}
    end
  end

  # Роль приезжает вместе с группой (`Group.caller_role`), тем же запросом.
  # Раньше здесь стоял `group_role/2` на каждую строку — один запрос к базе
  # на каждую группу списка при том, что join по членству в списке уже был.
  defp load_groups(socket) do
    assign(socket, :groups, Accounts.list_groups(socket.assigns.current_scope))
  end

  @doc false
  def role_label(:owner), do: "владелец"
  def role_label(:member), do: "участник"
  def role_label(_other), do: ""
end
