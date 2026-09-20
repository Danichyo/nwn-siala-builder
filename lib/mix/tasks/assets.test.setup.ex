defmodule Mix.Tasks.Assets.Test.Setup do
  @shortdoc "Ставит npm-зависимость JS-тестов колокированных хуков (happy-dom)"

  @moduledoc """
  `npm install` в `assets/` — один раз, чтобы `mix assets.test` (задача 3.138 П1,
  `AGENT_QUEUE.md`) было чем гонять.

      mix assets.test.setup

  `mix setup` зовёт эту задачу сам, поэтому разработчику вызывать её отдельно
  не нужно — она существует как именованный шаг, а не только как часть цепочки.

  ## Почему это НЕ часть `assets.setup`

  `assets.setup` зовёт `Dockerfile` (`RUN mix assets.setup`, шаг сборки прод-образа),
  и он не должен НАЧАТЬ требовать npm — прод собирает esbuild/tailwind бандлы,
  а не гоняет тесты. `Dockerfile` эту задачу не зовёт вовсе; `mix assets.deploy`
  её тоже не задевает. Это то самое ограничение, с которым заведён весь заход:
  ни один из существующих asset-алиасов не должен начать требовать npm.

  ## Что ставится

  Ровно одна зависимость — `happy-dom` (assets/package.json), настоящий DOM
  без ~200 пакетов бандлера вроде vitest. Прогонщик тестов — встроенный
  `node:test`, Node 24 (минимум, на котором проверялось) несёт его сам,
  отдельным пакетом не ставится.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    ensure_npm!()

    unless File.exists?("assets/package.json") do
      Mix.raise("assets/package.json не найден — задаче нечего ставить")
    end

    Mix.shell().info("[assets.test.setup] npm install (assets/)")

    {_, status} =
      System.cmd("npm", ["install"],
        cd: "assets",
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0 do
      Mix.raise("npm install в assets/ вышел с кодом #{status}")
    end
  end

  defp ensure_npm! do
    case System.find_executable("npm") do
      nil -> Mix.raise("нужен npm (идёт с Node.js, node.dev) — JS-тесты им ставятся")
      _ -> :ok
    end
  end
end
