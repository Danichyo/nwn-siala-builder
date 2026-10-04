defmodule Mix.Tasks.Hak.Extract do
  @shortdoc "Достаёт .2da шарда из nwsync-кэша игрового клиента"

  @moduledoc """
  Выкладывает таблицы правил шарда из локального клиента NWN в `priv/hak/2da/`.

  ## Зачем это существует

  Полтора месяца проект держался на том, что `CLAUDE.md` §3 называет «вики + ручная
  выверка»: машинночитаемого источника истины у нас не было, и там же дважды
  записано «доступа к `.2da`/хакам не будет». ⚠️ **Посылка этой записи была
  неверна** — она говорила «сервером заведуют другие люди», а хаки шард отдаёт
  **клиенту**: NWN:EE складывает их в `nwsync`, и они лежат на диске у любого,
  кто хоть раз зашёл на сервер. Проверено 27.08.2026: 4.1 ГБ, из них 185 таблиц.

  Первая же сверка (шесть фитов и таблица атаки монаха) показала, что ручная
  выверка по вики была точной — и что теперь у неё есть чем проверяться.

  ## Как устроено хранилище клиента

  Две базы SQLite в `~/Documents/Neverwinter Nights/nwsync/`:

    * `nwsyncmeta.sqlite3` — `manifest_resrefs(resref, restype, resref_sha1)`,
      то есть имя ресурса и его хэш. `restype` 2017 — это `.2da`;
    * `nwsyncdata_0.sqlite3` — `resrefs(sha1, data, size)`, сами файлы.

  ⚠️ **Содержимое не лежит сырым.** Каждый blob — контейнер `NSYC`: 24 байта
  заголовка (сигнатура, версия, алгоритм, размер распакованного), дальше поток
  **zstd**. Магию zstd (`28 b5 2f fd`) видно на 25-м байте, ей и проверяем, что
  формат не сменился, вместо того чтобы верить смещению вслепую.

  ## Обновление

  Шард обновляет хаки, и Dan попросил уметь переложить новую версию (27.08.2026).
  Поэтому задача **идемпотентна** и пишет рядом `manifest.json` с `sha1` каждой
  таблицы: `git diff` после прогона показывает ровно то, что шард поменял.

      mix hak.extract

  ⚠️ Задача **читает** клиентский кэш и ничего в нём не трогает.
  """

  use Mix.Task

  @nwsync Path.expand("~/Documents/Neverwinter Nights/nwsync")
  @out "priv/hak/2da"
  @restype_2da 2017
  # `NSYC` + 5 полей по 4 байта: version, algorithm, size, и пара служебных.
  @header_bytes 24
  @zstd_magic <<0x28, 0xB5, 0x2F, 0xFD>>

  @impl true
  def run(_args) do
    meta = Path.join(@nwsync, "nwsyncmeta.sqlite3")
    data = Path.join(@nwsync, "nwsyncdata_0.sqlite3")

    unless File.exists?(meta) and File.exists?(data) do
      Mix.raise("""
      nwsync-кэш не найден: #{@nwsync}

      Он появляется после первого захода на сервер игровым клиентом.
      Если игра стоит в другом месте — путь задан константой @nwsync.
      """)
    end

    ensure_zstd!()
    File.mkdir_p!(@out)

    rows =
      query(data, meta, """
      ATTACH '#{meta}' AS m;
      SELECT mr.resref, r.sha1, length(r.data)
      FROM resrefs r JOIN m.manifest_resrefs mr ON mr.resref_sha1 = r.sha1
      WHERE mr.restype = #{@restype_2da}
      GROUP BY mr.resref
      ORDER BY mr.resref;
      """)

    Mix.shell().info("нашлось таблиц: #{length(rows)}")

    manifest =
      rows
      |> Enum.map(fn [resref, sha1, _size] -> extract_one(data, meta, resref, sha1) end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    File.write!(
      Path.join(@out, "manifest.json"),
      Jason.encode!(
        %{
          "_note" =>
            "sha1 каждой таблицы в клиентском кэше на момент выгрузки. " <>
              "Меняется, когда шард обновил хаки — `git diff` после `mix hak.extract` " <>
              "показывает ровно то, что изменилось.",
          "_source" => "nwsync клиента NWN:EE, restype 2017",
          "tables" => manifest
        },
        pretty: true
      ) <> "\n"
    )

    Mix.shell().info("выложено в #{@out}: #{map_size(manifest)} таблиц + manifest.json")
  end

  defp extract_one(data, meta, resref, sha1) do
    blob = read_blob(data, meta, sha1)

    case unpack(blob) do
      {:ok, text} ->
        File.write!(Path.join(@out, "#{resref}.2da"), text)
        {resref, sha1}

      {:error, why} ->
        Mix.shell().error("  пропущено #{resref}: #{why}")
        nil
    end
  end

  defp read_blob(data, meta, sha1) do
    tmp = Path.join(System.tmp_dir!(), "hak_#{sha1}.bin")

    query(data, meta, "SELECT writefile('#{tmp}', data) FROM resrefs WHERE sha1='#{sha1}';")

    blob = File.read!(tmp)
    File.rm(tmp)
    blob
  end

  # ⚠️ Заголовок срезается по фиксированной длине, но результат ПРОВЕРЯЕТСЯ магией
  # zstd: если шард или движок сменят формат контейнера, задача скажет об этом,
  # а не выложит мусор под видом таблицы.
  defp unpack(<<"NSYC", _::binary-size(@header_bytes - 4), rest::binary>>) do
    case rest do
      <<@zstd_magic, _::binary>> -> zstd_decompress(rest)
      _ -> {:error, "после заголовка NSYC нет потока zstd — формат контейнера сменился"}
    end
  end

  defp unpack(<<"2DA ", _::binary>> = plain), do: {:ok, plain}
  defp unpack(_), do: {:error, "неизвестный контейнер"}

  defp zstd_decompress(stream) do
    in_path = Path.join(System.tmp_dir!(), "hak_in.zst")
    out_path = Path.join(System.tmp_dir!(), "hak_out.2da")
    File.write!(in_path, stream)

    case System.cmd("zstd", ["-d", "-q", "-f", in_path, "-o", out_path], stderr_to_stdout: true) do
      {_, 0} ->
        text = File.read!(out_path)
        File.rm(in_path)
        File.rm(out_path)

        if String.starts_with?(text, "2DA "),
          do: {:ok, text},
          else: {:error, "не 2DA после распаковки"}

      {out, code} ->
        {:error, "zstd вышел с #{code}: #{String.trim(out)}"}
    end
  end

  defp query(data, _meta, sql) do
    case System.cmd("sqlite3", [data, sql], stderr_to_stdout: true) do
      {out, 0} ->
        out |> String.split("\n", trim: true) |> Enum.map(&String.split(&1, "|"))

      {out, code} ->
        Mix.raise("sqlite3 вышел с #{code}: #{String.trim(out)}")
    end
  end

  defp ensure_zstd! do
    case System.find_executable("zstd") do
      nil -> Mix.raise("нужен zstd (brew install zstd) — контейнеры nwsync сжаты им")
      _ -> :ok
    end
  end
end
