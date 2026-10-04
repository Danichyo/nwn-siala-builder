defmodule BuildCalculator.Data.WeaponOffHandHakTest do
  @moduledoc """
  Доказательство таблицами для «какой рукой можно» на Сиале (задача 4.29) —
  сверка базовой `baseitems.2da` (`priv/base_2da/`) и хака шарда
  (`priv/hak/2da/`):

    * **`EquipableSlots`**: у 41 оружия справочника строки хака стоят на тех же
      позициях с теми же метками, и ячейка расходится с базовой ровно там, где
      у слоя Сиалы (`siala_41/weapon_off_hand.json`) есть запись — сегодня это
      одна строка, 111 `Whip` (`0x1C030` против `0x1C010`: шард добавил кнуту
      бит второй руки). Остальные 40 строк доезжают до Сиалы из ванильного
      файла законно;
    * **запрет движка** на цепы и моргенштерн в таблицах не лежит вовсе, и хак
      его не трогает: строки 4, 35 и 47 у хака — те же предметы на тех же
      позициях, с тем же `EquipableSlots`.

  🔴 Разойдётся хак — значит шард обновил таблицы, и Сиале нужна своя запись
  с `kind: "hak"`, а не молча унаследованная ванильная; тест упадёт первым.
  ⚠️ Совпадение таблиц — довод, а не замер: хак говорит, что видит КЛИЕНТ
  (`priv/hak/README.md`); серверные скрипты шарда в выгрузке не лежат.

  Нужны обе выгрузки. В публичном репозитории и в CI их нет — модуль
  пропускается, а не падает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Ids, Source}
  alias BuildCalculator.Data
  alias BuildCalculator.GameFiles.TwoDA

  @base Path.expand("../../../priv/base_2da", __DIR__)
  @hak Path.expand("../../../priv/hak/2da", __DIR__)

  unless File.regular?(Path.join(@base, "manifest.json")) and
           File.regular?(Path.join(@hak, "manifest.json")) do
    @moduletag skip:
                 "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                   "выгрузки: mix base2da.extract, mix hak.extract"
  end

  @vanilla_file "priv/rules/vanilla/weapon_off_hand.json"
  @siala_file "priv/rules/siala_41/weapon_off_hand.json"

  setup_all do
    {:ok, source} = Source.load(@base)
    manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
    bytes = File.read!(Path.join(@hak, "baseitems.2da"))
    vanilla = Data.ruleset!("vanilla")

    %{
      base: Source.table(source, "baseitems"),
      hak: TwoDA.parse!(bytes),
      hak_sha1: :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower),
      manifest_sha1: manifest["tables"]["baseitems"],
      rows: Ids.weapons(source, vanilla),
      vanilla: vanilla,
      siala: Data.ruleset!("siala_41"),
      vanilla_raw: @vanilla_file |> File.read!() |> Jason.decode!(),
      siala_raw: @siala_file |> File.read!() |> Jason.decode!()
    }
  end

  test "хак — та самая выгрузка, на которую ссылаются данные", context do
    assert context.hak_sha1 == context.manifest_sha1

    for %{"source" => source} <- context.siala_raw["weapons"] do
      assert source["sha1"] == context.hak_sha1
    end

    assert context.vanilla_raw["rule"]["hak"]["source"]["sha1"] == context.hak_sha1
    assert context.vanilla_raw["engine_barred"]["hak"]["source"]["sha1"] == context.hak_sha1
  end

  test "строки оружия у хака — те же предметы на тех же позициях", %{
    base: base,
    hak: hak,
    rows: rows
  } do
    assert map_size(rows) == 41

    for {id, row} <- rows do
      assert TwoDA.get(hak, row, "label") == TwoDA.get(base, row, "label"), "#{id}"
    end
  end

  # 🔴 Главное утверждение: запись слоя Сиалы есть ровно там, где хак говорит
  # иное, чем база, — ни одной лишней, ни одной недостающей.
  test "хак расходится с базой ровно там, где у Сиалы есть запись", %{
    base: base,
    hak: hak,
    rows: rows,
    siala_raw: siala_raw
  } do
    differ =
      for {id, row} <- Enum.sort(rows),
          TwoDA.get(hak, row, "EquipableSlots") != TwoDA.get(base, row, "EquipableSlots"),
          do: Atom.to_string(id)

    assert differ == ["whip"]
    assert Enum.map(siala_raw["weapons"], & &1["id"]) == differ
  end

  # Запись Сиалы — дословно ячейка хака: строка, метка, колонка, значение.
  test "запись Сиалы — ячейка хака", %{hak: hak, siala_raw: siala_raw} do
    for %{"source" => s} = record <- siala_raw["weapons"] do
      assert s["kind"] == "hak"
      assert s["table"] == "baseitems.2da"
      assert TwoDA.get(hak, s["row"], "label") == s["label"]
      assert TwoDA.get(hak, s["row"], s["column"]) == s["value"]
      assert record["equipable_slots"] == s["value"]

      # Цитата — начало строки хака, слово в слово.
      [line] =
        @hak
        |> Path.join("baseitems.2da")
        |> File.read!()
        |> String.split(~r/\r?\n/)
        |> Enum.filter(&String.starts_with?(&1, "#{s["row"]} "))

      assert String.starts_with?(line, record["quote"])
    end
  end

  # Загруженный ruleset Сиалы — ровно строки хака без бита второй руки. Маска —
  # из данных (`rule.off_hand_bit`), а не из теста: тест сверяет чтение, а не
  # повторяет его.
  test "Сиала: без бита второй руки ровно те, у кого его нет в хаке", %{
    hak: hak,
    rows: rows,
    siala: siala,
    vanilla_raw: vanilla_raw
  } do
    "0x" <> digits = vanilla_raw["rule"]["off_hand_bit"]
    bit = String.to_integer(digits, 16)

    without_bit =
      for {id, row} <- rows,
          Bitwise.band(TwoDA.int(hak, row, "EquipableSlots"), bit) == 0,
          into: MapSet.new(),
          do: id

    assert siala.wield.main_hand_only.slot == without_bit
  end

  test "ваниль: без бита второй руки ровно те, у кого его нет в базе", %{
    base: base,
    rows: rows,
    vanilla: vanilla,
    vanilla_raw: vanilla_raw
  } do
    "0x" <> digits = vanilla_raw["rule"]["off_hand_bit"]
    bit = String.to_integer(digits, 16)

    without_bit =
      for {id, row} <- rows,
          Bitwise.band(TwoDA.int(base, row, "EquipableSlots"), bit) == 0,
          into: MapSet.new(),
          do: id

    assert vanilla.wield.main_hand_only.slot == without_bit
  end

  # Запрет движка назван по ТИПУ предмета, а тип — строка таблицы: у хака цепы
  # и моргенштерн на прежних позициях, с прежними метками и ячейкой слотов.
  # ⚠️ Строки при этом не тождественны: у моргенштерна хак сменил `WeaponType`
  # (5 → 2, дробяще-колющий → дробящий), у всех трёх — кубики урона. Ни то,
  # ни другое руки не касается, и тест на них не смотрит.
  test "запрет движка доезжает: строки цепов и моргенштерна у хака прежние", %{
    base: base,
    hak: hak,
    rows: rows,
    siala: siala,
    vanilla: vanilla
  } do
    engine = vanilla.wield.main_hand_only.engine
    assert engine == siala.wield.main_hand_only.engine
    assert Enum.sort(engine) == [:heavy_flail, :light_flail, :morningstar]

    for id <- engine do
      row = Map.fetch!(rows, id)

      assert TwoDA.get(hak, row, "label") == TwoDA.get(base, row, "label"), "#{id}"

      assert TwoDA.get(hak, row, "EquipableSlots") == TwoDA.get(base, row, "EquipableSlots"),
             "#{id}"
    end

    assert Enum.sort(for id <- engine, do: Map.fetch!(rows, id)) == [4, 35, 47]
  end
end
