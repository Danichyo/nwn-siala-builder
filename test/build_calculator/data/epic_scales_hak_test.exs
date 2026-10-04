defmodule BuildCalculator.Data.EpicScalesHakTest do
  @moduledoc """
  Доказательство по хаку Сиалы для эпических шкал престиж-классов после 30-го
  уровня класса (задача 4.26).

  Три ванильные записи продлены по таблицам базовой игры (`priv/base_2da/`):

    * уровни бонусных фитов десяти престиж-классов — `cls_bfeat_*.2da`
      (`vanilla/class_bonus_feat_levels.json`);
    * естественный AC Бледного мастера и РДД — `cls_stat_*.2da`
      (`vanilla/ac_bonuses.json`, Bone skin и Draconic armor);
    * Enchant Arrow Тайного лучника — `cls_feat_archer.2da` + `ruleset.2da`
      (`vanilla/feat_attack_bonuses.json`).

  Слой Сиалы накладывается сверху и ни одну из трёх шкал не переписывает, так
  что продление доезжает до `siala_41` само. Законно это ровно тогда, когда
  хак шарда (`priv/hak/2da/`) говорит то же, что базовая игра: здесь это
  сверяется таблицей, которую видит клиент Сиалы (своя — если шард её прислал,
  иначе базовая), и тем, что `classes.2da` хака назначает классам те же имена
  таблиц.

  🔴 У Сиалы из продлённого достижим 31-й уровень класса (потолок престижа 31):
  бонусный слот у Чёрного стража, Бледного мастера, Теневого танцора, Оборотня
  и Мастера оружия и Enchant Arrow +16. Разойдётся хак — значит шард обновил
  таблицы, и Сиале нужна своя запись с `kind: "hak"`, а не молча
  унаследованная ванильная.
  ⚠️ Совпадение таблиц — довод, а не замер: хак говорит, что видит КЛИЕНТ
  (`priv/hak/README.md`); серверные скрипты шарда в выгрузке не лежат.

  Нужны обе выгрузки. В публичном репозитории и в CI их нет — модуль
  пропускается, а не падает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.Source
  alias BuildCalculator.Data
  alias BuildCalculator.GameFiles.TwoDA

  @base Path.expand("../../../priv/base_2da", __DIR__)
  @hak Path.expand("../../../priv/hak/2da", __DIR__)
  @bonus_levels Path.expand("../../../priv/rules/vanilla/class_bonus_feat_levels.json", __DIR__)

  unless File.regular?(Path.join(@base, "manifest.json")) and
           File.regular?(Path.join(@hak, "manifest.json")) do
    @moduletag skip:
                 "нет priv/base_2da или priv/hak (публичный репозиторий, CI) — " <>
                   "выгрузки: mix base2da.extract, mix hak.extract"
  end

  # Строки classes.2da — ПОЗИЦИИ, и у хака они те же, что у базовой игры
  # (метка сверяется в `class_row/3`).
  @class_rows %{
    shadowdancer: 27,
    arcane_archer: 29,
    assassin: 30,
    blackguard: 31,
    champion_of_torm: 32,
    weapon_master: 33,
    pale_master: 34,
    shifter: 35,
    dwarven_defender: 36,
    red_dragon_disciple: 37
  }

  setup_all do
    {:ok, source} = Source.load(@base)
    manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

    %{
      source: source,
      manifest: manifest,
      hak: &hak_table(&1, manifest, source),
      vanilla: Data.ruleset!("vanilla"),
      siala: Data.ruleset!("siala_41")
    }
  end

  # Таблица так, как её видит клиент Сиалы: своя, если шард её переопределяет,
  # иначе базовая. Файл хака сверяется с `sha1` его манифеста — таблица,
  # поправленная руками после выгрузки, — не источник.
  defp hak_table(name, manifest, source) do
    key = String.downcase(name)

    case manifest["tables"][key] do
      nil ->
        Source.table(source, key)

      meta ->
        bytes = File.read!(Path.join(@hak, key <> ".2da"))
        sha1 = :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)
        expected = if is_map(meta), do: meta["sha1"], else: meta

        assert sha1 == expected, "#{key}.2da хака не совпадает с sha1 манифеста"
        TwoDA.parse!(bytes)
    end
  end

  defp class_row(base_classes, hak_classes, class) do
    row = Map.fetch!(@class_rows, class)
    label = TwoDA.get(base_classes, row, "Label")

    assert label != nil
    assert TwoDA.get(hak_classes, row, "Label") == label, "classes.2da:#{row} у хака не #{label}"

    row
  end

  defp bonus_levels(table) do
    for {i, row} <- TwoDA.rows(table),
        i + 1 <= 40,
        TwoDA.to_int(row["Bonus"]) not in [nil, 0],
        do: {i + 1, row["Bonus"]}
  end

  defp natural_ac(table) do
    for {i, row} <- TwoDA.rows(table), i + 1 <= 40, do: {i + 1, row["NaturalAC"]}
  end

  # Ступени Enchant Arrow: уровень выдачи → номер ступени, по меткам feat.2da
  # той же стороны (у хака — его feat.2da).
  defp enchant_grants(archer_table, feat_table) do
    for {_i, row} <- TwoDA.rows(archer_table),
        feat_row = TwoDA.to_int(row["FeatIndex"]),
        label = TwoDA.get(feat_table, feat_row, "LABEL") || "",
        [_, n] <- [Regex.run(~r/^FEAT_PRESTIGE_ENCHANT_ARROW_(\d+)$/, label)],
        into: %{},
        do: {TwoDA.to_int(row["GrantedOnLevel"]), String.to_integer(n)}
  end

  defp enchant_bonuses(ruleset_table) do
    for {_i, row} <- TwoDA.rows(ruleset_table),
        [_, n] <- [Regex.run(~r/^PRESTIGE_ENCHANT_ARROW_(\d+)_BONUS$/, row["Label"] || "")],
        into: %{},
        do: {String.to_integer(n), row["Value"]}
  end

  describe "бонусные фиты: cls_bfeat_* у Сиалы базовые" do
    test "classes.2da хака назначает те же таблицы, и клиент Сиалы видит те же строки", %{
      source: source,
      hak: hak,
      manifest: manifest
    } do
      base_classes = Source.table(source, "classes")
      hak_classes = hak.("classes")

      records =
        @bonus_levels |> File.read!() |> Jason.decode!() |> Map.fetch!("classes")

      assert length(records) == 10

      for record <- records do
        class = String.to_existing_atom(record["id"])
        row = class_row(base_classes, hak_classes, class)
        name = TwoDA.get(base_classes, row, "BonusFeatsTable")

        assert TwoDA.get(hak_classes, row, "BonusFeatsTable") == name, "#{class}"
        assert bonus_levels(hak.(name)) == bonus_levels(Source.table(source, name)), "#{class}"

        # Сегодня шард ни одной из этих таблиц не присылает — сравнение выше
        # сводится к «базовая против базовой». Это факт, а не допущение:
        # пришлёт — эта строка упадёт первой, и сравнение станет настоящим.
        assert manifest["tables"][String.downcase(name)] == nil, "#{name} в хаке появилась"
      end
    end

    test "слой Сиалы уровней не переписывает: у обоих ruleset'ов одно и то же", %{
      vanilla: v,
      siala: s
    } do
      for class <- Map.keys(@class_rows) do
        assert s.classes[class].epic_bonus_feat_levels == v.classes[class].epic_bonus_feat_levels,
               "#{class}"

        assert s.classes[class].bonus_feat_levels == v.classes[class].bonus_feat_levels,
               "#{class}"
      end
    end
  end

  describe "естественный AC: cls_stat_* у Сиалы базовые" do
    test "StatGainTable у хака та же, и столбец NaturalAC тот же", %{
      source: source,
      hak: hak,
      manifest: manifest
    } do
      base_classes = Source.table(source, "classes")
      hak_classes = hak.("classes")

      for class <- [:pale_master, :red_dragon_disciple] do
        row = class_row(base_classes, hak_classes, class)
        name = TwoDA.get(base_classes, row, "StatGainTable")

        assert name != nil
        assert TwoDA.get(hak_classes, row, "StatGainTable") == name, "#{class}"
        assert natural_ac(hak.(name)) == natural_ac(Source.table(source, name)), "#{class}"
        assert manifest["tables"][String.downcase(name)] == nil, "#{name} в хаке появилась"
      end
    end

    test "Bone skin и Draconic armor у Сиалы — те же записи, что у ванили", %{
      vanilla: v,
      siala: s
    } do
      for id <- [:bone_skin, :draconic_armor] do
        ours = Enum.find(s.ac_bonuses.applied, &(&1.id == id))
        theirs = Enum.find(v.ac_bonuses.applied, &(&1.id == id))

        assert ours.amount == theirs.amount, "#{id}"
      end
    end
  end

  describe "Enchant Arrow: таблицу шард переопределяет, ступени — те же" do
    # Единственная из трёх шкал, чью таблицу шард ПРИСЫЛАЕТ сам
    # (`cls_feat_archer.2da` в хаке есть, строки в ней на других позициях),
    # — поэтому сверяются не позиции, а смысл: какую ступень на каком уровне
    # выдаёт таблица и сколько ступень стоит.
    test "уровни выдачи ступеней и их величины у хака — как в базовой игре", %{
      source: source,
      hak: hak,
      manifest: manifest
    } do
      assert manifest["tables"]["cls_feat_archer"] != nil,
             "положительный контроль: эту таблицу шард присылает, сравнение настоящее"

      base_classes = Source.table(source, "classes")
      hak_classes = hak.("classes")
      row = class_row(base_classes, hak_classes, :arcane_archer)
      name = TwoDA.get(base_classes, row, "FeatsTable")

      assert TwoDA.get(hak_classes, row, "FeatsTable") == name

      base = enchant_grants(Source.table(source, name), Source.table(source, "feat"))
      shard = enchant_grants(hak.(name), hak.("feat"))

      assert shard == base
      assert Map.keys(base) |> Enum.sort() == Enum.to_list(1..39//2)
      assert base[31] == 16 and base[33] == 17

      assert enchant_bonuses(hak.("ruleset")) == enchant_bonuses(Source.table(source, "ruleset"))
      assert enchant_bonuses(Source.table(source, "ruleset"))[16] == "16"
    end

    test "у Сиалы та же шкала, что у ванили; оружие у неё своё", %{vanilla: v, siala: s} do
      ours = Enum.find(s.attack_bonuses.applied, &(&1.id == :enchant_arrow))
      theirs = Enum.find(v.attack_bonuses.applied, &(&1.id == :enchant_arrow))

      assert ours.amount == theirs.amount
      assert ours.amount.attack_at_class_level[31] == 16

      # Положительный контроль: записи — не одна и та же структура, слой Сиалы
      # до этой записи доезжает (арбалеты) и шкалу при этом не трогает.
      refute ours.weapon_kind == theirs.weapon_kind
    end
  end
end
