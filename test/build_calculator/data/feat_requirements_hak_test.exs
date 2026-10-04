defmodule BuildCalculator.Data.FeatRequirementsHakTest do
  @moduledoc """
  Доказательство по хаку Сиалы для ванильных правок требований фитов
  (задачи 4.24 и 4.25).

  Ванильная запись `vanilla/feat_requirements.json` доезжает до `siala_41`
  сама: слой Сиалы накладывается сверху и переписывает только то, что
  называет. Значит правка ванили — законно и правка Сиалы, но только там, где
  шард этих строк не трогал. Хак шарда (`priv/hak/2da/`, задача 3.126) — это
  таблицы, которые исполняет клиент Сиалы; здесь сверяется, что у каждой
  записи они говорят то же, что базовая игра (`priv/base_2da/`, задача 4.5):

    * `only_on_class_levels` — строки `feat.2da` семейства у хака с той же
      меткой и тем же `ALLCLASSESCANUSE`, а классы, чьи `cls_feat_*` хака
      перечисляют эти строки с List 0/1, — ровно список записи (таблица
      класса у хака своя, если он её переопределяет, иначе базовая);
    * `Weapon specialization` — порог «воин 4» у хака тот же в 39 строках
      семейства из 40, а сороковая (дубина, строка 47) — без порога, и ровно
      это значение и ровно этот класс снимает запись слоя Сиалы
      (`siala_41/feats.json`, `what: "requirement_class_level_for_choice"`,
      задача 4.43, замер `BB1`);
    * `Lasting inspiration` — хак требует ту же строку 373 (Bard Song 20),
      и её выдаёт тот же бард 20;
    * **все семейства с выбором** (строк больше одной, задача 4.43) —
      хак отличается от базовой игры в колонках требований ровно там, где
      это известно и разобрано: дубина `Weapon specialization`, владение
      у `Weapon focus` / `Improved critical` (группы Сиалы, сверены с нашим
      слоем), выключенный `Devastating critical`, `Epic toughness I`
      и `Inspire courage`.

  🔴 Разойдётся — значит шард обновил хаки, и Сиале нужна своя запись
  (`siala_41/feats.json`, `kind: "hak"`), а не молча унаследованная ванильная
  (или, у дубины, снятая запись, если шард вернул строке порог).
  ⚠️ Совпадение таблиц — довод, а не замер: хак говорит, что видит КЛИЕНТ
  (`priv/hak/README.md`), а серверные скрипты шарда в выгрузке не лежат.
  Тот же механизм (`ALLCLASSESCANUSE 0` + списки `cls_feat_*`) Dan мерил на
  Сиале у трёх семей фитов — `*_rage`, `Automatic *`, эпические формы
  Оборотня, — и каждый раз игра сошлась с таблицей.

  Нужны обе выгрузки. В публичном репозитории и в CI их нет — модуль
  пропускается, а не падает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Diff, Source}
  alias BuildCalculator.Data
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules.GearWeapon

  @base Path.expand("../../../priv/base_2da", __DIR__)
  @hak Path.expand("../../../priv/hak/2da", __DIR__)
  @requirements Path.expand("../../../priv/rules/vanilla/feat_requirements.json", __DIR__)

  unless File.regular?(Path.join(@base, "manifest.json")) and
           File.regular?(Path.join(@hak, "manifest.json")) do
    @moduletag skip:
                 "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                   "выгрузки: mix base2da.extract, mix hak.extract"
  end

  # Восемь записей задачи 4.24 — обязаны быть среди проверенных, иначе цикл
  # ниже мог бы зеленеть, не дойдя до них.
  @task_4_24 ~w(bane_of_enemies great_smiting improved_ki_strike_4 improved_ki_strike_5
                improved_sneak_attack improved_spell_resistance lasting_inspiration
                planar_turning)

  setup_all do
    {:ok, source} = Source.load(@base)
    ctx = Diff.context(source, Data.ruleset!("vanilla"), "priv/rules")
    manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

    %{source: source, ctx: ctx, hak: &hak_table(&1, manifest, source)}
  end

  # Таблица хака — если шард её переопределяет, иначе базовая: так её видит
  # клиент Сиалы. Файл сверяется с `sha1` манифеста хака по той же причине,
  # что и базовая выгрузка (`Base2da.Source`): таблица, поправленная руками
  # после выгрузки, — не источник, а наше мнение под чужим именем.
  defp hak_table(name, manifest, source) do
    key = String.downcase(name)
    path = Path.join(@hak, key <> ".2da")

    case manifest["tables"][key] do
      nil ->
        Source.table(source, key)

      meta ->
        bytes = File.read!(path)
        sha1 = :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)
        expected = if is_map(meta), do: meta["sha1"], else: meta

        assert sha1 == expected, "#{path} не совпадает с sha1 манифеста хака"
        TwoDA.parse!(bytes)
    end
  end

  # Классы, чья таблица `cls_feat_*` перечисляет хоть одну из `rows` с List 0
  # или 1 — общим слотом фит берётся на их уровне (nwn.wiki, `feat.2da`,
  # `ALLCLASSESCANUSE`). Строка `classes.2da` — ПОЗИЦИЯ; метка у хака обязана
  # совпасть с базовой, иначе сопоставление классов было бы чужим.
  defp listing(ctx, classes_table, table_for, rows) do
    for {class, row} <- ctx.class_rows,
        assert_same_class_row(ctx, classes_table, row),
        table = table_for.(TwoDA.get(classes_table, row, "FeatsTable")),
        Enum.any?(TwoDA.rows(table), fn {_i, r} ->
          TwoDA.to_int(r["FeatIndex"]) in rows and TwoDA.to_int(r["List"]) in [0, 1]
        end),
        into: MapSet.new(),
        do: class
  end

  defp assert_same_class_row(ctx, classes_table, row) do
    assert TwoDA.get(classes_table, row, "Label") == TwoDA.get(ctx.classes, row, "Label"),
           "classes.2da хака, строка #{row}: метка не та же, что в базовой игре"

    true
  end

  defp shard_feats do
    "../../../priv/rules/siala_41/feats.json"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("feats")
  end

  defp hak_sha1(table) do
    @hak
    |> Path.join("manifest.json")
    |> File.read!()
    |> Jason.decode!()
    |> get_in(["tables", table])
  end

  defp entries_with_class_gate do
    @requirements
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("feats")
    |> Enum.filter(&is_list(&1["only_on_class_levels"]))
  end

  test "`only_on_class_levels`: хак Сиалы перечисляет те же классы, что запись и базовая игра",
       %{ctx: ctx, hak: hak} do
    hak_feat = hak.("feat")
    hak_classes = hak.("classes")

    checked =
      for entry <- entries_with_class_gate() do
        id = String.to_existing_atom(entry["id"])
        rows = ctx.families[id] || []
        assert rows != [], "#{id}: в feat.2da нет строк семейства"

        for row <- rows do
          for column <- ~w(LABEL ALLCLASSESCANUSE) do
            assert TwoDA.get(hak_feat, row, column) == TwoDA.get(ctx.feat, row, column),
                   "#{id}: feat.2da:#{row} #{column} у хака не тот, что в базовой игре"
          end
        end

        stated = MapSet.new(entry["only_on_class_levels"], &String.to_existing_atom/1)
        rowset = MapSet.new(rows)

        base = listing(ctx, ctx.classes, &Source.table(ctx.source, &1), rowset)
        shard = listing(ctx, hak_classes, hak, rowset)

        assert base == stated,
               "#{id}: запись называет #{inspect(Enum.sort(stated))}, базовая игра — " <>
                 inspect(Enum.sort(base))

        assert shard == stated,
               "#{id}: хак Сиалы перечисляет #{inspect(Enum.sort(shard))}, запись — " <>
                 "#{inspect(Enum.sort(stated))}. Сиале нужна своя запись с kind: hak"

        entry["id"]
      end

    assert length(checked) > 20
    assert @task_4_24 -- checked == []
  end

  # 🔴 Единственное расхождение хака с базовой игрой во всём, что правили
  # задачи 4.24 и 4.25, — и названо оно поимённо, а не допуском «примерно
  # совпадает». Строка 47 (club) у хака несёт правило ДО 1.69 (Fandom
  # «Weapon specialization», Previous versions: «Prior to version 1.69, only
  # a single fighter level was required to take weapon specialization in the
  # club»). С задачи 4.43 (замер BB1: «Дубина предлагается, рукопашный — нет»)
  # у Сиалы на неё своя запись, и тест держит ОБЕ стороны: строки хака
  # и ruleset Сиалы. Шард вернёт строке порог — тест упадёт, и запись надо
  # снять; снимет порог ещё у одной строки — упадёт тоже, и запись надо
  # дописать.
  test "`Weapon specialization`: порог «воин 4» у хака тот же, кроме строки дубины",
       %{ctx: ctx, hak: hak} do
    hak_feat = hak.("feat")
    rows = ctx.families[:weapon_specialization]

    threshold = fn table, row ->
      {TwoDA.get(table, row, "MinLevel"), TwoDA.get(table, row, "MinLevelClass")}
    end

    with_threshold = Enum.filter(rows, &(threshold.(ctx.feat, &1) != {nil, nil}))

    assert length(with_threshold) == 40
    assert Enum.all?(with_threshold, &(threshold.(ctx.feat, &1) == {"4", "4"}))
    assert TwoDA.get(ctx.classes, 4, "Label") == "Fighter"

    differ = for row <- with_threshold, threshold.(hak_feat, row) != {"4", "4"}, do: row

    assert differ == [47]
    assert TwoDA.get(hak_feat, 47, "LABEL") == "WeapSpeClub"
    assert threshold.(hak_feat, 47) == {nil, nil}

    # Остальное в строке дубины у хака то же: BAB 4 и Weapon Focus (club).
    for column <- ~w(MINATTACKBONUS PREREQFEAT1 ALLCLASSESCANUSE) do
      assert TwoDA.get(hak_feat, 47, column) == TwoDA.get(ctx.feat, 47, column)
    end

    # Сторона ruleset'а: Сиала снимает порог ровно у тех значений, чьи строки
    # хак оставил без него, и ровно у того класса, который строка называла
    # (`MinLevelClass 4` — строка Fighter в `classes.2da`).
    siala = Data.ruleset!("siala_41").feats[:weapon_specialization].prereqs
    family = siala["class_levels"]

    assert family == %{"fighter" => 4}

    unthresholded = for row <- differ, into: %{}, do: {to_string(ctx.choice_of_row.(row)), row}

    assert Map.keys(siala["class_levels_by_choice"]) == Map.keys(unthresholded)

    for {value, _row} <- unthresholded do
      assert siala["class_levels_by_choice"][value] == Map.delete(family, "fighter")
    end

    # И запись называет эту строку хака и тот же файл — sha1 манифеста.
    [record] =
      for entry <- shard_feats(),
          entry["id"] == "weapon_specialization",
          change <- entry["changes"],
          change["what"] == "requirement_class_level_for_choice",
          do: change

    assert record["source"]["kind"] == "hak"
    assert record["source"]["row"] == 47
    assert record["source"]["sha1"] == hak_sha1("feat")

    assert record["source"]["columns"] == %{
             "MinLevel" => TwoDA.get(hak_feat, 47, "MinLevel") || "****",
             "MinLevelClass" => TwoDA.get(hak_feat, 47, "MinLevelClass") || "****"
           }

    assert record["source_2"]["kind"] == "user"
  end

  # Колонки `feat.2da`, которые доходят до наших требований фитов.
  @requirement_columns ~w(MINATTACKBONUS MINSTR MINDEX MININT MINWIS MINCON MINCHA
                          MINSPELLLVL PREREQFEAT1 PREREQFEAT2 ALLCLASSESCANUSE
                          OrReqFeat0 OrReqFeat1 OrReqFeat2 OrReqFeat3 OrReqFeat4
                          REQSKILL ReqSkillMinRanks REQSKILL2 ReqSkillMinRanks2
                          MinLevel MinLevelClass MaxLevel MinFortSave PreReqEpic SUCCESSOR)

  @proficiency_columns ~w(PREREQFEAT1 OrReqFeat0 OrReqFeat1 OrReqFeat2 OrReqFeat3 OrReqFeat4)

  # 🔴 Сверка задачи 4.43, оформленная сторожем: у ВСЕХ семейств фитов
  # с выбором (строк в `feat.2da` больше одной — 54 семейства) хак отличается
  # от базовой игры в колонках требований РОВНО в шести семействах, и каждое
  # разобрано. Шард тронет ещё одну строку значения — тест упадёт и назовёт
  # её; так и находится следующая дубина.
  test "семейства с выбором: хак отличается от базы только там, где это разобрано",
       %{ctx: ctx, hak: hak} do
    hak_feat = hak.("feat")

    diffs =
      for {family, rows} <- ctx.families,
          length(rows) > 1,
          row <- rows,
          column <- @requirement_columns,
          {base, shard} = {TwoDA.get(ctx.feat, row, column), TwoDA.get(hak_feat, row, column)},
          base != shard,
          do: {family, row, column, base, shard}

    by_family = Enum.group_by(diffs, &elem(&1, 0), &Tuple.delete_at(&1, 0))

    assert by_family |> Map.keys() |> Enum.sort() ==
             [
               :devastating_critical,
               :epic_toughness,
               :improved_critical,
               :inspire_courage,
               :weapon_focus,
               :weapon_specialization
             ]

    # Дубина — тот же порог, что разбирает тест выше; запись слоя Сиалы.
    assert Enum.sort(by_family.weapon_specialization) ==
             [{47, "MinLevel", "4", nil}, {47, "MinLevelClass", "4", nil}]

    # Выключение `MINSTR 99` у сорока строк из 41 — уже записано у Сиалы
    # (`devastating_critical`, `what: "disabled"`, `kind: "hak"`, 3.130).
    assert Enum.all?(by_family.devastating_critical, &match?({_, "MINSTR", "25", "99"}, &1))
    assert length(by_family.devastating_critical) == 40

    # Другой формы, не порог по значению — описано в отчёте задачи 4.43
    # и стоит пунктом задачи 4.49 (сверка хака Сиалы против её слоя).
    assert Enum.sort(by_family.epic_toughness) ==
             [{754, "PreReqEpic", "1", "0"}, {754, "SUCCESSOR", "755", nil}]

    assert Enum.sort(by_family.inspire_courage) ==
             [{1085, "MINSTR", nil, "99"}, {1086, "MINSTR", nil, "99"}]

    # Владение у фокуса и улучшенного крита: только колонки владения. Что
    # они говорят, сверяет следующий тест.
    for family <- [:weapon_focus, :improved_critical],
        {_row, column, _b, _h} <- by_family[family] do
      assert column in @proficiency_columns, "#{family}: #{column}"
    end
  end

  # Хак Сиалы переписал владение у `Weapon focus` и `Improved critical` СВОИМИ
  # фитами: `PREREQFEAT1` — одна из пяти строк 2001–2005 (Hammers, Axes,
  # Polearms, Bows, Swords), списки `OrReqFeat*` сняты. Это третий,
  # независимый маршрут к таксономии `siala_proficiency_group` (до него —
  # страницы Сиалы и сверка Dan, `_siala_proficiency._note`), и он сходится
  # с ней у всех 38 оружий. Дубина у хака просит строку 46 (Weapon proficiency
  # (simple)), а у нас — «владения не требует»: на Сиале simple выдан всем
  # 23 классам на 1-м уровне (`siala_41/feats.json` → `weapon_proficiency_simple`),
  # так что ответы совпадают.
  @siala_proficiency_rows %{
    2001 => {"Hammers", :siala_hammer_proficiency},
    2002 => {"Axes", :siala_axe_proficiency},
    2003 => {"Polearms", :siala_polearm_proficiency},
    2004 => {"Bows", :siala_ranged_proficiency},
    2005 => {"Swords", :siala_blade_proficiency}
  }

  test "владение у Weapon focus и Improved critical: хак называет те же группы, что слой Сиалы",
       %{ctx: ctx, hak: hak} do
    hak_feat = hak.("feat")
    siala = Data.ruleset!("siala_41")

    for {row, {label, _feat}} <- @siala_proficiency_rows do
      assert TwoDA.get(hak_feat, row, "LABEL") == label
    end

    assert TwoDA.get(hak_feat, 46, "LABEL") == "WeapProfSim"

    by_row = Map.new(@siala_proficiency_rows, fn {row, {_label, feat}} -> {feat, row} end)

    checked =
      for family <- [:weapon_focus, :improved_critical],
          row <- ctx.families[family],
          weapon = ctx.choice_of_row.(row),
          is_atom(weapon) do
        required = TwoDA.to_int(TwoDA.get(hak_feat, row, "PREREQFEAT1"))

        for column <- @proficiency_columns -- ["PREREQFEAT1"] do
          assert TwoDA.get(hak_feat, row, column) == nil, "#{family} (#{weapon}): #{column}"
        end

        case GearWeapon.proficiency(siala, weapon) do
          {:feat, feat} -> assert required == Map.fetch!(by_row, feat), "#{family} (#{weapon})"
          :none_needed -> assert required in [nil, 46], "#{family} (#{weapon})"
        end

        weapon
      end

    # 39 значений у каждого из двух фитов: 38 оружий групп, дубина
    # и рукопашный удар (строка атаки существ — не оружие справочника).
    assert length(checked) == 80
  end

  # Хак требует ту же ступень, что и базовая игра, — значит страница Сиалы
  # («Песня барда (Bard song)») таблице не противоречит, а повторяет
  # недосказанность шаблона Fandom: игра называет «Bard Song» все двадцать
  # ступеней. Слой Сиалы этим требованием всё равно владеет сам (тест
  # слоения — `feat_requirements_test.exs`), и вопрос отдан координатору.
  test "`Lasting inspiration`: хак требует Bard Song 20, и выдаёт её тот же бард 20",
       %{ctx: ctx, hak: hak} do
    hak_feat = hak.("feat")
    hak_classes = hak.("classes")

    assert TwoDA.get(ctx.feat, 870, "LABEL") == "FEAT_EPIC_LASTING_INSPIRATION"

    for column <- ~w(LABEL PREREQFEAT1 PREREQFEAT2 REQSKILL ReqSkillMinRanks ALLCLASSESCANUSE) do
      assert TwoDA.get(hak_feat, 870, column) == TwoDA.get(ctx.feat, 870, column)
    end

    assert TwoDA.get(hak_feat, 870, "PREREQFEAT1") == "373"
    assert TwoDA.get(hak_feat, 373, "LABEL") == "Bard_Song_20"

    grants =
      for {class, row} <- ctx.class_rows,
          table = hak.(TwoDA.get(hak_classes, row, "FeatsTable")),
          {_i, r} <- TwoDA.rows(table),
          TwoDA.to_int(r["FeatIndex"]) == 373,
          do: {class, TwoDA.to_int(r["List"]), TwoDA.to_int(r["GrantedOnLevel"])}

    assert grants == [{:bard, 3, 20}]
  end
end
