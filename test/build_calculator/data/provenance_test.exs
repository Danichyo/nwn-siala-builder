defmodule BuildCalculator.Data.ProvenanceTest do
  @moduledoc """
  🔴 Сторож провенанса ванили (задача 4.6, `VANILLA.md` §4.6).

  Ваниль — отдельный продукт, и её число не должно держаться на странице вики
  Сиалы или на замере с сервера Сиалы. Каждая запись с источником, видимая ванили
  (`priv/rules/vanilla/*.json`) и решающая её число, несёт ванильный источник
  (Fandom или строку базовой таблицы игры, `kind: "2da"`) либо честную пометку
  «замер движка на сервере Сиалы; шард механику не трогает» с доводом. Правила —
  `BuildCalculator.Data.Provenance`, отчёт — `mix provenance.audit`.

  Здесь пять вещей, и каждая стережёт своё:

    * **сторож** — нарушений в живых данных ноль, иначе тест печатает их списком;
    * **положительный контроль** — подложенная в память запись с источником Сиалы
      (страница, `quote_siala`, `kind: "user"` без пометки) сторожа роняет; без
      этого «ноль нарушений» было бы неотличимо от слепого обхода;
    * **правило «не читается»** проверено МУТАЦИЕЙ: всё, что `Provenance` считает
      непрочитанным, вырезается из копии данных, и оба ruleset'а обязаны совпасть
      с настоящими — со своим положительным контролем;
    * **цитаты-строки `.2da`** сверены с самими таблицами (строка, колонка,
      значение, метка);
    * **цитаты Fandom** в ручных файлах лежат в кэше `priv/wiki_cache/fandom/`
      дословно — «ванильный источник» значит цитату из снапшота, а не пересказ.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BuildCalculator.Base2da.Source
  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Data.Provenance
  alias BuildCalculator.GameFiles.TwoDA

  @root "priv/rules"

  setup_all do
    files = Provenance.read_vanilla!(@root)
    %{files: files, records: Provenance.records(files)}
  end

  defp describe_all(records) do
    Enum.map_join(records, "\n", fn r ->
      "  #{r.file} #{Provenance.render_path(r.path)} — #{r.verdict_why}"
    end)
  end

  defp violations_after(files, fun) do
    files |> fun.() |> Provenance.records() |> Provenance.violations()
  end

  defp put_rule(files, key, record),
    do: update_in(files, ["rules.json", "character"], &Map.put(&1, key, record))

  describe "сторож" do
    test "ни одна запись, решающая ванильное число, не держится на Сиале", %{records: records} do
      violations = Provenance.violations(records)

      assert violations == [],
             "записи решают число ванили без ванильного источника и без пометки «замер движка»:\n" <>
               describe_all(violations)
    end

    # Обход обязан видеть данные, а не пустоту: записей с источником — сотни,
    # решающих число — большинство, и ванильный источник у подавляющего числа.
    test "обход видит живые данные", %{records: records} do
      census = Provenance.census(records)

      assert census.total > 1000
      assert census.by_decides[:number] > 900
      assert census.by_verdict[:vanilla_source] > 1000
    end

    # 🔴 Спор в списке отложенного обязан совпадать с живой записью: устаревшее
    # исключение хуже отсутствующего — оно молча пропустит следующую запись
    # с тем же путём.
    test "каждый отложенный спор называет существующую запись", %{records: records} do
      for {file, path, why} <- Provenance.pending() do
        assert Enum.any?(
                 records,
                 &(&1.file == file and &1.path == path and &1.verdict == :pending)
               ),
               "#{file} #{Enum.join(path, "/")}: отложено («#{why}»), а такой решающей записи нет"
      end
    end

    # Задача 4.44: исключение «⏸ E5/X1» снято — кейс AX1 закрыт словом Dan
    # 27.09.2026 («правила AC на Сиале не менялись»), и запись проходит сторожа
    # по общим правилам: решает число ванили и держится на Fandom — цитаты
    # «Dodge», «Armor skin», «Draconic armor» стоят парами с источниками
    # (`quote_3` ↔ `source_3` …), и сторож цитат ниже сверяет их с кэшем.
    # Вернуть запись в `pending/0` значило бы спрятать то, что прятать незачем.
    test "AX1 закрыт: gear/ac_types/same_type — ванильный источник, а не спор", %{
      records: records,
      files: files
    } do
      path = ["gear", "ac_types", "same_type"]

      assert %{verdict: :vanilla_source, decides: :number, kinds: kinds} =
               Enum.find(records, &(&1.file == "rules.json" and &1.path == path))

      assert :fandom in kinds

      record = get_in(files, ["rules.json" | path])

      for n <- ~w(3 7 8) do
        assert %{"wiki" => "fandom", "page" => _} = record["source_" <> n], "source_#{n}"
        assert is_binary(record["quote_" <> n]), "quote_#{n}"
      end
    end
  end

  describe "положительный контроль" do
    test "запись со страницей Сиалы роняет сторожа", %{files: files} do
      violations =
        violations_after(files, fn f ->
          put_rule(f, "probe", %{
            "value" => 5,
            "source" => %{"wiki" => "siala", "kind" => "wiki", "page" => "Расы", "revid" => 1},
            "status" => "verified"
          })
        end)

      assert [%{path: ["character", "probe"], kinds: [:siala_wiki]}] = violations
    end

    test "цитата Сиалы без ванильного источника роняет сторожа", %{files: files} do
      violations =
        violations_after(files, fn f ->
          put_rule(f, "probe", %{"value" => 5, "quote_siala" => "…", "status" => "verified"})
        end)

      assert [%{path: ["character", "probe"], kinds: [:siala_quote]}] = violations
    end

    test "kind: user без пометки «замер движка» роняет сторожа", %{files: files} do
      user = %{"kind" => "user", "who" => "Dan", "date" => "2026-09-26"}

      violations =
        violations_after(files, fn f ->
          put_rule(f, "probe", %{"value" => 5, "source" => user, "status" => "verified"})
        end)

      assert [%{path: ["character", "probe"], unmarked_users: 1}] = violations
    end

    test "пометка «замер движка» с доводом сторожа устраивает, без довода — нет", %{files: files} do
      marked = fn engine ->
        violations_after(files, fn f ->
          put_rule(f, "probe", %{
            "value" => 5,
            "source" => %{"kind" => "user", "who" => "Dan", "engine" => engine},
            "status" => "verified"
          })
        end)
      end

      assert marked.(%{"basis" => "measurement", "untouched_by_shard" => "строки хака те же"}) ==
               []

      assert [_] = marked.(%{"basis" => "measurement", "untouched_by_shard" => "  "})

      # Слово без наблюдения пометкой не становится: ему нужен ванильный источник.
      assert [_] = marked.(%{"basis" => "word", "untouched_by_shard" => "так работает"})
    end

    # Провенанс ПОЛЯ — отдельная запись: Fandom у требований фита не покрывает
    # поле `only_on_class_levels`, у которого свой источник.
    test "источник поля судится отдельно от источника записи", %{files: files} do
      violations =
        violations_after(files, fn f ->
          update_in(f, ["feat_requirements.json", "feats"], fn [first | rest] ->
            [
              Map.merge(first, %{
                "only_on_class_levels" => ["bard"],
                "only_on_class_levels_source" => %{"kind" => "user", "who" => "Dan"}
              })
              | rest
            ]
          end)
        end)

      assert [%{file: "feat_requirements.json", path: [_, _, "only_on_class_levels"]}] =
               violations
    end

    # Задача 4.28: официальное руководство игры (BioWare, 2002) — ванильный
    # источник сам по себе; незнакомый вид источника — нет. Хват луков на Fandom
    # не назван ни одной страницей, и опора у него — руководство.
    test "руководство игры — ванильный источник, незнакомый вид — нет", %{files: files} do
      with_source = fn source ->
        violations_after(files, fn f ->
          put_rule(f, "probe", %{"value" => 5, "source" => source, "status" => "verified"})
        end)
      end

      assert with_source.(%{"kind" => "manual", "title" => "NWN Manual", "pdf_page" => 79}) ==
               []

      assert [%{path: ["character", "probe"], kinds: [:unknown]}] =
               with_source.(%{"kind" => "forum", "url" => "https://example.org"})

      assert :manual in Provenance.vanilla_kinds()
    end

    # Что загрузчик не читает, числа не решает: блок `siala` — место, где
    # ванильная запись хранит слова Сиалы о себе.
    test "источник Сиалы в блоке `siala` сторожа не роняет", %{files: files} do
      assert violations_after(files, fn f ->
               put_rule(f, "probe", %{
                 "value" => 5,
                 "source" => %{"wiki" => "fandom", "page" => "X"},
                 "siala" => %{"source" => %{"wiki" => "siala", "page" => "Y"}},
                 "status" => "verified"
               })
             end) == []
    end
  end

  describe "правило «не читается» проверено мутацией" do
    defp copy_stripped(files, strip) do
      root = BuildCalculator.TmpDir.unique_path!("provenance_")
      File.cp_r!(@root, root)
      on_exit(fn -> File.rm_rf!(root) end)

      for {file, json} <- files do
        File.write!(Path.join([root, "vanilla", file]), Jason.encode!(strip.(json)))
      end

      root
    end

    defp strip(%{} = map, drop?),
      do: for({k, v} <- map, not drop?.(k), into: %{}, do: {k, strip(v, drop?)})

    defp strip(list, drop?) when is_list(list), do: Enum.map(list, &strip(&1, drop?))
    defp strip(other, _drop?), do: other

    defp load(root) do
      log = capture_log(fn -> send(self(), {:loaded, Loader.load!(root)}) end)
      assert is_binary(log)
      assert_received {:loaded, loaded}
      loaded
    end

    # 🔴 Всё, что обход считает непрочитанным (`Provenance.unread_key?/1`: блоки
    # `siala`, подтверждения игрока, разбор под ключами с подчёркиванием…),
    # вырезается из КАЖДОГО ванильного файла — и ни одно поле ни одного ruleset'а
    # не сдвигается. Сдвинулось — ключ читается, и его место в списке
    # прочитанного, а не здесь.
    test "вырезанное непрочитанное не сдвигает ни одного поля", %{files: files} do
      root = copy_stripped(files, &strip(&1, fn key -> Provenance.unread_key?(key) end))
      loaded = load(root)

      assert loaded["vanilla"] == Data.ruleset!("vanilla")
      assert loaded["siala_41"] == Data.ruleset!("siala_41")
    end

    # Положительный контроль: прочитанный ключ, вырезанный тем же приёмом, ruleset
    # сдвигает — сравнение выше не слепое. (`max_classes`, а не секция с
    # подчёркиванием: без `_vanilla_constants_confirmed` не собирается Сиала,
    # и контроль проверял бы падение, а не сравнение.)
    test "контроль: вырезанный прочитанный ключ ruleset сдвигает", %{files: files} do
      root = copy_stripped(files, &strip(&1, fn key -> key == "max_classes" end))
      loaded = load(root)

      assert loaded["vanilla"].max_classes == nil
      refute loaded["vanilla"] == Data.ruleset!("vanilla")
    end
  end

  # 🔴 Решения показа (задача 4.20) — записи со словом владельца без ванильного
  # источника, которые сторож пропускает, потому что они решают ОГОВОРКУ, а не
  # число. Оба утверждения проверены, а не объявлены: путь совпадает с живой
  # записью, и вырезанная запись сдвигает в ruleset'ах только список оговорок.
  describe "решения показа" do
    test "каждое решение показа называет живую запись со словом владельца", %{records: records} do
      assert Enum.any?(
               Provenance.display_decisions(),
               &match?({"rules.json", ["character", "hit_points_shown"], _}, &1)
             )

      for {file, path, _why} <- Provenance.display_decisions() do
        assert %{decides: :caveat, verdict: :not_deciding, kinds: [:user]} =
                 Enum.find(records, &(&1.file == file and &1.path == path)),
               "#{file} #{Provenance.render_path(path)}: решения показа с таким путём нет"
      end
    end

    # Положительный контроль: та же запись под другим именем — уже не решение
    # из списка, а `kind: user` без пометки, и сторож падает.
    test "та же запись под другим именем роняет сторожа", %{files: files} do
      decision = get_in(files, ["rules.json", "character", "hit_points_shown"])

      assert [%{path: ["character", "probe"], unmarked_users: 1}] =
               violations_after(files, &put_rule(&1, "probe", decision))
    end

    test "вырезанное решение сдвигает в ruleset'ах только список оговорок", %{files: files} do
      for {file, path, _why} <- Provenance.display_decisions() do
        root = BuildCalculator.TmpDir.unique_path!("display_decision_")
        File.cp_r!(@root, root)
        on_exit(fn -> File.rm_rf!(root) end)

        stripped = Provenance.delete_at(files[file], path)
        File.write!(Path.join([root, "vanilla", file]), Jason.encode!(stripped))

        loaded = Loader.load!(root)

        for version <- ["vanilla", "siala_41"] do
          real = Data.ruleset!(version)

          assert %{loaded[version] | gaps: real.gaps} == real,
                 "#{file} #{Provenance.render_path(path)}: вырезанное решение двигает не только " <>
                   "оговорки (#{version})"
        end

        # ...и оговорку двигает: решение не мёртвое (контроль к сравнению выше).
        refute loaded["vanilla"].gaps == Data.ruleset!("vanilla").gaps
      end
    end
  end

  describe "цитаты-строки базовых таблиц" do
    @base2da Path.expand("../../../priv/base_2da", __DIR__)

    unless File.regular?(Path.join(@base2da, "manifest.json")) do
      @describetag skip:
                     "нет priv/base_2da (публичный репозиторий, CI) — выгрузка: mix base2da.extract"
    end

    # Каждый источник `kind: "2da"` называет таблицу и строку, и то, что он
    # утверждает о ячейке, обязано в ней лежать: `column` + `value` — значение
    # ячейки, `label` — метка строки. Строка — ПОЗИЦИЯ, а не метка (HANDOFF.md,
    # «Таблицы игры: два KEY-файла, строка — это позиция»).
    test "каждая ссылка на строку .2da совпадает с таблицей", %{files: files} do
      {:ok, source} = Source.load(@base2da)
      cited = for {file, json} <- files, s <- base2da_sources(json), do: {file, s}

      assert length(cited) > 20

      for {file, s} <- cited do
        where = "#{file}: #{s["table"]} строка #{s["row"]}"
        table = Source.table(source, String.replace_suffix(s["table"], ".2da", ""))

        assert table, "#{where}: таблицы нет в выгрузке"
        assert is_integer(s["row"]) and s["row"] < TwoDA.count(table), "#{where}: строки нет"

        if s["column"],
          do:
            assert(TwoDA.get(table, s["row"], s["column"]) == s["value"],
              message:
                "#{where}: #{s["column"]} = #{inspect(TwoDA.get(table, s["row"], s["column"]))}, " <>
                  "а цитата говорит #{inspect(s["value"])}"
            )

        if s["label"],
          do:
            assert(TwoDA.get(table, s["row"], "Label") == s["label"],
              message: "#{where}: метка строки не #{s["label"]}"
            )
      end
    end

    defp base2da_sources(%{"kind" => "2da", "table" => _} = s), do: [s]

    defp base2da_sources(%{} = map),
      do: Enum.flat_map(map, fn {_k, v} -> base2da_sources(v) end)

    defp base2da_sources(list) when is_list(list), do: Enum.flat_map(list, &base2da_sources/1)
    defp base2da_sources(_other), do: []
  end

  describe "цитаты Fandom лежат в кэше" do
    # Машинные файлы пишет `mix wiki.parse`, и их цитаты проверяют его тесты;
    # здесь — рукописные, которые правят люди.
    @machine ~w(classes.json skills.json feats.json spells.json races.json epic.json
                creature_types.json spell_schools.json energy_types.json weapons.json icons.json)

    test "каждая цитата Fandom в ручных файлах дословно есть на странице кэша", %{files: files} do
      index =
        "priv/wiki_cache/fandom/_index.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.new(&{&1["title"], &1["file"]})

      pairs =
        for {file, json} <- files,
            file not in @machine,
            pair <- quote_pairs(json, []),
            do: {file, pair}

      checked =
        for {file, {path, quote, page}} <- pairs, cached = index[page], cached != nil do
          text = normalize(File.read!(Path.join("priv/wiki_cache/fandom", cached)))

          assert String.contains?(text, normalize(quote)),
                 "#{file} #{Enum.join(path, "/")}: цитаты нет на странице Fandom «#{page}» в кэше"

          :ok
        end

      assert length(checked) > 300
    end

    # `quote` → `source`, `quote_2` → `source_2`, `scope_quote_2` → `scope_source_2`,
    # `quote_fandom` → `source_fandom`: цитата и её источник — соседние ключи.
    defp quote_pairs(%{} = map, path) do
      own =
        for {key, value} <- map,
            is_binary(value),
            [_, pre, suf] <- [Regex.run(~r/\A([a-z_]*?)quote((?:_[a-z0-9_]+)?)\z/, key)],
            %{"wiki" => "fandom", "page" => page} <- [map[pre <> "source" <> suf]],
            do: {path ++ [key], value, page}

      own ++ Enum.flat_map(map, fn {k, v} -> quote_pairs(v, path ++ [k]) end)
    end

    defp quote_pairs(list, path) when is_list(list),
      do: list |> Enum.with_index() |> Enum.flat_map(fn {v, i} -> quote_pairs(v, path ++ [i]) end)

    defp quote_pairs(_other, _path), do: []

    # Вики-ссылки `[[страница|текст]]` и сущности цитаты передают текстом —
    # сравнивается то, что видит читатель страницы.
    defp normalize(text) do
      text
      |> String.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/, "\\1")
      |> String.replace("&mdash;", "—")
      |> String.replace("&ndash;", "–")
      |> String.replace("&nbsp;", " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
    end
  end
end
