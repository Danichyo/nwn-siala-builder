defmodule BuildCalculator.GameFiles.BaseExtract do
  @moduledoc """
  Выгрузка базовых `.2da` NWN:EE из установки игры в `priv/base_2da/` —
  логика `mix base2da.extract` (задача 4.5). Задача только разбирает аргументы
  и печатает итог; всё остальное здесь, чтобы его можно было прогнать
  на синтетической «установке» в тесте.

  ## Откуда что берётся

    * `data/nwn_base.key` — индекс базовых ресурсов (обязателен);
    * `data/nwn_retail.key` — 🔴 **слой переопределения поверх него.** С патча
      89.8193.37 это «содержимое каталога `ovr/`», упакованное в `data/ovr.bif`
      (патчноут в установке, `lang/en/docs/patchnotes/89.8193.37.md`). В сборке
      37-17 он несёт более новые `classes`, `racialtypes`, `ruleset`, `skills`,
      `spells`: в `ruleset.2da` из `base_2da.bif` строки `MULTICLASS_LIMIT` нет,
      а в той, что читает игра, — есть. Поэтому ключи читаются **по старшинству**,
      первый нашедший таблицу выигрывает, а затенённая копия записывается
      в манифест рядом (`overrides`) — видно, что именно перекрыто;
    * `lang/en/data/dialog.tlk` — английские имена строк: таблицы называют
      сущности номером строки, а сопоставлять их с нашими id надо по имени,
      которое печатает игра. Выгружаются только имена, на которые ссылаются
      колонки имён выгруженных таблиц (`dialog_names.json`), не весь файл;
    * `databuild.txt`, самый новый патчноут и даты сборки в заголовках ключей —
      сборка игры, в манифест.

  ⚠ Россыпь `.2da` в `ovr/` — отказ, а не молчаливое чтение мимо: до 8193.37
  этот каталог был слоем переопределения, после — движок его не читает
  (кладёт туда только `nwscript.nss` «для людей»). Установка, где там лежат
  таблицы, — не та, для которой написан этот код, и выгрузить из неё неверный
  источник хуже, чем не выгрузить ничего.

  ## Какие таблицы

  Всё, что покрывает `vanilla/*.json` и нужно сверке (`mix base2da.diff`):
  точный список `tables/0` плюс семейства по префиксу `families/0`. После
  выгрузки проверяется **замыкание**: каждая таблица, на которую ссылается
  играбельный класс из `classes.2da` или играбельная раса из `racialtypes.2da`,
  обязана оказаться в выгрузке — иначе отказ с именем недостающей.

  ## Идемпотентность

  Файлы пишутся байт в байт как в BIF, `manifest.json` и `dialog_names.json` —
  детерминированным JSON (`BuildCalculator.Wiki.Json`), ключи по алфавиту.
  Повторный прогон на той же установке даёт пустой `git diff`; таблица, выпавшая
  из выгрузки, удаляется из каталога.
  """

  alias BuildCalculator.GameFiles.{KeyBif, Tlk, TwoDA}
  alias BuildCalculator.Wiki.Json

  # Порядок = старшинство: первый ключ, в котором нашлась таблица, выигрывает.
  @keys [
    {"data/nwn_retail.key", :optional},
    {"data/nwn_base.key", :required}
  ]

  @tables ~w(appearance armor baseitems classes creaturesize domains exptable feat
             masterfeats racialtypes ruleset skills spells spellschools)

  @families ~w(cls_atk_ cls_bfeat_ cls_feat_ cls_pres_ cls_savthr_ cls_skill_ cls_spgn_
               cls_spkn_ cls_stat_ race_feat_)

  @tlk "lang/en/data/dialog.tlk"

  # Колонки, где таблица держит номер строки в dialog.tlk с именем сущности.
  @name_columns [
    {"baseitems", "Name"},
    {"classes", "Name"},
    {"domains", "Name"},
    {"feat", "FEAT"},
    {"masterfeats", "STRREF"},
    {"racialtypes", "Name"},
    {"skills", "Name"},
    {"spells", "Name"},
    {"spellschools", "StringRef"}
  ]

  # Колонки, где играбельный класс или раса называют другую таблицу.
  @class_table_columns ~w(AttackBonusTable FeatsTable SavingThrowTable SkillsTable
                          BonusFeatsTable SpellGainTable SpellKnownTable PreReqTable
                          StatGainTable)

  @doc "Путь установки по умолчанию — Steam на macOS."
  @spec default_root() :: String.t()
  def default_root do
    Path.expand("~/Library/Application Support/Steam/steamapps/common/Neverwinter Nights")
  end

  @doc "Таблицы, выгружаемые по точному имени."
  @spec tables() :: [String.t()]
  def tables, do: @tables

  @doc "Префиксы семейств таблиц, выгружаемых целиком."
  @spec families() :: [String.t()]
  def families, do: @families

  @doc """
  Выгружает таблицы из установки `root` в каталог `out`.

  Опции (для теста): `:tables`, `:families` — заменить списки.
  Возвращает сводку или `{:error, текст}` — текст готов к показу человеку.
  """
  @spec run(Path.t(), Path.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(root, out, opts \\ []) do
    tables = Keyword.get(opts, :tables, @tables)
    families = Keyword.get(opts, :families, @families)

    with :ok <- check_root(root),
         :ok <- check_loose_overrides(root),
         {:ok, keys} <- load_keys(root),
         index = index_2da(keys),
         {:ok, wanted} <- wanted(index, tables, families),
         {:ok, extracted} <- extract(root, index, wanted),
         :ok <- check_closure(extracted),
         {:ok, names, tlk_info} <- names(root, extracted) do
      write(out, extracted, names, manifest(root, keys, extracted, tlk_info, names))
    end
  end

  # ---------------------------------------------------------------- input --

  defp check_root(root) do
    if File.regular?(Path.join(root, "data/nwn_base.key")) do
      :ok
    else
      {:error,
       """
       установка NWN:EE не найдена: #{root}
       (нет data/nwn_base.key)

       Задай путь переменной NWN_ROOT или ключом --root. По умолчанию берётся
       путь Steam на macOS: #{default_root()}
       """}
    end
  end

  defp check_loose_overrides(root) do
    loose = Path.wildcard(Path.join([root, "ovr", "*.2da"]), match_dot: true)

    if loose == [] do
      :ok
    else
      {:error,
       """
       в #{Path.join(root, "ovr")} лежат .2da (#{length(loose)} шт.).
       С 89.8193.37 движок этот каталог не читает, до — читал поверх KEY/BIF.
       Какая это сборка и что из этого действует, выгрузка решать не будет —
       разберись руками (priv/base_2da/README.md, «Старшинство источников»).
       """}
    end
  end

  defp load_keys(root) do
    Enum.reduce_while(@keys, {:ok, []}, fn {rel, need}, {:ok, acc} ->
      path = Path.join(root, rel)

      cond do
        File.regular?(path) ->
          bytes = File.read!(path)

          case KeyBif.parse_key(bytes) do
            {:ok, key} ->
              {:cont, {:ok, [Map.merge(key, %{file: rel, sha1: sha1(bytes)}) | acc]}}

            {:error, reason} ->
              {:halt, {:error, "#{rel}: не разобран как KEY V1 (#{inspect(reason)})"}}
          end

        need == :optional ->
          {:cont, {:ok, acc}}

        true ->
          {:halt, {:error, "нет #{rel} в #{root}"}}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      error -> error
    end
  end

  # resref → копии по старшинству ключей: [{key, resource}, …].
  defp index_2da(keys) do
    for key <- keys,
        resource <- key.resources,
        resource.type == KeyBif.restype_2da(),
        reduce: %{} do
      acc ->
        Map.update(
          acc,
          String.downcase(resource.resref),
          [{key, resource}],
          &(&1 ++ [{key, resource}])
        )
    end
  end

  defp wanted(index, tables, families) do
    missing = Enum.reject(tables, &Map.has_key?(index, &1))

    if missing != [] do
      {:error, "в установке нет таблиц: #{Enum.join(missing, ", ")}"}
    else
      by_family =
        index
        |> Map.keys()
        |> Enum.filter(fn resref -> Enum.any?(families, &String.starts_with?(resref, &1)) end)

      {:ok, Enum.sort(Enum.uniq(tables ++ by_family))}
    end
  end

  defp extract(root, index, wanted) do
    Enum.reduce_while(wanted, {{:ok, []}, %{}}, fn resref, {{:ok, acc}, cache} ->
      [{key, winner} | shadowed] = Map.fetch!(index, resref)

      with {:ok, bytes, cache} <- read(root, key, winner, cache),
           {:ok, table} <- parse_2da(resref, bytes),
           {:ok, overrides, cache} <- read_shadowed(root, shadowed, cache) do
        entry = %{
          resref: resref,
          bytes: bytes,
          table: table,
          key: key.file,
          bif: Enum.at(key.bifs, winner.bif).name,
          index: winner.index,
          overrides: overrides
        }

        {:cont, {{:ok, [entry | acc]}, cache}}
      else
        {:error, message} -> {:halt, {{:error, message}, cache}}
      end
    end)
    |> case do
      {{:ok, entries}, _cache} -> {:ok, Enum.reverse(entries)}
      {error, _cache} -> error
    end
  end

  defp read(root, key, resource, cache) do
    bif = Enum.at(key.bifs, resource.bif).name

    {bytes, cache} =
      case cache do
        %{^bif => bytes} ->
          {bytes, cache}

        _ ->
          path = Path.join(root, bif)
          bytes = if File.regular?(path), do: File.read!(path), else: nil
          {bytes, Map.put(cache, bif, bytes)}
      end

    cond do
      is_nil(bytes) ->
        {:error, "#{key.file} ссылается на #{bif}, а файла нет"}

      true ->
        case KeyBif.bif_resource(bytes, resource.index, KeyBif.restype_2da()) do
          {:ok, data} ->
            {:ok, data, cache}

          {:error, reason} ->
            {:error, "#{bif}, ресурс #{resource.index} (#{resource.resref}): #{inspect(reason)}"}
        end
    end
  end

  defp read_shadowed(root, shadowed, cache) do
    Enum.reduce_while(shadowed, {:ok, [], cache}, fn {key, resource}, {:ok, acc, cache} ->
      case read(root, key, resource, cache) do
        {:ok, bytes, cache} ->
          entry = %{
            key: key.file,
            bif: Enum.at(key.bifs, resource.bif).name,
            index: resource.index,
            sha1: sha1(bytes),
            bytes: byte_size(bytes)
          }

          {:cont, {:ok, acc ++ [entry], cache}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
  end

  defp parse_2da(resref, bytes) do
    case TwoDA.parse(bytes) do
      {:ok, table} -> {:ok, table}
      {:error, reason} -> {:error, "#{resref}.2da не разобрана как 2DA V2.0: #{inspect(reason)}"}
    end
  end

  # ------------------------------------------------------------- closure --

  defp check_closure(extracted) do
    have = MapSet.new(extracted, & &1.resref)
    by_name = Map.new(extracted, &{&1.resref, &1.table})

    referenced =
      referenced(by_name["classes"], "PlayerClass", @class_table_columns) ++
        referenced(by_name["racialtypes"], "PlayerRace", ["FeatsTable"])

    case Enum.reject(Enum.uniq(referenced), &MapSet.member?(have, &1)) do
      [] ->
        :ok

      missing ->
        {:error,
         "играбельные классы и расы ссылаются на невыгруженные таблицы: #{Enum.join(missing, ", ")}"}
    end
  end

  defp referenced(nil, _flag, _columns), do: []

  defp referenced(table, flag, columns) do
    for {_i, row} <- TwoDA.rows(table),
        row[flag] == "1",
        column <- columns,
        name = row[column],
        is_binary(name),
        do: String.downcase(name)
  end

  # --------------------------------------------------------------- names --

  defp names(root, extracted) do
    path = Path.join(root, @tlk)

    with true <- File.regular?(path) || {:error, "нет #{@tlk} — без имён сверку не сопоставить"},
         bytes = File.read!(path),
         {:ok, tlk} <- parse_tlk(bytes) do
      by_name = Map.new(extracted, &{&1.resref, &1.table})

      names =
        for {resref, column} <- @name_columns,
            table = by_name[resref],
            table != nil,
            {_i, row} <- TwoDA.rows(table),
            strref = TwoDA.to_int(row[column]),
            is_integer(strref),
            text = Tlk.string(tlk, strref),
            is_binary(text) and text != "",
            into: %{},
            do: {strref, text}

      {:ok, names, %{file: @tlk, sha1: sha1(bytes), language: tlk.language}}
    end
  end

  defp parse_tlk(bytes) do
    case Tlk.parse(bytes) do
      {:ok, tlk} -> {:ok, tlk}
      {:error, reason} -> {:error, "#{@tlk} не разобран как TLK V3.0: #{inspect(reason)}"}
    end
  end

  # -------------------------------------------------------------- output --

  defp manifest(root, keys, extracted, tlk_info, names) do
    {version, version_file, released} = game_version(root)

    {:obj,
     [
       {"_note",
        "Базовые .2da NWN:EE, выгруженные mix base2da.extract из установки игры. " <>
          "sha1 — байты файла рядом; key/bif/index — откуда он взят; overrides — " <>
          "затенённые копии из ключей ниже по старшинству. Копирайт Beamdog/WotC: " <>
          "каталог не публикуется (tools/public/publish.sh), см. README.md."},
       {"game",
        {:obj,
         [
           {"databuild", databuild(root)},
           {"keys",
            Enum.with_index(keys, 1)
            |> Enum.map(fn {key, order} ->
              {:obj,
               [
                 {"built_on", key.built_on && Date.to_iso8601(key.built_on)},
                 {"file", key.file},
                 {"precedence", order},
                 {"sha1", key.sha1}
               ]}
            end)},
           {"released", released},
           {"version", version},
           {"version_from", version_file}
         ]}},
       {"names",
        {:obj,
         [
           {"file", "dialog_names.json"},
           {"from", tlk_info.file},
           {"language", tlk_info.language},
           {"sha1", tlk_info.sha1},
           {"strings", map_size(names)}
         ]}},
       {"tables",
        {:obj,
         Enum.map(extracted, fn e ->
           {e.resref,
            {:obj,
             [
               {"bif", e.bif},
               {"bytes", byte_size(e.bytes)},
               {"index", e.index},
               {"key", e.key}
             ] ++
               overrides_field(e.overrides) ++
               [{"rows", TwoDA.count(e.table)}, {"sha1", sha1(e.bytes)}]}}
         end)}}
     ]}
  end

  defp overrides_field([]), do: []

  defp overrides_field(overrides) do
    [
      {"overrides",
       Enum.map(overrides, fn o ->
         {:obj,
          [
            {"bif", o.bif},
            {"bytes", o.bytes},
            {"index", o.index},
            {"key", o.key},
            {"sha1", o.sha1}
          ]}
       end)}
    ]
  end

  defp databuild(root) do
    path = Path.join(root, "databuild.txt")

    if File.regular?(path) do
      path
      |> File.read!()
      |> String.split(~r/\R/, trim: true)
      |> Enum.map_join(" ", &String.trim/1)
    end
  end

  # Самый новый патчноут по номеру версии: `89.8193.37-17.md` новее `89.8193.37.md`.
  defp game_version(root) do
    dir = Path.join(root, "lang/en/docs/patchnotes")

    newest =
      dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        case Regex.run(~r/^(\d+)\.(\d+)\.(\d+)(?:-(\d+))?\.md$/, Path.basename(path)) do
          [_, a, b, c] -> [{{int(a), int(b), int(c), 0}, path}]
          [_, a, b, c, d] -> [{{int(a), int(b), int(c), int(d)}, path}]
          _ -> []
        end
      end)
      |> Enum.max_by(&elem(&1, 0), fn -> nil end)

    case newest do
      nil ->
        {nil, nil, nil}

      {_order, path} ->
        rel = Path.relative_to(path, root)

        case Regex.run(~r/^##\s*\[([^\]]+)\]\s*-\s*(\d{4}-\d{2}-\d{2})/m, File.read!(path)) do
          [_, version, date] -> {version, rel, date}
          _ -> {Path.basename(path, ".md"), rel, nil}
        end
    end
  end

  defp int(s), do: String.to_integer(s)

  defp write(out, extracted, names, manifest) do
    File.mkdir_p!(out)
    keep = MapSet.new(extracted, &"#{&1.resref}.2da")

    stale =
      out
      |> Path.join("*.2da")
      |> Path.wildcard()
      |> Enum.reject(&MapSet.member?(keep, Path.basename(&1)))

    Enum.each(stale, &File.rm!/1)
    Enum.each(extracted, &write_if_changed(Path.join(out, "#{&1.resref}.2da"), &1.bytes))

    names_json =
      names
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {strref, text} -> {Integer.to_string(strref), text} end)
      |> then(&Json.encode!({:obj, &1}))

    write_if_changed(Path.join(out, "dialog_names.json"), names_json)
    write_if_changed(Path.join(out, "manifest.json"), Json.encode!(manifest))

    {:ok,
     %{
       tables: length(extracted),
       bytes: Enum.sum(Enum.map(extracted, &byte_size(&1.bytes))),
       overridden: Enum.count(extracted, &(&1.overrides != [])),
       removed: length(stale),
       names: map_size(names)
     }}
  end

  defp write_if_changed(path, bytes) do
    case File.read(path) do
      {:ok, ^bytes} -> :ok
      _ -> File.write!(path, bytes)
    end
  end

  defp sha1(bytes), do: :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)
end
