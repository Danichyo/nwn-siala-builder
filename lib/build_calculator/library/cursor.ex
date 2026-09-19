defmodule BuildCalculator.Library.Cursor do
  @moduledoc """
  The keyset cursor the feeds page with.

  Every feed is ordered `updated_at DESC, id DESC`, and a page asks for
  "everything strictly after this pair". That is one index seek regardless of
  how deep the reader has scrolled, which `OFFSET` is not: `OFFSET 10000` makes
  Postgres walk and discard ten thousand rows every time, and the deeper the
  feed grows the worse it gets.

  Keyset paging also does not skip or repeat rows when something is inserted
  while a reader is halfway down the list — with `OFFSET` a new row at the top
  shifts everything by one and the reader sees the same build twice.

  `id` is in the key because `updated_at` is only second-precision here
  (`timestamp_type: :utc_datetime`): several builds saved in the same second are
  normal, and without a tiebreaker the page boundary would be ambiguous and rows
  could be skipped.

  ## The cursor carries its direction

  A cursor is `{:after, key}` or `{:before, key}` — "the page below this row" or
  "the page above it". Going back is the same seek with *both* halves flipped:
  the comparison becomes `>` and the scan order becomes ascending, so the
  database still walks the same index from the boundary outward and still reads
  only one page. The rows then come back nearest-first and the caller reverses
  them, because the screen order never changes.

  Direction lives inside the cursor rather than beside it as a second query
  parameter so that a link is one opaque token either way: nothing outside this
  module has to know which way a given cursor points, and a URL cannot be
  half-updated into a cursor pointing one way with a direction saying the other.

  The cursor is opaque to callers but not secret — it is a position, not a
  capability. It is base64 only so it survives a query string intact.
  """

  alias BuildCalculator.Library.Build

  @type t :: String.t()
  @type key :: {DateTime.t(), Ecto.UUID.t()}
  @type direction :: :after | :before
  @type position :: {direction(), key()}

  @tags %{after: "a", before: "b"}
  @directions %{"a" => :after, "b" => :before}

  @doc """
  The cursor pointing just past `build`, in the given direction.

  `:after` is "the page that follows this row", `:before` is "the page that
  precedes it". Both are exclusive of the row itself, which is what makes
  a page boundary land in exactly one place.
  """
  @spec encode(direction(), Build.t() | key()) :: t()
  def encode(direction, %Build{updated_at: %DateTime{} = at, id: id}),
    do: encode(direction, {at, id})

  def encode(direction, {%DateTime{} = at, id}) when is_map_key(@tags, direction) do
    Base.url_encode64("#{@tags[direction]}:#{DateTime.to_unix(at)}:#{id}", padding: false)
  end

  @doc """
  Reads a cursor back.

  `nil` is the first page, not an error. Anything unreadable *is* an error and
  is not quietly treated as the first page: silently restarting the feed hides
  the bug and looks to the reader like the list jumped.
  """
  @spec decode(t() | nil) :: {:ok, position() | nil} | :error
  def decode(nil), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [tag, unix, id] <- String.split(raw, ":", parts: 3),
         {:ok, direction} <- Map.fetch(@directions, tag),
         {unix, ""} <- Integer.parse(unix),
         {:ok, at} <- DateTime.from_unix(unix),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {direction, {at, id}}}
    else
      _ -> :error
    end
  end

  def decode(_cursor), do: :error
end
