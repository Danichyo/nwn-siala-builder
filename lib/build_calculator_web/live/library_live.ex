defmodule BuildCalculatorWeb.LibraryLive do
  @moduledoc """
  The build library: the public feed, your own builds, and one group's feed.

  One module, three `live_action`s, because the three differ only in which
  `BuildCalculator.Library` call opens the feed — the filters, the card and the
  paging are the same screen. The two signed-in sections sit in the
  `:require_authenticated_user` live_session and the public one in
  `:current_user`, which is why moving between them is a full page load.

  ## Authorisation is not repeated here

  Every list call takes `@current_scope` and the context composes
  `Query.visible_to/2` into the `where` before anything else. This module never
  re-checks and, more importantly, never works around it: a private build
  belonging to somebody else simply does not come back, and the group feed of a
  group you are not in is an empty page rather than an error.

  ## Paging is keyset, so there are no page numbers

  The context pages by cursor (`Library.Cursor`) and a cursor is a position, not
  an index — there is no total and no "page 7" to link to without a second full
  scan. So the UI offers «Назад», «Дальше» and «В начало», and the cursor
  travels in the URL, which keeps a page shareable and the browser's back button
  working.

  Both arrows are cursors from the page itself, never a remembered stack of
  where the reader has been: a stack would go stale the moment somebody edits a
  build and the feed reorders, and it would not survive the F5 that the URL
  survives. The button is drawn only when the context says that side exists.

  ## Filters

  `class` + `от/до` is the search the wiki trained people to run — *"Weapon
  Master, between 5 and 10 levels"*. With no class chosen the same range reads
  as the total character level instead, which is the other question people ask.
  Ids from the URL are resolved against the ruleset dictionaries
  (`BuildCalculator.Ids`), never `String.to_atom/1`-ed.

  Filtering by author is by id, reachable from an author's name on a card. There
  is deliberately no "search by email" box: that is an email-enumeration oracle,
  the same reason groups are joined by code rather than by adding people
  (`BuildCalculator.Accounts.Group`).
  """
  use BuildCalculatorWeb, :live_view

  import BuildCalculatorWeb.LibraryComponents

  alias BuildCalculator.Accounts
  alias BuildCalculator.Accounts.{Scope, User}
  alias BuildCalculator.Data
  alias BuildCalculator.Ids
  alias BuildCalculator.Library
  alias BuildCalculatorWeb.Builder.Labels

  @filter_keys ~w(q class lmin lmax race author)

  @impl true
  def mount(_params, _session, socket) do
    ruleset = Data.ruleset!()

    {:ok,
     socket
     |> assign(:page_title, "Библиотека билдов · Сиала")
     |> assign(:ruleset, ruleset)
     |> assign(:class_options, class_options(ruleset))
     |> assign(:race_options, race_options(ruleset))
     |> assign(:groups, groups(socket))
     |> assign(:group, nil)
     |> stream_configure(:builds, dom_id: &"build-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys) |> Map.reject(fn {_k, v} -> blank?(v) end)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:filter_form, to_form(filters))
      |> assign(:cursor, params["cursor"])

    case section(socket, params) do
      {:ok, socket} -> {:noreply, load(socket)}
      {:error, socket} -> {:noreply, socket}
    end
  end

  # A group id from the URL is resolved through `Accounts.fetch_group/2`, which
  # has membership in its `where` — an id alone never opens a private group.
  defp section(socket, %{"group_id" => id}) do
    case Accounts.fetch_group(socket.assigns.current_scope, id) do
      {:ok, group} ->
        {:ok, assign(socket, :group, group)}

      {:error, :not_found} ->
        {:error,
         socket
         |> put_flash(:error, "Такой группы нет или вы в ней не состоите.")
         |> push_navigate(to: ~p"/groups")}
    end
  end

  defp section(socket, _params), do: {:ok, assign(socket, :group, nil)}

  @impl true
  def handle_event("filter", params, socket) do
    filters = params |> Map.take(@filter_keys) |> Map.reject(fn {_k, v} -> blank?(v) end)

    # A new filter starts a new feed: keeping the old cursor would land the
    # reader in the middle of a list they have not seen the top of.
    {:noreply, push_patch(socket, to: feed_path(socket.assigns, filters, nil))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: feed_path(socket.assigns, %{}, nil))}
  end

  # ------------------------------------------------------------------ loading --

  defp load(socket) do
    case list(socket) do
      {:ok, page} ->
        socket
        |> stream(:builds, page.entries, reset: true)
        |> assign(:count, length(page.entries))
        |> assign(:next_cursor, page.next_cursor)
        |> assign(:previous_cursor, page.previous_cursor)
        |> assign(:list_error, nil)

      {:error, :bad_cursor} ->
        socket
        |> stream(:builds, [], reset: true)
        |> assign(:count, 0)
        |> assign(:next_cursor, nil)
        |> assign(:previous_cursor, nil)
        |> assign(:list_error, "Ссылка на страницу списка не читается — начните сначала.")
    end
  end

  defp list(socket) do
    %{current_scope: scope, live_action: action} = socket.assigns
    opts = opts(socket)

    case action do
      :public -> Library.list_public_builds(scope, opts)
      :mine -> Library.list_user_builds(scope, scope.user, opts)
      :group -> Library.list_group_builds(scope, socket.assigns.group, opts)
    end
  end

  defp opts(socket) do
    %{filters: filters, ruleset: ruleset, cursor: cursor} = socket.assigns
    class = Ids.get(ruleset, :classes, filters["class"])
    range = {number(filters["lmin"]), number(filters["lmax"])}

    [
      cursor: cursor,
      name: filters["q"],
      race: Ids.get(ruleset, :races, filters["race"]),
      author_id: author_id(filters["author"]),
      class: class
    ]
    # Only one of the two, and only when a bound was actually given: the context
    # reads `:class_levels` together with `:class` and ignores it otherwise.
    |> Keyword.put(if(class, do: :class_levels, else: :total_level), range(range))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp range({nil, nil}), do: nil
  defp range(bounds), do: bounds

  defp author_id(nil), do: nil

  defp author_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp number(nil), do: nil

  defp number(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _rest} when n > 0 -> n
      _ -> nil
    end
  end

  defp number(_value), do: nil

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  # ------------------------------------------------------------------- paths --

  @doc false
  def feed_path(assigns, filters, cursor) do
    query =
      filters
      |> Map.put("cursor", cursor)
      |> Map.reject(fn {_key, value} -> blank?(value) end)
      |> Enum.sort()

    base =
      case assigns.live_action do
        :public -> ~p"/library"
        :mine -> ~p"/library/mine"
        :group -> ~p"/library/group/#{assigns.group}"
      end

    if query == [], do: base, else: base <> "?" <> URI.encode_query(query)
  end

  # ----------------------------------------------------------------- options --

  defp class_options(ruleset) do
    ruleset.classes
    |> Enum.map(fn {id, _class} -> {Labels.class_name(ruleset, id), Atom.to_string(id)} end)
    |> Enum.sort()
  end

  # Siala's own name leads and the engine's name follows, because a Siala player
  # searching for a «Гном» means Dwarf (CLAUDE.md §4).
  defp race_options(ruleset) do
    ruleset.races
    |> Enum.map(fn {id, _race} ->
      {"#{Labels.race_ru(ruleset, id)} (#{Labels.race_en(ruleset, id)})", Atom.to_string(id)}
    end)
    |> Enum.sort()
  end

  # Публичная лента открыта гостю, а `list_groups/1` спрашивает про вошедшего:
  # у гостя групп нет и спрашивать не о чем. Раньше здесь стояла утиная
  # проверка `%{user: %{}}` — теперь скоуп есть всегда и различие ровно одно.
  defp groups(%{assigns: %{current_scope: %Scope{user: %User{}} = scope}}),
    do: Accounts.list_groups(scope)

  defp groups(_socket), do: []

  @doc false
  def section_title(:public), do: "Публичные билды"
  def section_title(:mine), do: "Мои билды"
  def section_title(:group), do: "Билды группы"

  @doc false
  def nav_active(:mine), do: :mine
  def nav_active(_action), do: :library

  @doc false
  def empty_hint(:public), do: "Публичных билдов с такими условиями нет."
  def empty_hint(:mine), do: "Соберите билд в конструкторе и нажмите «Сохранить»."
  def empty_hint(:group), do: "В группу ещё никто не поделился билдом."
end
