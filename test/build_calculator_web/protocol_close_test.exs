defmodule BuildCalculatorWeb.ProtocolCloseTest do
  @moduledoc """
  Закрытие WebSocket за нарушение протокола клиентом — одна строка `warning`
  вместо отчёта `error` (задача 4.76, `BuildCalculatorWeb.LogRedaction.ProtocolClose`).

  До 4.76 сообщение сверх потолка сокета (4.41) приходило в лог отчётом
  `GenServer … terminating` на `error` (четыре строки, замер на dev-сервере),
  кадр сверх потолка — строкой `error` `Bandit.Logger`, а «лишний» кадр
  продолжения (три байта от собранного руками клиента) — тем же отчётом.

  Проверяется на настоящем Bandit сырым клиентом WebSocket: событие доходит
  до фильтра той формы, какой его шлёт Bandit. Положительный контроль — тот
  же отчёт с другой причиной и исключение в обработчике остаются `error`.

  ⚠️ `async: false` — `capture_log/1` видит процессы Bandit (не процессы
  теста), а значит и чужие строки.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BuildCalculatorWeb.LogRedaction.ProtocolClose

  @ceiling 1_000

  defmodule Sock do
    @moduledoc false
    @behaviour WebSock

    @impl true
    def init(state), do: {:ok, state}

    # `"boom"` — исключение в обработчике (контроль: настоящая ошибка),
    # `"stop"` — остановка со своей причиной (контроль: не протокол).
    @impl true
    def handle_in({"boom", _opts}, _state), do: raise("handler bug")
    def handle_in({"stop", _opts}, state), do: {:stop, "handler said stop", state}
    def handle_in(_message, state), do: {:ok, state}

    @impl true
    def handle_info(_message, state), do: {:ok, state}

    @impl true
    def terminate(_reason, _state), do: :ok
  end

  defmodule UpgradePlug do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts) do
      conn
      |> WebSockAdapter.upgrade(Sock, nil, max_frame_size: 1_000)
      |> Plug.Conn.halt()
    end
  end

  setup do
    pid =
      start_supervised!(
        {Bandit,
         plug: UpgradePlug,
         port: 0,
         ip: :loopback,
         startup_log: false,
         websocket_options: [max_fragmented_message_size: @ceiling]}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    %{bandit: %{port: port, server: pid}}
  end

  # Сырой клиент: подъём и кадры с нулевой маской (клиент обязан маскировать,
  # нулевой ключ оставляет полезную нагрузку как есть).
  defp open(port) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

    :ok =
      :gen_tcp.send(socket, [
        "GET / HTTP/1.1\r\nhost: localhost\r\nupgrade: websocket\r\nconnection: Upgrade\r\n",
        "sec-websocket-key: dGhlIHNhbXBsZSBub25jZQ==\r\nsec-websocket-version: 13\r\n\r\n"
      ])

    {:ok, "HTTP/1.1 101" <> _} = :gen_tcp.recv(socket, 0, 2_000)
    socket
  end

  defp frame(opcode, fin, payload) do
    size = byte_size(payload)

    length =
      cond do
        size < 126 -> <<1::1, size::7>>
        size < 65_536 -> <<1::1, 126::7, size::16>>
        true -> <<1::1, 127::7, size::64>>
      end

    <<fin::1, 0::3, opcode::4>> <> length <> <<0::32>> <> payload
  end

  # Отправить кадры и дождаться, пока процесс соединения на сервере
  # завершится: отчёт о его остановке пишется до выхода процесса.
  defp send_and_wait_close(%{port: port, server: server}, frames) do
    socket = open(port)
    {:ok, [connection]} = ThousandIsland.connection_pids(server)
    ref = Process.monitor(connection)
    for frame <- frames, do: :gen_tcp.send(socket, frame)
    assert_receive {:DOWN, ^ref, :process, ^connection, _reason}, 2_000
    :gen_tcp.close(socket)
  end

  defp lines(log), do: String.split(log, "\n", trim: true)

  test "сообщение из кадров сверх потолка — одна строка warning", %{bandit: bandit} do
    half = String.duplicate("a", 600)

    log =
      capture_log(fn ->
        send_and_wait_close(bandit, [frame(0x1, 0, half), frame(0x0, 1, half)])
      end)

    assert log =~
             "[warning] WebSocket closed by the server — the client broke the protocol: " <>
               "Received oversize fragmented message"

    refute log =~ "terminating"
    refute log =~ "[error]"
    assert length(Enum.filter(lines(log), &(&1 =~ "WebSocket closed"))) == 1
  end

  test "кадр сверх потолка кадра — тоже warning", %{bandit: bandit} do
    log =
      capture_log(fn ->
        send_and_wait_close(bandit, [frame(0x1, 1, String.duplicate("a", 2_000))])
      end)

    assert log =~
             "[warning] WebSocket closed by the server — the client broke the protocol: " <>
               "{:deserializing, :max_frame_size_exceeded}"

    refute log =~ "[error]"
  end

  test "лишний кадр продолжения — warning", %{bandit: bandit} do
    log =
      capture_log(fn ->
        send_and_wait_close(bandit, [frame(0x0, 1, "abc")])
      end)

    assert log =~ "Received unexpected continuation frame (RFC6455§5.4)"
    assert log =~ "[warning]"
    refute log =~ "[error]"
  end

  describe "положительный контроль: настоящая ошибка остаётся error" do
    test "исключение в обработчике сокета", %{bandit: bandit} do
      log =
        capture_log(fn ->
          send_and_wait_close(bandit, [frame(0x1, 1, "boom")])
        end)

      assert log =~ "[error]"
      assert log =~ "handler bug"
      refute log =~ "WebSocket closed by the server"
    end

    test "остановка обработчика со своей причиной", %{bandit: bandit} do
      log =
        capture_log(fn ->
          send_and_wait_close(bandit, [frame(0x1, 1, "stop")])
        end)

      assert log =~ "[error]"
      assert log =~ "handler said stop"
      refute log =~ "WebSocket closed by the server"
    end

    test "отчёт с другой причиной не трогается" do
      event = %{
        level: :error,
        msg: {:report, %{label: {:gen_server, :terminate}, reason: "handler said stop"}},
        meta: %{time: 0}
      }

      assert ProtocolClose.rewrite(event) == :keep
    end
  end

  test "причины — строки самого Bandit (переименование в Bandit уронит этот тест)" do
    source =
      Mix.Project.deps_paths()
      |> Map.fetch!(:bandit)
      |> Path.join("lib/bandit/websocket/connection.ex")
      |> File.read!()

    for reason <- ProtocolClose.reasons() do
      assert source =~ ~s("#{reason}"), reason
    end
  end
end
