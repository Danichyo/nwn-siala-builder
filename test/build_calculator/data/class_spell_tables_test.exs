defmodule BuildCalculator.Data.ClassSpellTablesTest do
  @moduledoc """
  Ячейки таблиц заклинаний, где таблица игры правит таблицу Fandom, —
  `priv/rules/vanilla/class_spell_tables.json` (задача 4.44), ручной слой поверх
  машинного `vanilla/classes.json`.

  Сегодня ячейка одна: **друид 15-го уровня, 3-й круг — 4 слота, а не 5.**
  Fandom (страница Druid, строка 15th) печатает 6/5/5/5/4/4/3/2/1, таблица игры
  `cls_spgn_dru.2da` (строка 14) — 6 5 5 4 4 4 3 2 1. Спор решил замер `AW1`
  (`GAME_CHECKS.md`; Dan, сервер Сиалы, 27.09.2026): «друид 15, WIS 14, 3-го
  круга доступно 4 слота».

  Здесь проверяется, что ячейка доехала до обоих ruleset'ов и до `Rules.compute`,
  что соседние ячейки и уровни не сдвинулись, что без файла ячейка возвращается
  к числу Fandom, что сторожа загрузчика падают, — а при наличии выгрузок
  (`priv/base_2da/`, `priv/hak/2da/`) ещё и полная сверка таблицы друида
  с `cls_spgn_dru.2da` и то, что хак Сиалы этой таблицы не присылает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.Source
  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  @file_path "priv/rules/vanilla/class_spell_tables.json"
  @raw @file_path |> File.read!() |> Jason.decode!()
  @versions ["vanilla", "siala_41"]

  # Ожидания продублированы намеренно: тест, читающий их из проверяемого файла,
  # зеленеет и на пустом файле. Источник — cls_spgn_dru.2da, строки 13–15
  # (уровни класса 14–16), SpellLevel0…8; у строк 13 и 15 Fandom с таблицей
  # согласен, у строки 14 спорит в одной ячейке — 3-й круг.
  @row_14 %{0 => 6, 1 => 5, 2 => 5, 3 => 4, 4 => 4, 5 => 3, 6 => 3, 7 => 2}
  @row_15 %{0 => 6, 1 => 5, 2 => 5, 3 => 4, 4 => 4, 5 => 4, 6 => 3, 7 => 2, 8 => 1}
  @row_16 %{0 => 6, 1 => 5, 2 => 5, 3 => 5, 4 => 4, 5 => 4, 6 => 3, 7 => 3, 8 => 2}

  setup_all do
    %{rulesets: Map.new(@versions, &{&1, Data.ruleset!(&1)})}
  end

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!("class_spell_tables_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_cells(root, fun) do
    path = Path.join(root, "vanilla/class_spell_tables.json")

    File.write!(
      path,
      path |> File.read!() |> Jason.decode!() |> Map.update!("cells", fun) |> Jason.encode!()
    )

    root
  end

  defp edit_druid_cell(root, fun) do
    edit_cells(root, fn cells ->
      Enum.map(cells, fn
        %{"class" => "druid", "class_level" => 15, "circle" => 3} = cell -> fun.(cell)
        cell -> cell
      end)
    end)
  end

  defp druid_cell, do: Enum.find(@raw["cells"], &(&1["class"] == "druid"))

  # Лестница, по которой идёт игрок: по одному левелапу, каждый через
  # `validate_level_up/3` (CLAUDE.md §3 — `Build.new(levels: …)` валидацию
  # не проходит вовсе).
  defp druid(ruleset, level, wis) do
    start =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        base_abilities: Map.merge(Build.new().base_abilities, %{wis: wis})
      )

    Enum.reduce(1..level, start, fn _, %Build{} = acc ->
      assert :ok = Rules.validate_level_up(acc, :druid, ruleset)
      Build.add_level(acc, :druid)
    end)
  end

  defp slots_per_day(ruleset, level, wis) do
    assert [%{class: :druid, slots: slots}] =
             ruleset |> druid(level, wis) |> Rules.compute(ruleset) |> Map.fetch!(:spells_per_day)

    slots
  end

  describe "друид 15: 4 слота 3-го круга (замер AW1)" do
    # source: GAME_CHECKS.md, кейс AW1 — Dan, сервер Сиалы, 27.09.2026:
    # «друид 15, WIS 14, 3-го круга доступно 4 слота». WIS 14 (+2) даёт по
    # бонусному слоту 1-му и 2-му кругу (`spellcasting.json` →
    # `bonus_spell_slots`), 3-му — нет, поэтому у него чистое число таблицы:
    # cls_spgn_dru.2da, строка 14, SpellLevel3 = 4. Круги 5+ при WIS 14 закрыты
    # (10 + круг), их в `slots` нет. Соседние уровни — строки 13 и 15 той же
    # таблицы, с которыми Fandom согласен.
    test "Rules.compute на обоих ruleset'ах: 15-й — 4, 14-й и 16-й не сдвинулись", %{
      rulesets: rulesets
    } do
      for version <- @versions do
        ruleset = rulesets[version]

        assert slots_per_day(ruleset, 15, 14) == %{0 => 6, 1 => 6, 2 => 6, 3 => 4, 4 => 4},
               version

        assert slots_per_day(ruleset, 14, 14) == %{0 => 6, 1 => 6, 2 => 6, 3 => 4, 4 => 4},
               version

        assert slots_per_day(ruleset, 16, 14) == %{0 => 6, 1 => 6, 2 => 6, 3 => 5, 4 => 4},
               version
      end
    end

    test "строки 14, 15 и 16 таблицы друида — целиком, на обоих ruleset'ах", %{
      rulesets: rulesets
    } do
      for version <- @versions do
        table = rulesets[version].classes[:druid].spells_per_day

        assert table[14] == @row_14, version
        assert table[15] == @row_15, version
        assert table[16] == @row_16, version
      end
    end

    test "у Сиалы таблица друида та же, что у ванили", %{rulesets: rulesets} do
      assert rulesets["siala_41"].classes[:druid].spells_per_day ==
               rulesets["vanilla"].classes[:druid].spells_per_day
    end
  end

  describe "файл подключён" do
    test "зарегистрирован по имени и не стал доменом выбора", %{rulesets: rulesets} do
      assert "vanilla/class_spell_tables.json" in Loader.source_files()

      for {_version, ruleset} <- rulesets,
          do: refute(Map.has_key?(ruleset.choice_domains, :class_spell_tables))
    end

    test "одна ячейка, и её `replaces` — то самое число в строке Fandom" do
      assert [cell] = @raw["cells"]
      assert %{"class" => "druid", "table" => "spells_per_day"} = cell
      assert %{"class_level" => 15, "circle" => 3, "replaces" => 5, "value" => 4} = cell

      # Цитата — две строки таблицы Fandom: подпись уровня и «HP range || 0 || 1st …».
      # После HP range колонки идут кругами 0…9, так что 3-й круг — пятая ячейка.
      [_label, counts] = String.split(cell["quote_fandom"], "\n")
      [_hp_range | circles] = counts |> String.split("||") |> Enum.map(&String.trim/1)

      assert Enum.at(circles, 3) == "5"

      assert cell["source_fandom"] == %{
               "wiki" => "fandom",
               "page" => "Druid",
               "revid" => 71_575,
               "fetched" => "2026-08-01"
             }

      assert %{"kind" => "user", "case" => "AW1", "date" => "2026-09-27"} = cell["measured"]
    end

    # Без ручного слоя ячейка возвращается к числу Fandom, и больше НИЧЕГО
    # не меняется: файл трогает ровно одну ячейку на обоих ruleset'ах.
    test "без файла — 5, как на Fandom, и только эта ячейка", %{rulesets: rulesets} do
      root = copy_rules()
      File.rm!(Path.join(root, "vanilla/class_spell_tables.json"))
      loaded = Loader.load!(root)

      for version <- @versions do
        without = loaded[version].classes[:druid].spells_per_day
        with_file = rulesets[version].classes[:druid].spells_per_day

        assert without[15][3] == 5, version
        assert put_in(without[15][3], 4) == with_file, version
      end
    end
  end

  describe "сторож загрузчика роняет сборку, а не молчит" do
    test "машинный слой сдвинулся под записью" do
      root = copy_rules() |> edit_druid_cell(&Map.put(&1, "replaces", 6))

      assert_raise RuntimeError, ~r/vanilla\/classes.json now has 5/, fn -> Loader.load!(root) end
    end

    test "ячейка, которой у машинного слоя нет, — не правка, а дописывание" do
      root =
        copy_rules()
        |> edit_druid_cell(fn cell ->
          cell
          |> Map.put("circle", 9)
          |> Map.put("replaces", nil)
          |> Map.update!("source", &Map.put(&1, "column", "SpellLevel9"))
        end)

      assert_raise RuntimeError, ~r/now has nil/, fn -> Loader.load!(root) end
    end

    test "ячейка, которая ничего не меняет" do
      root =
        copy_rules()
        |> edit_druid_cell(fn cell ->
          cell |> Map.put("value", 5) |> Map.update!("source", &Map.put(&1, "value", "5"))
        end)

      assert_raise RuntimeError, ~r/changes nothing/, fn -> Loader.load!(root) end
    end

    test "источник называет другую строку" do
      root =
        copy_rules()
        |> edit_druid_cell(&Map.update!(&1, "source", fn s -> %{s | "row" => 15} end))

      assert_raise RuntimeError, ~r/not the cls_spgn_\*\.2da cell this record states/, fn ->
        Loader.load!(root)
      end
    end

    test "источник говорит другое число" do
      root =
        copy_rules()
        |> edit_druid_cell(&Map.update!(&1, "source", fn s -> %{s | "value" => "5"} end))

      assert_raise RuntimeError, ~r/not the cls_spgn_\*\.2da cell/, fn -> Loader.load!(root) end
    end

    test "источник — не таблица слотов" do
      root =
        copy_rules()
        |> edit_druid_cell(
          &Map.update!(&1, "source", fn s -> %{s | "table" => "cls_spkn_dru.2da"} end)
        )

      assert_raise RuntimeError, ~r/not the cls_spgn_\*\.2da cell/, fn -> Loader.load!(root) end
    end

    test "ячейка дважды" do
      root = copy_rules() |> edit_cells(&(&1 ++ [druid_cell()]))

      assert_raise RuntimeError, ~r/spells_per_day\[15\]\[3\] is stated twice/, fn ->
        Loader.load!(root)
      end
    end

    test "статус не verified" do
      root = copy_rules() |> edit_druid_cell(&Map.put(&1, "status", "assumed"))

      assert_raise RuntimeError, ~r/is not "verified"/, fn -> Loader.load!(root) end
    end

    test "ключ, которого загрузчик не читает" do
      root = copy_rules() |> edit_druid_cell(&Map.put(&1, "vaule", 4))

      assert_raise RuntimeError, ~r/states \["vaule"\]/, fn -> Loader.load!(root) end
    end

    test "класса нет" do
      root = copy_rules() |> edit_druid_cell(&Map.put(&1, "class", "cavalier"))

      assert_raise RuntimeError, ~r/names a class that does not exist/, fn ->
        Loader.load!(root)
      end
    end

    test "таблица, которой у класса нет" do
      root = copy_rules() |> edit_druid_cell(&Map.put(&1, "table", "spells_per_week"))

      assert_raise RuntimeError, ~r/`table` must be one of/, fn -> Loader.load!(root) end
    end
  end

  describe "сверка с таблицей игры" do
    @base2da Path.expand("../../../priv/base_2da", __DIR__)

    unless File.regular?(Path.join(@base2da, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da (публичный репозиторий, CI) — выгрузка: mix base2da.extract"
    end

    setup do
      {:ok, source} = Source.load(@base2da)
      %{source: source}
    end

    # Строка — ПОЗИЦИЯ: уровень класса = позиция + 1, колонка `Level` рядом это
    # подтверждает. `****` — круга нет.
    defp table_slots(table, level) do
      assert TwoDA.get(table, level - 1, "Level") == Integer.to_string(level)

      for circle <- 0..9,
          n = TwoDA.int(table, level - 1, "SpellLevel#{circle}"),
          is_integer(n),
          into: %{},
          do: {circle, n}
    end

    test "classes.2da назначает друиду cls_spgn_dru", %{source: source} do
      classes = Source.table(source, "classes")

      assert TwoDA.get(classes, 3, "Label") == "Druid"
      assert TwoDA.get(classes, 3, "SpellGainTable") == "CLS_SPGN_DRU"
    end

    # Вся таблица друида, 20 уровней × все круги, на обоих ruleset'ах: других
    # расхождений с игрой нет, а исправленная ячейка — ровно та, что в записи.
    test "таблица друида целиком совпадает с cls_spgn_dru.2da — 128 ячеек", %{
      source: source,
      rulesets: rulesets
    } do
      table = Source.table(source, "cls_spgn_dru")
      game = Map.new(1..20, &{&1, table_slots(table, &1)})

      assert game[15] == @row_15
      assert game |> Map.values() |> Enum.map(&map_size/1) |> Enum.sum() == 128

      for version <- @versions do
        ours = rulesets[version].classes[:druid].spells_per_day

        assert Map.keys(ours) |> Enum.sort() == Enum.to_list(1..20), version

        for level <- 1..20, do: assert(ours[level] == game[level], "#{version} уровень #{level}")
      end
    end
  end

  describe "Сиала: хак таблицу слотов друида не присылает" do
    @base2da Path.expand("../../../priv/base_2da", __DIR__)
    @hak Path.expand("../../../priv/hak/2da", __DIR__)

    unless File.regular?(Path.join(@base2da, "manifest.json")) and
             File.regular?(Path.join(@hak, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                       "выгрузки: mix base2da.extract, mix hak.extract"
    end

    # Таблица хака сверяется с `sha1` его манифеста — таблица, поправленная
    # руками после выгрузки, — не источник.
    test "classes.2da хака назначает друиду ту же таблицу, а самой таблицы в хаке нет" do
      {:ok, source} = Source.load(@base2da)
      manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

      meta = Map.fetch!(manifest["tables"], "classes")
      bytes = File.read!(Path.join(@hak, "classes.2da"))
      sha1 = :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)

      assert sha1 == if(is_map(meta), do: meta["sha1"], else: meta)
      assert sha1 == druid_cell()["hak"]["source"]["sha1"]

      hak_classes = TwoDA.parse!(bytes)
      base_classes = Source.table(source, "classes")

      assert TwoDA.get(hak_classes, 3, "Label") == TwoDA.get(base_classes, 3, "Label")

      assert TwoDA.get(hak_classes, 3, "SpellGainTable") ==
               TwoDA.get(base_classes, 3, "SpellGainTable")

      # Положительный контроль формы манифеста: таблицы, которые шард присылает,
      # в нём есть, — значит, отсутствие cls_spgn_dru не пустой манифест.
      assert Map.has_key?(manifest["tables"], "classes")

      # Пришлёт шард свою таблицу — эта строка упадёт первой, и Сиале понадобится
      # своя запись, а не молча унаследованная ванильная.
      refute Map.has_key?(manifest["tables"], "cls_spgn_dru"), "cls_spgn_dru.2da в хаке появилась"
    end
  end
end
