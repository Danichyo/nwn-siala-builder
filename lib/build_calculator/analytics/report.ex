defmodule BuildCalculator.Analytics.Report do
  @moduledoc """
  Отчёт по аналитике текстом — для консоли сервера (задача 4.54).

  Два входа, один текст:

    * `mix analytics.report [--days N]` — на машине разработчика;
    * релиз: `bin/build_calculator eval "BuildCalculator.Release.analytics_report(30)"`
      (поднимает только Repo), или `bin/build_calculator rpc
      "BuildCalculator.Analytics.Report.print(days: 30)"` у работающего узла.

  Читает те же таблицы, что Grafana (`analytics.visits`, `analytics.events`);
  срезы по дням для панелей — представления `analytics.daily_*` (миграция).
  Уникальные за период считаются как «посетитель-дни»: соль меняется каждый
  день, и один человек в два разных дня — два разных хеша по построению.
  """

  import Ecto.Query

  alias BuildCalculator.Analytics.{Event, Visit}
  alias BuildCalculator.Repo

  @default_days 30

  @doc "Печатает `text/1`."
  @spec print(keyword()) :: :ok
  def print(opts \\ []), do: IO.puts(text(opts))

  @doc "Отчёт за последние `:days` дней UTC, включая сегодняшний (умолчание 30)."
  @spec text(keyword()) :: String.t()
  def text(opts \\ []) do
    days = Keyword.get(opts, :days, @default_days)
    today = Date.utc_today()
    since = Date.add(today, -(days - 1))

    visits = from(v in Visit, where: v.day >= ^since)
    events = from(e in Event, where: e.day >= ^since)

    by_day =
      from(v in visits,
        group_by: [v.day, v.edition],
        order_by: [v.day, v.edition],
        select: [v.day, v.edition, count(v.id), count(v.visitor, :distinct)]
      )

    pages =
      from(v in visits,
        group_by: v.page,
        order_by: [desc: count(v.id), asc: v.page],
        select: [v.page, count(v.id), fragment("count(DISTINCT (?, ?))", v.day, v.visitor)]
      )

    hosts =
      from(v in visits,
        where: not is_nil(v.referrer_host),
        group_by: v.referrer_host,
        order_by: [desc: count(v.id), asc: v.referrer_host],
        select: [v.referrer_host, count(v.id)]
      )

    utm =
      from(v in visits,
        where:
          not is_nil(v.utm_source) or not is_nil(v.utm_medium) or not is_nil(v.utm_campaign) or
            not is_nil(v.utm_term) or not is_nil(v.utm_content),
        group_by: [v.utm_source, v.utm_medium, v.utm_campaign, v.utm_term, v.utm_content],
        order_by: [desc: count(v.id)],
        select: [
          v.utm_source,
          v.utm_medium,
          v.utm_campaign,
          v.utm_term,
          v.utm_content,
          count(v.id)
        ]
      )

    event_rows =
      from(e in events,
        group_by: [e.name, e.ruleset],
        order_by: [e.name, e.ruleset],
        select: [e.name, e.ruleset, count(e.id)]
      )

    totals =
      Repo.one(
        from(v in visits,
          select: [count(v.id), fragment("count(DISTINCT (?, ?))", v.day, v.visitor)]
        ),
        log: false
      )

    [total_visits, visitor_days] = totals

    utm_rows =
      for [source, medium, campaign, term, content, count] <- all(utm) do
        [Enum.map_join([source, medium, campaign, term, content], " / ", &(&1 || "-")), count]
      end

    [
      "Analytics #{since} .. #{today} (#{days} days, UTC)",
      "visits #{total_visits}, visitor-days #{visitor_days}",
      section("Visits by day", ["day", "edition", "visits", "visitors"], all(by_day)),
      section("Pages (route templates)", ["page", "visits", "visitor-days"], all(pages)),
      section("Referrer hosts", ["host", "visits"], all(hosts)),
      section("UTM (source / medium / campaign / term / content)", ["utm", "visits"], utm_rows),
      section("Events", ["event", "ruleset", "count"], all(event_rows))
    ]
    |> Enum.join("\n")
  end

  # Запросы отчёта не пишутся в лог: в dev Ecto печатает каждый на `:debug`,
  # и текст отчёта тонул бы в них.
  defp all(query), do: Repo.all(query, log: false)

  defp section(title, _header, []), do: "\n#{title}\n  (none)"

  defp section(title, header, rows), do: "\n#{title}\n" <> table([header | rows])

  defp table(rows) do
    cells = Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)
    columns = cells |> Enum.zip() |> Enum.map(&Tuple.to_list/1)

    widths =
      Enum.map(columns, fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    Enum.map_join(cells, "\n", fn row ->
      "  " <>
        (row
         |> Enum.zip(widths)
         |> Enum.map_join("  ", fn {value, width} -> String.pad_trailing(value, width) end)
         |> String.trim_trailing())
    end)
  end

  defp cell(nil), do: "-"
  defp cell(%Date{} = date), do: Date.to_iso8601(date)
  defp cell(value) when is_binary(value), do: value
  defp cell(value), do: to_string(value)
end
