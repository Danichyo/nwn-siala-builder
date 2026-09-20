defmodule BuildCalculator.ShortLinks.ShortLink do
  @moduledoc """
  Одна короткая ссылка: ключ из шести символов и код билда за ним.

  ## Чего у неё нет

  Ни владельца, ни имени, ни видимости. Это не сохранённый билд
  (`BuildCalculator.Library.Build`), а именно **короткая форма ссылки**, и
  получает её тот, кто не регистрировался. Общее у двух таблиц одно, зато
  главное: источник истины — строка кода, а не колонки. Формат билда будет
  расти (заклинания, армори), а код версионируется сам.

  ## Ни одного поля из формы

  Формы здесь нет вообще: ключ генерирует контекст, код приходит из адресной
  строки конструктора уже закодированным, хэш и версия набора правил выводятся
  из кода. Поэтому и `cast/3` нет — только `change/2` с явными значениями
  (AGENTS.md: поля, которые ставятся программно, в `cast` не перечисляют).

  ## Дедупликация — по `code_hash`, а не по `code`

  Уникальный индекс прямо по `code` невозможен: код бывает до 4096 байт
  (`BuildCalculator.Encoding`), а строка b-tree-индекса в Postgres
  ограничена примерно 2704 байтами — такой индекс упал бы на длинном билде,
  то есть в проде и не сразу. Хэш длины не имеет.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "short_links" do
    field :key, :string
    field :code, :string
    field :code_hash, :binary
    field :ruleset_version, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Отпечаток кода, по которому идёт дедупликация.

  SHA-256, потому что длина у него постоянная, а у кода — нет.
  """
  @spec fingerprint(String.t()) :: binary()
  def fingerprint(code) when is_binary(code), do: :crypto.hash(:sha256, code)

  @doc """
  Changeset на вставку.

  Оба `unique_constraint` объявлены не для красоты: на них держатся два разных
  решения контекста. Совпавший `key` — повод сгенерировать другой и повторить;
  совпавший `code_hash` — признак того, что этот билд кто-то сократил
  параллельно с нами, и тогда мы обязаны вернуть **его** ключ, а не завести
  второй. Без объявления Ecto превратил бы оба в исключение, и различить их
  было бы нечем.
  """
  @spec insert_changeset(String.t(), binary(), String.t(), String.t()) :: Ecto.Changeset.t()
  def insert_changeset(code, code_hash, key, ruleset_version) do
    %__MODULE__{}
    |> change(%{
      code: code,
      code_hash: code_hash,
      key: key,
      ruleset_version: ruleset_version
    })
    |> validate_required([:code, :code_hash, :key, :ruleset_version])
    |> unique_constraint(:key)
    |> unique_constraint(:code_hash)
  end
end
