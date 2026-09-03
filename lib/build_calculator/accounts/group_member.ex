defmodule BuildCalculator.Accounts.GroupMember do
  @moduledoc """
  Membership of a user in a group, with a role.

  Two roles is the whole ladder: `:owner` may rotate the invite code, remove
  members and delete the group; `:member` may see the group's builds and leave.
  Anything finer would be inventing policy nobody asked for.

  This row is also what every build visibility check probes, so the
  `(group_id, user_id)` unique index is load-bearing rather than hygiene.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BuildCalculator.Accounts.{Group, User}

  @type t :: %__MODULE__{}

  @roles [:owner, :member]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "group_members" do
    field :role, Ecto.Enum, values: @roles, default: :member

    belongs_to :group, Group
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc "The two roles, in descending order of power."
  @spec roles() :: [atom()]
  def roles, do: @roles

  @doc """
  Changeset for a membership.

  `group_id` and `user_id` are set by the caller when building the struct, never
  cast: both decide who sees what, and a cast turns them into form input.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:group_id, :user_id],
      name: :group_members_group_id_user_id_index,
      message: "is already a member"
    )
    |> assoc_constraint(:group)
    |> assoc_constraint(:user)
  end
end
