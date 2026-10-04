defmodule BuildCalculator.RateLimitTest do
  @moduledoc """
  Счётчики «не больше N за окно» в памяти (задача 4.75). Каждый тест берёт
  ключи с `make_ref/0` — таблица общая на всё приложение, и чужой тест
  не досчитывает в наш ключ; поэтому `async: true`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.RateLimit

  @far 4_000_000_000

  test "до потолка — :ok, дальше — :limited, и счёт растёт" do
    key = {:test, make_ref()}

    assert for(_ <- 1..3, do: RateLimit.hit(key, 3, @far)) == [ok: 1, ok: 2, ok: 3]
    assert RateLimit.hit(key, 3, @far) == {:limited, 4}
    assert RateLimit.hit(key, 3, @far) == {:limited, 5}

    # Чужой ключ — свой счёт.
    assert RateLimit.hit({:test, make_ref()}, 3, @far) == {:ok, 1}
  end

  test "окно выровнено по эпохе: сутки — от полуночи UTC" do
    midnight = ~U[2026-10-04 00:00:00Z] |> DateTime.to_unix()

    assert RateLimit.window(midnight, 86_400) == {div(midnight, 86_400), midnight + 86_400}
    assert RateLimit.window(midnight + 86_399, 86_400) == RateLimit.window(midnight, 86_400)
    refute RateLimit.window(midnight + 86_400, 86_400) == RateLimit.window(midnight, 86_400)
    assert RateLimit.window(7_200, 3_600) == {2, 10_800}
  end

  test "кончившиеся окна снимаются, живые остаются" do
    gone = {:test, make_ref()}
    alive = {:test, make_ref()}
    RateLimit.hit(gone, 5, 1_000)
    RateLimit.hit(alive, 5, @far)

    RateLimit.purge(1_000)

    # Снятый ключ считается с нуля, живой — продолжает.
    assert RateLimit.hit(gone, 5, 2_000) == {:ok, 1}
    assert RateLimit.hit(alive, 5, @far) == {:ok, 2}
  end

  test "адрес: IPv4 целиком, IPv6 — сеть /64" do
    assert RateLimit.address({203, 0, 113, 7}) == {:v4, {203, 0, 113, 7}}

    assert RateLimit.address({0x2001, 0xDB8, 1, 2, 3, 4, 5, 6}) ==
             RateLimit.address({0x2001, 0xDB8, 1, 2, 9, 9, 9, 9})

    refute RateLimit.address({0x2001, 0xDB8, 1, 2, 0, 0, 0, 1}) ==
             RateLimit.address({0x2001, 0xDB8, 1, 3, 0, 0, 0, 1})

    assert RateLimit.address(nil) == nil
  end
end
