defmodule BuildCalculator.Analytics.Visit do
  @moduledoc """
  Строка посещения — `analytics.visits` (задача 4.54).

  Пишется только `BuildCalculator.Analytics.record_visit/1`, одной вставкой
  без changeset'а: поля проверены там, и других путей в таблицу нет. Схема
  нужна отчёту (`BuildCalculator.Analytics.Report`) и вставке — для типов
  и префикса схемы Postgres.
  """
  use Ecto.Schema

  @schema_prefix "analytics"

  schema "visits" do
    field :day, :date
    field :edition, :string
    field :page, :string
    field :visitor, :binary
    field :referrer_host, :string
    field :utm_source, :string
    field :utm_medium, :string
    field :utm_campaign, :string
    field :utm_term, :string
    field :utm_content, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
