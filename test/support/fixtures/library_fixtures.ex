defmodule BuildCalculator.LibraryFixtures do
  @moduledoc """
  Test helpers for `BuildCalculator.Library`.

  Codes are produced with the real codec rather than by hand: the denormalised
  columns are read back out of a code, so a fake one would test nothing.
  """

  import Ecto.Query

  alias BuildCalculator.Encoding
  alias BuildCalculator.Library
  alias BuildCalculator.Library.Build
  alias BuildCalculator.Repo
  alias BuildCalculator.Rules.Build, as: Character

  @doc """
  A real build code.

  `:levels` is the class ladder, one entry per character level — `[:fighter,
  :fighter, :rogue]` is a Fighter 2 / Rogue 1.
  """
  def build_code(opts \\ []) do
    Character.new(
      ruleset_version: Keyword.get(opts, :ruleset_version, "siala_41"),
      race: Keyword.get(opts, :race, :human),
      levels: Keyword.get(opts, :levels, List.duplicate(:fighter, 10))
    )
    |> Encoding.encode()
  end

  def build_fixture(scope, attrs \\ %{}) do
    attrs = Map.new(attrs)

    attrs =
      Map.merge(
        %{
          name: "Build #{System.unique_integer([:positive])}",
          code: Map.get(attrs, :code) || build_code(),
          visibility: :private
        },
        attrs
      )

    {:ok, build} = Library.create_build(scope, attrs)
    build
  end

  @doc """
  Backdates a build's `updated_at`.

  Feeds order by it, and every fixture in a test lands in the same second
  otherwise — which tests the id tiebreaker but not the ordering.
  """
  def touch(%Build{id: id} = build, %DateTime{} = at) do
    at = DateTime.truncate(at, :second)

    Repo.update_all(from(b in Build, where: b.id == type(^id, :binary_id)),
      set: [updated_at: at]
    )

    %Build{build | updated_at: at}
  end
end
