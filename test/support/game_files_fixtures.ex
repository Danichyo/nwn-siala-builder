defmodule BuildCalculator.GameFilesFixtures do
  @moduledoc """
  Сборщики синтетических архивов игры для тестов задачи 4.5: `KEY V1`,
  `BIFF V1`, `TLK V3.0`, текст `2DA V2.0` и целая «установка» NWN:EE
  в каталоге. Настоящих файлов игры в тестах нет и быть не должно — их нет
  ни в CI, ни в публичном репозитории.

  Форматы записаны по той же раскладке, что читает
  `BuildCalculator.GameFiles.KeyBif` / `Tlk`, но **независимо** от читателя:
  сборщик не зовёт ни одной его функции, иначе тест сверял бы код сам с собой.
  """

  import Bitwise

  @doc """
  `KEY V1`: `bifs` — список имён BIF (через `\\\\`, как в игре), `resources` —
  `{resref, type, bif_position, resource_position}`.
  """
  def key_binary(bifs, resources, opts \\ []) do
    year = Keyword.get(opts, :year, 124)
    day = Keyword.get(opts, :day, 56)
    header_size = 64
    file_table_at = header_size
    names_at = file_table_at + 12 * length(bifs)

    {names_blob, name_offsets} =
      Enum.reduce(bifs, {<<>>, []}, fn name, {blob, offsets} ->
        bytes = name <> <<0>>
        {blob <> bytes, offsets ++ [{names_at + byte_size(blob), byte_size(bytes)}]}
      end)

    key_table_at = names_at + byte_size(names_blob)

    file_table =
      for {_name, {offset, size}} <- Enum.zip(bifs, name_offsets), into: <<>> do
        <<1234::little-32, offset::little-32, size::little-16, 1::little-16>>
      end

    key_table =
      for {resref, type, bif, index} <- resources, into: <<>> do
        padded = resref <> :binary.copy(<<0>>, 16 - byte_size(resref))
        <<padded::binary, type::little-16, bif <<< 20 ||| index::little-32>>
      end

    <<"KEY ", "V1  ", length(bifs)::little-32, length(resources)::little-32,
      file_table_at::little-32, key_table_at::little-32, year::little-32, day::little-32,
      0::size(32 * 8)>> <> file_table <> names_blob <> key_table
  end

  @doc "`BIFF V1` из списка `{type, data}` — позиция в списке становится индексом."
  def bif_binary(resources) do
    var_table_at = 20
    data_at = var_table_at + 16 * length(resources)

    {table, data, _} =
      Enum.reduce(Enum.with_index(resources), {<<>>, <<>>, data_at}, fn {{type, bytes}, index},
                                                                        {table, data, at} ->
        entry = <<index::little-32, at::little-32, byte_size(bytes)::little-32, type::little-32>>
        {table <> entry, data <> bytes, at + byte_size(bytes)}
      end)

    <<"BIFF", "V1  ", length(resources)::little-32, 0::little-32, var_table_at::little-32>> <>
      table <> data
  end

  @doc "`TLK V3.0`: `nil` в списке — запись без текста."
  def tlk_binary(strings) do
    count = length(strings)
    strings_at = 20 + 40 * count

    {entries, blob} =
      Enum.reduce(strings, {<<>>, <<>>}, fn text, {entries, blob} ->
        {flags, bytes} = if is_nil(text), do: {0, <<>>}, else: {1, text}

        entry =
          <<flags::little-32, 0::size(16 * 8), 0::little-32, 0::little-32,
            byte_size(blob)::little-32, byte_size(bytes)::little-32, 0::little-32>>

        {entries <> entry, blob <> bytes}
      end)

    <<"TLK ", "V3.0", 0::little-32, count::little-32, strings_at::little-32>> <> entries <> blob
  end

  @doc "Текст `2DA V2.0` с CRLF, как в BIF базовой игры."
  def two_da(columns, rows) do
    lines =
      ["2DA V2.0", "", "      " <> Enum.join(columns, "   ")] ++
        for {row, index} <- Enum.with_index(rows) do
          Enum.join([Integer.to_string(index) | Enum.map(row, &cell/1)], "   ")
        end

    Enum.join(lines, "\r\n") <> "\r\n"
  end

  defp cell(nil), do: "****"
  defp cell(value) when is_integer(value), do: Integer.to_string(value)

  defp cell(value) when is_binary(value) do
    if String.contains?(value, " "), do: ~s("#{value}"), else: value
  end

  @doc """
  Синтетическая установка NWN:EE в `root`: `data/nwn_base.key` + `base_2da.bif`,
  по желанию `data/nwn_retail.key` + `ovr.bif` (перекрывает базу),
  `lang/en/data/dialog.tlk`, `databuild.txt` и патчноуты.

  `base` и `retail` — карты `resref => bytes`; `strings` — строки TLK по номеру.
  """
  def install!(root, opts) do
    base = Keyword.fetch!(opts, :base)
    retail = Keyword.get(opts, :retail, %{})
    strings = Keyword.get(opts, :strings, [])

    File.mkdir_p!(Path.join(root, "data"))
    write_key!(root, "nwn_base.key", "data\\base_2da.bif", "base_2da.bif", base, {124, 56})

    if retail != %{} do
      write_key!(root, "nwn_retail.key", "data\\ovr.bif", "ovr.bif", retail, {125, 278})
    end

    if Keyword.get(opts, :tlk, true) do
      File.mkdir_p!(Path.join(root, "lang/en/data"))
      File.write!(Path.join(root, "lang/en/data/dialog.tlk"), tlk_binary(strings))
    end

    File.write!(Path.join(root, "databuild.txt"), "r42\nMon Jan  1 00:00:00 UTC 2024\n")
    notes = Path.join(root, "lang/en/docs/patchnotes")
    File.mkdir_p!(notes)
    File.write!(Path.join(notes, "89.8193.37.md"), "## [89.8193.37] - 2025-01-01\n")
    File.write!(Path.join(notes, "89.8193.37-2.md"), "## [89.8193.37-2] - 2025-02-02\n")
    root
  end

  defp write_key!(root, key_name, bif_ref, bif_name, tables, {year, day}) do
    # Ещё один ресурс не-.2da в том же BIF: выгрузка обязана его пропустить.
    entries = Enum.sort(tables) ++ [{"nwscript", {2009, "void main() {}"}}]

    resources =
      entries
      |> Enum.with_index()
      |> Enum.map(fn
        {{resref, {type, _bytes}}, index} -> {resref, type, 0, index}
        {{resref, _bytes}, index} -> {resref, 2017, 0, index}
      end)

    payload =
      Enum.map(entries, fn
        {_resref, {type, bytes}} -> {type, bytes}
        {_resref, bytes} -> {2017, bytes}
      end)

    File.write!(Path.join([root, "data", bif_name]), bif_binary(payload))

    File.write!(
      Path.join([root, "data", key_name]),
      key_binary([bif_ref], resources, year: year, day: day)
    )
  end
end
