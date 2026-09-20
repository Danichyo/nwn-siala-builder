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
          <.link navigate={~p"/library/group/#{@group}"} id="group-feed">Билды группы</.link>
          · вы {role_label(@role)}
        </p>

        <h2 class="page-h2">Код приглашения</h2>
        <p class="page-sub">
          Кто знает код — вступает сам. Утёк — смените: старый перестанет работать.
        </p>
        <div class="form-row">
          <code class="invite-code" id="invite-code">{@group.invite_code}</code>
          <button
            :if={@role == :owner}
            type="button"
            class="btn"
            id="rotate-code"
            phx-click="rotate"
            data-confirm="Сменить код? Старый перестанет работать у всех, кому вы его дали."
          >
            Сменить код
          </button>
        </div>

        <h2 class="page-h2">Участники</h2>
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
              data-confirm="Убрать участника из группы?"
            >
              Убрать
            </button>
          </div>
        </div>

        <div class="form-row" id="group-actions">
          <button
            type="button"
            class="btn"
            id="leave-group"
            phx-click="leave"
            data-confirm="Выйти из группы? Билды группы перестанут быть видны."
          >
            Выйти из группы
          </button>
          <button
            :if={@role == :owner}
            type="button"
            class="btn"
            id="delete-group"
            phx-click="delete"
            data-confirm="Удалить группу? Билды с видимостью «группа» станут личными."
          >
            Удалить группу
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
         |> assign(:page_title, "#{group.name} · Группы")
         |> load(group)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Такой группы нет или вы в ней не состоите.")
         |> push_navigate(to: ~p"/groups")}
    end
  end

  @impl true
  def handle_event("rotate", _params, socket) do
    case Accounts.rotate_invite_code(socket.assigns.current_scope, socket.assigns.group) do
      {:ok, group} ->
        {:noreply, socket |> put_flash(:info, "Код сменён.") |> load(group)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Менять код может только владелец.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Код сменить не удалось, попробуйте ещё раз.")}
    end
  end

  def handle_event("remove", %{"user" => user_id}, socket) do
    %{current_scope: scope, group: group} = socket.assigns

    with {:ok, member} <- find_member(socket, user_id),
         :ok <- Accounts.remove_member(scope, group, member.user) do
      {:noreply, socket |> put_flash(:info, "Участник убран.") |> load(group)}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Убирать участников может только владелец.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Участника убрать не удалось.")}
    end
  end

  def handle_event("leave", _params, socket) do
    case Accounts.leave_group(socket.assigns.current_scope, socket.assigns.group) do
      :ok ->
        {:noreply,
         socket |> put_flash(:info, "Вы вышли из группы.") |> push_navigate(to: ~p"/groups")}

      # Передать владение контекст пока не умеет, поэтому и не обещаем: единственный
      # доступный выход для последнего владельца — удалить группу.
      {:error, :last_owner} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Вы последний владелец — группа осталась бы без администратора. Её можно удалить."
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
         |> put_flash(:info, "Группа удалена, её билды стали личными.")
         |> push_navigate(to: ~p"/groups")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Удалить группу может только владелец.")}
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
  def role_label(:owner), do: "владелец"
  def role_label(:member), do: "участник"
  def role_label(_other), do: "не участник"
end
