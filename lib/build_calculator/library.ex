defmodule BuildCalculator.Library do
  @moduledoc """
  Saved builds: storing them, finding them, and deciding who may see them.

  ## What a saved build is

  A row here is a *build code* plus a name, plus enough denormalised columns to
  put it in a list and find it again. The code is the build (see
  `BuildCalculator.Library.Build`); the columns are a derived index that any
  migration may drop and rebuild with `refresh_facts/1`.

  ## Authorisation

  Every read composes `Query.visible_to/2` before anything else, so a build the
  caller may not see is never fetched — the check is in the `where`, not on the
  result. Writes work the same way: `update_build/3` re-reads the row with
  `user_id = <caller>` in the `where`, and `delete_build/2` puts it in the
  `DELETE` itself. `can_edit?/2` and friends exist for rendering buttons, not
  for guarding the operation.

  The caller is always a `BuildCalculator.Accounts.Scope` — reading the public
  feed does not need an account, but it does need a scope: гость это
  `%Scope{user: nil}`, а не `nil` (см. `BuildCalculator.Accounts.Scope`).
  """

  import Ecto.Query, warn: false

  alias BuildCalculator.Accounts.{Group, GroupMember, Scope, User}
  alias BuildCalculator.Library.{Build, BuildClass, Cursor, Facts, Page, Query}
  alias BuildCalculator.Repo
  alias Ecto.Multi

  @default_limit 20
  @max_limit 100

  @list_preloads [:user, :class_levels]
  @show_preloads [:user, :group, :class_levels]

  ## Reading

  @doc """
  Fetches one build, if the caller may see it.

  A private build belonging to somebody else is `{:error, :not_found}` and not
  `{:error, :forbidden}`: telling a stranger that a build exists but is not for
  them is itself a small leak.
  """
  @spec fetch_build(Scope.t(), Ecto.UUID.t()) :: {:ok, Build.t()} | {:error, :not_found}
  def fetch_build(scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Build{} = build <-
           Query.base()
           |> Query.visible_to(scope)
           |> where([build: b], b.id == ^id)
           |> preload(^@show_preloads)
           |> Repo.one() do
      {:ok, build}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  One page of builds the caller may see, newest edit first.

  Options are `Query.filter/2`'s, plus:

    * `:limit`  — page size, capped at #{@max_limit}, default #{@default_limit}
    * `:cursor` — the `next_cursor` or `previous_cursor` of an adjacent page

  A cursor knows which way it points (`Library.Cursor`), so both directions
  arrive here as the same option and the caller never has to say "backwards".

  An unreadable cursor is `{:error, :bad_cursor}` rather than a silent jump back
  to page one: the cursor comes from the URL, and a mangled URL should say so.
  """
  @spec list_builds(Scope.t(), keyword()) :: {:ok, Page.t()} | {:error, :bad_cursor}
  def list_builds(scope, opts \\ []) do
    with {:ok, position} <- Cursor.decode(Keyword.get(opts, :cursor)) do
      limit = limit(opts)

      rows =
        Query.base()
        |> Query.visible_to(scope)
        |> Query.filter(opts)
        |> Query.order(scan_order(position))
        |> Query.seek(position)
        |> limit(^(limit + 1))
        |> preload(^@list_preloads)
        |> Repo.all()

      {:ok, page(rows, limit, position)}
    else
      :error -> {:error, :bad_cursor}
    end
  end

  @doc """
  The public feed.

  Narrowed to `visibility: :public` on purpose — without it the caller's own
  private builds would show up in what reads like a public list.
  """
  @spec list_public_builds(Scope.t(), keyword()) :: {:ok, Page.t()} | {:error, :bad_cursor}
  def list_public_builds(scope \\ %Scope{}, opts \\ []) do
    list_builds(scope, Keyword.put(opts, :visibility, :public))
  end

  @doc """
  Builds by one author.

  Still visibility-scoped, so this doubles as both "my builds" and "somebody
  else's profile": the caller sees everything of their own and only the public
  and shared parts of anybody else's.
  """
  @spec list_user_builds(Scope.t(), %User{} | Ecto.UUID.t(), keyword()) ::
          {:ok, Page.t()} | {:error, :bad_cursor}
  def list_user_builds(scope, author, opts \\ []) do
    list_builds(scope, Keyword.put(opts, :author_id, author))
  end

  @doc """
  One group's feed.

  Non-members get an empty page rather than an error, because `visible_to/2`
  already excluded every row — there is no separate membership check to fail.
  """
  @spec list_group_builds(Scope.t(), Group.t() | Ecto.UUID.t(), keyword()) ::
          {:ok, Page.t()} | {:error, :bad_cursor}
  def list_group_builds(scope, group, opts \\ []) do
    list_builds(
      scope,
      opts |> Keyword.put(:group_id, group) |> Keyword.put(:visibility, :group)
    )
  end

  ## Writing

  @doc """
  Saves a new build for the caller.

  `user_id` comes from the scope and never from `attrs`. So does `group_id`:
  `attrs["group_id"]` is only ever *consulted*, and only accepted if the caller
  is actually in that group — otherwise anyone could publish into any group by
  posting its id.
  """
  @spec create_build(%Scope{}, map()) :: {:ok, Build.t()} | {:error, Ecto.Changeset.t()}
  def create_build(%Scope{user: %User{} = user}, attrs) do
    save(%Build{user_id: user.id}, user, attrs)
  end

  @doc """
  Updates a build the caller owns.

  The row is re-read with `user_id = <caller>` in the `where`; a build somebody
  else owns is `{:error, :not_found}` and never reaches the changeset.
  """
  @spec update_build(%Scope{}, Build.t(), map()) ::
          {:ok, Build.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  def update_build(%Scope{user: %User{} = user}, %Build{} = build, attrs) do
    case own_build(user, build.id) do
      {:ok, owned} -> save(owned, user, attrs)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Deletes a build the caller owns.

  Ownership is a clause of the `DELETE` itself, so there is no window between
  the check and the write.
  """
  @spec delete_build(%Scope{}, Build.t()) :: :ok | {:error, :not_found}
  def delete_build(%Scope{user: %User{id: user_id}}, %Build{id: id}) do
    {count, nil} =
      Repo.delete_all(
        from b in Build,
          where: b.id == type(^id, :binary_id) and b.user_id == type(^user_id, :binary_id)
      )

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  @doc "A changeset for a build form."
  @spec change_build(Build.t(), map()) :: Ecto.Changeset.t()
  def change_build(%Build{} = build, attrs \\ %{}), do: Build.changeset(build, attrs)

  @doc """
  Recomputes the denormalised columns from the stored code.

  This is what makes "the columns are only an index" true rather than a claim:
  a migration that adds or reshapes a searchable field can stream over `builds`
  and call this, with no risk to the codes themselves.
  """
  @spec refresh_facts(Build.t()) :: {:ok, Build.t()} | {:error, Ecto.Changeset.t()}
  def refresh_facts(%Build{} = build) do
    facts = Facts.derive(build.code)

    build
    |> Ecto.Changeset.change()
    |> Build.put_facts(facts)
    |> commit(facts)
  end

  ## Permissions
  #
  # These answer "should I render the button". They are not the guard — the
  # guard is the `where` clause inside `update_build/3` and `delete_build/2`.

  @doc "Whether the caller owns this build and may edit it."
  @spec can_edit?(Scope.t(), Build.t()) :: boolean()
  def can_edit?(%Scope{user: %User{id: user_id}}, %Build{user_id: user_id}), do: true

  # Именно `%Scope{}`, а не `_scope`: гость сюда приходит скоупом, и `nil`
  # от вызывающего — это ошибка, а не «нельзя». Молчаливое `false` на неё
  # выглядело бы как честный ответ.
  def can_edit?(%Scope{}, %Build{}), do: false

  @doc "Whether the caller may delete this build. Owner only, same as editing."
  @spec can_delete?(Scope.t(), Build.t()) :: boolean()
  def can_delete?(scope, %Build{} = build), do: can_edit?(scope, build)

  # ------------------------------------------------------------------ saving --

  defp save(%Build{} = build, %User{} = user, attrs) do
    changeset =
      build
      |> Build.changeset(attrs)
      |> put_group(user, attrs)

    facts = changeset |> Ecto.Changeset.get_field(:code) |> Facts.derive()

    changeset
    |> Build.put_facts(facts)
    |> commit(facts)
  end

  # The build row and its class rows move together: a build whose composition
  # is half-rewritten would answer class searches wrongly and nothing would say so.
  #
  # `no_opaque` because `Ecto.Multi.new/0` hands back a literal struct whose
  # `names` field dialyzer sees as a concrete empty `MapSet`, while `Multi.t()`
  # declares it as the opaque `MapSet.t()`. The mismatch is Ecto's own and shows
  # up in every project that pipes `Multi.new()` straight into a step; nothing
  # here reaches into anybody's opaque type. Scoped to this one function so a
  # real opacity violation elsewhere would still be caught.
  @dialyzer {:no_opaque, commit: 2}
  defp commit(changeset, facts) do
    Multi.new()
    |> Multi.insert_or_update(:build, changeset)
    |> Multi.delete_all(:clear_class_levels, fn %{build: saved} ->
      from c in BuildClass, where: c.build_id == type(^saved.id, :binary_id)
    end)
    |> Multi.insert_all(:class_levels, BuildClass, fn %{build: saved} ->
      class_rows(saved, facts)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{build: saved}} -> {:ok, Repo.preload(saved, @show_preloads, force: true)}
      {:error, :build, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  defp class_rows(%Build{id: build_id}, {:ok, facts}) do
    for %{class_id: class_id, levels: levels} <- facts.class_levels do
      %{id: Ecto.UUID.generate(), build_id: build_id, class_id: class_id, levels: levels}
    end
  end

  defp class_rows(%Build{}, _facts), do: []

  # `group_id` is authorisation data, so it is never cast. It is looked up here
  # against the caller's own memberships, and a group the caller does not belong
  # to fails the changeset instead of quietly widening who can read the build.
  #
  # The message is Russian and not the usual English changeset phrasing because
  # it is read by a person on a Russian screen (CLAUDE.md §4) — this one goes
  # straight to the form rather than through a label the web layer owns.
  defp put_group(changeset, %User{} = user, attrs) do
    case Ecto.Changeset.get_field(changeset, :visibility) do
      :group ->
        case member_group(user, attr(attrs, :group_id)) do
          {:ok, %Group{id: id}} ->
            Ecto.Changeset.put_change(changeset, :group_id, id)

          :error ->
            Ecto.Changeset.add_error(changeset, :group_id, group_error(attr(attrs, :group_id)))
        end

      _other ->
        Ecto.Changeset.put_change(changeset, :group_id, nil)
    end
  end

  # "No such group" and "not yours" deliberately answer the same thing: telling
  # a stranger that a group id exists but is not theirs turns the form into an
  # oracle for probing group ids, the same reason groups are joined by invite
  # code and never by being added (`BuildCalculator.Accounts.Group`).
  defp group_error(blank) when blank in [nil, ""],
    do: "Выберите группу: билд с видимостью «группа» должен её называть."

  defp group_error(_named), do: "Такой группы нет или вы в ней не состоите."

  defp member_group(%User{}, nil), do: :error
  defp member_group(%User{} = user, %Group{id: id}), do: member_group(user, id)

  defp member_group(%User{id: user_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Group{} = group <-
           Repo.one(
             from g in Group,
               join: m in GroupMember,
               on: m.group_id == g.id and m.user_id == type(^user_id, :binary_id),
               where: g.id == ^id
           ) do
      {:ok, group}
    else
      _ -> :error
    end
  end

  defp own_build(%User{id: user_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Build{} = build <-
           Repo.one(
             from b in Build,
               where: b.id == ^id and b.user_id == type(^user_id, :binary_id)
           ) do
      {:ok, build}
    else
      _ -> {:error, :not_found}
    end
  end

  # ------------------------------------------------------------------ paging --
  #
  # One row more than the page is asked for, always: its presence is the whole
  # proof that another page exists, and it costs one row rather than a second
  # `COUNT(*)` over the same filters.
  #
  # ⚠️ Both boundaries are built from the rows on *screen*, never from the
  # cursor we arrived on. Seeks are exclusive on both sides, so going back from
  # the cursor would land one row short and quietly hide a build at every page
  # boundary — the classic keyset off-by-one. `before(first row shown)` is the
  # page that ends exactly where this one begins.

  defp scan_order({:before, _key}), do: :asc
  defp scan_order(_position), do: :desc

  # The first page: nothing above it by definition.
  defp page(rows, limit, nil) do
    {entries, extra} = Enum.split(rows, limit)

    %Page{entries: entries, next_cursor: next_cursor(entries, extra), previous_cursor: nil}
  end

  # Forwards. We got here from somewhere, so there is a page above — even when
  # this one came back empty, which is what a bookmarked cursor looks like after
  # the rows it pointed past were deleted. Then the cursor itself is the only
  # position left to walk back from, and it is the right one.
  defp page(rows, limit, {:after, key}) do
    {entries, extra} = Enum.split(rows, limit)

    %Page{
      entries: entries,
      next_cursor: next_cursor(entries, extra),
      previous_cursor: Cursor.encode(:before, first_key(entries) || key)
    }
  end

  # Backwards. The rows arrived nearest-boundary first, so the surplus row is
  # the far one and dropping it keeps the page adjacent to where we came from;
  # then they flip, because the screen order never changes.
  defp page(rows, limit, {:before, _key}) do
    {entries, extra} = Enum.split(rows, limit)
    entries = Enum.reverse(entries)

    %Page{
      entries: entries,
      # The page we came from is still below us, whatever happened to it since.
      # With nothing above the cursor at all there is no row left to point at —
      # «В начало» stays, and it shows that row rather than skipping it.
      next_cursor: if(entries != [], do: Cursor.encode(:after, List.last(entries))),
      previous_cursor: if(extra != [], do: Cursor.encode(:before, List.first(entries)))
    }
  end

  defp next_cursor(_entries, []), do: nil
  defp next_cursor(entries, _extra), do: Cursor.encode(:after, List.last(entries))

  defp first_key([]), do: nil
  defp first_key([%Build{updated_at: at, id: id} | _rest]), do: {at, id}

  defp limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> case do
      n when is_integer(n) and n > 0 -> min(n, @max_limit)
      _ -> @default_limit
    end
  end

  # Forms hand us string keys, tests and internal callers hand us atoms.
  defp attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp attr(_attrs, _key), do: nil
end
