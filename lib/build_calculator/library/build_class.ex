defmodule BuildCalculator.Library.BuildClass do
  @moduledoc """
  One class of a build with the number of levels taken in it — `{:weapon_master, 7}`.

  Denormalised out of the build code so the search people already know from the
  wiki works: *"Weapon Master, between 5 and 10 levels"*. That is a range over a
  number, and a range wants a b-tree; a JSON column on `builds` could be indexed
  for `class = X` but not usefully for `levels BETWEEN N AND M`.

  `class_id` is the ruleset's class id as a string, not a foreign key: classes
  live in `priv/rules/`, not in the database, and a build saved under an older
  ruleset may name a class the current one has renamed.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BuildCalculator.Library.Build

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "build_classes" do
    field :class_id, :string
    field :levels, :integer

    belongs_to :build, Build
  end

  @doc false
  def changeset(%__MODULE__{} = class, attrs) do
    class
    |> cast(attrs, [:class_id, :levels])
    |> validate_required([:class_id, :levels])
    |> validate_number(:levels, greater_than: 0)
    |> unique_constraint([:build_id, :class_id])
  end
end
