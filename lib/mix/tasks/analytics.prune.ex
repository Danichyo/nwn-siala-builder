defmodule Mix.Tasks.Analytics.Prune do
  @shortdoc "Удаляет строки посещений старше последних N дней (задача 4.75)"

  @moduledoc """
  Срок хранения `analytics.visits` (`BuildCalculator.Analytics.Retention`):

      mix analytics.prune --keep-days 400 --dry-run   # только посчитать
      mix analytics.prune --keep-days 400             # удалить

  `--keep-days` обязателен: сколько последних дней UTC оставить, включая
  сегодняшний. Удаление данных — решение Dan, поэтому ни умолчания, ни
  расписания нет. Поднимает только Repo. На сервере mix нет — там тот же
  текст отдаёт релиз:

      bin/build_calculator eval "BuildCalculator.Release.analytics_prune(400, true)"
      bin/build_calculator eval "BuildCalculator.Release.analytics_prune(400)"
  """

  use Mix.Task

  alias BuildCalculator.Analytics.Retention

  @switches [keep_days: :integer, dry_run: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] or rest != [],
      do: Mix.raise("неизвестные ключи: #{inspect(invalid ++ rest)}")

    keep_days =
      opts[:keep_days] || Mix.raise("нужен --keep-days N: сколько последних дней оставить")

    if keep_days < 1, do: Mix.raise("--keep-days должно быть не меньше 1")

    Mix.Task.run("app.config")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(BuildCalculator.Repo, fn _repo ->
        keep_days
        |> Retention.prune_visits(dry_run: opts[:dry_run] || false)
        |> Retention.text()
        |> IO.puts()
      end)

    :ok
  end
end
