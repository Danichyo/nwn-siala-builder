defmodule BuildCalculator.Analytics.Event do
  @moduledoc """
  Строка события калькулятора — `analytics.events` (задача 4.54).

  Пишется только `BuildCalculator.Analytics.record_event/3`: имя из закрытого
  списка `BuildCalculator.Analytics.events/0`, редакция и версия ruleset'а —
  и ничего о самом билде.
  """
  use Ecto.Schema

  @schema_prefix "analytics"

  schema "events" do
    field :day, :date
    field :edition, :string
    field :name, :string
    field :ruleset, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
