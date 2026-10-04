defmodule Mix.Tasks.Base2da.Diff do
  @shortdoc "Сверяет базовые .2da (priv/base_2da) с ванильным ruleset'ом → docs/base2da_diff.md"

  @moduledoc """
  Сверка базовых таблиц NWN:EE с ванильным слоем (задача 4.5).

      mix base2da.diff            # переписать машинные блоки docs/base2da_diff.md
      mix base2da.diff --check    # ничего не писать; упасть, если документ устарел
                                  # или появилась находка без вида

  Читает `priv/base_2da/` (выгрузка `mix base2da.extract`) и загруженный
  ruleset `vanilla`, сравнивает по областям и классифицирует находки
  (`BuildCalculator.Base2da.Diff`). В документе переписываются только два
  блока между маркерами `<!-- base2da.diff:summary:… -->` и
  `<!-- base2da.diff:details:… -->`; текст вокруг — ручной и не трогается.

  **Данные не правятся.** Сверка — вход для задач на правку, а не правка.

  Повторный прогон на тех же данных даёт пустой `git diff`: в выводе нет ни
  даты, ни времени, всё отсортировано. Сети не нужно, установки игры тоже —
  только выгрузка в репозитории.

  Та же печать и та же проверка у сиальской сверки `mix hak2da.diff`
  (задача 4.49) — `write_or_check/5` ниже.
  """

  use Mix.Task

  alias BuildCalculator.Base2da.{Diff, Report, Source}

  @switches [check: :boolean, dir: :string, doc: :string]

  @impl true
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("неизвестные ключи: #{inspect(invalid)}")

    Mix.Task.run("compile")

    dir = opts[:dir] || "priv/base_2da"
    doc = opts[:doc] || "docs/base2da_diff.md"

    source =
      case Source.load(dir) do
        {:ok, source} -> source
        {:error, message} -> Mix.raise(message)
      end

    ruleset = BuildCalculator.Data.ruleset!("vanilla")
    result = Diff.run(source, ruleset, "priv/rules")

    write_or_check(
      result,
      source,
      Report.profile(:vanilla, ruleset.version),
      doc,
      opts[:check] == true
    )
  end

  @doc """
  Печатает счёт, переписывает машинные блоки документа `doc` или (`check?`)
  падает, если документ устарел или у находки нет вида. Общая часть
  `mix base2da.diff` и `mix hak2da.diff`.
  """
  @spec write_or_check(%{areas: list()}, Source.t(), map(), Path.t(), boolean()) :: :ok
  def write_or_check(result, source, profile, doc, check?) do
    current = if File.regular?(doc), do: File.read!(doc), else: Mix.raise("нет #{doc}")

    updated =
      current
      |> replace_block(:summary, Report.summary(result, source, profile), doc, profile)
      |> replace_block(:details, Report.details(result, profile, source), doc, profile)

    findings = Enum.flat_map(result.areas, & &1.findings)
    unclassified = Enum.count(findings, &is_nil(&1.kind))
    checks = Enum.sum(Enum.map(result.areas, & &1.checks))

    frequencies = Enum.frequencies_by(findings, & &1.kind)

    counts =
      profile
      |> Report.kinds()
      |> Enum.filter(&Map.has_key?(frequencies, &1))
      |> Enum.map_join(", ", &"#{&1 || "без вида"}: #{frequencies[&1]}")

    Mix.shell().info("сравнений #{checks}, находок #{length(findings)} (#{counts})")

    cond do
      check? and (updated != current or unclassified > 0) ->
        Mix.raise(
          "#{doc} устарел или есть находки без вида (#{unclassified}) — " <>
            "запусти mix #{profile.marker} и разбери новое"
        )

      check? ->
        Mix.shell().info("#{doc} актуален")

      updated == current ->
        Mix.shell().info("#{doc} не изменился")

      true ->
        File.write!(doc, updated)
        Mix.shell().info("#{doc} переписан")
    end

    :ok
  end

  defp replace_block(text, block, body, doc, profile) do
    {open, close} = Report.markers(block, profile)

    case String.split(text, [open, close]) do
      [before, _old, rest] ->
        before <> open <> "\n" <> String.trim_trailing(body) <> "\n" <> close <> rest

      _ ->
        Mix.raise("в #{doc} нет пары маркеров #{open} … #{close}")
    end
  end
end
