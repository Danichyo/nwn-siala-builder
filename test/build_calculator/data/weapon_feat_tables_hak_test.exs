defmodule BuildCalculator.Data.WeaponFeatTablesHakTest do
  @moduledoc """
  Доказательство таблицами для двух ванильных правок, которые доезжают до Сиалы
  (задачи 4.27 и 4.30), — сверка базовых `.2da` (`priv/base_2da/`) и хака шарда
  (`priv/hak/2da/`):

    * **вход Чемпиона Торма и Мастера оружия** (4.27): FEATOR таблиц
      `cls_pres_divcha.2da` и `cls_pres_wm.2da` перечисляет Weapon Focus ровно
      тех 31 оружия, которые засчитывает наше требование, — без безоружного
      удара и оружия существ. Хак назначает классам те же таблицы и своих
      не присылает, а строки feat.2da, на которые они указывают, у него те же
      Weapon Focus, — значит исключение законно и для Сиалы;
    * **повторяемость Overwhelming critical и Devastating critical** (4.30):
      семейство по оружию — 40 строк feat.2da под MASTERFEAT 12 и 13, каждая
      требует фит того же оружия ступенью ниже. У хака те же строки; у
      Devastating critical отличается только MINSTR 99 — приём, которым шард
      фит выключил.

  🔴 Разойдётся хак — значит шард обновил таблицы, и Сиале нужна своя запись
  с `kind: "hak"`, а не молча унаследованная ванильная.
  ⚠️ Совпадение таблиц — довод, а не замер: хак говорит, что видит КЛИЕНТ
  (`priv/hak/README.md`); серверные скрипты шарда в выгрузке не лежат.

  Нужны обе выгрузки. В публичном репозитории и в CI их нет — модуль
  пропускается, а не падает.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Base2da.{Diff, Source}
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

  # Дословно то, что записано в данных, — строки семейств (ПОЗИЦИИ feat.2da).
  @overwhelming Enum.to_list(709..745) ++ [958, 999, 1078]
  @devastating Enum.to_list(495..531) ++ [955, 996, 1075]

  # Строки classes.2da и таблицы требований — у хака те же (сверяется ниже).
  @prestige %{champion_of_torm: {32, "cls_pres_divcha"}, weapon_master: {33, "cls_pres_wm"}}

  setup_all do
    {:ok, source} = Source.load(@base)
    manifest = @hak |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
    vanilla = Data.ruleset!("vanilla")

    %{
      source: source,
      manifest: manifest,
      hak: &hak_table(&1, manifest, source),
      ctx: Diff.context(source, vanilla, "priv/rules"),
      vanilla: vanilla,
      siala: Data.ruleset!("siala_41")
    }
  end

  # Таблица так, как её видит клиент Сиалы: своя, если шард её прислал, иначе
  # базовая. Файл хака сверяется с `sha1` его манифеста.
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

  defp rows_under(table, masterfeat) do
    for {i, r} <- TwoDA.rows(table), r["MASTERFEAT"] == masterfeat, do: i
  end

  # «Improved Critical (longsword)» → "longsword": оружие строки по её имени
  # из dialog.tlk (у хака имена те же — FEAT совпадает, см. тесты ниже).
  #
  # ⚠ Пробелы снимаются: имена писали разные руки — «Overwhelming Critical
  # (shortsword)» требует «Improved Critical (short sword)» (строки 723 и 65).
  defp weapon_of(source, row) do
    name = Source.row_name(source, "feat", row, "FEAT") || ""
    [_, weapon] = Regex.run(~r/\(([^)]+)\)\s*$/, name)
    weapon |> String.downcase() |> String.replace(" ", "")
  end

  describe "вход Чемпиона Торма и Мастера оружия (задача 4.27)" do
    test "FEATOR базовой игры — ровно то, что засчитывает наше требование", %{
      source: source,
      ctx: ctx,
      vanilla: vanilla,
      siala: siala
    } do
      for {class, {_row, table}} <- @prestige do
        feator =
          for {_i, r} <- TwoDA.rows(Source.table(source, table)),
              r["ReqType"] == "FEATOR",
              into: MapSet.new(),
              do: ctx.choice_of_row.(TwoDA.to_int(r["ReqParam1"]))

        assert MapSet.size(feator) == 31, "#{table}"
        refute MapSet.member?(feator, :creature_weapon)
        refute MapSet.member?(feator, :unarmed_strike)

        # Наше требование — все выбираемые, минус дальнобойные, минус
        # перечисленные исключения; на обоих ruleset'ах тот же итог.
        for ruleset <- [vanilla, siala] do
          domain = ruleset.choice_domains[:weapon]
          excluded = ruleset.classes[class].requirements[:feat_choice_excludes]["weapon_focus"]

          allowed =
            domain.flags.selectable
            |> MapSet.difference(domain.flags.ranged)
            |> MapSet.difference(MapSet.new(excluded, &String.to_existing_atom/1))

          assert allowed == feator, "#{ruleset.version} #{class}"
        end
      end
    end

    test "хак назначает те же таблицы и своих не присылает; строки FEATOR у него те же", %{
      source: source,
      manifest: manifest,
      hak: hak
    } do
      base_classes = Source.table(source, "classes")
      hak_classes = hak.("classes")
      base_feat = Source.table(source, "feat")
      hak_feat = hak.("feat")

      for {_class, {row, table}} <- @prestige do
        assert TwoDA.get(hak_classes, row, "Label") == TwoDA.get(base_classes, row, "Label")

        assert String.downcase(TwoDA.get(hak_classes, row, "PreReqTable")) == table
        assert String.downcase(TwoDA.get(base_classes, row, "PreReqTable")) == table

        refute Map.has_key?(manifest["tables"], table), "#{table}: хак присылает свою"

        for {_i, r} <- TwoDA.rows(Source.table(source, table)), r["ReqType"] == "FEATOR" do
          feat_row = TwoDA.to_int(r["ReqParam1"])

          for column <- ~w(LABEL FEAT MASTERFEAT) do
            assert TwoDA.get(hak_feat, feat_row, column) == TwoDA.get(base_feat, feat_row, column),
                   "feat.2da:#{feat_row}.#{column}"
          end
        end
      end
    end
  end

  describe "Overwhelming и Devastating critical — семейство по оружию (задача 4.30)" do
    test "базовая игра: по строке на оружие, каждая требует фит того же оружия", %{
      source: source
    } do
      feat = Source.table(source, "feat")

      assert rows_under(feat, "12") == @overwhelming
      assert rows_under(feat, "13") == @devastating

      for row <- @overwhelming ++ @devastating do
        assert TwoDA.get(feat, row, "GAINMULTIPLE") == "0", "feat.2da:#{row}"

        # Требование ступенью ниже — того же оружия (Improved Critical или
        # Overwhelming Critical), а PREREQFEAT1 — Great Cleave.
        below = TwoDA.int(feat, row, "PREREQFEAT2")
        assert weapon_of(source, below) == weapon_of(source, row), "feat.2da:#{row}"
        assert TwoDA.get(feat, row, "PREREQFEAT1") == "391"
      end

      for row <- @devastating, do: assert(TwoDA.int(feat, row, "PREREQFEAT2") in @overwhelming)
      assert Enum.uniq(Enum.map(@overwhelming, &TwoDA.get(feat, &1, "MINSTR"))) == ["23"]
      assert Enum.uniq(Enum.map(@devastating, &TwoDA.get(feat, &1, "MINSTR"))) == ["25"]

      assert Enum.uniq(Enum.map(@overwhelming ++ @devastating, &weapon_of(source, &1)))
             |> length() == 40
    end

    test "хак: те же строки; у Devastating critical отличается только MINSTR 99", %{
      source: source,
      hak: hak
    } do
      base = Source.table(source, "feat")
      hak_feat = hak.("feat")

      assert rows_under(hak_feat, "12") == @overwhelming
      assert rows_under(hak_feat, "13") == @devastating

      columns =
        ~w(LABEL FEAT MASTERFEAT PREREQFEAT1 PREREQFEAT2 MINSTR ALLCLASSESCANUSE PreReqEpic
           GAINMULTIPLE MinLevel MinLevelClass REMOVED)

      differing =
        for row <- @overwhelming ++ @devastating,
            column <- columns,
            TwoDA.get(hak_feat, row, column) != TwoDA.get(base, row, column),
            do: {row, column, TwoDA.get(base, row, column), TwoDA.get(hak_feat, row, column)}

      assert differing == for(row <- @devastating, do: {row, "MINSTR", "25", "99"})
    end

    # Слой Сиалы повторяемость этих двух не перекрывает — значит у неё тот же
    # блок, что у ванили, и это законно ровно потому, что хак тот же (выше).
    test "у Сиалы тот же блок повторяемости, что у ванили", %{vanilla: v, siala: s} do
      for id <- [:overwhelming_critical, :devastating_critical] do
        assert s.feats[id].repeatable == v.feats[id].repeatable
        assert %{choice: :weapon, distinct?: true} = v.feats[id].repeatable
      end

      refute s.feats[:overwhelming_critical].disabled?
      assert s.feats[:devastating_critical].disabled?
    end
  end
end
