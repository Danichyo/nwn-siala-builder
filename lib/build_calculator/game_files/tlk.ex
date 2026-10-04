defmodule BuildCalculator.GameFiles.Tlk do
  @moduledoc """
  Reader of `TLK V3.0` string tables — `lang/en/data/dialog.tlk` of NWN:EE
  (task 4.5).

  The `.2da` tables name things by **string reference** (`Name` in `classes.2da`,
  `FEAT` in `feat.2da`), and the English text lives here. The base-table diff
  needs those names to match rows to our ids by the name the game prints rather
  than by guessing from a `Constant` column.

  Layout: a 20-byte header (`"TLK "`, `"V3.0"`, language id, string count, offset
  of the string data), then 40 bytes per entry — flags, a 16-byte sound resref,
  two variance fields, the offset and size of the text inside the string data and
  the sound length. Bit `0x1` of the flags says the entry has text.

  Text is Windows-1252; it is converted to UTF-8 here (`’` is `0x92`, and latin-1
  would turn it into a control character). A string reference with bit
  `0x01000000` set points at a module's custom table, never at this file, and
  resolves to `nil`.
  """

  import Bitwise

  defstruct [:language, :count, :strings_at, :bytes]

  @type t :: %__MODULE__{
          language: non_neg_integer(),
          count: non_neg_integer(),
          strings_at: non_neg_integer(),
          bytes: binary()
        }

  @custom_tlk 0x01000000

  # Windows-1252 differs from latin-1 only in 0x80..0x9F.
  @cp1252 %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  @doc "Parses the header; entries are read lazily by `string/2`."
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(
        <<"TLK ", "V3.0", language::little-32, count::little-32, strings_at::little-32,
          _rest::binary>> = bytes
      ) do
    if 20 + 40 * count > byte_size(bytes) do
      {:error, :truncated_entry_table}
    else
      {:ok, %__MODULE__{language: language, count: count, strings_at: strings_at, bytes: bytes}}
    end
  end

  def parse(<<"TLK ", version::binary-size(4), _rest::binary>>),
    do: {:error, {:unsupported_tlk_version, version}}

  def parse(_other), do: {:error, :not_a_tlk_file}

  @doc "Text of string reference `strref`, or `nil` when there is none."
  @spec string(t(), integer()) :: String.t() | nil
  def string(%__MODULE__{} = tlk, strref) when is_integer(strref) do
    cond do
      strref < 0 or (strref &&& @custom_tlk) != 0 or strref >= tlk.count ->
        nil

      true ->
        <<flags::little-32, _sound::binary-size(16), _volume::little-32, _pitch::little-32,
          offset::little-32, size::little-32, _length::binary-size(4)>> =
          binary_part(tlk.bytes, 20 + 40 * strref, 40)

        at = tlk.strings_at + offset

        if (flags &&& 0x1) == 0 or at + size > byte_size(tlk.bytes) do
          nil
        else
          tlk.bytes |> binary_part(at, size) |> decode()
        end
    end
  end

  defp decode(bytes) do
    for <<byte <- bytes>>, into: "", do: <<Map.get(@cp1252, byte, byte)::utf8>>
  end
end
