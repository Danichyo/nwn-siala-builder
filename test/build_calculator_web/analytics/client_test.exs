defmodule BuildCalculatorWeb.Analytics.ClientTest do
  @moduledoc """
  Что от посетителя становится полем строки аналитики (задача 4.54):
  адрес за Caddy, хост источника, `utm_*`, вид перехода.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Analytics.Client

  # Пир внутри контейнера за Caddy: мост Docker, в сокете `::` — IPv4-mapped.
  @docker_bridge %{address: {0, 0, 0, 0, 0, 0xFFFF, 0xAC12, 0x0001}, port: 51_000}
  @loopback %{address: {127, 0, 0, 1}, port: 51_000}
  @public_peer %{address: {198, 51, 100, 9}, port: 51_000}

  describe "ip/2 — настоящий адрес за прокси" do
    test "свой пир: правый адрес X-Forwarded-For" do
      headers = [{"x-forwarded-for", "203.0.113.7"}]

      assert Client.ip(@docker_bridge, headers) == {203, 0, 113, 7}
      assert Client.ip(@loopback, headers) == {203, 0, 113, 7}
    end

    test "подделанный клиентом левый адрес не читается — только правый, дописанный прокси" do
      headers = [{"x-forwarded-for", "1.1.1.1, 2.2.2.2"}, {"x-forwarded-for", "203.0.113.7"}]
      assert Client.ip(@docker_bridge, headers) == {203, 0, 113, 7}
    end

    test "публичный пир: заголовок написал сам клиент — не читается вовсе" do
      for forged <- ["1.1.1.1", "8.8.8.8", "203.0.113.7"] do
        assert Client.ip(@public_peer, [{"x-forwarded-for", forged}]) == {198, 51, 100, 9}
      end
    end

    test "правый адрес не читается — пир, а не соседний левый" do
      headers = [{"x-forwarded-for", "203.0.113.7, not-an-ip"}]
      assert Client.ip(@loopback, headers) == {127, 0, 0, 1}
    end

    test "без заголовка — пир (IPv4-mapped развёрнут); без пира — nil" do
      assert Client.ip(@docker_bridge, []) == {172, 18, 0, 1}
      assert Client.ip(nil, [{"x-forwarded-for", "203.0.113.7"}]) == nil
    end

    test "IPv6 клиента и IPv4-mapped в заголовке" do
      assert Client.ip(@loopback, [{"x-forwarded-for", "2001:db8::1"}]) ==
               {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}

      assert Client.ip(@loopback, [{"x-forwarded-for", "::ffff:203.0.113.7"}]) ==
               {203, 0, 113, 7}
    end
  end

  describe "trusted_proxy?/1" do
    test "петля, частные сети, link-local — свои; публичные — нет" do
      for address <- [
            {127, 0, 0, 1},
            {10, 1, 2, 3},
            {172, 16, 0, 1},
            {172, 31, 255, 255},
            {192, 168, 1, 1},
            {169, 254, 1, 1},
            {0, 0, 0, 0, 0, 0, 0, 1},
            {0xFD00, 0, 0, 0, 0, 0, 0, 1},
            {0xFE80, 0, 0, 0, 0, 0, 0, 1},
            {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 0x0001}
          ] do
        assert Client.trusted_proxy?(address), inspect(address)
      end

      for address <- [
            {172, 32, 0, 1},
            {172, 15, 0, 1},
            {8, 8, 8, 8},
            {45, 83, 105, 99},
            {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
          ] do
        refute Client.trusted_proxy?(address), inspect(address)
      end
    end
  end

  describe "referrer_host/2" do
    test "только хост: путь, query, порт и www. отрезаны" do
      assert Client.referrer_host("discord.com", "builder.example") == "discord.com"
      assert Client.referrer_host("www.Reddit.com", nil) == "reddit.com"

      assert Client.referrer_host("https://forum.example/t/123?b=abc#x", "builder.example") ==
               "forum.example"

      assert Client.referrer_host("forum.example:8080/path", nil) == "forum.example"
    end

    test "свой хост, пусто, не хост, не строка — nil" do
      assert Client.referrer_host("builder.example", "builder.example") == nil
      assert Client.referrer_host("www.builder.example", "Builder.Example") == nil
      assert Client.referrer_host("", nil) == nil
      assert Client.referrer_host("not a host", nil) == nil
      assert Client.referrer_host("бук.рф", nil) == nil
      assert Client.referrer_host(String.duplicate("a", 254), nil) == nil
      assert Client.referrer_host(%{"host" => "x.com"}, nil) == nil
      assert Client.referrer_host(nil, nil) == nil
    end
  end

  describe "utm/1" do
    test "пять стандартных ключей; b и прочий query не читаются" do
      params = %{
        "b" => "anything",
        "l" => "5",
        "utm_source" => "discord",
        "utm_medium" => " social ",
        "utm_campaign" => "launch",
        "utm_id" => "42",
        "fbclid" => "xyz"
      }

      assert Client.utm(params) == %{
               utm_source: "discord",
               utm_medium: "social",
               utm_campaign: "launch",
               utm_term: nil,
               utm_content: nil
             }
    end

    test "длинное, пустое, с управляющими, не строка — nil" do
      utm =
        Client.utm(%{
          "utm_source" => String.duplicate("x", 65),
          "utm_medium" => "",
          "utm_campaign" => "a\u0000b",
          "utm_term" => ["list"],
          "utm_content" => <<0xFF, 0xFE>>
        })

      assert Enum.all?(utm, fn {_key, value} -> value == nil end)
    end

    test "значение, которое раскодируется как код билда, выбрасывается" do
      # Самый короткий код — пустой билд ванили, 64 байта: ровно в потолок
      # метки (у Сиалы пустой — 65, его отбивает уже длина).
      code = Encoding.encode(Build.new(ruleset_version: "vanilla"))
      assert byte_size(code) <= 64, "контроль: короткий код помещается в потолок метки"
      assert {:ok, _} = Encoding.decode(code)

      assert Client.utm(%{"utm_source" => code}).utm_source == nil

      # Положительный контроль: такая же длина без кода проходит.
      assert Client.utm(%{"utm_source" => "forum"}).utm_source == "forum"
    end
  end

  describe "plan/2 — что считать у подключения" do
    test "первый join свежим переходом — посещение, переход по ссылке, источник" do
      assert Client.plan(%{"_mounts" => 0, "_analytics_ref" => "x.example"}, "builder.example") ==
               %{visit?: true, link_open?: true, referrer_host: "x.example"}

      # Нет параметров (старый клиент) — как первый join без источника.
      assert Client.plan(nil, "builder.example") ==
               %{visit?: true, link_open?: true, referrer_host: nil}
    end

    test "повторный join (обрыв связи, выкат) — ни посещения, ни перехода" do
      for mounts <- [1, 2, 7] do
        assert %{visit?: false, link_open?: false} =
                 Client.plan(%{"_mounts" => mounts, "_analytics_nav" => "navigate"}, nil)
      end
    end

    test "живая навигация — посещение без источника и без перехода по ссылке" do
      assert Client.plan(
               %{
                 "_mounts" => 0,
                 "_live_referer" => "https://builder.example/",
                 "_analytics_ref" => "x.example"
               },
               "builder.example"
             ) == %{visit?: true, link_open?: false, referrer_host: nil}
    end

    test "перезагрузка и «Назад» — посещение, но не переход по ссылке" do
      for nav <- ["reload", "back_forward"] do
        assert %{visit?: true, link_open?: false} =
                 Client.plan(%{"_mounts" => 0, "_analytics_nav" => nav}, "builder.example")
      end
    end

    test "полная загрузка со своего же сайта — посещение без источника, не переход по ссылке" do
      assert Client.plan(
               %{"_mounts" => 0, "_analytics_ref" => "www.builder.example"},
               "builder.example"
             ) == %{visit?: true, link_open?: false, referrer_host: nil}
    end
  end

  test "fresh_navigation?/1 — перезагрузка и «Назад» не свежие" do
    assert Client.fresh_navigation?("navigate")
    assert Client.fresh_navigation?(nil)
    assert Client.fresh_navigation?("prerender")
    refute Client.fresh_navigation?("reload")
    refute Client.fresh_navigation?("back_forward")
  end
end
