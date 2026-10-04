defmodule BuildCalculatorWeb.NumberInputLimitsLiveTest do
  @moduledoc """
  Число из события или адреса разбирается с пределом длины — задача 4.74
  (`BuildCalculatorWeb.InputLimits.integer/1`).

  `Integer.parse/1` бросает `SystemLimitError` примерно на 1,26 млн значащих
  цифр, а сообщение сокета в 2 МБ несёт их до двух миллионов. Через
  `type=number` браузер такого не пришлёт (число больше double уходит пустым,
  4.41), но событие, собранное руками, — пришлёт: падал процесс экрана
  (`gear_number/1` первым, остальные места — перепись 4.74).

  Каждый тест шлёт огромное число туда, где строку разбирают в число, и
  проверяет две вещи: **значение отброшено** (код билда в `#share-link` не
  сдвинулся) и **экран отвечает на следующее событие** (законный выбор уровня
  виден в `aria-current`). Процесс, упавший на первом событии, на втором уже
  не ответил бы — `render_hook/3` бросил бы выход.

  Положительный контроль того, что число действительно опасно, —
  `InputLimitsTest` («число в 2 млн цифр ломает голый Integer.parse/1»).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Library.Cursor
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.IssueGroups

  @huge String.duplicate("7", 2_000_000)

  setup %{conn: conn} do
    ruleset = Data.ruleset!("siala_41")

    code =
      Build.new(
        ruleset_version: ruleset.version,
        levels: [:fighter, :fighter, :fighter],
        base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}
      )
      |> Encoding.encode()

    {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
    %{view: view, code: code}
  end

  defp share_link(view) do
    view
    |> element("#share-link")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("value")
    |> List.first()
  end

  # Экран жив: законный выбор уровня доходит и виден.
  defp assert_answers(view, level) do
    render_hook(view, "select_level", %{"level" => Integer.to_string(level)})
    assert has_element?(view, ~s(#level-#{level}[aria-current="true"]))
  end

  test "«Вещи»: огромное число в каждом числовом поле отброшено, экран отвечает", %{view: view} do
    view |> element("#gear-toggle") |> render_click()
    before = share_link(view)

    render_hook(view, "gear", %{
      "ability" => %{"str" => @huge},
      "ac" => %{"deflection" => @huge},
      "saves" => @huge,
      "saves_specific" => %{"fort" => @huge}
    })

    render_hook(view, "gear_skill", %{"skill" => %{"discipline" => @huge}})
    render_hook(view, "gear_weapon_attack", %{"attack" => @huge})
    render_hook(view, "gear_off_weapon_attack", %{"attack" => @huge})
    render_hook(view, "gear_named_items", %{"count" => @huge})

    assert share_link(view) == before
    assert_answers(view, 2)

    # Контроль чтения кода: законное число сдвигает ссылку — сравнение не слепо.
    view |> form("#gear-form", %{"saves" => "5"}) |> render_change()
    refute share_link(view) == before
  end

  test "уровень, поинт-бай, навыки, мини-сеты, слоты — огромное число отброшено", %{view: view} do
    assert_answers(view, 1)
    before = share_link(view)

    for {event, params} <- [
          {"select_level", %{"level" => @huge}},
          {"point_buy", %{"ability" => "str", "delta" => @huge}},
          {"skill_rank", %{"skill" => "discipline", "delta" => @huge}},
          {"mini_set_more", %{"index" => @huge}},
          {"mini_set_less", %{"index" => @huge}},
          {"clear_slot", %{"slot" => "class_bonus:fighter:" <> @huge}},
          {"filter_slot", %{"slot" => "class_bonus:fighter:" <> @huge}},
          {"clear_spell", %{"slot" => "circle:1:" <> @huge}},
          {"clear_spell", %{"slot" => "circle:" <> @huge <> ":0"}}
        ] do
      render_hook(view, event, params)
      assert share_link(view) == before, event
    end

    assert has_element?(view, ~s(#level-1[aria-current="true"]))
    assert_answers(view, 3)
  end

  test "не строка там, где ждут число, — тоже не падение", %{view: view} do
    for value <- [5, %{"a" => "1"}, ["1"], nil] do
      render_hook(view, "select_level", %{"level" => value})
      render_hook(view, "point_buy", %{"ability" => "str", "delta" => value})
      render_hook(view, "skill_rank", %{"skill" => "discipline", "delta" => value})
    end

    assert_answers(view, 2)
  end

  # ⚠️ Адрес с таким числом приходит только ПО СОКЕТУ — join или живая навигация
  # несут его в сообщении до 2 МБ. HTTP-запрос его не донесёт: Plug режет строку
  # запроса длиннее 1 000 000 байт (`Plug.Conn.InvalidQueryError`) ещё до
  # маршрутизатора. Поэтому здесь `render_patch/2`, а не `live/2` с таким адресом.
  #
  # ⚠️ Код в адресе — ДРУГОЙ билд: `l` читается, только когда ссылка меняет
  # билд (`load_code/3`); свой же код `handle_params/3` пропускает целиком.
  test "адрес: `l` в 2 млн цифр — уровень по умолчанию, а не падение", %{conn: conn, view: view} do
    ruleset = Data.ruleset!("siala_41")

    other =
      Build.new(
        ruleset_version: ruleset.version,
        levels: [:fighter, :fighter, :fighter, :fighter],
        base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8}
      )
      |> Encoding.encode()

    # Уровень по умолчанию — тот, что ссылка без `l` открывает сама.
    {:ok, plain, _html} = live(conn, ~p"/?b=#{other}")
    default = active_level(plain)
    assert ["level-" <> _] = default

    render_patch(view, "/?b=#{other}&l=#{@huge}")

    assert active_level(view) == default
    assert share_link(view) =~ other
    assert_answers(view, 3)
  end

  defp active_level(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s(#level-ladder [aria-current="true"]))
    |> LazyHTML.attribute("id")
  end

  describe "библиотека" do
    test "`lmin`/`lmax` в 2 млн цифр — фильтр без границы, страница жива", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")
      render_patch(view, "/library?lmin=#{@huge}&lmax=#{@huge}")

      assert has_element?(view, "#library-filters")
      refute has_element?(view, "#library-error")
    end

    test "курсор длиннее настоящего — «битый курсор», не падение", %{conn: conn} do
      cursor = Base.url_encode64("a:" <> @huge <> ":" <> Ecto.UUID.generate(), padding: false)

      assert Cursor.decode(cursor) == :error
      {:ok, view, _html} = live(conn, ~p"/library")
      render_patch(view, "/library?cursor=#{cursor}")
      assert has_element?(view, "#library-error")
    end
  end

  test "раскрытие группы отчёта: огромный номер и карта ничего не меняют" do
    groups = [%{kind: :x, total: 1, items: [], rest: [], hidden: 0, expandable?: false}]

    for at <- [@huge, %{"a" => "1"}, ["0"]] do
      assert IssueGroups.expand_at(groups, at, &inspect/1) == groups
    end
  end
end
