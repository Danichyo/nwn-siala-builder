defmodule BuildCalculatorWeb.LongPollBodyLimitTest do
  @moduledoc """
  Потолок тела POST транспорта LongPoll сокета LiveView — задача 4.74
  (`BuildCalculatorWeb.LongPollBodyLimit`).

  У вебсокета потолок одного сообщения — `Endpoint.max_message_bytes/0` (4.41).
  LongPoll читал тело POST умолчанием Plug (8 МБ) и рассылал до 100 сообщений
  пачкой — мимо потолка. Транспорт не выключается (решение Dan 15.08.2026),
  поэтому перед ним стоит свой предел тела с тем же числом, и стоит он в
  `Endpoint.call/2`: сокет разбирается самым первым плагом эндпоинта.

  Здесь — настоящие запросы к эндпоинту, весь путь Phoenix: GET открывает сеанс
  LongPoll (`{"status": 410, "token": …}`), POST несёт heartbeat с набивкой,
  следующий GET того же сеанса приносит ответы `phx_reply`. **Дошло ли
  сообщение до сокета, видно по ответу на его `ref`**, а не по статусу POST.
  Чтобы не ждать окно опроса (10 с) на отвергнутом теле, за ним идёт маленький
  heartbeat со своим `ref`: опрос отдаёт всё накопленное разом, и ответа на
  отвергнутый `ref` среди него нет.

  `content-length` тест кладёт сам, как браузер. Что Bandit читает ровно
  объявленную длину (HTTP/1.1) и рвёт поток с длиной, не совпавшей с данными
  (HTTP/2), — свойство сервера, его тест без поднятого сервера не проверит;
  это показал живой замер 4.74 (`tmp/4.74/raw_lp.py`, curl по HTTP/1.1 и h2c:
  2 000 001 байт — 413, chunked и без длины — 411, ровно 2 000 000 — дошло;
  на `76b597e` 2,1 МБ и пачка 4 × 600 000 доходили).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  alias BuildCalculatorWeb.{Endpoint, LongPollBodyLimit}

  @path "/live/longpoll"

  # Сообщение протокола V2 ровно в `size` байт: heartbeat обслуживает сам
  # `Phoenix.Socket`, join канала не нужен.
  defp heartbeat(size, ref) do
    head = ~s([null,"#{ref}","phoenix","heartbeat",{"pad":")
    tail = ~s("}])
    head <> String.duplicate("a", size - byte_size(head) - byte_size(tail)) <> tail
  end

  defp open_session do
    conn = get(build_conn(), @path, %{"vsn" => "2.0.0"})
    assert %{"status" => 410, "token" => token} = json_response(conn, 200)
    token
  end

  defp post_body(token, body, opts \\ []) do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/x-ndjson")

    conn =
      if Keyword.get(opts, :length, true),
        do: put_req_header(conn, "content-length", Integer.to_string(byte_size(body))),
        else: conn

    post(conn, "#{@path}?vsn=2.0.0&token=#{URI.encode_www_form(token)}", body)
  end

  # Ответы `phx_reply`, накопленные сеансом, — по `ref`.
  defp replied_refs(token) do
    conn = get(build_conn(), @path, %{"vsn" => "2.0.0", "token" => token})
    %{"status" => 200, "messages" => messages} = json_response(conn, 200)

    for message <- messages,
        [_join_ref, ref, "phoenix", "phx_reply", _payload] <- [Jason.decode!(message)],
        do: ref
  end

  test "путь потолка — путь транспорта LongPoll, число — потолок сообщения вебсокета" do
    assert Endpoint.longpoll_path() == @path
    assert %{max_bytes: 2_000_000} = LongPollBodyLimit.init(path: @path, max_bytes: 2_000_000)

    # GET по этому пути отвечает сам транспорт — сеанс с токеном (`open_session/0`).
    assert is_binary(open_session())
  end

  test "тело ровно в потолок доходит до сокета" do
    token = open_session()
    conn = post_body(token, heartbeat(Endpoint.max_message_bytes(), "1"))

    assert json_response(conn, 200) == %{"status" => 200}
    assert replied_refs(token) == ["1"]
  end

  test "тело на байт длиннее — 413, до сокета не доходит, соединение закрывается" do
    token = open_session()
    conn = post_body(token, heartbeat(Endpoint.max_message_bytes() + 1, "1"))

    assert json_response(conn, 413) == %{"status" => 413}
    assert get_resp_header(conn, "connection") == ["close"]

    # Сеанс жив: следующее, законное, сообщение доходит, отвергнутое — нет.
    assert json_response(post_body(token, heartbeat(100, "2")), 200) == %{"status" => 200}
    assert replied_refs(token) == ["2"]
  end

  test "потолок — на всё тело: пачка из трёх по 600 000 доходит, из четырёх — 413" do
    token = open_session()
    three = Enum.map_join(1..3, "\n", &heartbeat(600_000, Integer.to_string(&1)))

    assert byte_size(three) < Endpoint.max_message_bytes()
    assert json_response(post_body(token, three), 200) == %{"status" => 200}
    assert Enum.sort(replied_refs(token)) == ["1", "2", "3"]

    token = open_session()
    four = Enum.map_join(4..7, "\n", &heartbeat(600_000, Integer.to_string(&1)))

    assert byte_size(four) > Endpoint.max_message_bytes()
    assert json_response(post_body(token, four), 413) == %{"status" => 413}
    assert json_response(post_body(token, heartbeat(100, "8")), 200) == %{"status" => 200}
    assert replied_refs(token) == ["8"]
  end

  test "без объявленной длины — 411: судить по такому телу нечему" do
    token = open_session()
    conn = post_body(token, heartbeat(100, "1"), length: false)

    assert json_response(conn, 411) == %{"status" => 411}
    assert json_response(post_body(token, heartbeat(100, "2")), 200) == %{"status" => 200}
    assert replied_refs(token) == ["2"]
  end

  test "длина мусором или двумя заголовками — тоже 411" do
    token = open_session()
    body = heartbeat(100, "1")

    for lengths <- [["abc"], ["100", "100"], [String.duplicate("1", 2_000_000)]] do
      conn =
        Enum.reduce(lengths, build_conn(), fn value, conn ->
          %{conn | req_headers: [{"content-length", value} | conn.req_headers]}
        end)
        |> put_req_header("content-type", "application/x-ndjson")
        |> post("#{@path}?vsn=2.0.0&token=#{URI.encode_www_form(token)}", body)

      assert json_response(conn, 411) == %{"status" => 411}, inspect(lengths, limit: 3)
    end
  end

  describe "плаг сам по себе" do
    setup do
      %{opts: LongPollBodyLimit.init(path: @path, max_bytes: 10)}
    end

    test "трогает только POST на свой путь", %{opts: opts} do
      for {method, path} <- [{"GET", @path}, {"OPTIONS", @path}, {"POST", "/live/websocket"}] do
        conn =
          Plug.Test.conn(method, path)
          |> put_req_header("content-length", "11")
          |> LongPollBodyLimit.call(opts)

        refute conn.halted, "#{method} #{path}"
        assert conn.state == :unset
      end

      conn =
        Plug.Test.conn("POST", @path)
        |> put_req_header("content-length", "11")
        |> LongPollBodyLimit.call(opts)

      assert conn.halted and conn.status == 413
    end

    test "по HTTP/2 заголовка соединения нет — он там запрещён", %{opts: opts} do
      conn =
        Plug.Test.conn("POST", @path)
        |> Plug.Test.put_http_protocol(:"HTTP/2")
        |> put_req_header("content-length", "11")
        |> LongPollBodyLimit.call(opts)

      assert conn.status == 413
      assert get_resp_header(conn, "connection") == []
    end
  end
end
