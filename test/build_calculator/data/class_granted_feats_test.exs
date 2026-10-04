defmodule BuildCalculator.Data.ClassGrantedFeatsTest do
  @moduledoc """
  Выдачи классов из таблиц игры, которых нет в таблицах прогрессии Fandom, —
  `priv/rules/vanilla/class_granted_feats.json` и его сиальская половина
  `priv/rules/siala_41/class_granted_feats.json` (задача 4.27).

  Запись сегодня одна: Mount actions (FEAT_HORSE_MENU) выдаётся на 1-м уровне
  всех одиннадцати базовых классов (`cls_feat_*.2da`, List 3; Fandom «Mount
  actions», Notes). Хак Сиалы выносит ту же выдачу на 60-й уровень класса —
  за кап 41, — и слой Сиалы говорит `classes: []`: у неё фит не выдаёт никто.

  Здесь проверяется, что выдача доехала до ванили и НЕ доехала до Сиалы, что
  снапшот Сиалы от пары файлов не зависит (а без сиальской половины — зависел
  бы), что сторожа загрузчика роняют сборку, и — при наличии обеих выгрузок —
  что каждая названная строка совпадает с таблицами базовой игры и хака.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BuildCalculator.Base2da.Source
  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  @vanilla_file "vanilla/class_granted_feats.json"
  @siala_file "siala_41/class_granted_feats.json"

  # Дословно то, что записано, — таблица продублирована намеренно: тест,
  # читающий ожидания из проверяемого файла, зеленеет и на пустом файле.
  @base_classes ~w(barbarian bard cleric druid fighter monk paladin ranger rogue sorcerer wizard)a

  setup_all do
    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41")}
  end

  defp copy_rules do
    root = BuildCalculator.TmpDir.unique_path!("class_granted_feats_")
    File.cp_r!("priv/rules", root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp edit(root, relative, fun) do
    path = Path.join(root, relative)
    File.write!(path, path |> File.read!() |> Jason.decode!() |> fun.() |> Jason.encode!())
    root
  end

  defp edit_grant(root, fun),
    do: edit(root, @vanilla_file, &update_in(&1, ["grants"], fn [g] -> [fun.(g)] end))

  defp load_raising(root, pattern) do
    capture_log(fn -> assert_raise RuntimeError, pattern, fn -> Loader.load!(root) end end)
  end

  # Все уровни, на которых класс выдаёт фит, — не только первый: запись,
  # легшая не на тот уровень, была бы видна здесь.
  defp grant_levels(ruleset, class, feat) do
    for {level, ids} <- ruleset.classes[class].granted_feats, feat in ids, do: level
  end

  defp fighter_1 do
    Build.new(
      race: :human,
      alignment: :true_neutral,
      levels: [:fighter],
      base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}
    )
  end

  describe "файл подключён" do
    test "оба файла зарегистрированы, и ванильный не стал доменом выбора", %{
      vanilla: v,
      siala: s
    } do
      assert @vanilla_file in Loader.source_files()
      assert @siala_file in Loader.source_files()

      for ruleset <- [v, s],
          do: refute(Map.has_key?(ruleset.choice_domains, :class_granted_feats))
    end
  end

  describe "ваниль: Mount actions на 1-м уровне каждого базового класса" do
    test "выдан ровно одиннадцати базовым и ровно на 1-м уровне", %{vanilla: v} do
      granted = for {id, _class} <- v.classes, grant_levels(v, id, :mount_actions) != [], do: id

      assert Enum.sort(granted) == Enum.sort(@base_classes)

      for class <- @base_classes do
        assert grant_levels(v, class, :mount_actions) == [1], "#{class}"
      end

      # Положительный контроль: у престиж-класса выдачи нет — список выше
      # отличает базовые от прочих, а не «все классы подряд».
      refute v.classes[:weapon_master].granted_feats
             |> Map.values()
             |> List.flatten()
             |> Enum.member?(:mount_actions)
    end

    test "персонаж владеет им с первого уровня, и «Класс даёт сам» его называет", %{vanilla: v} do
      assert :mount_actions in Build.granted_feats_at(fighter_1(), v, 1)
      assert MapSet.member?(Build.feats_owned(fighter_1(), v, 1), :mount_actions)
    end

    # Второе следствие выдачи, и ради него запись не «чисел не двигает»:
    # фит `type: general` без требований брался общим слотом, а игра его
    # выбрать не даёт (feat.2da:1089 — MinLevel 99, ALLCLASSESCANUSE 0).
    # С выдачей слот, потраченный на него, ловится.
    #
    # ⚠️ С задачи 4.49 причин ДВЕ, и это не дубль: таблица закрывает фит от
    # выбора сама (`vanilla/feat_level_up_selectable.json` — у Сиалы, где
    # выдачи нет, это единственная причина), а выдача делает слот повтором.
    test "общий слот, потраченный на него, ловится — и выбором, и как повтор", %{vanilla: v} do
      spent = Build.put_feat(fighter_1(), 1, :general, :mount_actions)

      assert Rules.illegal_feats(spent, v) ==
               [
                 {1, :general, :mount_actions, {:not_selectable_at_level_up, :mount_actions}},
                 {1, :general, :mount_actions, {:already_taken, :mount_actions}}
               ]
    end
  end

  describe "Сиала: хак выносит выдачу за кап — не выдаёт никто" do
    test "ни одного класса, ни одного уровня", %{siala: s} do
      for {id, _class} <- s.classes do
        assert grant_levels(s, id, :mount_actions) == [], "#{id}"
      end

      refute :mount_actions in Build.granted_feats_at(fighter_1(), s, 1)
    end

    # 🔴 Снапшот Сиалы от пары файлов не зависит — и доказательство этого
    # двустороннее: без обоих Сиала та же, а без одной сиальской половины
    # ванильная выдача доезжает до неё. Второе — положительный контроль
    # первого: без него «та же» зеленело бы и у файла, которого загрузчик
    # не читает вовсе.
    test "без обоих файлов Сиала та же; без сиальской половины — нет", %{vanilla: v, siala: s} do
      root = copy_rules()
      File.rm!(Path.join(root, @vanilla_file))
      File.rm!(Path.join(root, @siala_file))
      without_both = Loader.load!(root)

      assert without_both["siala_41"] == s
      refute without_both["vanilla"] == v
      assert grant_levels(without_both["vanilla"], :fighter, :mount_actions) == []

      root = copy_rules()
      File.rm!(Path.join(root, @siala_file))
      without_siala_half = Loader.load!(root)

      assert grant_levels(without_siala_half["siala_41"], :fighter, :mount_actions) == [1]
      assert without_siala_half["vanilla"] == v
    end

    # Половина Сиалы без ванильной записи — отличие, которое ни на что
    # не легло: у неё нет уровня, и молча она не применится.
    test "сиальская запись без ванильной роняет сборку" do
      root = copy_rules()
      File.rm!(Path.join(root, @vanilla_file))

      load_raising(root, ~r/class_level/)
    end
  end

  describe "сторож загрузчика роняет сборку, а не молчит" do
    test "чистая копия грузится — иначе проверки ниже зеленели бы впустую" do
      loaded = copy_rules() |> Loader.load!()
      assert grant_levels(loaded["vanilla"], :fighter, :mount_actions) == [1]
    end

    test "фита нет" do
      root = edit_grant(copy_rules(), &Map.put(&1, "feat", "mount_actionz"))
      load_raising(root, ~r/names a feat that does not exist/)
    end

    # Ванильная запись переименована в ДРУГОЙ существующий фит — сама по себе
    # законна, а сиальская половина, названная по старому имени, ложится
    # в пустоту. Молча это значило бы: у Сиалы снова выдача, а отличие
    # «не выдаёт никто» потеряно.
    test "запись Сиалы, которая ни на что не легла" do
      root = edit_grant(copy_rules(), &Map.put(&1, "feat", "mounted_combat"))
      load_raising(root, ~r/lands on nothing/)
    end

    test "класса нет" do
      root =
        edit_grant(
          copy_rules(),
          &Map.update!(&1, "classes", fn c -> Enum.sort(["warlock" | c]) end)
        )

      load_raising(root, ~r/names warlock, which is not a class/)
    end

    test "классы не по порядку или с повтором" do
      root = edit_grant(copy_rules(), &Map.update!(&1, "classes", fn c -> Enum.reverse(c) end))
      load_raising(root, ~r/ascending list of class ids/)
    end

    test "уровень не уровень" do
      root = edit_grant(copy_rules(), &Map.put(&1, "class_level", 0))
      load_raising(root, ~r/class_level/)
    end

    test "статус не verified" do
      root = edit_grant(copy_rules(), &Map.put(&1, "status", "unclear"))

      # Слой Сиалы свой статус кладёт поверх — проверяется ваниль без него.
      File.rm!(Path.join(root, @siala_file))
      load_raising(root, ~r/is not "verified"/)
    end

    test "ни один источник не строка cls_feat_*" do
      root = copy_rules()
      File.rm!(Path.join(root, @siala_file))
      root = edit_grant(root, &Map.delete(&1, "source_2"))
      load_raising(root, ~r/no source is a cls_feat_\*\.2da row/)
    end

    test "незнакомый ключ" do
      root = edit_grant(copy_rules(), &Map.put(&1, "granted_at", 1))
      load_raising(root, ~r/states \["granted_at"\]/)
    end

    test "запись дважды" do
      root = edit(copy_rules(), @vanilla_file, &update_in(&1, ["grants"], fn [g] -> [g, g] end))
      load_raising(root, ~r/twice/)
    end

    # Парсер научился читать выдачу сам — ручную запись надо снять, а не
    # держать тенью поверх машинной.
    test "выдача, которую машинный слой уже несёт" do
      root =
        edit(copy_rules(), "vanilla/classes.json", fn classes ->
          for c <- classes do
            if c["id"] == "fighter",
              do: update_in(c, ["granted_feats", "1"], &(&1 ++ ["mount_actions"])),
              else: c
          end
        end)

      load_raising(root, ~r/already grants mount_actions to fighter/)
    end
  end

  describe "сверка с таблицами игры и хака" do
    @base Path.expand("../../../priv/base_2da", __DIR__)
    @hak Path.expand("../../../priv/hak/2da", __DIR__)

    unless File.regular?(Path.join(@base, "manifest.json")) and
             File.regular?(Path.join(@hak, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                       "выгрузки: mix base2da.extract, mix hak.extract"
    end

    # FeatIndex 1089 — строка FEAT_HORSE_MENU в feat.2da; у хака она та же.
    @horse_menu "1089"

    setup do
      {:ok, source} = Source.load(@base)
      manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
      vanilla = "priv/rules" |> Path.join(@vanilla_file) |> File.read!() |> Jason.decode!()
      siala = "priv/rules" |> Path.join(@siala_file) |> File.read!() |> Jason.decode!()

      %{
        source: source,
        manifest: manifest,
        vanilla_record: hd(vanilla["grants"]),
        siala_record: hd(siala["grants"])
      }
    end

    # Таблица так, как её видит клиент Сиалы: своя, если шард её прислал,
    # иначе базовая. Файл хака сверяется с `sha1` его манифеста.
    defp hak_table(name, manifest, source) do
      key = String.downcase(name)

      case manifest["tables"][key] do
        nil ->
          Source.table(source, key)

        sha1 ->
          bytes = File.read!(Path.join(@hak, key <> ".2da"))
          assert :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower) == sha1
          TwoDA.parse!(bytes)
      end
    end

    # Строки FEAT_HORSE_MENU в таблице выдач каждого играбельного класса:
    # `%{class_label => [{row, list, level, on_menu}]}`.
    defp horse_rows(classes, table_of) do
      for {_i, r} <- TwoDA.rows(classes),
          r["PlayerClass"] == "1",
          table = table_of.(r["FeatsTable"]),
          rows =
            for(
              {j, fr} <- TwoDA.rows(table),
              fr["FeatIndex"] == @horse_menu,
              do: {j, fr["List"], TwoDA.to_int(fr["GrantedOnLevel"]), fr["OnMenu"]}
            ),
          rows != [],
          into: %{},
          do: {r["Label"], rows}
    end

    defp cited_rows(note) do
      for [_, table, row] <- Regex.scan(~r/(cls_feat_[a-z]+)\.2da:(\d+)/, note),
          into: %{},
          do: {table, String.to_integer(row)}
    end

    test "базовая игра: List 3 на 1-м уровне ровно у одиннадцати базовых, строки названы верно",
         %{source: source, vanilla_record: record} do
      classes = Source.table(source, "classes")
      rows = horse_rows(classes, &Source.table(source, &1))

      assert map_size(rows) == 11

      for {label, found} <- rows do
        assert [{_row, "3", 1, _menu}] = found, label
      end

      # Строки, названные в заметке записи, — те самые (позиция, не метка).
      cited = cited_rows(record["source_2"]["note"])
      assert map_size(cited) == 11

      for {table, row} <- cited do
        assert TwoDA.get(Source.table(source, table), row, "FeatIndex") == @horse_menu, table
      end

      assert TwoDA.get(Source.table(source, "feat"), 1089, "LABEL") == "HORSE_MENU"
      assert TwoDA.get(Source.table(source, "feat"), 1089, "MinLevel") == "99"
    end

    test "хак Сиалы: та же строка у тех же классов, но на 60-м уровне и без меню",
         %{source: source, manifest: manifest, vanilla_record: vrec, siala_record: srec} do
      classes = hak_table("classes", manifest, source)
      rows = horse_rows(classes, &hak_table(&1, manifest, source))
      cap = Data.ruleset!("siala_41").level_cap

      assert map_size(rows) == 11

      for {label, found} <- rows do
        assert [{_row, "3", level, "0"}] = found, label
        assert level > cap, "#{label}: выдача на #{level} — в пределах капа #{cap}"
        assert level == 60, label
      end

      # Все 11 таблиц шард присылает сам, а не наследует базовые.
      for {table, row} <- cited_rows(vrec["hak"]["note"]) do
        assert Map.has_key?(manifest["tables"], table), "#{table}: хак её не присылает"
        assert TwoDA.get(hak_table(table, manifest, source), row, "FeatIndex") == @horse_menu
        assert TwoDA.get(hak_table(table, manifest, source), row, "GrantedOnLevel") == "60"
      end

      assert map_size(cited_rows(vrec["hak"]["note"])) == 11
      assert cited_rows(srec["note"]) == cited_rows(vrec["hak"]["note"])

      # Цитата записи Сиалы — строка хака целиком, и её источник — эта строка.
      table = srec["source"]["table"] |> String.replace_suffix(".2da", "")
      assert srec["source"]["sha1"] == manifest["tables"][table]
      hak_row = TwoDA.row(hak_table(table, manifest, source), srec["source"]["row"])

      assert Enum.join(
               [
                 to_string(srec["source"]["row"])
                 | Enum.map(~w(FeatLabel FeatIndex List GrantedOnLevel OnMenu), &hak_row[&1])
               ],
               " "
             ) == srec["quote"]

      assert TwoDA.get(hak_table("feat", manifest, source), 1089, "MinLevel") == "99"
    end
  end
end
