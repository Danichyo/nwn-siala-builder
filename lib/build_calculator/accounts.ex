defmodule BuildCalculator.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias BuildCalculator.Repo

  alias BuildCalculator.Accounts.{Group, GroupMember, Scope, User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `BuildCalculator.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `BuildCalculator.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Groups
  #
  # A group is private: there is no directory, no "browse groups", and every
  # read below is scoped to membership rather than to a bare id. Joining is by
  # invite code — see `BuildCalculator.Accounts.Group` for why that beat
  # "the owner adds people by email".

  @doc """
  Creates a group and makes the caller its owner.

  Both rows go in one transaction: a group with no owner could never be
  administered, and nothing else would repair it.
  """
  @spec create_group(%Scope{}, map()) :: {:ok, Group.t()} | {:error, Ecto.Changeset.t()}
  def create_group(%Scope{user: %User{} = user}, attrs) do
    changeset =
      %Group{invite_code: Group.generate_invite_code()}
      |> Group.changeset(attrs)

    Repo.transact(fn ->
      with {:ok, group} <- Repo.insert(changeset),
           {:ok, _membership} <- insert_membership(group, user, :owner) do
        {:ok, Repo.preload(group, :memberships)}
      end
    end)
  end

  @doc """
  Fetches a group the caller belongs to.

  Membership is part of the `where`, not a check on the result: an id alone is
  never enough to see a private group.
  """
  @spec fetch_group(%Scope{}, Ecto.UUID.t()) :: {:ok, Group.t()} | {:error, :not_found}
  def fetch_group(%Scope{user: %User{id: user_id}}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Group{} = group <-
           Repo.one(
             from g in Group,
               join: m in GroupMember,
               on: m.group_id == g.id and m.user_id == ^user_id,
               where: g.id == ^id
           ) do
      {:ok, group}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Groups the caller belongs to, alphabetically.

  Каждая группа приходит с заполненным `caller_role` — ролью **спросившего**,
  а не чьей-то вообще. Join по членству в запросе уже есть, поэтому роль стоит
  ноль дополнительных запросов; без неё экран групп добирал её отдельным
  `group_role/2` на каждую строку (N+1).

  Возвращаемый тип не изменился — это по-прежнему `[Group.t()]`, так что
  вызывающим, которым роль не нужна (`BuildFormLive`, `LibraryLive` — им нужен
  только список для селекта), не приходится ничего знать про неё.
  """
  @spec list_groups(%Scope{}) :: [Group.t()]
  def list_groups(%Scope{user: %User{id: user_id}}) do
    Repo.all(
      from g in Group,
        join: m in GroupMember,
        on: m.group_id == g.id and m.user_id == ^user_id,
        order_by: [asc: g.name, asc: g.id],
        select: %{g | caller_role: m.role}
    )
  end

  @doc """
  Joins the group whose invite code this is.

  Re-joining is not an error — the caller ends up a member either way, which is
  what they asked for.
  """
  @spec join_group(%Scope{}, String.t()) :: {:ok, Group.t()} | {:error, :invalid_code}
  def join_group(%Scope{user: %User{} = user}, invite_code) when is_binary(invite_code) do
    case Repo.get_by(Group, invite_code: invite_code) do
      nil ->
        {:error, :invalid_code}

      %Group{} = group ->
        case insert_membership(group, user, :member) do
          {:ok, _membership} -> {:ok, group}
          {:error, _changeset} -> {:ok, group}
        end
    end
  end

  def join_group(%Scope{user: %User{}}, _invite_code), do: {:error, :invalid_code}

  @doc """
  Leaves a group.

  The last owner may not leave: the group would keep existing with nobody able
  to administer it.
  """
  @spec leave_group(%Scope{}, Group.t()) :: :ok | {:error, :not_a_member | :last_owner}
  def leave_group(%Scope{user: %User{} = user}, %Group{} = group) do
    case group_role(user, group) do
      nil ->
        {:error, :not_a_member}

      :owner ->
        if owner_count(group) > 1,
          do: drop_membership(group, user),
          else: {:error, :last_owner}

      :member ->
        drop_membership(group, user)
    end
  end

  @doc "Removes someone else from a group. Owners only."
  @spec remove_member(%Scope{}, Group.t(), %User{}) ::
          :ok | {:error, :forbidden | :not_a_member | :last_owner}
  def remove_member(%Scope{user: %User{} = actor}, %Group{} = group, %User{} = member) do
    cond do
      group_role(actor, group) != :owner -> {:error, :forbidden}
      actor.id == member.id -> leave_group(Scope.for_user(actor), group)
      true -> drop_membership(group, member)
    end
  end

  @doc "Members of a group, with their roles. Members only."
  @spec list_group_members(%Scope{}, Group.t()) ::
          {:ok, [GroupMember.t()]} | {:error, :forbidden}
  def list_group_members(%Scope{user: %User{} = user}, %Group{} = group) do
    if group_role(user, group) do
      {:ok,
       Repo.all(
         from m in GroupMember,
           where: m.group_id == type(^group.id, :binary_id),
           order_by: [asc: m.role, asc: m.inserted_at],
           preload: [:user]
       )}
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Mints a new invite code, invalidating the old one. Owners only.

  The code carries a `unique_index`, so the changeset carries the matching
  `unique_constraint` — without it a collision would come back as an
  `Ecto.ConstraintError` raised from the database instead of `{:error,
  changeset}`, and the caller's error branch would be unreachable. A collision
  is vanishingly unlikely (72 bits of entropy) but "unlikely" is not "handled":
  the one path that turns it into a 500 is the one that skips the constraint.
  """
  @spec rotate_invite_code(%Scope{}, Group.t()) ::
          {:ok, Group.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def rotate_invite_code(%Scope{user: %User{} = user}, %Group{} = group) do
    if group_role(user, group) == :owner do
      group
      |> Ecto.Changeset.change(invite_code: Group.generate_invite_code())
      |> Ecto.Changeset.unique_constraint(:invite_code)
      |> Repo.update()
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Deletes a group. Owners only.

  Builds shared with the group are demoted to private first. The alternative —
  letting the foreign key cascade — would delete other people's builds, and
  nilifying the group would leave a row that claims group visibility and names
  no group. Failing closed is the only safe direction.

  The demotion is written against the table rather than `Library.Build` on
  purpose: `Library` already depends on `Accounts`, and importing the schema
  back would make the two contexts mutually compile-dependent.
  """
  @spec delete_group(%Scope{}, Group.t()) :: :ok | {:error, :forbidden}
  def delete_group(%Scope{user: %User{} = user}, %Group{} = group) do
    if group_role(user, group) == :owner do
      {:ok, :ok} =
        Repo.transact(fn ->
          {_count, nil} =
            Repo.update_all(
              from(b in "builds", where: b.group_id == type(^group.id, :binary_id)),
              set: [visibility: "private", group_id: nil]
            )

          Repo.delete!(group)
          {:ok, :ok}
        end)

      :ok
    else
      {:error, :forbidden}
    end
  end

  @doc "The caller's role in a group, or `nil` when they are not a member."
  @spec group_role(%User{} | %Scope{} | nil, Group.t()) :: :owner | :member | nil
  def group_role(%Scope{user: user}, %Group{} = group), do: group_role(user, group)
  def group_role(nil, %Group{}), do: nil

  def group_role(%User{id: user_id}, %Group{id: group_id}) do
    Repo.one(
      from m in GroupMember,
        where:
          m.group_id == type(^group_id, :binary_id) and
            m.user_id == type(^user_id, :binary_id),
        select: m.role
    )
  end

  @doc "Whether the caller belongs to the group at all."
  @spec group_member?(%User{} | %Scope{} | nil, Group.t()) :: boolean()
  def group_member?(user_or_scope, %Group{} = group), do: group_role(user_or_scope, group) != nil

  defp insert_membership(%Group{} = group, %User{} = user, role) do
    %GroupMember{group_id: group.id, user_id: user.id}
    |> GroupMember.changeset(%{role: role})
    |> Repo.insert()
  end

  defp drop_membership(%Group{id: group_id}, %User{id: user_id}) do
    {count, nil} =
      Repo.delete_all(
        from m in GroupMember,
          where:
            m.group_id == type(^group_id, :binary_id) and
              m.user_id == type(^user_id, :binary_id)
      )

    if count == 1, do: :ok, else: {:error, :not_a_member}
  end

  defp owner_count(%Group{id: group_id}) do
    Repo.aggregate(
      from(m in GroupMember,
        where: m.group_id == type(^group_id, :binary_id) and m.role == ^:owner
      ),
      :count
    )
  end
end
