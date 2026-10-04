defmodule BuildCalculator.Base2da.Report do
  @moduledoc """
  Markdown сверки таблиц `.2da` с ruleset'ом — два машинных блока документа:
  сводка и подробности. Всё остальное в документе пишет человек; задача сверки
  меняет только текст между маркерами.

  Сверок две, и печать у них одна (`profile/1`):

    * `:vanilla` — `mix base2da.diff` → `docs/base2da_diff.md` (задача 4.5):
      базовые таблицы игры против ruleset'а `vanilla`, виды (a)–(d);
    * `:siala` — `mix hak2da.diff` → `docs/hak2da_diff.md` (задача 4.49):
      хак Сиалы поверх базы против ruleset'а `siala_41`, виды (a)–(e) с рангом
      Сиалы (`Base2da.SialaClassification`). У каждой таблицы в подробностях
      помечено, откуда она: `хак/` или `база/`.

  Вывод детерминирован: области в порядке сверки, находки по ключу, ни даты,
  ни времени прогона — повторный прогон на тех же данных даёт пустой `git diff`.
  """

  alias BuildCalculator.Base2da.{Finding, Source}

  @vanilla_kinds [
    a: "(a) наши данные неверны",
    d: "(d) Fandom и .2da спорят — замер",
    c: "(c) .2da не решает — движок",
    b: "(b) разница представления",
    nil: "не классифицировано"
  ]

  @siala_kinds [
    a: "(a) наши данные неверны",
    d:
      "(d) нужен замер — источники спорят (хак с вики Сиалы или с решением Dan; «как у ванили» — Fandom с таблицей)",
    e: "(e) объяснено — вики Сиалы, замер или решение Dan",
    c: "(c) таблица не решает — движок или сервер шарда",
    b: "(b) разница представления или до печатаемого не доезжает",
    nil: "не классифицировано"
  ]

  @doc """
  Профиль печати сверки: маркеры, виды находок, ruleset. Имя ruleset'а
  передаёт mix-задача — та, что его загрузила (`VANILLA.md` §2: код вне
  загрузчика и mix-задач имени ruleset'а не называет).
  """
  @spec profile(:vanilla | :siala, String.t() | nil) :: map()
  def profile(kind, ruleset \\ nil)

  def profile(:vanilla, ruleset),
    do: %{marker: "base2da.diff", kinds: @vanilla_kinds, ruleset: ruleset}

  def profile(:siala, ruleset),
    do: %{marker: "hak2da.diff", kinds: @siala_kinds, ruleset: ruleset}

  @doc "Виды профиля в порядке печати (последний — `nil`, «без вида»)."
  @spec kinds(map()) :: [Finding.kind()]
  def kinds(profile), do: Keyword.keys(profile.kinds)

  @doc "Имена маркеров блоков: `{начало, конец}`."
  @spec markers(:summary | :details, map()) :: {String.t(), String.t()}
  def markers(block, profile \\ profile(:vanilla)),
    do: {"<!-- #{profile.marker}:#{block}:begin -->", "<!-- #{profile.marker}:#{block}:end -->"}

  @doc "Сводка: источник и таблица чисел по областям и видам."
  @spec summary(%{areas: list()}, Source.t(), map()) :: String.t()
  def summary(%{areas: areas}, source, profile \\ profile(:vanilla)) do
    kinds = kinds(profile)
    totals = counts(Enum.flat_map(areas, & &1.findings))

    rows =
      Enum.map(areas, fn area ->
        c = counts(area.findings)

        "| #{area.title} | #{area.checks} | #{length(area.findings)} | " <>
          Enum.map_join(kinds, " | ", &cell(c[&1])) <> " |"
      end)

    total_checks = Enum.sum(Enum.map(areas, & &1.checks))
    total_findings = Enum.sum(Enum.map(areas, &length(&1.findings)))

    header = Enum.map_join(kinds, " | ", &kind_header/1)
    align = Enum.map_join(kinds, "|", fn _ -> "---:" end)

    """
    #{source_line(source, profile)}

    | область | сравнений | находок | #{header} |
    |---|---:|---:|#{align}|
    #{Enum.join(rows, "\n")}
    | **всего** | **#{total_checks}** | **#{total_findings}** | #{Enum.map_join(kinds, " | ", &"**#{totals[&1] || 0}**")} |
    """
  end

  defp kind_header(nil), do: "без вида"
  defp kind_header(kind), do: "(#{kind})"

  defp source_line(source, profile) do
    game = Source.game(source)

    build =
      "**#{game["version"] || "—"}** (#{game["released"] || "дата не прочитана"}), " <>
        "данные #{game["databuild"] || "—"}; ключи: #{keys(game)}"

    if Source.layered?(source) do
      own = source.top.tables
      shared = Enum.filter(own, &Map.has_key?(source.base.tables, &1))

      """
      Таблицы — те, что исполняет клиент Сиалы: хак (`#{source.top.dir}`, \
      #{length(own)} #{plural(length(own), "таблица", "таблицы", "таблиц")}) поверх \
      базовой игры #{build}. Хак перекрывает #{length(shared)} базовых \
      #{plural(length(shared), "таблицу", "таблицы", "таблиц")}: \
      #{Enum.map_join(shared, ", ", &"`#{&1}`")}; остальные таблицы сверки — из базы \
      (в подробностях у каждой стоит `хак/` или `база/`). Имён из dialog.tlk: \
      #{map_size(source.names)}; имена из `.tlk` шарда в выгрузке не лежат — строки \
      с ними сопоставлены по базовой строке с той же меткой или явной таблицей \
      (`Base2da.SialaRows`). Сверяется загруженный ruleset `#{profile.ruleset}` \
      (`Data.ruleset!/1` — слои наложены).
      """
      |> String.trim_trailing()
    else
      "Сборка игры: #{build}. Таблиц в выгрузке: #{map_size(source.tables)}, " <>
        "имён из dialog.tlk: #{map_size(source.names)}. Сверяется загруженный ruleset " <>
        "`#{profile.ruleset}` (`Data.ruleset!/1` ванили — ручные слои наложены)."
    end
  end

  @doc "Подробности: по областям, внутри — по виду и доводу."
  @spec details(%{areas: list()}, map(), Source.t() | nil) :: String.t()
  def details(%{areas: areas}, profile \\ profile(:vanilla), source \\ nil) do
    areas
    |> Enum.map(&area(&1, profile, source))
    |> Enum.join("\n")
  end

  defp area(%{findings: []} = area, _profile, _source) do
    "### #{area.title}\n\n#{checks(area.checks)} — расхождений нет.\n"
  end

  defp area(area, profile, source) do
    order = kinds(profile)

    groups =
      area.findings
      |> Enum.group_by(&{&1.kind, &1.note})
      |> Enum.sort_by(fn {{kind, note}, findings} ->
        {Enum.find_index(order, &(&1 == kind)),
         findings |> Enum.map(&Finding.key/1) |> Enum.min(), note || ""}
      end)
      |> Enum.map(fn {{kind, note}, findings} -> group(kind, note, findings, profile, source) end)

    "### #{area.title}\n\n#{checks(area.checks)}, #{findings(length(area.findings))}.\n\n" <>
      Enum.join(groups, "\n")
  end

  defp group(kind, note, findings, profile, source) do
    lines =
      findings
      |> Enum.sort_by(&Finding.key/1)
      |> Enum.map(fn f ->
        "- `#{Finding.key(f)}` — .2da: #{code(f.base)}" <>
          if(f.base_at, do: " _(#{origins(f.base_at, source)})_", else: "") <>
          " · у нас: #{code(f.ours)}" <> if(f.ours_at, do: " _(#{f.ours_at})_", else: "")
      end)

    "**#{profile.kinds[kind]}.** #{note || "Довода нет — находку ещё никто не разобрал."}\n\n" <>
      Enum.join(lines, "\n") <> "\n"
  end

  # У слоёного источника каждое имя таблицы получает приставку слоя: «хак/»
  # или «база/». Шаблон `cls_feat_*.2da` не трогается — у него слоя нет.
  defp origins(text, nil), do: text

  defp origins(text, source) do
    if Source.layered?(source) do
      Regex.replace(~r/(?<![\w\/*])([a-z][a-z0-9_]*)\.2da/, text, fn whole, name ->
        case Source.origin(source, name) do
          :hak -> "хак/" <> whole
          :base -> "база/" <> whole
          nil -> whole
        end
      end)
    else
      text
    end
  end

  defp counts(findings), do: Enum.frequencies_by(findings, & &1.kind)

  defp checks(n), do: "#{n} #{plural(n, "сравнение", "сравнения", "сравнений")}"
  defp findings(n), do: "#{n} #{plural(n, "находка", "находки", "находок")}"

  @doc false
  def plural(n, one, few, many) do
    cond do
      rem(n, 100) in 11..14 -> many
      rem(n, 10) == 1 -> one
      rem(n, 10) in 2..4 -> few
      true -> many
    end
  end

  defp cell(nil), do: "·"
  defp cell(n), do: Integer.to_string(n)

  defp keys(game) do
    game
    |> Map.get("keys", [])
    |> Enum.map_join(" > ", fn key -> "`#{key["file"]}` (#{key["built_on"]})" end)
  end

  defp code(text) do
    text = String.replace(text, "`", "'")
    text = if String.length(text) > 600, do: String.slice(text, 0, 600) <> "…", else: text
    "`#{text}`"
  end
end
