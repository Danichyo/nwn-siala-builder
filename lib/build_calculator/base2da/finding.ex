defmodule BuildCalculator.Base2da.Finding do
  @moduledoc """
  Одно расхождение сверки базовых `.2da` с ванильным слоем (задача 4.5).

    * `area` / `subject` / `field` — где: область сверки, сущность (наш id или
      метка таблицы), поле. Вместе — стабильный `key/1`, по нему классификация
      и отчёт ссылаются на находку;
    * `base` — что говорит `.2da`, `base_at` — точная строка и колонка;
    * `ours` — что лежит у нас, `ours_at` — поле загруженного ruleset'а или файл;
    * `kind` — вид: `:a` наши данные неверны, `:b` разница представления,
      `:c` `.2da` этого не решает (правило в движке), `:d` источники спорят —
      нужен замер; `:e` — только у сверки Сиалы (задача 4.49): отличие
      объяснено вики Сиалы, замером или решением Dan; `nil`, пока не
      классифицировано;
    * `note` — почему этот вид, одной-двумя фразами.
  """

  @enforce_keys [:area, :subject, :field]
  defstruct [:area, :subject, :field, :base, :base_at, :ours, :ours_at, :kind, :note]

  @type kind :: :a | :b | :c | :d | :e | nil
  @type t :: %__MODULE__{
          area: atom(),
          subject: String.t(),
          field: String.t(),
          base: String.t(),
          base_at: String.t() | nil,
          ours: String.t(),
          ours_at: String.t() | nil,
          kind: kind(),
          note: String.t() | nil
        }

  @doc "Стабильный ключ находки: `область/сущность/поле`."
  @spec key(t()) :: String.t()
  def key(%__MODULE__{area: area, subject: subject, field: field}),
    do: "#{area}/#{subject}/#{field}"

  @doc "Значение в строку для отчёта: коротко, детерминированно."
  @spec show(term()) :: String.t()
  def show(nil), do: "—"
  def show(true), do: "да"
  def show(false), do: "нет"
  def show(value) when is_binary(value), do: value
  def show(value) when is_atom(value), do: Atom.to_string(value)
  def show(value) when is_number(value), do: to_string(value)
  def show(%MapSet{} = set), do: set |> Enum.to_list() |> show()
  def show([]), do: "∅"

  # Сортируются сами значения (числа — по величине), а не их строки.
  def show(list) when is_list(list) do
    list |> Enum.sort() |> Enum.map_join(", ", &show/1)
  end

  def show(map) when is_map(map) and map_size(map) == 0, do: "∅"

  def show(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> "#{show(k)}: #{show(v)}" end)
    |> Enum.sort_by(&sort_key/1)
    |> Enum.join(", ")
  end

  def show(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map_join(" ", &show/1)

  # Числа по возрастанию значения, а не строки: «2: …» раньше «10: …».
  defp sort_key(text) do
    case Integer.parse(text) do
      {n, _} -> {0, n, text}
      :error -> {1, 0, text}
    end
  end
end
