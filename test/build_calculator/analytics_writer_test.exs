defmodule BuildCalculator.AnalyticsWriterTest do
  @moduledoc """
  Запись задачей — путь прода и dev (задача 4.54, `BuildCalculator.Analytics`).

  Остальные тесты пишут в процессе вызывающего (`config/test.exs`:
  `:analytics_writer, :inline`), чтобы песочница видела строку сразу. Здесь —
  настоящий путь: `Task.Supervisor` с потолком, вызывающий не ждёт базу,
  отказ базы и переполнение не доходят до него.

  Здесь же отказ базы в режиме теста (`:inline`): он изображается `DROP TABLE`
  в песочнице.

  ⚠️ `async: false` — режим записи меняется `Application.put_env/3` на всё
  приложение, и супервизор задач общий: параллельный сосед писал бы задачами
  и считал бы чужих детей (CLAUDE.md §7). И `DROP TABLE` берёт блокировку
  таблицы до конца транзакции теста — параллельные соседи, пишущие посещения,
  ждали бы её. Песочница — общая (`shared`), поэтому задача видит транзакцию
  теста.
  """
  use BuildCalculator.DataCase, async: false

  import ExUnit.CaptureLog

  alias BuildCalculator.Analytics
  alias BuildCalculator.Analytics.Event

  @tasks BuildCalculator.Analytics.Tasks

  describe "в процессе вызывающего (:inline, режим тестов)" do
    test "запись в пропавшую таблицу не бросает: :ok и одна строка в логе без значений" do
      Repo.query!("DROP VIEW analytics.daily_events")
      Repo.query!("DROP TABLE analytics.events")

      log =
        capture_log(fn ->
          assert :ok = Analytics.record_event("siala", :export_downloaded, "siala_41")
        end)

      assert log =~ "analytics: write dropped (postgres undefined_table)"
      refute log =~ "siala_41"
    end
  end

  describe "задачей (:task, режим прода и dev)" do
    setup do
      Application.put_env(:build_calculator, :analytics_writer, :task)
      on_exit(fn -> Application.put_env(:build_calculator, :analytics_writer, :inline) end)
      :ok
    end

    defp await_tasks do
      for pid <- Task.Supervisor.children(@tasks) do
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
      end

      :ok
    end

    test "строка пишется задачей, вызывающий получает :ok сразу" do
      assert :ok = Analytics.record_event("siala", :text_imported, "siala_41")
      await_tasks()

      assert [%Event{name: "text_imported"}] = Repo.all(Event)
    end

    test "отказ базы — в задаче: вызывающий получает :ok, в логе — вид отказа" do
      Repo.query!("DROP VIEW analytics.daily_events")
      Repo.query!("DROP TABLE analytics.events")

      log =
        capture_log(fn ->
          assert :ok = Analytics.record_event("siala", :text_imported, "siala_41")
          await_tasks()
        end)

      assert log =~ "analytics: write dropped (postgres undefined_table)"
    end

    test "потолок задач полон — запись выбрасывается, вызывающий не ждёт" do
      parent = self()

      blockers =
        for _ <- 1..100 do
          {:ok, pid} =
            Task.Supervisor.start_child(@tasks, fn ->
              send(parent, {:blocked, self()})

              receive do
                :release -> :ok
              end
            end)

          pid
        end

      for pid <- blockers, do: assert_receive({:blocked, ^pid})

      log =
        capture_log(fn ->
          assert :ok = Analytics.record_event("siala", :text_imported, "siala_41")
        end)

      assert log =~ "analytics: write dropped (max_children)"

      for pid <- blockers, do: send(pid, :release)
      await_tasks()
      assert Repo.all(Event) == []
    end
  end
end
