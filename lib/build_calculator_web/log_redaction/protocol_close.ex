defmodule BuildCalculatorWeb.LogRedaction.ProtocolClose do
  @moduledoc """
  A WebSocket the server closed because the client broke the protocol — one
  `warning` line instead of an `error` report (task 4.76).

  Bandit closes the connection when a message goes past the socket's ceiling
  (`BuildCalculatorWeb.InputLimits`, close code 1009) or a frame breaks
  RFC 6455 (a stray continuation frame, a text frame that is not UTF-8, …).
  It does so by stopping the connection process with its own reason string,
  and the process's stop came to the log as a `GenServer … terminating`
  report at `error` — four lines (measured on the dev server, 2.1 MB in
  frames of 131 000 bytes):

      [error] GenServer #PID<0.718.0> terminating
      ** (stop) "Received oversize fragmented message"
      Process Label: {Phoenix.Socket, Phoenix.LiveView.Socket, nil}
      Last message: #Withheld<{:tcp, …} of 3>

  — and one line at `error` for a single frame past the ceiling or a frame
  that does not parse (`** (exit) {:deserializing, :max_frame_size_exceeded}`,
  `Bandit.Logger`).
  None of it is an error of ours: the browser never sends either (its worst
  legitimate message is 0.58 MB, task 4.41), and a stray continuation frame
  costs a hand-made client three bytes — each connection could put an `error`
  report in the log.

  So the event is rewritten, not dropped: one line at `warning` that still
  says the connection was closed and why, in Bandit's own words (no byte of
  the client's in them):

      [warning] WebSocket closed by the server — the client broke the protocol: Received oversize fragmented message

  Only these exact shapes are touched: a `gen_server` stop whose reason is one
  of Bandit's protocol-close strings (`@reasons`, read from
  `Bandit.WebSocket.Connection`; `protocol_close_test.exs` checks they are
  still there), and a `Bandit.Logger` line whose crash reason is
  `{:deserializing, _}`. An exception, any other stop reason, any other
  `Bandit` line stays as it was — a real error is not quietened.
  """

  # Причины, с которыми Bandit останавливает соединение WebSocket за нарушение
  # протокола клиентом (`Bandit.WebSocket.Connection`, `do_error/4`): строки
  # Bandit, без единого байта клиента.
  @reasons [
    "Received oversize fragmented message",
    "Received unexpected continuation frame (RFC6455§5.4)",
    "Received non UTF-8 text frame (RFC6455§8.1)",
    "Received zero byte non-fin continuation frame",
    "Received unexpected text frame (RFC6455§5.4)",
    "Received unexpected binary frame (RFC6455§5.4)",
    "Received unexpected compressed frame (RFC6455§5.2)",
    "Received compressed frame inflating too much",
    "Inflation error"
  ]

  @prefix "WebSocket closed by the server — the client broke the protocol: "

  @doc "Bandit's protocol-close reasons this module rewrites."
  @spec reasons() :: [String.t()]
  def reasons, do: @reasons

  @doc """
  The event as one `warning` line, or `:keep` when it is not a protocol close.
  """
  @spec rewrite(:logger.log_event()) :: {:ok, :logger.log_event()} | :keep
  def rewrite(%{msg: {:report, report}, meta: meta} = event) when is_map(report) do
    case report do
      %{label: {:gen_server, :terminate}, reason: reason} when reason in @reasons ->
        {:ok, line(event, meta, reason)}

      _other ->
        :keep
    end
  end

  # Домен Bandit Elixir дополняет своим: `[:elixir, :bandit]`. Причина разбора
  # кадра — атом или строка Bandit (`"unknown opcode 3"`: число — четыре бита
  # заголовка кадра, не данные клиента).
  def rewrite(%{meta: %{domain: domain, crash_reason: {{:deserializing, why}, _}} = meta} = event)
      when is_list(domain) and (is_atom(why) or is_binary(why)) do
    if :bandit in domain,
      do: {:ok, line(event, meta, inspect({:deserializing, why}))},
      else: :keep
  end

  def rewrite(_event), do: :keep

  defp line(event, meta, reason) do
    %{
      event
      | level: :warning,
        msg: {:string, @prefix <> reason},
        meta: Map.take(meta, [:time, :pid, :gl, :domain, :mfa, :request_id])
    }
  end
end
