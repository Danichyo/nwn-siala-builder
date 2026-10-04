defmodule BuildCalculator.Data.WeaponSizeHakTest do
  @moduledoc """
  Размер оружия у Сиалы — её ручной слой оружия `siala_41/weapons.json`
  (задача 4.42).

  Хак шарда (`priv/hak/2da/baseitems.2da`) делает трезубец СРЕДНИМ: строка 95,
  `WeaponSize 3`. Базовая игра и Fandom зовут его большим (`4`, `size=large`).
  До задачи Сиала брала ванильный размер, и одноручная колонка хвата у трезубца
  (замер `AY1`: «Трезубец одноручный, причём его можно взять в левую руку тоже»)
  не сдвинула бы ничего: правило размеров делает хват только тяжелее, и `large`
  у человека вернул бы двуручный сам (`Rules.Wield`).

  Здесь две части:

    * **без выгрузок** — файл подключён и ложится на машинный слой по `id`; код
      таблицы переведён по документации колонки, а её цитата сверяется с кэшем
      Fandom; загруженная Сиала несёт размер слоя, ваниль — свой; сторожа
      загрузчика роняют сборку на битой записи;
    * **с выгрузками** (`priv/base_2da/`, `priv/hak/`) — запись есть ровно там,
      где хак расходится с базовой игрой по `WeaponSize`, и она — ячейка хака
      слово в слово. Размеры загруженной Сиалы совпадают с хаком у всех видов
      со строкой таблицы, кроме дротика: это спор ВАНИЛИ вида (d), и хак его
      не трогает. В публичном репозитории и в CI выгрузок нет — эта часть
      пропускается, а не падает.

  ⚠️ Хак — то, что исполняет КЛИЕНТ (`priv/hak/README.md`). Что сервер держит
  трезубец так же, подтверждает замер `AY1`, и только у человека.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BuildCalculator.Base2da.{Classification, Ids, Source}
  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules.{Build, Wield}

  @base Path.expand("../../../priv/base_2da", __DIR__)
  @hak Path.expand("../../../priv/hak/2da", __DIR__)
  @fandom Path.expand("../../../priv/wiki_cache/fandom", __DIR__)
  @siala_file "priv/rules/siala_41/weapons.json"

  setup_all do
    read = fn path -> path |> File.read!() |> Jason.decode!() end

    %{
      vanilla: Data.ruleset!("vanilla"),
      siala: Data.ruleset!("siala_41"),
      siala_raw: read.(@siala_file),
      vanilla_weapons: read.("priv/rules/vanilla/weapons.json")
    }
  end

  # Копия `priv/rules` с правкой ручного слоя — только через `TmpDir` (CLAUDE.md §7).
  defp copy_with(fun) do
    root = BuildCalculator.TmpDir.unique_path!("weapon_size_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, "siala_41/weapons.json")
    File.write!(path, path |> File.read!() |> Jason.decode!() |> fun.() |> Jason.encode!())
    root
  end

  defp load(root) do
    log = capture_log(fn -> send(self(), {:loaded, Loader.load!(root)}) end)
    assert is_binary(log)
    assert_received {:loaded, loaded}
    loaded
  end

  defp load_error(root) do
    capture_log(fn ->
      send(
        self(),
        {:raised,
         try do
           Loader.load!(root)
           nil
         rescue
           error in RuntimeError -> Exception.message(error)
         end}
      )
    end)

    assert_received {:raised, message}
    assert is_binary(message), "сборка не упала"
    message
  end

  defp set_trident_size(json, size) do
    update_in(json["weapons"], fn list ->
      for w <- list, do: if(w["id"] == "trident", do: Map.put(w, "size", size), else: w)
    end)
  end

  describe "ручной слой оружия Сиалы" do
    test "зарегистрирован по имени рядом с машинным — правка перекомпилирует ruleset" do
      assert "siala_41/weapons.json" in Loader.source_files()
      assert "siala_41/generated/weapons.json" in Loader.source_files()
    end

    # Код таблицы → ступень лестницы — документация колонки, и её цитата
    # стоит на странице Fandom дословно. Четыре кода ложатся на лестницу
    # справочника в её собственном порядке: перевод не наш.
    test "код WeaponSize переведён по документации колонки, цитата дословна", %{
      siala_raw: raw,
      vanilla_weapons: vanilla_weapons
    } do
      column = raw["_weapon_size_column"]
      assert column["table"] == "baseitems.2da"
      assert column["column"] == "WeaponSize"

      index = @fandom |> Path.join("_index.json") |> File.read!() |> Jason.decode!()
      page = Enum.find(index, &(&1["title"] == column["source"]["page"]))

      assert page["revid"] == column["source"]["revid"]
      assert @fandom |> Path.join(page["file"]) |> File.read!() =~ column["quote"]

      assert Enum.map(~w(1 2 3 4), &Map.fetch!(column["means"], &1)) ==
               vanilla_weapons["_grip"]["size_order"]
    end

    # Провенанс — ПО ПОЛЮ: запись сливается с машинной записью того же оружия,
    # у которой свои `status` и `conflicts` про хват, и общий `status` затёр бы их.
    test "запись: размер — перевод ячейки хака, провенанс по полю", %{siala_raw: raw} do
      column = raw["_weapon_size_column"]
      assert [_ | _] = raw["weapons"]

      for record <- raw["weapons"] do
        source = record["size_source"]

        assert source["kind"] == "hak", record["id"]
        assert source["table"] == column["table"], record["id"]
        assert source["column"] == column["column"], record["id"]
        assert record["size"] == Map.fetch!(column["means"], source["value"]), record["id"]
        assert record["size_status"] == "verified", record["id"]

        refute Map.has_key?(record, "status"), record["id"]
        refute Map.has_key?(record, "source"), record["id"]
      end

      assert %{"size_measured" => %{"kind" => "user", "case" => "AY1"}} =
               Enum.find(raw["weapons"], &(&1["id"] == "trident"))
    end

    # Слоение по id, проверенное загруженными ruleset'ами: у Сиалы размер слоя,
    # у ванили — свой, и больше расхождений между ними нет ни у одного вида.
    test "Сиала берёт размер слоя, ваниль — свой, у остальных видов они совпадают", %{
      vanilla: vanilla,
      siala: siala
    } do
      differ =
        for {id, weapon} <- Enum.sort(siala.weapons),
            weapon.size != vanilla.weapons[id].size,
            do: {id, vanilla.weapons[id].size, weapon.size}

      assert differ == [{:trident, :large, :medium}]
    end
  end

  describe "загрузчик" do
    # 🔴 Положительный контроль всей задачи: без рукописного слоя одноручная
    # колонка трезубца не значит ничего — правило размеров делает хват только
    # тяжелее, и ванильный `large` у человека возвращает двуручный.
    test "без файла Сиала берёт ванильный размер, и трезубец снова двуручный" do
      root = BuildCalculator.TmpDir.unique_path!("weapon_size_")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      File.rm!(Path.join(root, "siala_41/weapons.json"))

      siala = load(root)["siala_41"]
      human = Build.new(race: :human)

      assert siala.weapons[:trident].size == :large
      assert siala.weapons[:trident].stated_grip == :one_handed
      assert Wield.grip(human, :trident, siala) == :two_handed

      # А с файлом — одноручный: сдвинул его именно размер.
      assert Wield.grip(human, :trident, Data.ruleset!("siala_41")) == :one_handed
    end

    test "запись про оружие, которого нет, роняет сборку" do
      root =
        copy_with(fn json ->
          update_in(json["weapons"], &(&1 ++ [%{"id" => "no_such_weapon", "size" => "medium"}]))
        end)

      assert load_error(root) =~ "no_such_weapon"
    end

    test "размер вне лестницы роняет сборку" do
      root = copy_with(&set_trident_size(&1, "huge"))

      assert load_error(root) =~ "not rungs of the size ladder"
    end

    # Код таблицы вместо слова: `3` — это `WeaponSize`, а не ступень, и перевести
    # его — дело записи с документацией колонки, а не загрузчика.
    test "код таблицы вместо слова роняет сборку" do
      root = copy_with(&set_trident_size(&1, 3))

      assert load_error(root) =~ "written as a word"
    end
  end

  describe "сверка с хаком и базовой игрой" do
    unless File.regular?(Path.join(@base, "manifest.json")) and
             File.regular?(Path.join(@hak, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                       "выгрузки: mix base2da.extract, mix hak.extract"
    end

    setup %{vanilla: vanilla} do
      {:ok, source} = Source.load(@base)
      bytes = File.read!(Path.join(@hak, "baseitems.2da"))
      manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

      %{
        base: Source.table(source, "baseitems"),
        hak: TwoDA.parse!(bytes),
        hak_lines: String.split(bytes, ~r/\r?\n/),
        hak_sha1: :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower),
        manifest_sha1: manifest["tables"]["baseitems"],
        rows: Ids.weapons(source, vanilla)
      }
    end

    # Ступень лестницы по ячейке таблицы — переводом из самой записи Сиалы,
    # а не из теста: тест сверяет чтение, а не повторяет его.
    defp table_size(table, row, raw) do
      raw["_weapon_size_column"]["means"]
      |> Map.fetch!(TwoDA.get(table, row, "WeaponSize"))
      |> String.to_existing_atom()
    end

    # Где размер ruleset'а расходится с таблицей: `[{id, таблица, у нас}]`.
    defp size_mismatches(ruleset, table, rows, raw) do
      rows
      |> Enum.sort()
      |> Enum.map(fn {id, row} -> {id, table_size(table, row, raw), ruleset.weapons[id].size} end)
      |> Enum.reject(fn {_id, in_table, ours} -> in_table == ours end)
    end

    test "хак — та самая выгрузка, на которую ссылаются данные", context do
      assert context.hak_sha1 == context.manifest_sha1

      for %{"size_source" => source} <- context.siala_raw["weapons"] do
        assert source["sha1"] == context.hak_sha1
      end
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
    # иное, чем база, — ни одной лишней, ни одной недостающей. Разойдётся хак
    # (шард обновил таблицы) — тест упадёт первым.
    test "хак расходится с базой по WeaponSize ровно там, где у Сиалы есть запись", %{
      base: base,
      hak: hak,
      rows: rows,
      siala_raw: raw
    } do
      differ =
        for {id, row} <- Enum.sort(rows),
            TwoDA.get(hak, row, "WeaponSize") != TwoDA.get(base, row, "WeaponSize"),
            do: Atom.to_string(id)

      assert differ == ["trident"]
      assert Enum.map(raw["weapons"], & &1["id"]) == differ
    end

    # Запись — дословно ячейка хака: строка, метка, колонка, значение; цитата —
    # начало строки хака до `WeaponSize` включительно.
    test "запись Сиалы — ячейка хака слово в слово", %{
      hak: hak,
      hak_lines: lines,
      siala_raw: raw
    } do
      for %{"size_source" => s} = record <- raw["weapons"] do
        assert TwoDA.get(hak, s["row"], "label") == s["label"]
        assert TwoDA.get(hak, s["row"], s["column"]) == s["value"]

        assert [line] = Enum.filter(lines, &String.starts_with?(&1, "#{s["row"]} "))
        assert String.starts_with?(line, record["size_quote"])

        # Цитата кончается ровно на ячейке `WeaponSize`: её последний токен —
        # значение, а число токенов — позиция колонки плюс индекс строки.
        tokens = String.split(record["size_quote"])
        assert List.last(tokens) == s["value"]
        assert length(tokens) == Enum.find_index(hak.columns, &(&1 == s["column"])) + 2
      end
    end

    # Размеры загруженной Сиалы — по хаку у всех 41 вида со строкой таблицы,
    # кроме дротика. Дротик — спор ВАНИЛИ (Fandom `tiny`, таблица `small`), он
    # зарегистрирован находкой вида (d) у `mix base2da.diff`, и хак его не трогает:
    # у хака дротик тот же `small`, что у базы.
    test "размеры Сиалы — по хаку у всех видов, кроме дротика — спора ванили (d)", %{
      base: base,
      hak: hak,
      rows: rows,
      siala: siala,
      vanilla: vanilla,
      siala_raw: raw
    } do
      assert size_mismatches(siala, hak, rows, raw) == [{:dart, :small, :tiny}]
      assert size_mismatches(vanilla, base, rows, raw) == [{:dart, :small, :tiny}]

      assert {"weapons/dart/size", :d, _why} =
               Enum.find(Classification.rules(), &(elem(&1, 0) == "weapons/dart/size"))

      # Положительный контроль: с ванильными размерами сверка с хаком видит
      # строку 95 — то есть выше она сходится с Сиалой не по построению.
      assert size_mismatches(vanilla, hak, rows, raw) ==
               [{:dart, :small, :tiny}, {:trident, :medium, :large}]
    end
  end
end
