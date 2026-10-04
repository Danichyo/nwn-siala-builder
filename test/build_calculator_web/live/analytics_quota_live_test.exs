defmodule BuildCalculatorWeb.AnalyticsQuotaLiveTest do
  @moduledoc """
  Дневной потолок строк аналитики на живом экране (задача 4.75): ключи
  потолка считаются из того же адреса и User-Agent, что посетитель, и только
  у публичного адреса.

  Двести монтирований ради одного отказа дороги, поэтому бюджет посетителя
  тратится заранее вызовом хранилища (`Analytics.admit/1`) с теми же
  адресом и браузером, что у соединения теста, — а дальше настоящие
  монтирования. Сеть IPv6 `/64` у каждого теста своя (счёт общий на
  приложение) — `async: true`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Analytics
  alias BuildCalculator.Analytics.Visit
  alias BuildCalculator.Repo

  @moduletag :capture_log

  defp network do
    <<a::16, b::16>> = :crypto.strong_rand_bytes(4)

    {{0x2001, 0xDB8, a, b, 0, 0, 0, 7},
     "2001:db8:#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}::7"}
  end

  defp behind_proxy(conn, forwarded, agent) do
    conn
    |> Plug.Test.put_peer_data(%{address: {172, 18, 0, 1}, port: 50_000, ssl_cert: nil})
    |> put_req_header("x-forwarded-for", forwarded)
    |> put_req_header("user-agent", agent)
  end

  defp spend(ip, agent, times) do
    quota = Analytics.quota(ip, agent)
    for _ <- 1..times, do: Analytics.admit(quota)
  end

  test "посетитель у потолка: одна строка ещё пишется, следующая — нет", %{conn: conn} do
    {ip, forwarded} = network()
    spend(ip, "Bot/1.0", 199)
    conn = behind_proxy(conn, forwarded, "Bot/1.0")

    {:ok, _view, _html} = live(conn, "/sources")
    {:ok, _view, _html} = live(conn, "/sources")
    {:ok, _view, _html} = live(conn, "/")

    assert Repo.aggregate(Visit, :count) == 1

    # Контроль: другой браузер с того же адреса — свой бюджет.
    {:ok, _view, _html} = live(behind_proxy(conn, forwarded, "Firefox"), "/sources")
    assert Repo.aggregate(Visit, :count) == 2
  end

  test "адрес не публичный (X-Forwarded-For не дошёл) — потолка нет", %{conn: conn} do
    # Тот же «бот», но без заголовка: адрес — сам прокси, частная сеть.
    spend({172, 18, 0, 1}, "Bot/1.0", 300)

    conn =
      conn
      |> Plug.Test.put_peer_data(%{address: {172, 18, 0, 1}, port: 50_000, ssl_cert: nil})
      |> put_req_header("user-agent", "Bot/1.0")

    for _ <- 1..3, do: {:ok, _view, _html} = live(conn, "/sources")

    assert Repo.aggregate(Visit, :count) == 3
  end
end
