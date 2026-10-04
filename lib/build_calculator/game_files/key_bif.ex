defmodule BuildCalculator.GameFiles.KeyBif do
  @moduledoc """
  Reader of BioWare `KEY V1` / `BIFF V1` archives — the index and the storage of
  the base-game resources of NWN:EE (`data/nwn_base.key`, `data/nwn_retail.key`
  and the `.bif` files they point at). Task 4.5: the source of the vanilla `.2da`.

  Pure functions over binaries: no file I/O here, so the format is testable on
  a synthetic archive assembled in a test (`test/support/game_files_fixtures.ex`).

  ## KEY V1

  A 64-byte header — `"KEY "`, `"V1  "`, the number of BIF entries, the number of
  key entries, the offsets of both tables, the build year (counted from 1900) and
  the build day (counted from January 1st, zero-based), 32 reserved bytes. Then:

    * the file table, 12 bytes per BIF: size, offset of the name, name length,
      drive flags. Names are Windows paths relative to the install (`data\\x.bif`)
      and are returned here with forward slashes;
    * the key table, 22 bytes per resource: a 16-byte NUL-padded resref, the
      resource type (`2017` is `.2da`) and the resource id — `id >>> 20` is the
      BIF's position in the file table, `id &&& 0xFFFFF` the resource's position
      inside that BIF.

  ## BIFF V1

  A 20-byte header — `"BIFF"`, `"V1  "`, the number of variable-size resources,
  the number of fixed-size ones (always zero in NWN), the offset of the variable
  table. Each entry is 16 bytes: id, offset of the data, size, type.

  ⚠ Every read is **checked**, not trusted: an entry whose id does not carry the
  position asked for, or whose type is not the one the key promised, is an error
  rather than bytes handed out under a wrong name. A changed format has to fail
  loudly — the same stance `mix hak.extract` takes with the zstd magic.
  """

  import Bitwise

  @restype_2da 2017

  @type bif :: %{name: String.t(), size: non_neg_integer()}
  @type resource :: %{
          resref: String.t(),
          type: non_neg_integer(),
          bif: non_neg_integer(),
          index: non_neg_integer()
        }
  @type key :: %{built_on: Date.t() | nil, bifs: [bif()], resources: [resource()]}

  @doc "Resource type of a `.2da` table in KEY/BIF and ERF archives."
  @spec restype_2da() :: 2017
  def restype_2da, do: @restype_2da

  @doc """
  Parses a `KEY V1` file.

  `built_on` is the build date written into the header (`nil` when the two numbers
  do not form a date). Resrefs are returned as stored — the base game stores them
  in lower case.
  """
  @spec parse_key(binary()) :: {:ok, key()} | {:error, term()}
  def parse_key(
        <<"KEY ", "V1  ", bif_count::little-32, key_count::little-32, file_table::little-32,
          key_table::little-32, year::little-32, day::little-32, _reserved::binary-size(32),
          _rest::binary>> = bin
      ) do
    with {:ok, bifs} <- bifs(bin, file_table, bif_count),
         {:ok, resources} <- resources(bin, key_table, key_count, bif_count) do
      {:ok, %{built_on: built_on(year, day), bifs: bifs, resources: resources}}
    end
  end

  def parse_key(<<"KEY ", version::binary-size(4), _rest::binary>>),
    do: {:error, {:unsupported_key_version, version}}

  def parse_key(_other), do: {:error, :not_a_key_file}

  @doc """
  Returns the bytes of the resource at position `index` of a `BIFF V1` file,
  checking that the entry carries that position and the `expected_type`.
  """
  @spec bif_resource(binary(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  def bif_resource(
        <<"BIFF", "V1  ", var_count::little-32, _fixed_count::little-32, var_table::little-32,
          _rest::binary>> = bin,
        index,
        expected_type
      ) do
    entry_at = var_table + 16 * index

    cond do
      index >= var_count ->
        {:error, {:no_such_resource, index, var_count}}

      entry_at + 16 > byte_size(bin) ->
        {:error, {:truncated_table, index}}

      true ->
        <<id::little-32, offset::little-32, size::little-32, type::little-32>> =
          binary_part(bin, entry_at, 16)

        cond do
          (id &&& 0xFFFFF) != index -> {:error, {:resource_id_mismatch, index, id}}
          type != expected_type -> {:error, {:resource_type_mismatch, index, type}}
          offset + size > byte_size(bin) -> {:error, {:truncated_resource, index}}
          true -> {:ok, binary_part(bin, offset, size)}
        end
    end
  end

  def bif_resource(<<"BIFF", version::binary-size(4), _rest::binary>>, _index, _type),
    do: {:error, {:unsupported_bif_version, version}}

  def bif_resource(_other, _index, _type), do: {:error, :not_a_bif_file}

  defp bifs(bin, table, count) do
    if table + 12 * count > byte_size(bin) do
      {:error, :truncated_file_table}
    else
      0..(count - 1)//1
      |> Enum.reduce_while({:ok, []}, fn i, {:ok, acc} ->
        <<size::little-32, name_at::little-32, name_size::little-16, _drives::little-16>> =
          binary_part(bin, table + 12 * i, 12)

        if name_at + name_size > byte_size(bin) do
          {:halt, {:error, {:truncated_bif_name, i}}}
        else
          name =
            bin
            |> binary_part(name_at, name_size)
            |> until_nul()
            |> String.replace("\\", "/")

          {:cont, {:ok, [%{name: name, size: size} | acc]}}
        end
      end)
      |> case do
        {:ok, acc} -> {:ok, Enum.reverse(acc)}
        error -> error
      end
    end
  end

  defp resources(bin, table, count, bif_count) do
    if table + 22 * count > byte_size(bin) do
      {:error, :truncated_key_table}
    else
      0..(count - 1)//1
      |> Enum.reduce_while({:ok, []}, fn i, {:ok, acc} ->
        <<resref::binary-size(16), type::little-16, id::little-32>> =
          binary_part(bin, table + 22 * i, 22)

        bif = id >>> 20

        if bif >= bif_count do
          {:halt, {:error, {:bad_bif_index, i, bif}}}
        else
          resource = %{resref: until_nul(resref), type: type, bif: bif, index: id &&& 0xFFFFF}
          {:cont, {:ok, [resource | acc]}}
        end
      end)
      |> case do
        {:ok, acc} -> {:ok, Enum.reverse(acc)}
        error -> error
      end
    end
  end

  defp until_nul(bytes) do
    [head | _] = :binary.split(bytes, <<0>>)
    # Resrefs and BIF names are plain ASCII; latin-1 keeps any stray byte valid UTF-8.
    :unicode.characters_to_binary(head, :latin1)
  end

  defp built_on(year, day) do
    case Date.new(1900 + year, 1, 1) do
      {:ok, jan1} when day < 366 -> Date.add(jan1, day)
      _ -> nil
    end
  end
end
