defmodule BuildCalculator.Data.ClassBonusFeatLevelsTest do
  @moduledoc """
  Эпическая шкала бонусных фитов престиж-классов после 30-го уровня класса —
  `priv/rules/vanilla/class_bonus_feat_levels.json` (задача 4.26), ручной слой
  поверх машинного `vanilla/classes.json`.

  Машинный слой читает уровни бонусных фитов из таблиц Fandom, а эпические
  таблицы престиж-классов там кончаются на 30-м. Файл добавляет уровни таблиц
  игры `cls_bfeat_*.2da` за этим концом, до 40-го. Здесь проверяется, что
  записанное доехало до обоих ruleset'ов, что машинный слой под записью не
  сдвинулся, что сторожа загрузчика падают, и — при наличии выгрузки
  `priv/base_2da/` — что каждое число совпадает с таблицей.

  ⚠️ Достижимость решает не файл, а ядро: у ванили престиж-класс кончается
  на 30-м, у Сиалы на 31-м (`Rules.PrestigeEpicScalesTest`).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.Source
  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA

  @file_path "priv/rules/vanilla/class_bonus_feat_levels.json"
  @raw @file_path |> File.read!() |> Jason.decode!()

  # Ожидания продублированы намеренно: тест, читающий их из проверяемого файла,
  # зеленеет и на пустом файле. Слева — таблица Fandom (машинный слой), справа —
  # то, что добавила таблица игры.
  @scales %{
    arcane_archer: {[14, 18, 22, 26, 30], [34, 38]},
    assassin: {[14, 18, 22, 26, 30], [34, 38]},
    blackguard: {[13, 16, 19, 22, 25, 28], [31, 34, 37, 40]},
    champion_of_torm: {[14, 18, 22, 26, 30], [34, 38]},
    dwarven_defender: {[14, 18, 22, 26, 30], [34, 38]},
    pale_master: {[13, 16, 19, 22, 25, 28], [31, 34, 37, 40]},
    red_dragon_disciple: {[14, 18, 22, 26, 30], [34, 38]},
    shadowdancer: {[13, 16, 19, 22, 25, 28], [31, 34, 37, 40]},
    shifter: {[13, 16, 19, 22, 25, 28], [31, 34, 37, 40]},
    weapon_master: {[13, 16, 19, 22, 25, 28], [31, 34, 37, 40]}
  }

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!("class_bonus_feat_levels_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit_entries(root, fun) do
    path = Path.join(root, "vanilla/class_bonus_feat_levels.json")

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

  defp entry(id), do: Enum.find(@raw["classes"], &(&1["id"] == Atom.to_string(id)))

  defp levels(class), do: class.epic_bonus_feat_levels |> MapSet.to_list() |> Enum.sort()

  describe "файл подключён" do
    test "зарегистрирован по имени и не стал доменом выбора", %{vanilla: v, siala: s} do
      assert "vanilla/class_bonus_feat_levels.json" in Loader.source_files()

      for ruleset <- [v, s],
          do: refute(Map.has_key?(ruleset.choice_domains, :class_bonus_feat_levels))
    end

    test "десять классов, и у каждого — ровно записанное", %{vanilla: v, siala: s} do
      assert Enum.map(@raw["classes"], &String.to_existing_atom(&1["id"])) |> Enum.sort() ==
               @scales |> Map.keys() |> Enum.sort()

      for {class, {fandom, added}} <- @scales, ruleset <- [v, s] do
        assert levels(ruleset.classes[class]) == fandom ++ added, "#{class}"
        assert entry(class)["epic_bonus_feat_levels"]["extends"] == fandom
        assert entry(class)["epic_bonus_feat_levels"]["add"] == added
      end
    end

    # Цитата Fandom у каждой записи — открытое правило со страницы класса, и
    # оно обязано лежать на странице дословно. Пара `quote_2` ↔ `source_2`, а не
    # `quote` ↔ `source`: `source` здесь — строка таблицы игры, и цитата под
    # `quote` осталась бы непроверенной (общий сторож цитат спаривает ключи
    # по суффиксу).
    test "цитата Fandom у каждой записи дословно лежит на странице класса" do
      index =
        "priv/wiki_cache/fandom/_index.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.new(&{&1["title"], &1["file"]})

      squeeze = fn text ->
        text
        |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/, "\\1")
        |> String.replace(~r/\s+/u, " ")
      end

      for raw <- @raw["classes"],
          block = raw["epic_bonus_feat_levels"],
          {quote_key, source_key} <- [{"quote_2", "source_2"}, {"quote_notes", "source_notes"}],
          quote = block[quote_key] do
        source = block[source_key]
        assert source["wiki"] == "fandom", "#{raw["id"]}: #{source_key}"

        page = File.read!(Path.join("priv/wiki_cache/fandom", Map.fetch!(index, source["page"])))

        assert String.contains?(squeeze.(page), squeeze.(quote)),
               "#{raw["id"]} / #{quote_key}: цитаты нет на странице #{source["page"]}"
      end

      assert Enum.all?(@raw["classes"], &is_binary(&1["epic_bonus_feat_levels"]["quote_2"]))
      refute Enum.any?(@raw["classes"], &Map.has_key?(&1["epic_bonus_feat_levels"], "quote"))
    end

    test "у всех добавленных уровней — один слот, кратность не нужна", %{vanilla: v} do
      for {class, {_fandom, added}} <- @scales, level <- added do
        refute Map.has_key?(v.classes[class].bonus_feat_counts, level), "#{class} #{level}"
      end
    end
  end

  describe "без файла" do
    # Сиала слоя уровней бонусных фитов у этих классов не переписывает, поэтому
    # без файла обе стороны теряют ровно добавленное — и больше ничего.
    test "обе стороны возвращаются к таблице Fandom", %{vanilla: v, siala: s} do
      root = copy_rules()
      File.rm!(Path.join(root, "vanilla/class_bonus_feat_levels.json"))
      loaded = Loader.load!(root)

      for {class, {fandom, _added}} <- @scales, version <- ["vanilla", "siala_41"] do
        assert levels(loaded[version].classes[class]) == fandom, "#{version} #{class}"
      end

      # Положительный контроль: файл что-то делает.
      refute loaded["vanilla"] == v
      refute loaded["siala_41"] == s
    end
  end

  describe "сторож загрузчика роняет сборку, а не молчит" do
    test "класса нет" do
      root =
        copy_rules()
        |> edit_entries(&[%{"id" => "cavalier", "epic_bonus_feat_levels" => %{}} | &1])

      assert_raise RuntimeError, ~r/names a class that does not exist/, fn ->
        Loader.load!(root)
      end
    end

    test "запись дважды" do
      root = copy_rules() |> edit_entries(&(&1 ++ [entry(:pale_master)]))

      assert_raise RuntimeError, ~r/pale_master is stated twice/, fn -> Loader.load!(root) end
    end

    test "второй ключ рядом с фактом" do
      root =
        copy_rules()
        |> edit_entries(fn entries ->
          Enum.map(entries, fn
            %{"id" => "pale_master"} = e -> Map.put(e, "bonus_feat_levels", %{})
            e -> e
          end)
        end)

      assert_raise RuntimeError,
                   ~r/states \["bonus_feat_levels", "epic_bonus_feat_levels"\]/,
                   fn ->
                     Loader.load!(root)
                   end
    end

    test "машинный слой сдвинулся под записью" do
      root = copy_rules() |> edit_block("pale_master", &Map.put(&1, "extends", [13, 16, 19]))

      assert_raise RuntimeError, ~r/vanilla\/classes.json now has/, fn -> Loader.load!(root) end
    end

    test "уровень внутри таблицы Fandom — запись не переписывает таблицу" do
      root = copy_rules() |> edit_block("pale_master", &Map.put(&1, "add", [27, 31]))

      assert_raise RuntimeError, ~r/do not lie past the end of the Fandom table/, fn ->
        Loader.load!(root)
      end
    end

    test "уровни не по возрастанию" do
      root = copy_rules() |> edit_block("pale_master", &Map.put(&1, "add", [34, 31]))

      assert_raise RuntimeError, ~r/non-empty ascending list/, fn -> Loader.load!(root) end
    end

    test "статус не verified" do
      root = copy_rules() |> edit_block("pale_master", &Map.put(&1, "status", "assumed"))

      assert_raise RuntimeError, ~r/is not "verified"/, fn -> Loader.load!(root) end
    end

    test "источник — не строка cls_bfeat_*.2da" do
      root =
        copy_rules()
        |> edit_block("pale_master", &Map.put(&1, "source", %{"wiki" => "fandom"}))

      assert_raise RuntimeError, ~r/not a cls_bfeat_\*\.2da row/, fn -> Loader.load!(root) end
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

    # Строка таблицы — ПОЗИЦИЯ: уровень класса = позиция + 1 (nwn.wiki,
    # cls_bfeat_xxx.2da: «line 0 is level 1»). До 40-го — MaxLevel престиж-класса.
    defp table_levels(table) do
      for {i, row} <- TwoDA.rows(table),
          i + 1 <= 40,
          TwoDA.to_int(row["Bonus"]) not in [nil, 0],
          do: {i + 1, row["Bonus"]}
    end

    test "у каждой записи: таблица, которую назначает classes.2da, и её строки", %{
      source: source,
      vanilla: v
    } do
      classes = Source.table(source, "classes")

      for raw <- @raw["classes"] do
        id = String.to_existing_atom(raw["id"])
        block = raw["epic_bonus_feat_levels"]
        cited = block["source"]
        table_name = String.replace_suffix(cited["table"], ".2da", "")

        # Таблицу классу назначает classes.2da — строка, названная в `note`.
        [_, row] = Regex.run(~r/classes\.2da:(\d+)/, cited["note"])
        assigned = TwoDA.get(classes, String.to_integer(row), "BonusFeatsTable")
        assert String.downcase(assigned) == table_name, "#{id}: classes.2da:#{row} → #{assigned}"

        table = Source.table(source, table_name)
        base = table_levels(table)

        # Все ячейки — единицы: по слоту на уровень, как читает загрузчик.
        assert Enum.all?(base, fn {_level, bonus} -> bonus == "1" end), "#{id}: #{inspect(base)}"

        # Таблица игры до 40-го — ровно машинный слой плюс запись, а ячейка,
        # на которую указывает цитата, — первый добавленный уровень.
        table_set = Enum.map(base, &elem(&1, 0))
        class = v.classes[id]
        ours = MapSet.union(class.bonus_feat_levels, class.epic_bonus_feat_levels)

        extra =
          if id == :weapon_master,
            # Уровень 1 — Weapon of Choice: выдача с выбором, которую ядро
            # делает слотом (`grant_substitutions.json`), а не уровень списка.
            do: MapSet.new([1]),
            else: MapSet.new()

        assert MapSet.new(table_set) == MapSet.union(ours, extra), "#{id}"

        assert cited["row"] + 1 == hd(block["add"]),
               "#{id}: цитата — не первая добавленная строка"
      end
    end
  end
end
