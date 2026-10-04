defmodule BuildCalculatorWeb.RequestLogTest do
  @moduledoc """
  Строка журнала запроса — шаблон маршрута вместо пути (задача 4.75).

  Здесь — сопоставление «запрос → шаблон» как функция; сами строки на уровне
  `:info` через эндпоинт проверяет сторож `log_leak_test.exs`. Общих
  настроек тест не трогает — `async: true`.
  """
  use ExUnit.Case, async: true

  import Plug.Test

  alias BuildCalculatorWeb.RequestLog

  @code "2.fVTvb5swEDVgCCEhTZuk67aq3bRKjdR"

  test "путь с параметром — шаблоном роутера, query не печатается" do
    for {method, path, expected} <- [
          {"GET", "/b/#{@code}", "/b/:code"},
          {"GET", "/?b=#{@code}&l=5", "/"},
          {"GET", "/s/AbC123", "/s/:key"},
          {"GET", "/builds/98536704-499d-40cd-a2c9-c7cc4a659ca4", "/builds/:id"},
          {"GET", "/builds/new?b=#{@code}", "/builds/new"},
          {"GET", "/users/log-in/some-token", "/users/log-in/:token"},
          {"GET", "/sources", "/sources"},
          # `HEAD` превращается в `GET` ниже по цепочке (`Plug.Head`).
          {"HEAD", "/b/#{@code}", "/b/:code"},
          # `<.link method="delete">` приходит `POST` (`Plug.MethodOverride`).
          {"POST", "/users/log-out", "/users/log-out"},
          {"POST", "/users/log-in", "/users/log-in"}
        ] do
      assert RequestLog.describe(conn(method, path)) == expected, "#{method} #{path}"
    end
  end

  test "путь, которого роутер не знает, не печатается вовсе" do
    for path <- ["/#{@code}", "/b/#{@code}/extra", "/wp-login.php"] do
      assert RequestLog.describe(conn(:get, path)) == "(unmatched path)"
    end
  end

  test "адрес внутри текста лога — шаблон или «/(unmatched path)»" do
    assert RequestLog.route("/b/#{@code}", "example.com") == "/b/:code"
    assert RequestLog.route("/nope/#{@code}", nil) == "/(unmatched path)"
  end
end
