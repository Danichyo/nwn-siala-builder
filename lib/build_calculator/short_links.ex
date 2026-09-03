defmodule BuildCalculator.ShortLinks do
  @moduledoc """
  Короткая ссылка на билд — для того, кто не регистрировался.

  ## Зачем она, если ссылка уже есть

  Длинная ссылка **самодостаточна**: билд живёт внутри неё и не зависит ни от
  нашей базы, ни от нашего сервера — её раскодирует любая копия приложения
  (CLAUDE.md §9). Короткая это свойство отменяет: пропала запись — ссылка
  мертва, а живут такие ссылки в чужих Discord-логах годами.

  Поэтому короткая **дополняет** длинную, а не заменяет её. Длинная остаётся
  канонической и всегда доступна к копированию, а `/s/<key>` не рисует свой
  экран, а уводит на `/b/<code>` — то есть получатель оказывается на
  самодостаточном адресе, и именно он попадает в его буфер обмена, если он
  захочет поделиться дальше.

  ## Одинаковый код → тот же ключ

  Дедупликация здесь не экономия места, а поведение: повторное нажатие
  «поделиться» обязано вернуть ту же ссылку, а не завести вторую на тот же
  билд. Держит её уникальный индекс по `code_hash`, а не наш SELECT, — и это
  же снимает гонку: две одновременные вставки одного кода решает база,
  проигравшая читает победившую строку.

  ## Записи не чистятся

  Ни срока жизни, ни сборки мусора. Удалённая запись — это мёртвая ссылка
  в чьём-то сообщении двухлетней давности; строка весит около килобайта.

  ## Что здесь НЕ защищает от ботов

  Анонимная запись — открытый вектор для мусора, и настоящей защиты у неё
  ровно три:

    * **дедупликация** — бот, шлющий один и тот же билд, создаёт одну строку;
    * **код обязан раскодироваться** (`Facts.derive/1`): в таблицу не ляжет
      строка, которую потом никто не откроет;
    * **предел размера кода** — уже есть в `Encoding.decode/1`
      (`@max_code_bytes`), так что строка не может вырасти произвольно.

  ⚠️ Ограничения частоты по IP здесь нет **сознательно**, и причина не в лени:
  за Caddy приложение видит адрес прокси (`127.0.0.1`) у каждого посетителя —
  в `config/prod.exs` переписывается только `:x_forwarded_proto`, а
  `x-forwarded-for` не читает никто. Счётчик «по IP» сложил бы всех живых
  игроков в одно ведро, то есть был бы не ограничителем, а выключателем.
  Второй заслон живёт в конструкторе (предел на число разных кодов, сокращённых
  одним соединением) и честно называется тем, чем является: страховкой от
  зациклившегося клиента, а не от бота.
  """

  import Ecto.Query, warn: false

  alias BuildCalculator.Library.Facts
  alias BuildCalculator.Repo
  alias BuildCalculator.ShortLinks.ShortLink

  # 62^6 ≈ 5.7 × 10^10. При сотне тысяч записей вероятность совпадения на одну
  # вставку — около 2 × 10^(−6); пять попыток подряд не совпадут никогда.
  # Седьмой символ добавляется сменой этой цифры, и старые шестизначные ключи
  # продолжат открываться: читаем по значению, а не по длине.
  @key_length 6
  @max_attempts 5

  @alphabet "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  # 62 × 4 = 248. Байты 248..255 отбрасываются: без этого `rem 62` дал бы
  # первым шести символам алфавита лишний шанс.
  @unbiased_ceiling 248

  # Ключ приходит из адресной строки. Запрос параметризован, инъекции здесь
  # нет — отсекается заведомо чужое, чтобы не ходить в базу за «/s/<эссе>».
  @key_pattern ~r/\A[0-9A-Za-z]{1,16}\z/

  @typedoc """
  `:invalid_code` — код не раскодировался, такую строку хранить нельзя.
  `:unavailable` — ключ не удалось выдать (см. `shorten/2`); длинная ссылка
  при этом работает, так что отказ не теряет билд.
  """
  @type error :: :invalid_code | :unavailable

  @doc """
  Выдаёт короткую ссылку на код билда, повторно — ту же самую.

  Опция `:key_source` — генератор ключей, нулевой арности. Существует ради
  теста на коллизию: воспроизвести совпадение шестизначного ключа иначе нечем,
  а непроверенная ветка повтора — это ветка, которая однажды не сработает.
  """
  @spec shorten(term(), keyword()) :: {:ok, ShortLink.t()} | {:error, error()}
  def shorten(code, opts \\ [])

  def shorten(code, opts) when is_binary(code) do
    with {:ok, %{ruleset_version: version}} <- facts(code) do
      hash = ShortLink.fingerprint(code)

      case by_hash(hash) do
        %ShortLink{} = link -> {:ok, link}
        nil -> insert(code, hash, version, opts, 1)
      end
    end
  end

  def shorten(_code, _opts), do: {:error, :invalid_code}

  @doc """
  Находит код билда по ключу из адреса.

  `:error` и на неизвестный ключ, и на мусор вместо ключа: «такой ссылки нет» —
  один ответ на оба случая, разбирать за пользователя нечего.
  """
  @spec fetch(term()) :: {:ok, ShortLink.t()} | :error
  def fetch(key) when is_binary(key) do
    if Regex.match?(@key_pattern, key) do
      case Repo.get_by(ShortLink, key: key) do
        %ShortLink{} = link -> {:ok, link}
        nil -> :error
      end
    else
      :error
    end
  end

  def fetch(_key), do: :error

  # -------------------------------------------------------------- внутреннее --

  # ⚠️ Версия набора правил читается тем же самым способом, каким её читает
  # сохранённый билд, — `Facts.derive/1`. Второй разбор кода здесь был бы
  # вторым списком «какое поле билда считать версией», а два списка, написанных
  # руками, расходятся (баг 1.2 в бэклоге — ровно эта форма).
  defp facts(code) do
    case Facts.derive(code) do
      {:ok, facts} -> {:ok, facts}
      _none_or_error -> {:error, :invalid_code}
    end
  end

  defp by_hash(hash), do: Repo.get_by(ShortLink, code_hash: hash)

  defp insert(_code, _hash, _version, _opts, attempt) when attempt > @max_attempts do
    {:error, :unavailable}
  end

  defp insert(code, hash, version, opts, attempt) do
    key = next_key(opts)

    case Repo.insert(ShortLink.insert_changeset(code, hash, key, version)) do
      {:ok, %ShortLink{} = link} ->
        {:ok, link}

      {:error, %Ecto.Changeset{} = changeset} ->
        retry(changeset, code, hash, version, opts, attempt)
    end
  end

  # Две причины отказа, и они требуют разного.
  #
  # `key` — совпал ключ: генерируем другой и повторяем. Решение принял индекс,
  # а не наша проверка, поэтому окна между «свободен» и «занят» не бывает.
  #
  # `code_hash` — этот билд сократил кто-то параллельно с нами (последовательно
  # такое невозможно: `shorten/2` сначала смотрит по хэшу). Возвращаем **его**
  # ключ, а не заводим второй: «одинаковый код → тот же ключ» иначе перестало
  # бы быть правдой ровно в тот момент, когда двое нажали «поделиться» разом.
  defp retry(%Ecto.Changeset{errors: errors}, code, hash, version, opts, attempt) do
    cond do
      Keyword.has_key?(errors, :key) ->
        insert(code, hash, version, opts, attempt + 1)

      Keyword.has_key?(errors, :code_hash) ->
        raced(hash, code)

      true ->
        {:error, :unavailable}
    end
  end

  # ⚠️ Совпадение SHA-256 у двух разных кодов — не то событие, которое стоит
  # обслуживать, но и выдать чужой билд под нашим ключом нельзя: снаружи
  # подмена неотличима. Поэтому сверяется сам код, а не только его хэш.
  # Записей мы не удаляем, так что `nil` здесь означает не «строка исчезла»,
  # а что-то, о чём мы не знаем, — и тогда честнее отказать.
  defp raced(hash, code) do
    case by_hash(hash) do
      %ShortLink{code: ^code} = link -> {:ok, link}
      _other -> {:error, :unavailable}
    end
  end

  defp next_key(opts) do
    case Keyword.get(opts, :key_source) do
      nil -> random_key(@key_length, [])
      source when is_function(source, 0) -> source.()
    end
  end

  defp random_key(0, acc), do: List.to_string(acc)

  defp random_key(count, acc) do
    case :crypto.strong_rand_bytes(1) do
      <<byte>> when byte < @unbiased_ceiling ->
        random_key(count - 1, [:binary.at(@alphabet, rem(byte, byte_size(@alphabet))) | acc])

      _rejected ->
        random_key(count, acc)
    end
  end
end
