defmodule BuildCalculatorWeb.SocketLog do
  @moduledoc """
  The line about a LiveView socket connecting — one line, without the
  connection's parameters (task 4.76).

  `Phoenix.Logger` writes four lines at `:info` on every connection:

      CONNECTED TO Phoenix.LiveView.Socket in 13µs
        Transport: :websocket
        Serializer: Phoenix.Socket.V2.JSONSerializer
        Parameters: %{"_analytics_nav" => "navigate", "_csrf_token" => "[FILTERED]", …}

  — 234 bytes from a browser, and up to 8 KB from a hand-made client: the
  parameters are whatever the query string of `/live/websocket` carries, each
  printed up to 4096 characters (measured on the dev server: one parameter of
  9 800 characters — 4 287 bytes, twenty of 480 — 8 129; Bandit refuses a
  request line past 10 000 bytes with 414). A loop of connections with no
  join behind them filled the log of Docker, rotated at 30 MB (`DEPLOY.md`),
  with nothing but those.

  The line is not dropped to `:debug`, because it is a diagnostic production
  has used: right after a deploy it was the proof that sockets connect at all
  when no browser was at hand; checking `check_origin`, the own origin's
  request left a `CONNECTED TO` line; the Android reconnection fix (3.67) was
  confirmed by `CONNECTED TO Phoenix.LiveView.Socket … Transport: :websocket`
  three seconds after the client forced it (`docs/deploy_log.md`). What those
  checks read — that it connected, when, how long it took, over which
  transport — stays, in one line of about seventy bytes:

      CONNECTED TO Phoenix.LiveView.Socket in 13µs  Transport: :websocket

  The old greps (`CONNECTED TO Phoenix.LiveView.Socket`, `Transport: :websocket`)
  still match it. Phoenix's own line is switched off in the endpoint
  (`log: false` on both transports); this module answers the same telemetry
  event, `[:phoenix, :socket_connected]`, attached from
  `BuildCalculator.Application.start/2`.
  """

  require Logger

  @handler_id __MODULE__

  # Сокеты, чью строку Phoenix выключена в эндпоинте (`log: false`).
  @sockets [Phoenix.LiveView.Socket]

  @doc "Attaches the handler (again — without an error)."
  @spec attach() :: :ok
  def attach do
    case :telemetry.attach(
           @handler_id,
           [:phoenix, :socket_connected],
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle_event([:phoenix, :socket_connected], measurements, metadata, _config) do
    if Map.get(metadata, :user_socket) in @sockets do
      Logger.info(fn -> line(metadata, Map.get(measurements, :duration)) end)
    end

    :ok
  end

  @doc """
  The line for one connection: result, socket, duration, transport.
  Nothing the client sent is in it.
  """
  @spec line(map(), integer() | nil) :: iodata()
  def line(metadata, duration) do
    [
      result(Map.get(metadata, :result)),
      inspect(Map.get(metadata, :user_socket)),
      duration(duration),
      "  Transport: ",
      inspect(Map.get(metadata, :transport))
    ]
  end

  defp result(:ok), do: "CONNECTED TO "
  defp result(_refused), do: "REFUSED CONNECTION TO "

  defp duration(native) when is_integer(native) do
    case System.convert_time_unit(native, :native, :microsecond) do
      micro when micro > 1000 -> [" in ", Integer.to_string(div(micro, 1000)), "ms"]
      micro -> [" in ", Integer.to_string(micro), "µs"]
    end
  end

  defp duration(_unknown), do: []
end
