defmodule BuildCalculator.Base2da.Source do
  @moduledoc """
  Таблицы `.2da` в памяти — вход сверок `mix base2da.diff` (задача 4.5)
  и `mix hak2da.diff` (задача 4.49).

  Каждый файл сверяется с `sha1` из `manifest.json`: таблица, поправленная руками
  после выгрузки, — не источник, а наше мнение под чужим именем, и сверка на ней
  отказывается работать.

  ## Два вида источника

    * `load/1` — одна выгрузка: базовые таблицы игры (`priv/base_2da/`).
    * `load_layered/2` — **то, что исполняет клиент шарда**: таблица хака
      (`priv/hak/2da/`), если шард её прислал, иначе базовая. Так NWN ищет
      ресурс — хак перекрывает игру, а чего в хаке нет, движок берёт из своей
      установки. Откуда пришла каждая таблица — `origin/2`, отчёт печатает это
      рядом со строкой.

  ⚠ Имена строк у хака бывают из ЕГО `.tlk` (строки с номером от `0x01000000` —
  кастомный словарь шарда, русские имена рас и фитов), а такого словаря
  в выгрузке нет (`priv/hak/README.md`). Тогда `row_name/4` берёт имя
  **той же строки базовой таблицы, если у неё та же метка** — строка с той же
  меткой и тем же номером в обеих таблицах есть одна и та же сущность движка,
  переименованная шардом (расы Сиалы «пересобраны, а не переведены», а механика
  у них движковая). Строке, которой в базе нет (кастомные фиты 2001–2027),
  имя не выдумывается: её сопоставляют явной таблицей у сверки
  (`Base2da.Ids`, `row_overrides`), иначе она уходит в отчёт несопоставленной.
  """

  alias BuildCalculator.GameFiles.TwoDA

  defstruct dir: nil,
            tables: %{},
            names: %{},
            manifest: %{},
            origin: %{},
            base: nil,
            top: nil

  @type t :: %__MODULE__{
          dir: Path.t(),
          tables: %{String.t() => TwoDA.t()},
          names: %{integer() => String.t()},
          manifest: map(),
          origin: %{String.t() => :hak | :base},
          base: t() | nil,
          top: %{dir: Path.t(), manifest: map(), tables: [String.t()]} | nil
        }

  # Номера строк кастомного .tlk шарда: старший байт — 0x01 (формат TLK NWN).
  @custom_tlk 0x01000000

  @doc "Читает и проверяет выгрузку в каталоге `dir`."
  @spec load(Path.t()) :: {:ok, t()} | {:error, String.t()}
  def load(dir) do
    manifest_path = Path.join(dir, "manifest.json")

    with true <-
           File.regular?(manifest_path) ||
             {:error, "нет #{manifest_path} — сначала `mix base2da.extract`"},
         manifest = Jason.decode!(File.read!(manifest_path)),
         {:ok, tables} <- tables(dir, manifest["tables"]) do
      names =
        dir
        |> Path.join("dialog_names.json")
        |> File.read!()
        |> Jason.decode!()
        |> Map.new(fn {strref, text} -> {String.to_integer(strref), text} end)

      {:ok,
       %__MODULE__{
         dir: dir,
         tables: tables,
         names: names,
         manifest: manifest,
         origin: Map.new(tables, fn {name, _} -> {name, :base} end)
       }}
    end
  end

  @doc """
  Таблицы, которые исполняет клиент шарда: хак `top_dir` поверх базы `base_dir`.

  У манифеста хака (`mix hak.extract`) `tables` — карта «имя → sha1», у базового —
  «имя → описание с `sha1`»; читаются оба. Имена из `.tlk` — базовые (своего
  словаря хак в выгрузке не несёт, см. moduledoc).
  """
  @spec load_layered(Path.t(), Path.t()) :: {:ok, t()} | {:error, String.t()}
  def load_layered(top_dir, base_dir) do
    manifest_path = Path.join(top_dir, "manifest.json")

    with {:ok, base} <- load(base_dir),
         true <-
           File.regular?(manifest_path) ||
             {:error, "нет #{manifest_path} — сначала `mix hak.extract`"},
         manifest = Jason.decode!(File.read!(manifest_path)),
         {:ok, top} <- tables(top_dir, manifest["tables"]) do
      {:ok,
       %__MODULE__{
         dir: top_dir,
         tables: Map.merge(base.tables, top),
         names: base.names,
         manifest: base.manifest,
         origin: Map.merge(base.origin, Map.new(top, fn {name, _} -> {name, :hak} end)),
         base: base,
         top: %{dir: top_dir, manifest: manifest, tables: top |> Map.keys() |> Enum.sort()}
       }}
    end
  end

  defp tables(dir, entries) do
    Enum.reduce_while(entries || %{}, {:ok, %{}}, fn {name, meta}, {:ok, acc} ->
      path = Path.join(dir, name <> ".2da")
      bytes = File.read!(path)

      if sha1(bytes) == expected_sha1(meta) do
        {:cont, {:ok, Map.put(acc, name, TwoDA.parse!(bytes))}}
      else
        {:halt,
         {:error, "#{path} не совпадает с sha1 манифеста — поправлен руками? Перевыгрузи."}}
      end
    end)
  end

  defp expected_sha1(%{"sha1" => sha1}), do: sha1
  defp expected_sha1(sha1) when is_binary(sha1), do: sha1

  @doc "Таблица по имени без расширения, регистр не важен; `nil`, если её нет."
  @spec table(t(), String.t()) :: TwoDA.t() | nil
  def table(%__MODULE__{tables: tables}, name), do: Map.get(tables, String.downcase(name))

  @doc "Откуда таблица: `:hak` (прислал шард), `:base` (базовая игра) или `nil` — её нет."
  @spec origin(t(), String.t()) :: :hak | :base | nil
  def origin(%__MODULE__{origin: origin}, name), do: Map.get(origin, String.downcase(name))

  @doc "`true`, если источник слоёный (`load_layered/2`)."
  @spec layered?(t()) :: boolean()
  def layered?(%__MODULE__{base: base}), do: not is_nil(base)

  @doc "`sha1` таблицы из манифеста её слоя — для провенанса находки."
  @spec sha1_of(t(), String.t()) :: String.t() | nil
  def sha1_of(%__MODULE__{} = source, name) do
    key = String.downcase(name)

    case origin(source, key) do
      :hak -> source.top.manifest["tables"][key]
      :base -> get_in(base_manifest(source), ["tables", key, "sha1"])
      nil -> nil
    end
  end

  defp base_manifest(%__MODULE__{base: nil, manifest: manifest}), do: manifest
  defp base_manifest(%__MODULE__{base: base}), do: base.manifest

  @doc "Английский текст строки `strref` из dialog.tlk (`nil`, если его нет)."
  @spec name(t(), integer() | String.t() | nil) :: String.t() | nil
  def name(_source, nil), do: nil
  def name(%__MODULE__{names: names}, strref) when is_integer(strref), do: Map.get(names, strref)
  def name(source, strref) when is_binary(strref), do: name(source, TwoDA.to_int(strref))

  @doc """
  Имя строки `index` таблицы `table` — по колонке `column` с номером строки TLK.

  У слоёного источника строка кастомного `.tlk` шарда (или номер, которого нет
  в выгруженном словаре) получает имя той же строки базовой таблицы, если метка
  у строк одна (moduledoc); иначе `nil`.
  """
  @spec row_name(t(), String.t(), integer(), String.t()) :: String.t() | nil
  def row_name(source, table, index, column) do
    case table(source, table) do
      nil ->
        nil

      t ->
        strref = TwoDA.int(t, index, column)
        own = if is_integer(strref) and strref < @custom_tlk, do: name(source, strref)
        own || base_row_name(source, table, t, index, column)
    end
  end

  defp base_row_name(%__MODULE__{base: nil}, _table, _t, _index, _column), do: nil

  defp base_row_name(%__MODULE__{base: base}, table, t, index, column) do
    case table(base, table) do
      nil ->
        nil

      bt ->
        label = row_label(t, index)

        if label != nil and label == row_label(bt, index),
          do: row_name(base, table, index, column)
    end
  end

  # Метка строки: колонка называется по-разному в разных таблицах.
  defp row_label(table, index) do
    Enum.find_value(~w(LABEL Label label), &TwoDA.get(table, index, &1))
  end

  @doc "Сборка игры из манифеста — для шапки отчёта."
  @spec game(t()) :: map()
  def game(%__MODULE__{} = source), do: base_manifest(source)["game"] || %{}

  defp sha1(bytes), do: :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)
end
