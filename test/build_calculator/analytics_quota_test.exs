defmodule BuildCalculator.AnalyticsQuotaTest do
  @moduledoc """
  Дневной потолок строк аналитики (задача 4.75): 200 на посетителя, 2000
  на адрес — против бота, открывающего сокеты (`BuildCalculator.Analytics`,
  «Потолок строк»).

  Счёт живёт в памяти (`BuildCalculator.RateLimit`) и общий на всё
  приложение, поэтому каждый тест берёт свою случайную сеть IPv6 `/64`:
  чужой тест в наш ключ не досчитает — `async: true`.
  """
  use BuildCalculator.DataCase, async: true

  import ExUnit.CaptureLog

  # Предупреждение «потолок достигнут» пишут почти все тесты — в вывод прогона
  # оно не идёт (на провале ExUnit его покажет).
  @moduletag :capture_log

  alias BuildCalculator.Analytics
  alias BuildCalculator.Analytics.{Event, Visit}

  # Своя сеть `/64` на тест; `host` — адрес внутри неё.
  defp network do
    <<a::16, b::16>> = :crypto.strong_rand_bytes(4)
    fn host -> {0x2001, 0xDB8, a, b, 0, 0, 0, host} end
  end

  defp visit(ip, agent) do
    Analytics.record_visit(%{
      visitor: Analytics.visitor(ip, agent),
      edition: "siala",
      page: "/",
      quota: Analytics.quota(ip, agent)
    })
  end

  defp spend(quota, times), do: for(_ <- 1..times, do: Analytics.admit(quota))

  describe "quota/2" do
    test "хеш посетителя — тот же, что у строки; адрес — сеть /64, с солью дня" do
      ip = network()

      %{day: day, visitor: visitor, address: address} = Analytics.quota(ip.(1), "UA")
      assert {^day, ^visitor} = Analytics.visitor(ip.(1), "UA")
      assert byte_size(address) == 16

      # Другой адрес той же сети /64 — тот же адрес, но другой посетитель.
      other = Analytics.quota(ip.(2), "UA")
      assert other.address == address
      refute other.visitor == visitor

      # Адрес — не хеш посетителя и не сам адрес.
      refute address == visitor
      assert Analytics.quota(nil, "UA") == nil
    end
  end

  describe "посетитель" do
    test "200 строк в день — дальше :capped, и строк в таблице ровно 200" do
      ip = network().(1)

      results = for _ <- 1..202, do: visit(ip, "UA")

      assert Enum.count(results, &(&1 == :ok)) == 200
      assert Enum.drop(results, 200) == [{:error, :capped}, {:error, :capped}]
      assert Repo.aggregate(Visit, :count) == 200
    end

    test "события и посещения — из одного бюджета" do
      ip = network().(1)
      quota = Analytics.quota(ip, "UA")
      spend(quota, 199)

      assert Analytics.record_event("siala", :export_downloaded, "siala_41", quota) == :ok

      assert Analytics.record_event("siala", :export_downloaded, "siala_41", quota) ==
               {:error, :capped}

      assert visit(ip, "UA") == {:error, :capped}
      assert Repo.aggregate(Event, :count) == 1
    end

    test "соседи по адресу и без потолка пишутся (контроль)" do
      net = network()
      spend(Analytics.quota(net.(1), "UA"), 200)

      assert visit(net.(1), "UA") == {:error, :capped}
      assert visit(net.(1), "UA2") == :ok
      assert visit(net.(2), "UA") == :ok

      # Без ключей потолка (адрес не публичный) — пишется всегда.
      assert Analytics.record_event("siala", :export_downloaded, nil, nil) == :ok
    end

    test "первая строка за потолком — одно предупреждение без значений" do
      ip = network().(1)
      quota = Analytics.quota(ip, "Bot/1.0")
      spend(quota, 200)

      log = capture_log(fn -> for _ <- 1..5, do: visit(ip, "Bot/1.0") end)

      assert [_one] = Regex.scan(~r/analytics: daily row cap reached for one visitor/, log)
      refute log =~ "Bot/1.0"
      refute log =~ "2001:db8"
    end
  end

  describe "адрес" do
    test "2000 строк с одного адреса — новый посетитель (User-Agent) уже не пишется" do
      net = network()

      # Бот меняет User-Agent на каждом сокете: 10 «посетителей» по 200.
      for n <- 1..10, do: spend(Analytics.quota(net.(1), "UA#{n}"), 200)

      assert visit(net.(1), "UA-new") == {:error, :capped}
      assert visit(net.(9), "UA-new") == {:error, :capped}

      # Контроль: соседняя сеть /64 пишется.
      assert visit(network().(1), "UA-new") == :ok
    end
  end
end
