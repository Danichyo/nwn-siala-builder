defmodule BuildCalculator.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :build_calculator

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Отчёт по аналитике посещений и событий за последние `days` дней UTC
  (задача 4.54) — тот же текст, что `mix analytics.report`:

      bin/build_calculator eval "BuildCalculator.Release.analytics_report(30)"

  Поднимает только Repo, работающему узлу не мешает.
  """
  def analytics_report(days \\ 30) when is_integer(days) and days > 0 do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(
        BuildCalculator.Repo,
        fn _repo -> BuildCalculator.Analytics.Report.print(days: days) end
      )

    :ok
  end

  @doc """
  Срок хранения строк посещений (задача 4.75) — тот же текст, что
  `mix analytics.prune`: оставить последние `keep_days` дней UTC, остальное
  удалить; `dry_run` — только посчитать.

      bin/build_calculator eval "BuildCalculator.Release.analytics_prune(400, true)"
      bin/build_calculator eval "BuildCalculator.Release.analytics_prune(400)"

  Удаление — решение Dan: само приложение этого не делает никогда.
  """
  def analytics_prune(keep_days, dry_run \\ false)
      when is_integer(keep_days) and keep_days > 0 and is_boolean(dry_run) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(BuildCalculator.Repo, fn _repo ->
        keep_days
        |> BuildCalculator.Analytics.Retention.prune_visits(dry_run: dry_run)
        |> BuildCalculator.Analytics.Retention.text()
        |> IO.puts()
      end)

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
