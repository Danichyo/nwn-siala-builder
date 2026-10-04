defmodule BuildCalculator.GameFiles.KeyBifTest do
  @moduledoc """
  KEY V1 / BIFF V1 на синтетических архивах, собранных в тесте (задача 4.5).
  Настоящих файлов игры здесь нет: их нет ни в CI, ни в публичном репозитории.
  """
  use ExUnit.Case, async: true

  import BuildCalculator.GameFilesFixtures

  alias BuildCalculator.GameFiles.KeyBif

  describe "parse_key/1" do
    test "reads BIF names, resources, positions and the build date" do
      key =
        key_binary(
          ["data\\base_2da.bif", "data\\other.bif"],
          [{"classes", 2017, 0, 0}, {"feat", 2017, 0, 1}, {"nwscript", 2009, 1, 7}],
          year: 125,
          day: 278
        )

      assert {:ok, parsed} = KeyBif.parse_key(key)
      assert Enum.map(parsed.bifs, & &1.name) == ["data/base_2da.bif", "data/other.bif"]

      assert parsed.resources == [
               %{resref: "classes", type: 2017, bif: 0, index: 0},
               %{resref: "feat", type: 2017, bif: 0, index: 1},
               %{resref: "nwscript", type: 2009, bif: 1, index: 7}
             ]

      # Год от 1900, день от 1 января с нуля: 125/278 — это 6 октября 2025,
      # дата сборки nwn_retail.key в 89.8193.37-17 и дата её патчноута.
      assert parsed.built_on == ~D[2025-10-06]
    end

    test "a 16-byte resref is read whole, without a terminating NUL" do
      key = key_binary(["data\\a.bif"], [{"cls_savthr_wild1", 2017, 0, 0}])
      assert {:ok, %{resources: [%{resref: "cls_savthr_wild1"}]}} = KeyBif.parse_key(key)
    end

    test "a resource pointing past the file table is an error, not a guess" do
      key = key_binary(["data\\a.bif"], [{"classes", 2017, 3, 0}])
      assert {:error, {:bad_bif_index, 0, 3}} = KeyBif.parse_key(key)
    end

    test "other files and versions are refused by name" do
      assert {:error, :not_a_key_file} = KeyBif.parse_key("BIFFV1  ")

      assert {:error, {:unsupported_key_version, "V2  "}} =
               KeyBif.parse_key("KEY V2  " <> <<0::512>>)
    end

    test "a table cut short is an error" do
      key = key_binary(["data\\a.bif"], [{"classes", 2017, 0, 0}])

      assert {:error, :truncated_key_table} =
               KeyBif.parse_key(binary_part(key, 0, byte_size(key) - 5))
    end
  end

  describe "bif_resource/3" do
    setup do
      %{bif: bif_binary([{2017, "2DA V2.0\r\nfirst"}, {2009, "script"}, {2017, "second"}])}
    end

    test "returns the bytes at a position", %{bif: bif} do
      assert {:ok, "2DA V2.0\r\nfirst"} = KeyBif.bif_resource(bif, 0, 2017)
      assert {:ok, "second"} = KeyBif.bif_resource(bif, 2, 2017)
    end

    test "a type other than the one the key promised is refused", %{bif: bif} do
      assert {:error, {:resource_type_mismatch, 1, 2009}} = KeyBif.bif_resource(bif, 1, 2017)
    end

    test "a position past the table is refused", %{bif: bif} do
      assert {:error, {:no_such_resource, 3, 3}} = KeyBif.bif_resource(bif, 3, 2017)
    end

    test "an entry that does not carry its own position is refused" do
      # Вторая запись таблицы с id = 5 вместо 1: читатель не вправе отдать её байты
      # под чужим именем.
      <<head::binary-size(20), first::binary-size(16), _id::little-32, rest::binary>> =
        bif_binary([{2017, "a"}, {2017, "b"}])

      broken = head <> first <> <<5::little-32>> <> rest
      assert {:error, {:resource_id_mismatch, 1, 5}} = KeyBif.bif_resource(broken, 1, 2017)
    end

    test "other files and versions are refused by name" do
      assert {:error, :not_a_bif_file} = KeyBif.bif_resource("KEY V1  ", 0, 2017)

      assert {:error, {:unsupported_bif_version, "V1.1"}} =
               KeyBif.bif_resource("BIFFV1.1" <> <<0::96>>, 0, 2017)
    end
  end
end
