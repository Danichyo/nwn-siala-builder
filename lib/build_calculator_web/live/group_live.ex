defmodule BuildCalculatorWeb.GroupLive do
  @moduledoc """
  One group: who is in it, how to invite, how to leave.

  Every read and every write goes through `BuildCalculator.Accounts`, which puts
  membership in the `where` rather than checking the result — the group id in
  the URL is not by itself permission to see anything. What this module decides
  is only which buttons to draw.

  The invite code is shown to members, not just owners: inviting *is* sharing
  the code, and a member who cannot invite cannot do the one thing the group is
  for. Rotating it stays with owners, which is where the context puts it.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} active={:groups} />

      <div class="page page-narrow" id="group-page">
        <h1 class="page-title" id="group-name">{@group.name}</h1>
        <p class="page-sub">
          <.link navigate={~p"/library/group/#{@group}"} id="group-feed">{gettext("Group builds")}</.link>
          · {you_are(@role)}
        </p>

        <h2 class="page-h2">{gettext("Invite code")}</h2>
        <p class="page-sub">
          {gettext(
            "Anyone who knows the code can join on their own. If it leaks, change it: the old one will stop working."
          )}
        </p>
        <div class="form-row">
          <code class="invite-code" id="invite-code">{@group.invite_code}</code>
          <button
            :if={@role == :owner}
            type="button"
            class="btn"
            id="rotate-code"
            phx-click="rotate"
            data-confirm={
              gettext("Change the code? The old one will stop working for everyone you gave it to.")
            }
          >
            {gettext("Change code")}
          </button>
        </div>

        <h2 class="page-h2">{gettext("Members")}</h2>
        <div class="glist" id="members">
          <div :for={member <- @members} class="grow-row" id={"member-#{member.user_id}"}>
            <span class="grow-name">{member.user.email}</span>
            <span class="grow-role">{role_label(member.role)}</span>
            <button
              :if={@role == :owner && member.user_id != @current_scope.user.id}
              type="button"
              class="btn"
              id={"remove-#{member.user_id}"}
              phx-click="remove"
              phx-value-user={member.user_id}
              data-confirm={gettext("Remove this member from the group?")}
            >
              {gettext("Remove")}
            </button>
          </div>
        </div>

        <div class="form-row" id="group-actions">
          <button
            type="button"
            class="btn"
            id="leave-group"
            phx-click="leave"
            data-confirm={gettext("Leave the group? You will no longer see the group's builds.")}
          >
            {gettext("Leave group")}
          </button>
          <button
            :if={@role == :owner}
            type="button"
            class="btn"
            id="delete-group"
            phx-click="delete"
            data-confirm={
              gettext("Delete the group? Builds with “group” visibility will become private.")
            }
          >
            {gettext("Delete group")}
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.fetch_group(socket.assigns.current_scope, id) do
      {:ok, group} ->
        {:ok,
         socket
         # Задача 4.2: с хвостом редакции, как у всех страниц; до неё хвоста
         # не было вовсе (вкладка кончалась заготовочным « · Phoenix Framework»).
         |> assign(:page_title, Edition.page_title("#{group.name} · #{gettext("Groups")}"))
         |> load(group)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That group doesn't exist or you're not a member of it."))
         |> push_navigate(to: ~p"/groups")}
    end
  end

  @impl true
  def handle_event("rotate", _params, socket) do
    case Accounts.rotate_invite_code(socket.assigns.current_scope, socket.assigns.group) do
      {:ok, group} ->
        {:noreply, socket |> put_flash(:info, gettext("Code changed.")) |> load(group)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Only the owner can change the code."))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Couldn't change the code. Try again."))}
    end
  end

  def handle_event("remove", %{"user" => user_id}, socket) do
    %{current_scope: scope, group: group} = socket.assigns

    with {:ok, member} <- find_member(socket, user_id),
         :ok <- Accounts.remove_member(scope, group, member.user) do
      {:noreply, socket |> put_flash(:info, gettext("Member removed.")) |> load(group)}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Only the owner can remove members."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Couldn't remove the member."))}
    end
  end

  def handle_event("leave", _params, socket) do
    case Accounts.leave_group(socket.assigns.current_scope, socket.assigns.group) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("You left the group."))
         |> push_navigate(to: ~p"/groups")}

      # Передать владение контекст пока не умеет, поэтому и не обещаем: единственный
      # доступный выход для последнего владельца — удалить группу.
      {:error, :last_owner} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "You're the last owner — the group would be left without an admin. You can delete it instead."
           )
         )}

      {:error, :not_a_member} ->
        {:noreply, push_navigate(socket, to: ~p"/groups")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Accounts.delete_group(socket.assigns.current_scope, socket.assigns.group) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Group deleted. Its builds are now private."))
         |> push_navigate(to: ~p"/groups")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Only the owner can delete the group."))}
    end
  end

  defp load(socket, group) do
    scope = socket.assigns.current_scope
    {:ok, members} = Accounts.list_group_members(scope, group)

    socket
    |> assign(:group, group)
    |> assign(:members, members)
    |> assign(:role, Accounts.group_role(scope, group))
  end

  # The id from the click is matched against the membership list we already
  # read, so a hand-typed user id can only ever name somebody in this group.
  defp find_member(socket, user_id) do
    case Enum.find(socket.assigns.members, &(&1.user_id == user_id)) do
      nil -> :error
      member -> {:ok, member}
    end
  end

  @doc false
  def role_label(:owner), do: pgettext("group role", "owner")
  def role_label(:member), do: pgettext("group role", "member")
  def role_label(_other), do: pgettext("group role", "not a member")

  # «· вы владелец» под заголовком — предложение целиком, а не «вы» + роль:
  # по-английски роль идёт с артиклем (задача 4.48).
  defp you_are(:owner), do: gettext("you're the owner")
  defp you_are(:member), do: gettext("you're a member")
  defp you_are(_other), do: gettext("you're not a member")
end
