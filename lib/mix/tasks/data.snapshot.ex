defmodule Mix.Tasks.Data.Snapshot do
  @shortdoc "Сверяет загруженные ruleset'ы с эталонным слепком (--write перезаписывает эталон)"

  @moduledoc """
  Канонический слепок **загруженного** ruleset'а и сверка с эталоном.

      mix data.snapshot          # сверить, ничего не писать; код возврата 1 при расхождении
      mix data.snapshot --write  # перезаписать эталон (осознанно, с последующим git diff)

  Эталоны лежат в `test/snapshots/ruleset_<версия>.snap` и коммитятся. Их же
  сверяет `BuildCalculator.Data.RulesetSnapshotTest`, то есть в `mix precommit`
  расхождение всплывает само — задача не «не забыть прогнать», а «тест упал».

  Задача 3.46, заход 0: страховка под разрезание `loader.ex` на модули. Слепок
  отвечает на вопрос «ruleset не изменился ни в одном поле», не спрашивая, о чём
  мы подумали, когда писали тесты. Что именно канонизируется и почему списки
  **не** сортируются — в `BuildCalculator.Data.Snapshot`.

  ⚠️ `--write` — это не «починить упавший тест». Перезапись эталона законна
  ровно тогда, когда правка задумана (изменились данные в `priv/rules/` или
  правило загрузчика), и обязана сопровождаться чтением `git diff test/snapshots`
  глазами. Рефакторинг, сохраняющий поведение, эталон не трогает вовсе.
  """

  use Mix.Task

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Snapshot

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [write: :boolean])
    write? = Keyword.get(opts, :write, false)

    results = Enum.map(Enum.sort(Data.versions()), &check(&1, write?))

    if Enum.any?(results, &(&1 == :mismatch)) do
      Mix.raise("слепок разошёлся с эталоном; см. выше")
    end
  end

  defp check(version, write?) do
    path = Snapshot.golden_path(version)
    current = version |> Data.ruleset!() |> Snapshot.render()

    cond do
      write? ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, current)

        Mix.shell().info(
          "[#{version}] записано #{path} — #{lines(current)} строк, #{kb(current)} КБ"
        )

        :written

      not File.exists?(path) ->
        Mix.shell().error(
          "[#{version}] эталона нет: #{path} — создать `mix data.snapshot --write`"
        )

        :mismatch

      true ->
        case Snapshot.compare(File.read!(path), current) do
          :ok ->
            Mix.shell().info("[#{version}] совпадает — #{lines(current)} строк")
            :ok

          {:mismatch, report} ->
            Mix.shell().error(Snapshot.explain(version, report))
            :mismatch
        end
    end
  end

  defp lines(text), do: text |> String.split("\n", trim: true) |> length()
  defp kb(text), do: div(byte_size(text), 1024)
end
