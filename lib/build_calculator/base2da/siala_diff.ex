defmodule BuildCalculator.Base2da.SialaDiff do
  @moduledoc """
  Сверка ruleset'а `siala_41` с таблицами, которые исполняет клиент Сиалы, —
  `mix hak2da.diff` (задача 4.49).

  Та же сверка, что ванильная (`Base2da.Diff`, задача 4.5), на других входах:

    * таблицы — хак шарда поверх базовой игры (`Source.load_layered/2`);
    * строки без имени в словаре — явной таблицей `Base2da.SialaRows`;
    * виды находок — с рангом Сиалы (`Base2da.SialaClassification`).

  Находка, совпавшая с ванильной до буквы (ключ, значение таблицы и наше
  значение), получает вид и довод ванильной сверки: хак эту строку не трогал,
  слой Сиалы это число не переписал, и спор — тот же самый. Поэтому сверка
  Сиалы прогоняет и ванильную, на базе того же источника.
  """

  alias BuildCalculator.Base2da.{Diff, Finding, SialaClassification, SialaRows, Source}

  @doc """
  Прогоняет сверку. `source` — слоёный (`Source.load_layered/2`); индекс
  ванильных находок для наследования видов — `opts[:vanilla_index]`
  (`vanilla_index/3` на базе того же источника и ванильном ruleset'е; его
  загружает mix-задача — `VANILLA.md` §2).
  """
  @spec run(Source.t(), map(), Path.t(), keyword()) :: %{areas: list()}
  def run(%Source{} = source, ruleset, rules_dir, opts \\ []) do
    index = Keyword.fetch!(opts, :vanilla_index)

    Diff.run(source, ruleset, rules_dir,
      row_overrides: SialaRows.row_overrides(),
      classify: &SialaClassification.classify(&1, index)
    )
  end

  @doc "Ванильные находки по ключу — для наследования вида."
  @spec vanilla_index(Source.t(), map(), Path.t()) :: %{String.t() => Finding.t()}
  def vanilla_index(base, vanilla_ruleset, rules_dir) do
    for area <- Diff.run(base, vanilla_ruleset, rules_dir).areas,
        finding <- area.findings,
        into: %{},
        do: {Finding.key(finding), finding}
  end
end
