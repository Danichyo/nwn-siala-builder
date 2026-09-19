defmodule BuildCalculator.Repo.Migrations.CreateUserGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      # Joining is by code, not by an owner picking people out of a user list:
      # that would need a "find user by email" call, and email enumeration is
      # exactly what a private community does not want.
      add :invite_code, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # The code is the credential, so it has to be unique, and the join path is
    # `where invite_code = ?`.
    create unique_index(:groups, [:invite_code])

    create table(:group_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # "owner" | "member". Two roles cover everything the group has to decide:
      # who may rotate the invite code, rename the group and delete it.
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime)
    end

    # One membership per person per group, and the exact shape every visibility
    # check probes: `where group_id = ? and user_id = ?`.
    create unique_index(:group_members, [:group_id, :user_id])
    # "which groups am I in" — the group feed picker, and the FK index.
    create index(:group_members, [:user_id])
  end
end
