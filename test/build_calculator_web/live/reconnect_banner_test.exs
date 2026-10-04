defmodule BuildCalculatorWeb.ReconnectBannerTest do
  @moduledoc """
  Плашки состояния соединения (AGENT_QUEUE §3.32).

  Их показывает не сервер, а клиент — по классам `phx-client-error` /
  `phx-server-error`, которые LiveView вешает на `<html>` при обрыве. Поэтому
  здесь проверяется не «плашка видна», а то, что она **есть в разметке и
  подписана по-русски**: до 15.08.2026 обе печатались по-английски
  («We can't find the internet»), потому что домена `default` в переводах
  не было вовсе.

  ⚠️ Отдельным тестом, а не строкой в `gettext_test`, потому что вопрос другой:
  тот сторожит словарь, а этот — что баннеры вообще дошли до страницы. Убрать
  их из `Layouts.flash_group/1` можно, не тронув ни одного `.po`.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BuildCalculator.LibraryFixtures

  describe "плашка обрыва связи" do
    test "есть на конструкторе и подписана по-русски", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#client-error", "Нет связи с сервером")
      assert has_element?(view, "#client-error", "Пытаемся переподключиться")
    end

    test "есть на экране просмотра — по ссылке приходят чужие люди", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/#{build_code()}")

      assert has_element?(view, "#client-error", "Нет связи с сервером")
    end
  end

  describe "плашка серверной ошибки" do
    test "есть и подписана по-русски", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#server-error", "Что-то пошло не так")
      assert has_element?(view, "#server-error", "Пытаемся переподключиться")
    end
  end
end
