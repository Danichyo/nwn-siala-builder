defmodule BuildCalculator.Analytics.ReportTest do
  @moduledoc """
  Отчёт-команда по аналитике (задача 4.54): `mix analytics.report`
  и `BuildCalculator.Release.analytics_report/1` печатают `Report.text/1`.
  """
  use BuildCalculator.DataCase, async: true

  alias BuildCalculator.Analytics
  alias BuildCalculator.Analytics.Report

  test "пустые таблицы — отчёт без строк, а не падение" do
    text = Report.text(days: 7)

    assert text =~ "visits 0, visitor-days 0"
    assert text =~ "Events\n  (none)"
  end

  test "посещения, уникальные, страницы, источники, метки и события" do
    one = Analytics.visitor({203, 0, 113, 7}, "UA")
    two = Analytics.visitor({203, 0, 113, 8}, "UA")

    for {visitor, page, host, source} <- [
          {one, "/b/:code", "discord.com", "discord"},
          {one, "/", nil, nil},
          {two, "/b/:code", nil, nil}
        ] do
      :ok =
        Analytics.record_visit(%{
          visitor: visitor,
          edition: "siala",
          page: page,
          referrer_host: host,
          utm: %{utm_source: source}
        })
    end

    :ok = Analytics.record_event("siala", :link_opened, "siala_41")
    :ok = Analytics.record_event("siala", :link_opened, "siala_41")
    :ok = Analytics.record_event("siala", :export_downloaded, "siala_41")

    text = Report.text(days: 30)
    today = Date.to_iso8601(Date.utc_today())

    assert text =~ "visits 3, visitor-days 2"
    assert text =~ ~r/#{today}\s+siala\s+3\s+2/
    assert text =~ ~r{/b/:code\s+2\s+2}
    assert text =~ ~r{  /\s+1\s+1}
    assert text =~ ~r/discord\.com\s+1/
    assert text =~ ~r{discord / - / - / - / -\s+1}
    assert text =~ ~r/link_opened\s+siala_41\s+2/
    assert text =~ ~r/export_downloaded\s+siala_41\s+1/
  end
end
