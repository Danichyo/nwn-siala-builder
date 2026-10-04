defmodule Mix.Tasks.Provenance.Audit do
  @shortdoc "Провенанс ванили: записи с источником, видимые ванили, и вердикт по каждой"

  @moduledoc """
  Обход провенанса ванили (задача 4.6, `VANILLA.md` §4.6).

      mix provenance.audit           # сводка и нарушения
      mix provenance.audit --list    # плюс каждая запись: файл, путь, виды, решает, вердикт
      mix provenance.audit --check   # код возврата 1, если есть нарушения
      mix provenance.audit --probe   # плюс проба: читает ли загрузчик каждую запись
                                     # без ванильного источника (вырезать и сравнить)

  Читает `priv/rules/vanilla/*.json` — ровно то, из чего собирается ванильный
  ruleset, — и для каждой записи с источником называет вид источника, решает ли
  она число ванильного билда и вердикт: ванильный источник, пометка «замер
  движка на сервере Сиалы» с доводом, не решает числа, отложено поимённо — или
  нарушение. Правила — `BuildCalculator.Data.Provenance`, сторож —
  `test/build_calculator/data/provenance_test.exs`.

  Сети не нужно, данные не правятся. Вывод детерминирован: файлы и пути
  отсортированы, дат в нём нет.
  """

  use Mix.Task

  alias BuildCalculator.Data.Provenance

  @switches [list: :boolean, check: :boolean, probe: :boolean, root: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("неизвестные ключи: #{inspect(invalid)}")

    Mix.Task.run("compile")
    root = opts[:root] || "priv/rules"
    records = root |> Provenance.read_vanilla!() |> Provenance.records()
    census = Provenance.census(records)
    violations = Provenance.violations(records)

    shell = Mix.shell()
    shell.info("Провенанс ванили — #{root}/vanilla/*.json")
    shell.info("записей с источником: #{census.total}")
    shell.info("по вердикту: #{render(census.by_verdict)}")
    shell.info("что решают: #{render(census.by_decides)}")

    shell.info(
      "решают число: с сиальским источником #{census.deciding_with_siala}, " <>
        "с kind: user #{census.deciding_with_user}, " <>
        "без ванильного источника #{census.deciding_without_vanilla}, " <>
        "смешанных (ванильный + сиальский или user) #{census.deciding_mixed}"
    )

    shell.info("по файлам: #{render(census.by_file)}")

    if opts[:list] do
      shell.info("\nфайл\tпуть\tвиды\tрешает\tвердикт\tпочему")

      for r <- records do
        shell.info(
          Enum.join(
            [
              r.file,
              Provenance.render_path(r.path),
              Enum.join(r.kinds, ","),
              r.decides,
              r.verdict,
              r.verdict_why
            ],
            "\t"
          )
        )
      end
    end

    if opts[:list] do
      mixed = records |> Enum.filter(&(&1.decides == :number)) |> Provenance.mixed()

      shell.info(
        "\nсмешанные — ванильная цитата обязана покрывать решающий факт (#{length(mixed)}):"
      )

      for r <- mixed,
          do:
            shell.info(
              "  #{r.file} #{Provenance.render_path(r.path)} — #{Enum.join(r.kinds, ",")}"
            )
    end

    pending = Enum.filter(records, &(&1.verdict == :pending))

    unless pending == [] do
      shell.info("\nотложено поимённо (#{length(pending)}):")

      for r <- pending,
          do: shell.info("  #{r.file} #{Provenance.render_path(r.path)} — #{r.verdict_why}")
    end

    if violations == [] do
      shell.info("\nнарушений нет")
    else
      shell.error("\nнарушения (#{length(violations)}):")

      for r <- violations,
          do: shell.error("  #{r.file} #{Provenance.render_path(r.path)} — #{r.verdict_why}")

      if opts[:check],
        do:
          Mix.raise("#{length(violations)} записей решают число ванили без ванильного источника")
    end

    if opts[:probe], do: probe(root, records)
  end

  # Для каждой записи без ванильного источника, которую правила считают
  # решающей число: вырезать её узел из копии данных, загрузить и сравнить оба
  # ruleset'а с настоящими. Совпали — загрузчик запись не читает, и её место
  # в списке непрочитанного (`Provenance.unread_key?/1`, `@unread_paths`).
  defp probe(root, records) do
    alias BuildCalculator.Data.Loader

    baseline = Loader.load!(root)
    candidates = Enum.filter(records, &(&1.decides == :number and &1.verdict != :vanilla_source))
    Mix.shell().info("\nпроба «читает ли загрузчик» — #{length(candidates)} записей:")

    for r <- candidates do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "provenance_probe_#{:os.getpid()}_#{System.unique_integer([:positive])}"
        )

      File.cp_r!(root, tmp)
      path = Path.join([tmp, "vanilla", r.file])
      json = path |> File.read!() |> Jason.decode!()
      File.write!(path, Jason.encode!(Provenance.delete_at(json, r.path)))

      answer =
        try do
          if Loader.load!(tmp) == baseline, do: "НЕ ЧИТАЕТ", else: "читает"
        rescue
          e -> "читает (падение: #{e |> Exception.message() |> String.slice(0, 80)})"
        after
          File.rm_rf!(tmp)
        end

      Mix.shell().info("  #{answer}\t#{r.file} #{Provenance.render_path(r.path)}")
    end
  end

  defp render(map) do
    map
    |> Enum.sort_by(fn {key, _count} -> to_string(key) end)
    |> Enum.map_join(", ", fn {key, count} -> "#{key} #{count}" end)
  end
end
