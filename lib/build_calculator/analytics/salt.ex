defmodule BuildCalculator.Analytics.Salt do
  @moduledoc """
  Соль дня для хеша посетителя (задача 4.54) — только в памяти.

  Одна соль на день UTC: 32 случайных байта, выдаются при первом спросе
  за день и заменяются при первом спросе следующего. Прежняя соль не хранится
  нигде — после полуночи хеши вчерашнего дня нельзя ни пересчитать, ни
  сопоставить с сегодняшними, и потому баннер согласия не нужен (cookie нет,
  идентификатора, живущего дольше дня, нет).

  Чтение — из ETS без похода в процесс; процесс нужен только смене соли:
  два запроса в первую секунду дня не заведут двух солей. День не идёт назад:
  запрос с прошлым днём (часы, перевод времени) получает нынешнюю соль
  и нынешний день, а не новую соль для вчера.
  """
  use GenServer

  @table __MODULE__

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Соль на сегодня (UTC) — вместе с днём, которому она принадлежит."
  @spec current() :: {Date.t(), binary()}
  def current do
    today = Date.utc_today()

    case :ets.lookup(@table, :salt) do
      [{:salt, ^today, salt}] -> {today, salt}
      _stale_or_missing -> GenServer.call(__MODULE__, {:current, today})
    end
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    {:ok, nil}
  end

  @impl true
  def handle_call({:current, today}, _from, state) do
    stored =
      case :ets.lookup(@table, :salt) do
        [{:salt, day, salt}] -> {day, salt}
        [] -> nil
      end

    reply =
      case decide(stored, today) do
        {:keep, current} ->
          current

        :rotate ->
          salt = :crypto.strong_rand_bytes(32)
          :ets.insert(@table, {:salt, today, salt})
          {today, salt}
      end

    {:reply, reply, state}
  end

  @doc """
  Оставить ли соль `stored` (`{день, соль}` или `nil`) на день `today`.

  Новая соль — только когда её нет или она за прошлый день; соль за тот же
  или более поздний день остаётся: день не идёт назад.
  """
  @spec decide({Date.t(), binary()} | nil, Date.t()) :: {:keep, {Date.t(), binary()}} | :rotate
  def decide(nil, _today), do: :rotate

  def decide({day, _salt} = stored, today) do
    if Date.compare(day, today) == :lt, do: :rotate, else: {:keep, stored}
  end
end
