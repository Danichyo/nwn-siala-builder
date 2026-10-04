defmodule BuildCalculatorWeb.SiteHeaderTest do
  @moduledoc """
  Блок аккаунта в шапке — единственная строка интерфейса, длину которой задаёт
  не дизайн, а пользователь: своя почта.

  ⚠️ **Раскладку этим не проверить**, и делать вид, что проверено, нельзя:
  `Phoenix.LiveViewTest` не применяет CSS (AGENT_QUEUE.md, «Зелёные тесты ≠
  работающая фича»). Само обрезание длинной почты замерено в браузере — Chromium,
  390/360/320px, страницы `/` и `/library`, вошедший пользователь: до правки
  почта из 56 символов уезжала левым краем за ноль (−82px на 390px), причём
  `document.scrollWidth` равнялся `innerWidth`, то есть доскроллить до неё было
  нельзя. Числа и довод — в комментарии у `.who` в `assets/css/app.css`.

  Здесь держится то, что тестом держится: **`#account-email` существует именно
  под этим id на обоих видах шапки**. Многоточие в CSS повешено на этот id, и
  переименование молча вернуло бы обрезание за краем экрана — а увидел бы его
  только тот, у кого длинный адрес.

  Двух видов шапки действительно два, и это не перестраховка: `/library`
  рисует `Layouts.site_header/1`, а конструктор и экран просмотра — свою шапку
  с `Layouts.account/1` внутри (`builder_live.html.heex`,
  `build_view_live.html.heex`).
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BuildCalculator.LibraryFixtures

  describe "вошедший пользователь" do
    setup :register_and_log_in_user

    test "почта висит на #account-email в шапке библиотеки", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")

      assert has_element?(view, "#account")
      assert has_element?(view, "#account-email")
      assert has_element?(view, "#log-out")
    end

    test "и в собственной шапке конструктора", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#account-email")
    end

    test "и в собственной шапке экрана просмотра", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/#{build_code()}")

      assert has_element?(view, "#account-email")
    end
  end

  # Положительный контроль к трём проверкам выше: без аккаунта почты в шапке нет
  # вовсе, значит `has_element?` там ловит именно её, а не любой элемент шапки.
  #
  # ⚠️ Раньше здесь стояло «вместо почты — вход и регистрация». Задача 3.23
  # спрятала и то и другое (решение Dan 10.08.2026: для запуска нужны только
  # конструктор и просмотр), поэтому у гостя в шапке не остаётся блока аккаунта
  # вовсе. Проверку не выбросили: она переехала в положительную сторону — блок
  # есть только у вошедшего. Скрытость сама держится в `launch_ui_test.exs`,
  # там же и её положительный контроль флагом.
  describe "без аккаунта" do
    test "блока аккаунта в шапке нет вовсе", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")

      refute has_element?(view, "#account")
      refute has_element?(view, "#account-email")
      refute has_element?(view, "#log-in")
      refute has_element?(view, "#register")

      # А шапка на месте — значит `refute` выше ловит именно скрытие, а не
      # разъехавшийся селектор на снесённой шапке.
      assert has_element?(view, "#site-header")
      assert has_element?(view, "#brand-home")
      assert has_element?(view, "#theme-toggle")
    end
  end
end
