defmodule BuildCalculator.Analytics.RetentionTest do
  @moduledoc """
  Срок хранения строк посещений (задача 4.75): команда удаляет только то,
  что старше названного числа дней, только посещения и только когда её
  позвали без `dry_run`. Строки — в песочнице теста, `async: true`.
  """
  use BuildCalculator.DataCase, async: true

  alias BuildCalculator.Analytics.{Event, Retention, Visit}

  @today ~D[2026-10-04]

  defp seed(days) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      Visit,
      for {day, n} <- Enum.with_index(days) do
        %{day: day, edition: "siala", page: "/", visitor: <<n::128>>, inserted_at: now}
      end
    )

    Repo.insert_all(
      Event,
      for(day <- days, do: %{day: day, edition: "siala", name: "link_opened", inserted_at: now})
    )
  end

  defp days_left, do: Visit |> Repo.all() |> Enum.map(& &1.day) |> Enum.sort(Date)

  test "оставляет последние N дней включая сегодняшний, старше — удаляет" do
    seed([~D[2025-01-01], ~D[2026-09-04], ~D[2026-09-05], ~D[2026-10-04]])

    result = Retention.prune_visits(30, today: @today)

    assert result.cutoff == ~D[2026-09-05]
    assert %{before: 4, older: 2, deleted: 2, after: 2, oldest: ~D[2025-01-01]} = result
    assert days_left() == [~D[2026-09-05], ~D[2026-10-04]]

    # События не трогаются.
    assert Repo.aggregate(Event, :count) == 4
    assert Retention.text(result) =~ "deleted 2"
  end

  test "dry run только считает" do
    seed([~D[2025-01-01], ~D[2026-10-04]])

    result = Retention.prune_visits(1, today: @today, dry_run: true)

    assert %{older: 1, deleted: 0, after: 2, dry_run?: true} = result
    assert Retention.text(result) =~ "would delete 1 (dry run: nothing deleted)"
    assert length(days_left()) == 2
  end

  test "keep_days меньше 1 не принимается" do
    assert_raise FunctionClauseError, fn -> Retention.prune_visits(0) end
  end
end
