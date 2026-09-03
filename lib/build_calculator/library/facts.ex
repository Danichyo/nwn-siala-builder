defmodule BuildCalculator.Library.Facts do
  @moduledoc """
  The searchable facts of a build, read back out of its code.

  This is the one place that knows how a stored `code` becomes the denormalised
  columns. Everything it returns is rebuildable: drop the columns, run this over
  every row, and the index is back. That is the whole point of keeping the code
  as the source of truth (see `BuildCalculator.Library.Build`).

  Decoding also *validates*: a code that does not decode has no facts, and the
  context refuses the save rather than storing a row nobody can open.
  """

  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build, as: Character

  @typedoc """
  `class_levels` is sorted by class id so two saves of the same build produce
  the same rows in the same order.
  """
  @type t :: %{
          ruleset_version: String.t(),
          total_level: non_neg_integer(),
          race: String.t() | nil,
          class_levels: [%{class_id: String.t(), levels: pos_integer()}]
        }

  @doc """
  Derives the facts of a build code.

  Returns `:none` for a missing code — the caller has a `validate_required` for
  that and does not need a second complaint about it.
  """
  @spec derive(String.t() | nil) :: :none | {:ok, t()} | {:error, atom()}
  def derive(nil), do: :none
  def derive(""), do: :none

  def derive(code) when is_binary(code) do
    with {:ok, %{build: %Character{} = build}} <- Encoding.decode(code) do
      {:ok,
       %{
         ruleset_version: build.ruleset_version,
         total_level: Character.character_level(build),
         race: build.race && Atom.to_string(build.race),
         class_levels: class_levels(build)
       }}
    end
  end

  def derive(_code), do: {:error, :malformed}

  defp class_levels(%Character{} = build) do
    build
    |> Character.class_levels()
    |> Enum.sort_by(fn {class, _levels} -> Atom.to_string(class) end)
    |> Enum.map(fn {class, levels} -> %{class_id: Atom.to_string(class), levels: levels} end)
  end
end
