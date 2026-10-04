defmodule Mix.Tasks.Base2da.Extract do
  @shortdoc "Выгружает базовые .2da NWN:EE из установки игры (KEY/BIF) в priv/base_2da/"

  @moduledoc """
  Выкладывает базовые таблицы правил NWN:EE в `priv/base_2da/` — источник
  для ванильного ruleset'а, как `priv/hak/2da/` для Сиалы (задача 4.5).

      mix base2da.extract                    # установка по умолчанию (Steam, macOS)
      NWN_ROOT=/путь/к/игре mix base2da.extract
      mix base2da.extract --root /путь --out priv/base_2da

  Сети не нужно: читаются `data/nwn_retail.key` и `data/nwn_base.key`
  (по старшинству), BIF-файлы, на которые они указывают, и `lang/en/data/dialog.tlk`.
  Установка не трогается. Нет установки — внятная ошибка с тем, что задать.

  Задача идемпотентна: повторный прогон на той же установке даёт пустой
  `git diff`, а рядом лежит `manifest.json` с `sha1` каждой таблицы, её BIF
  и позицией в нём, затенёнными копиями и сборкой игры. Обновилась игра —
  прогон и `git diff` показывают ровно то, что поменяла Beamdog.

  Что выгружается и почему, старшинство ключей, права — `priv/base_2da/README.md`.
  Устройство — `BuildCalculator.GameFiles.BaseExtract`.
  """

  use Mix.Task

  alias BuildCalculator.Base2da.Report
  alias BuildCalculator.GameFiles.BaseExtract

  @out "priv/base_2da"

  @impl true
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, strict: [root: :string, out: :string])

    if invalid != [] do
      Mix.raise("неизвестные ключи: #{inspect(invalid)}; есть только --root и --out")
    end

    root = Path.expand(opts[:root] || System.get_env("NWN_ROOT") || BaseExtract.default_root())
    out = opts[:out] || @out

    case BaseExtract.run(root, out) do
      {:ok, summary} ->
        tables = Report.plural(summary.tables, "таблица", "таблицы", "таблиц")
        names = Report.plural(summary.names, "имя", "имени", "имён")

        Mix.shell().info(
          "выложено в #{out}: #{summary.tables} #{tables} (#{summary.bytes} байт), " <>
            "#{summary.names} #{names} из dialog.tlk; перекрыто слоем nwn_retail.key: " <>
            "#{summary.overridden}; удалено устаревших: #{summary.removed}"
        )

      {:error, message} ->
        Mix.raise(message)
    end
  end
end
