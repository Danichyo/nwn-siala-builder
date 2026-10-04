defmodule Mix.Tasks.Hak2da.Diff do
  @shortdoc "Сверяет хак Сиалы (priv/hak/2da поверх priv/base_2da) с ruleset'ом siala_41 → docs/hak2da_diff.md"

  @moduledoc """
  Сверка слоя Сиалы с таблицами, которые исполняет клиент шарда (задача 4.49).

      mix hak2da.diff            # переписать машинные блоки docs/hak2da_diff.md
      mix hak2da.diff --check    # ничего не писать; упасть, если документ устарел
                                 # или появилась находка без вида

  Читает `priv/hak/2da/` (`mix hak.extract`) поверх `priv/base_2da/`
  (`mix base2da.extract`) — таблица хака, если шард её прислал, иначе базовая —
  и загруженный ruleset `siala_41` (`BuildCalculator.Base2da.SialaDiff`).
  В документе переписываются только блоки между маркерами
  `<!-- hak2da.diff:summary:… -->` и `<!-- hak2da.diff:details:… -->`.

  🔴 Хак — сильный источник гипотез, а не арбитр: шард выдаёт и выключает
  скриптами мимо таблиц (`priv/hak/README.md`). Ранг источников Сиалы и виды
  находок — `BuildCalculator.Base2da.SialaClassification`.

  **Данные не правятся.** Повторный прогон на тех же данных даёт пустой
  `git diff`. Сети и установки игры не нужно — только обе выгрузки.
  """

  use Mix.Task

  alias BuildCalculator.Base2da.{Report, SialaDiff, Source}

  @switches [check: :boolean, hak: :string, base: :string, doc: :string]

  @impl true
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("неизвестные ключи: #{inspect(invalid)}")

    Mix.Task.run("compile")

    hak = opts[:hak] || "priv/hak/2da"
    base = opts[:base] || "priv/base_2da"
    doc = opts[:doc] || "docs/hak2da_diff.md"

    source =
      case Source.load_layered(hak, base) do
        {:ok, source} -> source
        {:error, message} -> Mix.raise(message)
      end

    vanilla = BuildCalculator.Data.ruleset!("vanilla")
    index = SialaDiff.vanilla_index(source.base, vanilla, "priv/rules")
    ruleset = BuildCalculator.Data.ruleset!("siala_41")
    result = SialaDiff.run(source, ruleset, "priv/rules", vanilla_index: index)

    Mix.Tasks.Base2da.Diff.write_or_check(
      result,
      source,
      Report.profile(:siala, ruleset.version),
      doc,
      opts[:check] == true
    )
  end
end
