defmodule BuildCalculatorWeb.RequestLog do
  @moduledoc """
  Строка журнала запроса — с **шаблоном маршрута** вместо пути (задача 4.75).

  `Phoenix.Logger` печатает на `:info` путь запроса как есть: `GET /b/<код>`
  на каждый переход по ссылке на билд, `GET /s/<ключ>`, `GET /builds/<id>`,
  `GET /users/log-in/<токен>`. В проде это лог Docker (`DEPLOY.md`), и слово
  Dan — «главное, чтобы мы не логировали билды». Поэтому строку Phoenix
  выключает `log: false` у `Plug.Telemetry` в эндпоинте, а её место занимает
  этот плаг — та же пара строк, тот же уровень, но путь назван шаблоном,
  которым его знает роутер:

      GET /b/:code
      Sent 200 in 12ms

  Query в строку не идёт вовсе — его не печатал и `Phoenix.Logger`
  (`request_path`, без query), так что `/?b=<код>` и раньше был `GET /`.
  Путь, которого роутер не знает (404), печатается `(unmatched path)`:
  в нём бывает что угодно, в том числе код, вставленный не туда.

  Шаблон ищется ДО роутера (`Phoenix.Router.route_info/4`): метод `HEAD`
  ищется как `GET` (его превращает в `GET` `Plug.Head` ниже по цепочке), а
  `POST`, не нашедший маршрута, — ещё и как `PUT`/`PATCH`/`DELETE`
  (`Plug.MethodOverride` ниже: `<.link method="delete">` приходит `POST`).
  Статика (`Plug.Static`) стоит раньше и в журнал не попадала и прежде.
  """
  @behaviour Plug

  require Logger

  alias Plug.Conn

  @router BuildCalculatorWeb.Router
  @unmatched "(unmatched path)"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Conn{} = conn, _opts) do
    start = System.monotonic_time()
    Logger.info(fn -> [conn.method, ?\s, describe(conn)] end)

    Conn.register_before_send(conn, fn conn ->
      Logger.info(fn ->
        [sent(conn.state), ?\s, Integer.to_string(conn.status), " in ", duration(start)]
      end)

      conn
    end)
  end

  @doc """
  Шаблон маршрута для запроса — или `"(unmatched path)"`.
  """
  @spec describe(Conn.t()) :: String.t()
  def describe(%Conn{method: method, request_path: path, host: host}) do
    case template(method, path, host) do
      {:ok, route} -> route
      :error -> @unmatched
    end
  end

  @doc """
  Шаблон маршрута для `GET` по пути `path` — или `"/(unmatched path)"`.

  Для адресов внутри текста лога (`BuildCalculatorWeb.LogRedaction`): адрес
  сводится к хосту и шаблону, так что всё, что после хоста, остаётся
  с косой чертой в начале.
  """
  @spec route(String.t(), String.t() | nil) :: String.t()
  def route(path, host) do
    case template("GET", path, host) do
      {:ok, route} -> route
      :error -> "/" <> @unmatched
    end
  end

  defp template(method, path, host) do
    Enum.find_value(methods(method), :error, fn verb ->
      case Phoenix.Router.route_info(@router, verb, path, host || "") do
        %{route: route} when is_binary(route) -> {:ok, route}
        _ -> nil
      end
    end)
  rescue
    _ -> :error
  end

  defp methods("HEAD"), do: ["GET"]
  defp methods("POST"), do: ["POST", "PUT", "PATCH", "DELETE"]
  defp methods(method), do: [method]

  defp sent(:set_chunked), do: "Chunked"
  defp sent(_state), do: "Sent"

  defp duration(start) do
    micros = System.convert_time_unit(System.monotonic_time() - start, :native, :microsecond)

    if micros > 1000,
      do: [Integer.to_string(div(micros, 1000)), "ms"],
      else: [Integer.to_string(micros), "µs"]
  end
end
