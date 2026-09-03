defmodule BuildCalculatorWeb.ShortLinkTest do
  @moduledoc """
  Короткая ссылка от кнопки в конструкторе до открытия по адресу.

  Утверждения — через `element/2` и `has_element?/2` по DOM-id, а не по сырому
  HTML (AGENTS.md, CLAUDE.md §7).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Encoding
  alias BuildCalculator.Repo
  alias BuildCalculator.Rules.Build
  alias BuildCalculator.ShortLinks.ShortLink

  defp dwarf_defender do
    Build.new(
      ruleset_version: "siala_41",
      race: :dwarf,
      alignment: :lawful_good,
      base_abilities: %{str: 16, dex: 12, con: 16, int: 12, wis: 10, cha: 8},
      levels: List.duplicate(:fighter, 10) ++ List.duplicate(:dwarven_defender, 11),
      feats: %{1 => %{general: :toughness}}
    )
  end

  describe "конструктор" do
    test "длинная ссылка есть сразу, короткая — по кнопке", %{conn: conn} do
      code = Encoding.encode(dwarf_defender())
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      # Длинная — на месте и первая, ещё до всякой короткой.
      assert has_element?(view, "#share-link")
      assert has_element?(view, "#copy-link")
      assert has_element?(view, "#short-link-button")
      refute has_element?(view, "#short-link")

      view |> element("#short-link-button") |> render_click()

      link = Repo.one!(ShortLink)

      # Значение поля — короткий адрес с выданным ключом. Проверяется
      # селектором по атрибуту, а не сравнением с куском разметки.
      assert has_element?(view, "#short-link[value$='/s/#{link.key}']")
      assert has_element?(view, "#copy-short-link")

      # Длинная никуда не делась и осталась выше — это и есть главное
      # требование задачи: короткая дополняет, а не заменяет.
      assert has_element?(view, "#share-link[value$='/b/#{code}']")

      # Кнопки больше нет: ссылка на ЭТОТ билд уже выдана.
      refute has_element?(view, "#short-link-button")
    end

    test "оговорка напечатана строкой, а не подсказкой при наведении", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(dwarf_defender())}")

      refute has_element?(view, "#short-link-note")
      view |> element("#short-link-button") |> render_click()

      # ⚠️ На мобильном наведения не существует (баг 1.11), поэтому оговорка
      # обязана быть отдельным элементом, а не атрибутом `title` на чём-то.
      assert has_element?(view, "#short-link-note")
      refute has_element?(view, "#short-link[title]")
      refute has_element?(view, "#copy-short-link[title]")
    end

    test "повторное нажатие на том же билде не заводит вторую запись", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(dwarf_defender())}")

      view |> element("#short-link-button") |> render_click()
      first = Repo.one!(ShortLink)

      # Кнопки на экране уже нет, но устаревший DOM может прислать событие
      # ещё раз — запись от этого не удваивается.
      render_click(view, "short_link", %{})

      assert Repo.one!(ShortLink).key == first.key
    end

    test "правка билда убирает короткую ссылку, возврат к прежнему — возвращает",
         %{conn: conn} do
      before = Encoding.encode(dwarf_defender())
      {:ok, view, _html} = live(conn, ~p"/?b=#{before}")

      view |> element("#short-link-button") |> render_click()
      key = Repo.one!(ShortLink).key
      assert has_element?(view, "#short-link[value$='/s/#{key}']")

      # Другой билд — прежняя короткая ссылка его не описывает, и её нет.
      other = Encoding.encode(%{dwarf_defender() | race: :elf})
      render_patch(view, ~p"/?b=#{other}")
      refute has_element?(view, "#short-link")
      assert has_element?(view, "#short-link-button")

      # Вернулись к прежнему билду — ключ нашёлся в памяти соединения, новой
      # записи в базе не появилось.
      render_patch(view, ~p"/?b=#{before}")
      assert has_element?(view, "#short-link[value$='/s/#{key}']")
      assert Repo.aggregate(ShortLink, :count) == 1
    end

    test "у одного соединения есть предел, и отказ не теряет длинную ссылку",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Разные билды: сила 8..80 даёт заведомо больше кодов, чем предел.
      refused =
        Enum.reduce_while(8..80, false, fn str, _acc ->
          build = %{
            dwarf_defender()
            | base_abilities: %{str: str, dex: 12, con: 16, int: 12, wis: 10, cha: 8}
          }

          render_patch(view, ~p"/?b=#{Encoding.encode(build)}")
          html = view |> element("#short-link-button") |> render_click()

          if html =~ "коротких ссылок сделано слишком много",
            do: {:halt, true},
            else: {:cont, false}
        end)

      assert refused, "предел на число коротких ссылок за соединение не сработал"

      # Отказ ничего не теряет: длинная ссылка на экране и работает.
      assert has_element?(view, "#share-link")

      # Положительный контроль: до предела ссылки выдавались, а не отказывались
      # с самого начала.
      assert Repo.aggregate(ShortLink, :count) > 1
    end
  end

  describe "адрес /s/:key" do
    # ⚠️ Обе половины парного правила — одним тестом. По отдельности «короткая
    # открывается» и «длинная по-прежнему открывается» зеленеют и при сломанной
    # модели: первую можно удовлетворить, потеряв вторую, а вторая жива и без
    # короткой вовсе.
    test "короткая ведёт на тот же билд, что и длинная", %{conn: conn} do
      code = Encoding.encode(dwarf_defender())
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      view |> element("#short-link-button") |> render_click()
      key = Repo.one!(ShortLink).key

      # Короткая: разворачивается в длинную, то есть получатель оказывается
      # на самодостаточном адресе.
      short = get(conn, ~p"/s/#{key}")
      assert redirected_to(short) == ~p"/b/#{code}"

      {:ok, from_short, _html} = live(conn, redirected_to(short))
      assert has_element?(from_short, "#build-view")
      assert has_element?(from_short, "#view-title")

      # Длинная: та же страница, тот же билд, без всякой короткой ссылки.
      {:ok, from_long, _html} = live(conn, ~p"/b/#{code}")
      assert has_element?(from_long, "#build-view")
      assert has_element?(from_long, "#view-title")

      assert render(element(from_short, "#view-title")) ==
               render(element(from_long, "#view-title"))
    end

    test "неизвестный ключ ведёт на главную с сообщением, а не в 500", %{conn: conn} do
      conn = get(conn, ~p"/s/000000")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "короткой ссылки"
    end

    test "мусор вместо ключа тоже не роняет приложение", %{conn: conn} do
      for key <- ["не-ключ", String.duplicate("a", 300), "!!!"] do
        assert redirected_to(get(conn, "/s/#{URI.encode(key)}")) == ~p"/"
      end

      # Положительный контроль: настоящий ключ ведёт на билд, а не на главную.
      code = Encoding.encode(dwarf_defender())
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      view |> element("#short-link-button") |> render_click()

      assert redirected_to(get(conn, ~p"/s/#{Repo.one!(ShortLink).key}")) == ~p"/b/#{code}"
    end
  end
end
