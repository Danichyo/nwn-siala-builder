defmodule BuildCalculator.Library.Page do
  @moduledoc """
  One page of a keyset-paginated feed.

  A page carries the two positions next to it: `next_cursor` is the page below,
  `previous_cursor` the page above. Either is `nil` when there is nothing on
  that side, which is what the buttons are drawn from — a feed knows its own
  edges even though it does not know its length.

  There is still no total count and no page number, and that is not an
  omission: a cursor feed has no way to know either without a second full scan,
  which is exactly the cost keyset paging exists to avoid. Two cursors do not
  change that — a cursor answers "what is adjacent to this row", never "how far
  along am I", so "страница 7 из 12" remains unavailable at any price the feed
  is willing to pay.
  """

  @type t :: %__MODULE__{
          entries: [struct()],
          next_cursor: String.t() | nil,
          previous_cursor: String.t() | nil
        }

  defstruct entries: [], next_cursor: nil, previous_cursor: nil

  @doc "Whether asking for another page would return anything."
  @spec more?(t()) :: boolean()
  def more?(%__MODULE__{next_cursor: cursor}), do: cursor != nil

  @doc "Whether there is a page above this one to go back to."
  @spec previous?(t()) :: boolean()
  def previous?(%__MODULE__{previous_cursor: cursor}), do: cursor != nil
end
