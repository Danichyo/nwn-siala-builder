defmodule BuildCalculatorWeb.RequestBodyLimitTest do
  @moduledoc """
  Потолок тела HTTP-запроса — задача 4.76 (`InputLimits.request_body/0`,
  `Plug.Parsers` в эндпоинте).

  До 4.76 парсеры держали умолчания: форма — 1 МБ, JSON и multipart — 8 МБ,
  и тело читалось и разбиралось на ЛЮБОМ пути, до роутера и проверки CSRF
  (замер «до»: JSON 7,9 МБ на `/users/log-in` — 403 после разбора, на
  несуществующий путь — 404 после разбора; multipart 7,9 МБ — 403).

  Граница проверяется с обеих сторон: тело на байт меньше потолка доходит
  до контроллера (вход отвечает переадресацией), на байт больше — 413 до
  разбора.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  alias BuildCalculatorWeb.InputLimits

  defp status(fun) do
    fun.().status
  rescue
    e in Plug.Conn.WrapperError -> Plug.Exception.status(e.reason)
    e -> Plug.Exception.status(e)
  end

  # Форма входа с набивкой ровно до `size` байт тела.
  defp login_body(size) do
    head =
      Plug.Conn.Query.encode(%{"user" => %{"email" => "a@b.c", "password" => "p"}}) <> "&pad="

    head <> String.duplicate("x", size - byte_size(head))
  end

  defp post_raw(conn, path, type, body) do
    conn
    |> put_req_header("content-type", type)
    |> post(path, body)
  end

  test "форма на потолке доходит до контроллера, на байт больше — 413", %{conn: conn} do
    limit = InputLimits.request_body()
    form = "application/x-www-form-urlencoded"

    at_limit = post_raw(conn, ~p"/users/log-in", form, login_body(limit))
    assert byte_size(login_body(limit)) == limit
    assert redirected_to(at_limit) == ~p"/users/log-in"

    assert status(fn -> post_raw(conn, ~p"/users/log-in", form, login_body(limit + 1)) end) ==
             413
  end

  test "JSON и multipart сверх потолка — 413 на любом пути, до роутера", %{conn: conn} do
    json = Jason.encode!(%{"user" => %{"password" => String.duplicate("x", 100_000)}})

    for path <- [~p"/users/log-in", "/no/such/path"] do
      assert status(fn -> post_raw(conn, path, "application/json", json) end) == 413
    end

    boundary = "----b476"

    multipart =
      "--#{boundary}\r\ncontent-disposition: form-data; name=\"f\"; filename=\"f.bin\"\r\n" <>
        "content-type: application/octet-stream\r\n\r\n" <>
        String.duplicate("x", 100_000) <> "\r\n--#{boundary}--\r\n"

    assert status(fn ->
             post_raw(
               conn,
               ~p"/users/log-in",
               "multipart/form-data; boundary=#{boundary}",
               multipart
             )
           end) == 413

    # Положительный контроль: тот же путь с маленьким JSON доходит до роутера.
    assert status(fn -> post_raw(conn, "/no/such/path", "application/json", ~s({"a":1})) end) ==
             404
  end
end
