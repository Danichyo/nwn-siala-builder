defmodule BuildCalculator.Data.SialaClassBonusFeatLevelsTest do
  @moduledoc """
  Эпический бонусный фит базовых классов на 41-м уровне КЛАССА — сиальская
  половина `vanilla/class_bonus_feat_levels.json`,
  `priv/rules/siala_41/class_bonus_feat_levels.json` (задача 4.51).

  Кап Сиалы 41, и у шести базовых классов шаг эпических бонусных фитов
  приходится ровно на 41: строка-позиция 40 базовых `cls_bfeat_*.2da` даёт
  Bonus 1 у барда, священника, паладина, рейнджера, колдуна и волшебника.
  Хак своих таблиц не шлёт, его `classes.2da` назначает базовые.

  Здесь проверяется: что записанное доехало до Сиалы и не тронуло ваниль; что
  статус `assumed` несёт решение Dan `BC1` и цитаты лежат в источниках дословно;
  что проход идёт ПОСЛЕ слоя классов Сиалы (запись пула Священника осталась
  применённой); что сторожа загрузчика падают; и — при наличии выгрузок
  `priv/base_2da/` и `priv/hak/2da/` — что шкалы всех ОДИННАДЦАТИ базовых
  классов совпадают с таблицами, которые исполняет клиент Сиалы, до её капа 41,
  а ванильные — до капа 40.

  Сценарии по одному левелапу — `Rules.SialaLevel41BonusFeatTest`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.Source
  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA

  @file_rel "siala_41/class_bonus_feat_levels.json"
  @raw "priv/rules" |> Path.join(@file_rel) |> File.read!() |> Jason.decode!()

  # Ожидания продублированы намеренно: тест, читающий их из проверяемого файла,
  # зеленеет и на пустом файле. Слева — что класс несёт до записи (таблица
  # Fandom), справа — что добавила строка 40 таблицы игры.
  @scales %{
    bard: {[23, 26, 29, 32, 35, 38], [41]},
    cleric: {[23, 26, 29, 32, 35, 38], [41]},
    paladin: {[23, 26, 29, 32, 35, 38], [41]},
    ranger: {[23, 25, 26, 29, 30, 32, 35, 38, 40], [41]},
    sorcerer: {[23, 26, 29, 32, 35, 38], [41]},
    wizard: {[23, 26, 29, 32, 35, 38], [41]}
  }

  @base_classes ~w(barbarian bard cleric druid fighter monk paladin ranger rogue sorcerer wizard)a

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp entry(id), do: Enum.find(@raw["classes"], &(&1["id"] == Atom.to_string(id)))
  defp block(id), do: entry(id)["epic_bonus_feat_levels"]

  defp levels(class), do: class.epic_bonus_feat_levels |> MapSet.to_list() |> Enum.sort()

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!("siala_class_bonus_feat_levels_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_entries(root, fun) do
    path = Path.join(root, @file_rel)

    File.write!(
      path,
      path |> File.read!() |> Jason.decode!() |> Map.update!("classes", fun) |> Jason.encode!()
    )

    root
  end

  defp edit_block(root, id, fun) do
    edit_entries(root, fn entries ->
      Enum.map(entries, fn
        %{"id" => ^id} = entry -> Map.update!(entry, "epic_bonus_feat_levels", fun)
        entry -> entry
      end)
    end)
  end

  describe "файл подключён" do
    test "зарегистрирован по имени", _ctx do
      assert @file_rel in Loader.source_files()
    end

    test "шесть классов, у каждого — ровно записанное; ваниль не тронута", %{
      vanilla: v,
      siala: s
    } do
      assert Enum.map(@raw["classes"], &String.to_existing_atom(&1["id"])) |> Enum.sort() ==
               @scales |> Map.keys() |> Enum.sort()

      for {class, {before, added}} <- @scales do
        assert levels(s.classes[class]) == before ++ added, "siala #{class}"
        assert levels(v.classes[class]) == before, "vanilla #{class}"
        assert block(class)["extends"] == before
        assert block(class)["add"] == added

        # Один слот на уровень: таблица говорит Bonus 1, кратность не нужна.
        refute Map.has_key?(s.classes[class].bonus_feat_counts, 41), "#{class}"
      end
    end

    test "остальные пять базовых классов шкалу не меняют", %{vanilla: v, siala: s} do
      for class <- @base_classes -- Map.keys(@scales) do
        assert levels(s.classes[class]) == levels(v.classes[class]), "#{class}"
        refute 41 in levels(s.classes[class]), "#{class}"
      end
    end

    test "статус assumed и решение BC1 у каждой записи — одно и то же" do
      decisions =
        for raw <- @raw["classes"], block = raw["epic_bonus_feat_levels"] do
          assert block["status"] == "assumed", raw["id"]
          assert is_binary(block["status_why"]) and block["status_why"] != "", raw["id"]
          assert [_ | _] = block["not_measured"]
          block["decision"]
        end

      assert [decision] = Enum.uniq(decisions)

      assert %{
               "kind" => "user",
               "who" => "Dan",
               "date" => "2026-09-27",
               "case" => "BC1",
               "quote" => "41 уровень подчиняется всем обычным правилам"
             } = decision
    end

    test "источник — строка 40 таблицы cls_bfeat_* того же класса" do
      tables = %{
        bard: "cls_bfeat_bard.2da",
        cleric: "cls_bfeat_cler.2da",
        paladin: "cls_bfeat_pal.2da",
        ranger: "cls_bfeat_rang.2da",
        sorcerer: "cls_bfeat_sorc.2da",
        wizard: "cls_bfeat_wiz.2da"
      }

      for {class, table} <- tables do
        assert %{"kind" => "2da", "table" => ^table, "row" => 40, "column" => "Bonus"} =
                 block(class)["source"]

        assert block(class)["source"]["value"] == "1"
        # Строка — позиция, уровень класса — позиция + 1.
        assert block(class)["source"]["row"] + 1 == hd(block(class)["add"])
      end
    end

    test "цитата Fandom у каждой записи дословно лежит на странице класса" do
      index =
        "priv/wiki_cache/fandom/_index.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.new(&{&1["title"], &1})

      for raw <- @raw["classes"], block = raw["epic_bonus_feat_levels"] do
        source = block["source_2"]
        assert source["wiki"] == "fandom", raw["id"]
        page = Map.fetch!(index, source["page"])
        assert page["revid"] == source["revid"], "#{raw["id"]}: revid кэша"

        text = File.read!(Path.join("priv/wiki_cache/fandom", page["file"]))
        assert String.contains?(text, block["quote_2"]), "#{raw["id"]}: цитаты нет на странице"
      end

      refute Enum.any?(@raw["classes"], &Map.has_key?(&1["epic_bonus_feat_levels"], "quote"))
    end

    # Довод статуса `assumed` стоит на двух цитатах из источников, которые
    # перепроверить можно: страница вики Сиалы и лог `.билд`. Обе обязаны
    # лежать там дословно — иначе довод выдуман.
    test "довод статуса: цитата вики Сиалы и строка лога лежат дословно" do
      index =
        "priv/wiki_cache/siala/_index.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.new(&{&1["title"], &1})

      page = Map.fetch!(index, "41-ый уровень")
      assert page["revid"] == 20387
      text = File.read!(Path.join("priv/wiki_cache/siala", page["file"]))

      quote =
        "Нельзя выбирать заклинания на чистом 41-м уровне! Вашему барду, волшебнику или " <>
          "колдуну стоит позаботиться об этом заранее."

      assert String.contains?(text, quote)
      assert String.contains?(@raw["_note"], "Нельзя выбирать заклинания на чистом 41-м уровне!")

      for raw <- @raw["classes"] do
        assert Enum.any?(
                 raw["epic_bonus_feat_levels"]["not_measured"],
                 &String.contains?(&1, quote)
               ),
               raw["id"]
      end

      log = File.read!("test/fixtures/game_logs/moxie.log")

      assert log =~
               ~r/LEVEL 41: RANGER\n  FEATS: Toughness, Trackless Step, Dual-Wield, Epic Spell Focus \(Necromancy\)\n/
    end
  end

  describe "порядок: после слоя классов Сиалы" do
    # Запись Священника `bonus_feat_pool` цитирует «23, 26, 29, 32, 35 и 38» и
    # применяется только при равенстве с бонусными уровнями класса. Положенный
    # до слоя классов 41 выбил бы её в `siala_unapplied` — гэп и потерю пула.
    test "пул эпических заклинаний Священника остался применённым", %{siala: s} do
      cleric = s.classes[:cleric]

      assert Map.has_key?(cleric.bonus_feat_pool_adds, "epic_spell_feats")
      refute Enum.any?(cleric.siala_unapplied, &(&1["what"] == "bonus_feat_pool"))
    end

    test "владения в эпическом бонусном слоте паладина (AK1) — тоже", %{siala: s} do
      paladin = s.classes[:paladin]

      assert Map.has_key?(paladin.bonus_feat_pool_adds, "weapon_proficiency_feats")
      refute Enum.any?(paladin.siala_unapplied, &(&1["what"] == "bonus_feat_pool"))
    end
  end

  describe "без файла" do
    test "Сиала возвращается к таблице Fandom, ваниль не сдвигается", %{vanilla: v, siala: s} do
      root = copy_rules()
      File.rm!(Path.join(root, @file_rel))
      loaded = Loader.load!(root)

      for {class, {before, _added}} <- @scales do
        assert levels(loaded["siala_41"].classes[class]) == before, "#{class}"
      end

      # Положительный контроль: файл что-то делает — и только у Сиалы.
      refute loaded["siala_41"] == s
      assert loaded["vanilla"] == v
    end
  end

  describe "сторож загрузчика роняет сборку, а не молчит" do
    test "assumed без решения" do
      root = copy_rules() |> edit_block("bard", &Map.delete(&1, "decision"))

      assert_raise RuntimeError, ~r/is "assumed" and states no `decision`/, fn ->
        Loader.load!(root)
      end
    end

    test "решение не названо: нет кейса" do
      root =
        copy_rules()
        |> edit_block("bard", fn b -> update_in(b, ["decision"], &Map.delete(&1, "case")) end)

      assert_raise RuntimeError, ~r/states no `decision`/, fn -> Loader.load!(root) end
    end

    test "статус вне двух допустимых" do
      root = copy_rules() |> edit_block("wizard", &Map.put(&1, "status", "unclear"))

      assert_raise RuntimeError, ~r/is not "verified" or "assumed"/, fn -> Loader.load!(root) end
    end

    test "слой ниже сдвинулся под записью" do
      root = copy_rules() |> edit_block("cleric", &Map.put(&1, "extends", [23, 26, 29]))

      assert_raise RuntimeError, ~r/siala_41\/classes.json now has/, fn -> Loader.load!(root) end
    end

    test "уровень внутри таблицы Fandom" do
      root = copy_rules() |> edit_block("ranger", &Map.put(&1, "add", [40, 41]))

      assert_raise RuntimeError, ~r/do not lie past the end of the Fandom table/, fn ->
        Loader.load!(root)
      end
    end

    test "источник — не строка cls_bfeat_*.2da" do
      root =
        copy_rules()
        |> edit_block("paladin", &Map.put(&1, "source", %{"kind" => "hak", "table" => "x"}))

      assert_raise RuntimeError, ~r/not a cls_bfeat_\*\.2da row/, fn -> Loader.load!(root) end
    end

    test "класса нет и запись дважды" do
      root =
        copy_rules()
        |> edit_entries(&[%{"id" => "cavalier", "epic_bonus_feat_levels" => %{}} | &1])

      assert_raise RuntimeError,
                   ~r/siala_41\/class_bonus_feat_levels.json: cavalier names a class/,
                   fn -> Loader.load!(root) end

      root = copy_rules() |> edit_entries(&(&1 ++ [entry(:sorcerer)]))

      assert_raise RuntimeError, ~r/sorcerer is stated twice/, fn -> Loader.load!(root) end
    end
  end

  describe "сверка с таблицами, которые исполняет клиент Сиалы" do
    @base Path.expand("../../../priv/base_2da", __DIR__)
    @hak Path.expand("../../../priv/hak/2da", __DIR__)

    unless File.regular?(Path.join(@base, "manifest.json")) and
             File.regular?(Path.join(@hak, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                       "выгрузки: mix base2da.extract, mix hak.extract"
    end

    setup do
      {:ok, client} = Source.load_layered(@hak, @base)
      {:ok, base} = Source.load(@base)
      %{client: client, base: base}
    end

    # Строки classes.2da — позиции; у хака и базы те же.
    @class_rows %{
      barbarian: {0, "Barbarian"},
      bard: {1, "Bard"},
      cleric: {2, "Cleric"},
      druid: {3, "Druid"},
      fighter: {4, "Fighter"},
      monk: {5, "Monk"},
      paladin: {6, "Paladin"},
      ranger: {7, "Ranger"},
      rogue: {8, "Rogue"},
      sorcerer: {9, "Sorcerer"},
      wizard: {10, "Wizard"}
    }

    defp table_of(source, class) do
      {row, label} = Map.fetch!(@class_rows, class)
      classes = Source.table(source, "classes")
      assert TwoDA.label(classes, row) == Integer.to_string(row)
      assert TwoDA.get(classes, row, "Label") == label
      name = classes |> TwoDA.get(row, "BonusFeatsTable") |> String.downcase()
      {name, Source.table(source, name)}
    end

    # Уровень класса = позиция + 1 (nwn.wiki, cls_bfeat_xxx.2da: «line 0 is level 1»).
    defp table_levels(table, cap) do
      for {i, row} <- TwoDA.rows(table),
          i + 1 <= cap,
          (n = TwoDA.to_int(row["Bonus"])) not in [nil, 0],
          into: %{},
          do: {i + 1, n}
    end

    defp our_levels(class) do
      class.bonus_feat_levels
      |> MapSet.union(class.epic_bonus_feat_levels)
      |> Map.new(&{&1, Map.get(class.bonus_feat_counts, &1, 1)})
    end

    test "все одиннадцать базовых классов: таблица клиента до капа = наша шкала", %{
      client: client,
      siala: s,
      vanilla: v
    } do
      assert s.level_cap == 41
      assert v.level_cap == 40

      for class <- @base_classes do
        {name, table} = table_of(client, class)

        # Клиент Сиалы исполняет базовую таблицу: хак своей не шлёт.
        assert Source.origin(client, name) == :base, "#{class}: #{name} пришла из хака"

        assert table_levels(table, 41) == our_levels(s.classes[class]), "siala #{class}"
        assert table_levels(table, 40) == our_levels(v.classes[class]), "vanilla #{class}"
      end
    end

    test "строка 40 даёт Bonus 1 ровно у шести классов", %{client: client} do
      at_41 =
        for class <- @base_classes,
            {_name, table} = table_of(client, class),
            TwoDA.int(table, 40, "Bonus") == 1,
            do: class

      assert Enum.sort(at_41) == @scales |> Map.keys() |> Enum.sort()
    end

    test "у каждой записи — sha1 базовой таблицы и строка classes.2da хака", %{
      client: client,
      base: base
    } do
      hak_sha1 = Source.sha1_of(client, "classes")

      for raw <- @raw["classes"] do
        class = String.to_existing_atom(raw["id"])
        block = raw["epic_bonus_feat_levels"]
        {name, _table} = table_of(client, class)

        assert block["source"]["table"] == name <> ".2da"
        assert block["source"]["sha1"] == Source.sha1_of(base, name), "#{class}"
        assert block["source"]["build"] == Source.game(base)["version"]

        {row, _label} = Map.fetch!(@class_rows, class)
        hak = block["hak"]["source"]

        assert %{"kind" => "hak", "table" => "classes.2da", "column" => "BonusFeatsTable"} = hak
        assert hak["row"] == row
        assert hak["value"] == TwoDA.get(Source.table(client, "classes"), row, "BonusFeatsTable")
        assert Source.origin(client, "classes") == :hak
        assert hak["sha1"] == hak_sha1
      end
    end
  end
end
