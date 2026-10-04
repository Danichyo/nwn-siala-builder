defmodule BuildCalculator.RateLimit do
  @moduledoc """
  Счётчики «не больше N за окно» в памяти узла (задача 4.75).

  Два потребителя, оба — против бота, а не против игрока:

    * `BuildCalculator.Analytics` — потолок строк аналитики на одного
      посетителя и на один адрес в день;
    * `BuildCalculator.ShortLinks` — потолок новых коротких ссылок с одного
      адреса в час.

  ## Устройство

  Одна таблица ETS (`:public`, атомарный `:ets.update_counter/4`): ключ —
  то, что считаем, ВМЕСТЕ с номером окна; значение — счёт и конец окна.
  Обращение не ходит в процесс — процесс только владеет таблицей и раз
  в минуту снимает строки окон, которые кончились. Новое окно — новый ключ,
  так что счёт «обнуляется» без участия процесса.

  ## Что теряется и почему так можно

    * **Перезапуск** (выкат, ночная перезагрузка сервера) обнуляет счёт —
      бот получает новое окно чуть раньше. Ради этого не стоит заводить
      таблицу в базе: потолки здесь страхуют от роста таблиц, а не держат
      точный счёт.
    * **Таблицы нет** (процесс перезапускается) — обращение пропускается
      (`:ok`): потолок — страховка, и его отказ не должен отнимать у игрока
      короткую ссылку или терять посещение.

  ## Адрес

  `address/1` — ключ адреса для счёта: IPv4 целиком, IPv6 — первые 64 бита
  (сеть `/64`): один хост IPv6 получает от провайдера всю `/64` и может менять
  адрес внутри неё сколько угодно, поэтому счёт по полному адресу IPv6
  обходится сменой адреса. Сам адрес нигде не хранится дольше окна и никуда
  не пишется.
  """
  use GenServer

  @table __MODULE__
  @purge_every :timer.minutes(1)

  @typedoc "Ключ адреса: IPv4 целиком или сеть IPv6 `/64`."
  @type address ::
          {:v4, :inet.ip4_address()} | {:v6, {0..65_535, 0..65_535, 0..65_535, 0..65_535}}

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Засчитывает одно обращение по ключу `key` — ключ обязан нести номер окна
  (`window/2`). `expires_at` — конец окна, Unix-секунды.

  `{:ok, count}`, пока счёт не больше `limit`; дальше `{:limited, count}` —
  счёт растёт и после потолка, так что первый отказ (`limit + 1`) виден.
  """
  @spec hit(term(), pos_integer(), integer()) ::
          {:ok, pos_integer()} | {:limited, pos_integer()}
  def hit(key, limit, expires_at) when is_integer(limit) and limit > 0 do
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0, expires_at})
    if count <= limit, do: {:ok, count}, else: {:limited, count}
  rescue
    ArgumentError -> {:ok, 1}
  end

  @doc """
  Окно длиной `seconds`, в которое попадает момент `now` (Unix-секунды):
  `{номер окна, конец окна}`. Окна выровнены по эпохе Unix — сутки
  начинаются в полночь UTC, как день соли аналитики.
  """
  @spec window(integer(), pos_integer()) :: {integer(), integer()}
  def window(now, seconds) when is_integer(now) and is_integer(seconds) and seconds > 0 do
    index = div(now, seconds)
    {index, (index + 1) * seconds}
  end

  @doc """
  Ключ адреса для счёта — или `nil`, если адреса нет.
  """
  @spec address(:inet.ip_address() | nil) :: address() | nil
  def address({_, _, _, _} = ip), do: {:v4, ip}
  def address({a, b, c, d, _, _, _, _}), do: {:v6, {a, b, c, d}}
  def address(_none), do: nil

  # ---------------------------------------------------------------- server --

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:purge, state) do
    purge(System.system_time(:second))
    schedule()
    {:noreply, state}
  end

  @doc false
  # Снимает строки окон, кончившихся к `now`. Публичная ради теста.
  def purge(now) do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
  end

  defp schedule, do: Process.send_after(self(), :purge, @purge_every)
end
