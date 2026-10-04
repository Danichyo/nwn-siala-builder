defmodule BuildCalculatorWeb.LongPollBodyLimit do
  @moduledoc """
  The ceiling on one request body of the LongPoll transport of the LiveView
  socket (task 4.74) — the same number as the ceiling on one WebSocket message,
  `BuildCalculatorWeb.Endpoint.max_message_bytes/0` (task 4.41).

  ## Why a plug of our own

  The socket has two transports, and since 4.41 only one of them had a
  ceiling. Phoenix's LongPoll reads the body of a `POST` with Plug's default
  (`read_body/2`: 8 000 000 bytes) and dispatches every line of it as a
  message, up to 100 of them — the ceiling of the WebSocket did not apply, and
  the transport has no option of its own (Phoenix 1.8.9,
  `Phoenix.Transports.LongPoll.publish/4`). The transport stays on (Dan's
  decision of 15.08.2026: the client no longer falls back to it, the server
  keeps it so that bringing the fallback back is one line in `app.js`), so the
  ceiling goes in front of it.

  The socket is dispatched by the very first plug of the endpoint —
  `plug :socket_dispatch` comes from `use Phoenix.Endpoint`, before any `plug`
  the endpoint declares. So this plug runs from the endpoint's own `call/2`,
  before `super`.

  ## The ceiling is on the whole body, not on each message

  A LongPoll body is a batch: phoenix.js sends in one `POST` whatever was pushed
  within one tick plus whatever piled up while the previous `POST` waited for its
  answer. The ceiling is on the batch because:

    * the server reads the body whole before it dispatches a single message —
      the body is the unit of memory here, as one message is on the WebSocket
      (Bandit gathers the frames of a message whole); the same number bounds
      the same thing;
    * a body under the ceiling cannot carry a message over it — the transport
      is never looser than the WebSocket;
    * a paste window sends one message per `POST`: the worst legitimate paste
      (64 001 × «漢») went as 576 196 bytes, and a submit right after the
      paste went alone — the debounced change was not sent at all (live
      measurement, `tmp/4.74/`). A batch of several big messages takes a
      player editing the nearly full window while the previous `POST` still
      uploads: four edits of that paste on a 200 KB/s uplink made a body of
      2 304 697 bytes;
    * such a batch, refused, costs one reconnect and not the text: LiveView
      recovers the form on rejoin with its current value — one message — and
      the window read the last text (same measurement; before the ceiling the
      body went through in 17 s, with it the window settled in 9 s). On a
      slower uplink the same batch fails anyway: phoenix.js gives a `POST`
      20 s, and 3.5 MB at 100 KB/s timed out before 4.74 too.

  ## How it decides — by the declared length, without reading

  The body is not read here: Phoenix's transport reads it itself, and Plug has
  no way to hand it a body read before. The declared `content-length` is the
  real bound — over HTTP/1.1 Bandit reads exactly that many bytes, and over
  HTTP/2 it refuses a stream whose data does not match it. A `POST` with no
  length — chunked, or HTTP/2 without the header — is refused (411): nothing
  but reading would bound it, and a browser's `XMLHttpRequest` with a string
  body always declares its length.

  ## What the client gets

  `413` (`411` without a length) with `{"status": 413}` — the shape of the
  transport's own answers — and, over HTTP/1.x, `connection: close`, so that
  Bandit does not drain the body it refused into memory to keep the
  connection alive (curl, sending with `Expect: 100-continue`, did not send
  the body at all).
  phoenix.js takes any status but 200 as an error and reconnects; LiveView
  then recovers the form once and drops it if that fails too
  (`pendingForms`) — two reconnects and quiet, as with the WebSocket.
  """

  @behaviour Plug

  import Plug.Conn

  alias BuildCalculatorWeb.InputLimits

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    max_bytes = Keyword.fetch!(opts, :max_bytes)
    %{path_info: String.split(path, "/", trim: true), max_bytes: max_bytes}
  end

  @impl true
  def call(
        %Plug.Conn{method: "POST", path_info: path_info} = conn,
        %{path_info: path_info} = opts
      ) do
    case declared_length(conn) do
      {:ok, length} when length <= opts.max_bytes -> conn
      {:ok, _over} -> refuse(conn, 413)
      :none -> refuse(conn, 411)
    end
  end

  def call(conn, _opts), do: conn

  # Ровно один заголовок с целым числом. Два заголовка, мусор или число
  # длиннее разумного — «длина не объявлена»: судить по такому нечему.
  defp declared_length(conn) do
    with [value] <- get_req_header(conn, "content-length"),
         {length, ""} when length >= 0 <- InputLimits.integer(value) do
      {:ok, length}
    else
      _no_length -> :none
    end
  end

  defp refuse(conn, status) do
    conn
    |> close_after_response()
    |> put_resp_content_type("application/json")
    |> send_resp(status, Phoenix.json_library().encode_to_iodata!(%{"status" => status}))
    |> halt()
  end

  # `connection: close` — только HTTP/1.x: там без него Bandit, держа соединение
  # живым, дочитал бы отвергнутое тело в память (`ensure_completed`, до 8 МБ).
  # В HTTP/2 заголовок соединения запрещён (RFC 9113 §8.2.2: curl рвёт поток
  # «Invalid HTTP header field», замер 4.74), а поток закрывается сам.
  defp close_after_response(conn) do
    case get_http_protocol(conn) do
      :"HTTP/2" -> conn
      _http1 -> put_resp_header(conn, "connection", "close")
    end
  end
end
