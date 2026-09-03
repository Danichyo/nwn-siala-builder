defmodule BuildCalculator.Library.Build do
  @moduledoc """
  A saved build.

  ## The code is the build; the columns are an index

  The only field that carries the character is `code` — the versioned string
  `BuildCalculator.Encoding` produces (CLAUDE.md §9). Everything else
  about the game — the level ladder, the feats in their slots, the ranks bought
  at each level — stays inside it.

  That is a deliberate choice against a column per concept. The build format is
  going to grow: spells first, an armoury after that (CLAUDE.md §1). A column
  layout would need a migration for each of those and a rewrite of every row;
  the code needs neither, because it versions itself and old codes keep decoding
  through `decode/1`'s version dispatch.

  What the columns hold instead is only what a *list* or a *filter* needs:
  `total_level`, `race`, and the class composition in `BuildCalculator.Library.BuildClass`.
  All three are recomputed from `code` on every save, so they can never disagree
  with it, and a migration may drop and rebuild them at will — they are a
  derived index, not data.

  `ruleset_version` is not optional and is not taken from the form: a build is
  recomputed with the ruleset it was built in, never with the newest one
  (CLAUDE.md §5), so it is read out of the code itself.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BuildCalculator.Accounts.{Group, User}
  alias BuildCalculator.Library.BuildClass

  @type t :: %__MODULE__{}

  @visibilities [:private, :public, :group]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "builds" do
    field :name, :string
    field :description, :string
    field :code, :string
    field :ruleset_version, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :private

    # Derived from `code`. Never set from user input.
    field :total_level, :integer, default: 0
    field :race, :string

    belongs_to :user, User
    belongs_to :group, Group
    has_many :class_levels, BuildClass, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc "The three visibilities, in order of how much they expose."
  @spec visibilities() :: [atom()]
  def visibilities, do: @visibilities

  @doc """
  Casts what a person may actually type.

  `user_id` and `group_id` are absent on purpose: the first decides ownership
  and the second decides who can read the build, so neither may arrive from a
  form. The context sets them.
  """
  def changeset(%__MODULE__{} = build, attrs) do
    build
    |> cast(attrs, [:name, :description, :code, :visibility])
    |> validate_required([:name, :code, :visibility])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:description, max: 4000)
    |> validate_inclusion(:visibility, @visibilities)
    |> assoc_constraint(:user)
    |> assoc_constraint(:group)
    |> check_constraint(:visibility,
      name: :builds_group_visibility,
      message: "group builds must name a group"
    )
  end

  @doc """
  Writes the facts derived from `code` onto the changeset.

  `:none` means there was no code to read — `validate_required/2` has already
  said so and there is nothing to add. An `{:error, reason}` from the codec is
  reported on `:code`, so a build whose code does not decode cannot be stored:
  the row would be unopenable and the derived columns meaningless.
  """
  @spec put_facts(Ecto.Changeset.t(), :none | {:ok, map()} | {:error, atom()}) ::
          Ecto.Changeset.t()
  def put_facts(changeset, :none), do: changeset

  def put_facts(changeset, {:error, reason}) do
    add_error(changeset, :code, "is not a readable build code", reason: reason)
  end

  def put_facts(changeset, {:ok, facts}) do
    changeset
    |> put_change(:ruleset_version, facts.ruleset_version)
    |> put_change(:total_level, facts.total_level)
    |> put_change(:race, facts.race)
    |> validate_required([:ruleset_version])
  end
end
