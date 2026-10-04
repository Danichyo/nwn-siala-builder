defmodule BuildCalculatorWeb.EndpointFrameLimitTest do
  @moduledoc """
  Потолок одного сообщения браузера по сокету LiveView — задача 4.41.

  Предел стоит в ДВУХ местах из одного числа (`config.exs`,
  `:websocket_max_message_bytes`), и тест проверяет оба там, где их читает
  сервер, а не в конфиге:

    * **на кадр** — `max_frame_size` в настройках сокета (`endpoint.ex`). Phoenix
      отдаёт их `WebSockAdapter.upgrade/4`, тот — Bandit; без ключа
      WebSockAdapter ставит 10 МБ. Проверяется настоящим запросом на
      `/live/websocket`: тестовый адаптер Plug присылает процессу ровно то, что
      ушло бы Bandit;
    * **на сообщение из нескольких кадров** — `max_fragmented_message_size`
      в серверных настройках Bandit (`http: [websocket_options: …]`), умолчание
      Bandit — 8 МБ. Через настройки сокета Phoenix этот ключ не пропускает.
      Chrome шлёт длинное сообщение кадрами по 131 000 байт, так что для него
      действует только этот предел (замер 4.41, `tmp/4.41/ws_tap.py`).
      Проверяется спецификацией ребёнка, которую `Bandit.PhoenixAdapter`
      собирает из настроек эндпоинта, — тем, с чем Bandit стартует.

  Что Bandit на этих числах действительно рвёт соединение (код 1009), тест
  не проверяет — сервер в тестах не поднят; это показал живой замер 4.41
  (сырой клиент: один кадр и дробное сообщение по 2,1 МБ — закрыты, по 1,9 МБ —
  ответ; на `e3848fa` 2,1 МБ проходили оба).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  alias BuildCalculatorWeb.Endpoint

  test "потолок — 2 000 000 байт, из конфига" do
    assert Endpoint.max_message_bytes() == 2_000_000

    assert Endpoint.max_message_bytes() ==
             Application.fetch_env!(:build_calculator, :websocket_max_message_bytes)
  end

  test "сокет LiveView поднимается с потолком кадра", %{conn: conn} do
    # `host` — заголовком, а не полем `conn.host`: его требует проверка запроса
    # на подъём (`WebSockAdapter.UpgradeValidation`), а `put_req_header/3` его
    # не ставит (Plug велит класть `host` в поле).
    conn =
      %{conn | req_headers: [{"host", "www.example.com"} | conn.req_headers]}
      |> put_req_header("connection", "Upgrade")
      |> put_req_header("upgrade", "websocket")
      |> put_req_header("sec-websocket-version", "13")
      |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
      |> get("/live/websocket", %{"vsn" => "2.0.0"})

    assert conn.state == :upgraded

    assert_received {_ref, :upgrade, {:websocket, {Phoenix.LiveView.Socket, _state, opts}}}
    assert opts[:max_frame_size] == Endpoint.max_message_bytes()
  end

  test "Bandit стартует с тем же потолком сообщения из кадров" do
    config = [otp_app: :build_calculator, http: Endpoint.config(:http)]

    starts =
      for %{start: {Bandit, :start_link, [arg]}} <-
            Bandit.PhoenixAdapter.child_specs(Endpoint, config),
          do: arg

    assert [arg] = starts

    assert arg[:websocket_options][:max_fragmented_message_size] ==
             Endpoint.max_message_bytes()
  end
end
