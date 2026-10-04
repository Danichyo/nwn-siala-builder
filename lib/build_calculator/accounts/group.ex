defmodule BuildCalculator.Accounts.Group do
  @moduledoc """
  A private circle of players.

  Groups exist for one reason: a build can be shared with "my group" instead of
  with the world (CLAUDE.md §1). There is no public group directory and no way
  to list a group you are not in — `Accounts.get_group/2` is scoped to
  membership, not just the group id.

  ## Why joining is by code

  The two options were "the owner adds people" and "the owner shares a code".
  Adding people needs a *find user by email* call, which is an email-enumeration
  oracle: anybody with an account could probe whether an address is registered.
  A code needs one column and no lookup of other people at all — the person
  joining identifies themselves. It is also how a shard community already works:
  the link gets pasted into a Discord channel that is already private.

  The code is a credential, so it is generated with `:crypto.strong_rand_bytes/1`
  and can be rotated (`Accounts.rotate_invite_code/2`) when it leaks.

  ## `caller_role` — роль того, кто спросил

  Роль живёт не у группы, а у пары «группа + спрашивающий», поэтому она
  виртуальная и её заполняет только тот запрос, который такую пару знает
  (`Accounts.list_groups/1`: join по членству там уже есть, роль приезжает
  тем же запросом и бесплатно).

  ⚠️ Значение по умолчанию — `:not_loaded`, а не `nil`. `nil` читался бы как
  «не участник», и это был бы уверенный ответ там, где ответа не спрашивали.
  Отличать «не знаю» от «не состоит» обязательно: группа, пришедшая
  из `fetch_group/2` или из `Repo.update`, роли не несёт.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BuildCalculator.Accounts.GroupMember

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "groups" do
    field :name, :string
    field :invite_code, :string

    # `:owner` | `:member` | `:not_loaded` — см. заголовок модуля.
    field :caller_role, :any, virtual: true, default: :not_loaded

    has_many :memberships, GroupMember, on_delete: :delete_all
    has_many :members, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or renaming a group.

  `invite_code` is never cast: it is a credential the server mints, not a field
  a form may set.
  """
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:invite_code)
  end

  @doc "A fresh invite code. 12 url-safe characters over 72 bits of entropy."
  @spec generate_invite_code() :: String.t()
  def generate_invite_code do
    9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
