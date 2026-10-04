defmodule Mix.Tasks.Analytics.Report do
  @shortdoc "Аналитика посещений и событий за последние дни (задача 4.54)"

  @moduledoc """
  Отчёт по таблицам аналитики (`BuildCalculator.Analytics.Report`).

      mix analytics.report             # последние 30 дней UTC
      mix analytics.report --days 7

  Поднимает только Repo (как `mix ecto.migrate`), эндпоинт не нужен. На сервере
  mix нет — там тот же текст отдаёт релиз:

      bin/build_calculator eval "BuildCalculator.Release.analytics_report(30)"
  """

  use Mix.Task

  alias BuildCalculator.Analytics.Report

  @switches [days: :integer]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("неизвестные ключи: #{inspect(invalid)}")

    days = opts[:days] || 30
    if days < 1, do: Mix.raise("--days должно быть не меньше 1")

    Mix.Task.run("app.config")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(BuildCalculator.Repo, fn _repo -> Report.print(days: days) end)

    :ok
  end
end
