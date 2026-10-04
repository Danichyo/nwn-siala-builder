defmodule BuildCalculatorWeb.SocketLogTest do
  @moduledoc """
  Строка о подключении сокета LiveView — одна и без параметров клиента
  (задача 4.76, `BuildCalculatorWeb.SocketLog`).

  До 4.76 `Phoenix.Logger` писал на `:info` четыре строки с параметрами
  подключения: 234 байта от браузера, до 8 КБ от собранного руками
  (замер на dev-сервере). Строка не опущена на `:debug`: прод читал её при
  диагностике сокета (`docs/deploy_log.md`) — что подключилось, когда и каким
  транспортом. Это остаётся, в одну строку и с прежними подстроками для grep.

  ⚠️ `async: false` — уровень логгера (`Logger.configure/1`) общий на всё
  приложение: тест ставит `:info`, как в проде (`config/prod.exs`).
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias BuildCalculatorWeb.SocketLog

  setup do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
    :ok
  end

  defp open_socket(conn, params) do
    %{conn | req_headers: [{"host", "www.example.com"} | conn.req_headers]}
    |> put_req_header("connection", "Upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-version", "13")
    |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
    |> get("/live/websocket", Map.put(params, "vsn", "2.0.0"))
  end

  test "одна строка: результат, сокет, время, транспорт — и ни одного параметра", %{conn: conn} do
    pad = String.duplicate("z", 9_000)

    log = capture_log(fn -> assert open_socket(conn, %{"p" => pad}).state == :upgraded end)

    assert [line] =
             log
             |> String.split("\n", trim: true)
             |> Enum.filter(&(&1 =~ "Phoenix.LiveView.Socket"))

    assert line =~
             ~r/CONNECTED TO Phoenix\.LiveView\.Socket in \d+(µs|ms)  Transport: :websocket$/

    refute log =~ "zzzzzzzz"
    refute log =~ "Parameters:"
    refute log =~ "Serializer:"
    assert byte_size(line) < 120
  end

  test "положительный контроль: строка Phoenix на тех же данных несёт параметры" do
    pad = String.duplicate("z", 9_000)

    metadata = %{
      endpoint: BuildCalculatorWeb.Endpoint,
      transport: :websocket,
      params: %{"p" => pad, "vsn" => "2.0.0"},
      connect_info: %{},
      vsn: "2.0.0",
      user_socket: Phoenix.LiveView.Socket,
      log: :info,
      result: :ok,
      serializer: Phoenix.Socket.V2.JSONSerializer
    }

    phoenix =
      capture_log(fn ->
        Phoenix.Logger.phoenix_socket_connected([], %{duration: 1000}, metadata, :ok)
      end)

    ours =
      capture_log(fn ->
        SocketLog.handle_event([:phoenix, :socket_connected], %{duration: 1000}, metadata, nil)
      end)

    assert phoenix =~ "zzzzzzzz"
    assert byte_size(phoenix) > 4_000
    refute ours =~ "zzzzzzzz"
    assert ours =~ "CONNECTED TO Phoenix.LiveView.Socket"
  end

  test "своя строка Phoenix выключена на обоих транспортах" do
    assert [{"/live", Phoenix.LiveView.Socket, opts}] = BuildCalculatorWeb.Endpoint.__sockets__()

    for transport <- [:websocket, :longpoll] do
      assert Keyword.fetch!(opts, transport)[:log] == false, inspect(transport)
    end
  end

  test "отказ — REFUSED, другой сокет — не наша строка" do
    refused = %{user_socket: Phoenix.LiveView.Socket, transport: :longpoll, result: :error}

    assert IO.iodata_to_binary(SocketLog.line(refused, nil)) ==
             "REFUSED CONNECTION TO Phoenix.LiveView.Socket  Transport: :longpoll"

    other = %{user_socket: Phoenix.LiveReloader.Socket, transport: :websocket, result: :ok}

    assert capture_log(fn ->
             SocketLog.handle_event([:phoenix, :socket_connected], %{duration: 1}, other, nil)
           end) == ""
  end
end
