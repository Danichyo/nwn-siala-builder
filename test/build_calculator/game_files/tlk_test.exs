defmodule BuildCalculator.GameFiles.TlkTest do
  @moduledoc "TLK V3.0 на синтетической таблице строк (задача 4.5)."
  use ExUnit.Case, async: true

  import BuildCalculator.GameFilesFixtures

  alias BuildCalculator.GameFiles.Tlk

  setup do
    {:ok, tlk} =
      Tlk.parse(tlk_binary(["Bad Strref", nil, "Bull's Strength", <<"Cat", 0x92, "s Grace">>]))

    %{tlk: tlk}
  end

  test "text by string reference", %{tlk: tlk} do
    assert Tlk.string(tlk, 0) == "Bad Strref"
    assert Tlk.string(tlk, 2) == "Bull's Strength"
  end

  test "Windows-1252 becomes UTF-8, not a latin-1 control character", %{tlk: tlk} do
    assert Tlk.string(tlk, 3) == "Cat’s Grace"
  end

  test "no text, past the end, negative and custom-table references are nil", %{tlk: tlk} do
    assert Tlk.string(tlk, 1) == nil
    assert Tlk.string(tlk, 4) == nil
    assert Tlk.string(tlk, -1) == nil
    assert Tlk.string(tlk, 0x01000002) == nil
  end

  test "other files and a cut entry table are refused" do
    assert {:error, :not_a_tlk_file} = Tlk.parse("KEY V1  ")
    assert {:error, {:unsupported_tlk_version, "V4.0"}} = Tlk.parse("TLK V4.0" <> <<0::96>>)

    assert {:error, :truncated_entry_table} =
             Tlk.parse(binary_part(tlk_binary(["a", "b"]), 0, 40))
  end
end
