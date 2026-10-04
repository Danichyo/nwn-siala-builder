defmodule BuildCalculator.AnalyticsTest do
  @moduledoc """
  Хранилище счётчика (задача 4.54): форма строки, посетитель, соль дня,
  проверка полей и запись, которая не роняет вызывающего.

  Запись здесь — в процессе теста (`:analytics_writer, :inline`, `config/test.exs`);
  путь задачей и отказ базы — `analytics_writer_test.exs` (синхронно: отказ там
  изображается `DROP TABLE` в песочнице, а блокировка таблицы задержала бы
  параллельных соседей, пишущих посещения).
  """
  use BuildCalculator.DataCase, async: true

  alias BuildCalculator.Analytics
  alias BuildCalculator.Analytics.{Event, Salt, Visit}

  defp visit_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        visitor: Analytics.visitor({203, 0, 113, 7}, "Mozilla/5.0 test"),
        edition: "siala",
        page: "/b/:code",
        referrer_host: "discord.com",
        utm: %{utm_source: "forum", utm_medium: nil}
      },
      overrides
    )
  end

  describe "visitor/2" do
    test "16 байт, один и тот же у одного адреса и браузера в один день" do
      {day, hash} = Analytics.visitor({203, 0, 113, 7}, "UA")

      assert day == Date.utc_today()
      assert byte_size(hash) == 16
      assert {^day, ^hash} = Analytics.visitor({203, 0, 113, 7}, "UA")
    end

    test "другой адрес, другой браузер — другой хеш; хеш не содержит ни того, ни другого" do
      {_, a} = Analytics.visitor({203, 0, 113, 7}, "UA")
      {_, b} = Analytics.visitor({203, 0, 113, 8}, "UA")
      {_, c} = Analytics.visitor({203, 0, 113, 7}, "UA2")
      {_, d} = Analytics.visitor({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}, "UA")

      assert length(Enum.uniq([a, b, c, d])) == 4
      refute a =~ "203.0.113.7"
    end

    test "без адреса и без браузера — всё равно 16 байт, а не падение" do
      assert {_, <<_::128>>} = Analytics.visitor(nil, nil)
    end
  end

  describe "Salt.decide/2 — соль дня" do
    test "нет соли или она вчерашняя — новая; сегодняшняя и будущая — остаются" do
      today = ~D[2026-10-04]

      assert Salt.decide(nil, today) == :rotate
      assert Salt.decide({~D[2026-10-03], "old"}, today) == :rotate
      assert Salt.decide({today, "now"}, today) == {:keep, {today, "now"}}

      # День не идёт назад: часы отстали — соль не перевыпускается для вчера.
      assert Salt.decide({~D[2026-10-05], "next"}, today) == {:keep, {~D[2026-10-05], "next"}}
    end

    test "соль живёт в памяти и выдаётся вместе со своим днём" do
      {day, salt} = Salt.current()

      assert day == Date.utc_today()
      assert byte_size(salt) == 32
      assert Salt.current() == {day, salt}
    end
  end

  describe "record_visit/1" do
    test "пишет строку ровно из полей посещения" do
      assert :ok = Analytics.record_visit(visit_attrs())

      assert [%Visit{} = row] = Repo.all(Visit)
      assert row.page == "/b/:code"
      assert row.edition == "siala"
      assert row.referrer_host == "discord.com"
      assert row.utm_source == "forum"
      assert row.utm_medium == nil
      assert byte_size(row.visitor) == 16
      assert row.day == Date.utc_today()
    end

    test "страница не по форме шаблона — строка не пишется вовсе" do
      for page <- ["/b/:code?b=xyz", "b/:code", "/B/ABC", "", "/b/" <> String.duplicate("a", 70)] do
        assert {:error, :invalid} = Analytics.record_visit(visit_attrs(%{page: page})),
               "страница #{inspect(page)} должна быть отвергнута"
      end

      assert Repo.all(Visit) == []
    end

    test "длинная метка или хост — строка выбрасывается, а не обрезается" do
      long = String.duplicate("x", 65)

      assert {:error, :invalid} =
               Analytics.record_visit(visit_attrs(%{utm: %{utm_campaign: long}}))

      assert {:error, :invalid} =
               Analytics.record_visit(visit_attrs(%{referrer_host: String.duplicate("a", 254)}))

      assert {:error, :invalid} = Analytics.record_visit(%{page: "/"})
      assert Repo.all(Visit) == []
    end
  end

  describe "record_event/3" do
    test "имя из закрытого списка — строка с именем, редакцией и ruleset'ом" do
      assert :ok = Analytics.record_event("siala", :export_downloaded, "siala_41")

      assert [%Event{name: "export_downloaded", edition: "siala", ruleset: "siala_41"}] =
               Repo.all(Event)
    end

    test "чужое имя не пишется" do
      assert {:error, :invalid} = Analytics.record_event("siala", :build_code, "siala_41")
      assert {:error, :invalid} = Analytics.record_event("siala", "export_downloaded", nil)
      assert Repo.all(Event) == []
    end

    test "все имена списка проходят" do
      for name <- Analytics.events(), do: assert(:ok = Analytics.record_event("siala", name, nil))
      assert length(Repo.all(Event)) == length(Analytics.events())
    end
  end
end
