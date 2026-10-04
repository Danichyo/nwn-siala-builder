defmodule BuildCalculatorWeb.BuilderGameLogGearGroupsTest do
  @moduledoc """
  Задача 4.40, пункты 4 и 5 в окне лога `.билд` (видно Сиале).

  (4) Списки экипировки «Не наше» и «Не сложить» рисовали каждую строку: на
  вставке 64 КБ свойств — 3023 и 2992 `<p>` (`tmp/4.40a/p4_count_test.exs`,
  `HEAD` b241cd4). Теперь оба — тем же `IssueGroups`, что замечания окна
  (задача 4.35): по причине, в группе первые 150, «показать все» — до тысячи.

  (5) Реплики чата после лога `.билд+` не попадают в «экипировку: строка не по
  форме», а подсказка окна говорит, что у `.билд+` экипировка идёт после
  «Build sent to!».
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculatorWeb.Builder.IssueGroups

  @plus Path.expand("../../fixtures/game_logs_plus/hnyupius.log", __DIR__)

  defp paste(view, text) do
    view |> element("#game-log-import-button") |> render_click()

    view
    |> form("#game-log-import-form", %{"game_log_import" => %{"text" => text}})
    |> render_submit()
  end

  # Свойства последнего предмета лога (`[BELT]`): `Cast Spell` — механика, которую
  # мы не считаем («Не наше»), `Frobnicate` — имя свойства, которого мы не знаем
  # («Не сложить»). По `count` каждого.
  defp with_properties(
         count,
         unit \\ "  [5] Cast Spell (Darkfire (5)) 9\n  [6] Frobnicate Widget 3\n"
       ),
       do: File.read!(@plus) <> String.duplicate(unit, count)

  defp count(view, selector),
    do: view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  describe "(4) «Не наше» и «Не сложить» — группами IssueGroups" do
    test "настоящий лог рисуется целиком, без «…и ещё»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      paste(view, File.read!(@plus))

      # Положительный контроль: оба списка есть и не пусты.
      assert count(view, "#game-log-import-gear-not-ours-groups p.feat-why") == 34
      assert count(view, "#game-log-import-gear-unresolved-groups p.feat-why") == 1
      refute has_element?(view, "#game-log-import-gear-not-ours .import-more")
      refute has_element?(view, "#game-log-import-gear-unresolved .import-more")

      # Id строки «Не сложить» — прежний, по месту в списке ядра.
      assert has_element?(view, "#game-log-import-gear-unresolved-item-1")
    end

    test "длинный список — 150 строк в группе, число всех в заголовке, «показать все»", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      paste(view, with_properties(400))

      shown = IssueGroups.shown()
      not_ours = "#game-log-import-gear-not-ours-groups"
      unresolved = "#game-log-import-gear-unresolved-groups"

      # Группа причины «механика, которую мы не считаем» — первая у Хнюпиуса:
      # 33 его строки (34-я — «решением не считаем», своя группа) и 400.
      assert count(view, "#{not_ours}-group-0 p.feat-why") == shown
      assert render(element(view, "#{not_ours}-group-0 .import-count")) =~ "433"
      assert has_element?(view, "#{not_ours}-group-0-all")

      # «Не сложить»: первая группа у Хнюпиуса — фит не найден (Sneak Attack),
      # вторая — имя свойства не распознано, 400.
      assert count(view, "#{unresolved}-group-0 p.feat-why") == 1
      assert count(view, "#{unresolved}-group-1 p.feat-why") == shown
      assert render(element(view, "#{unresolved}-group-1 .import-count")) =~ "400"

      view |> element("#{not_ours}-group-0-all") |> render_click()
      assert count(view, "#{not_ours}-group-0 p.feat-why") == 433
      refute has_element?(view, "#{not_ours}-group-0-more")

      # Раскрытие одного списка другой не трогает.
      assert count(view, "#{unresolved}-group-1 p.feat-why") == shown

      view |> element("#{unresolved}-group-1-all") |> render_click()
      assert count(view, "#{unresolved}-group-1 p.feat-why") == 400
      assert has_element?(view, "#game-log-import-gear-unresolved-item-401")
    end

    # Самые короткие строки обоих вёдер: до потолка вставки (64 000 байт) их
    # по три тысячи. До 4.40 — 3023 и 2992 `<p>`.
    test "вставка 64 КБ свойств — сотни строк, а не тысячи", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      paste(view, with_properties(3600, "[1] Keen\n[2] Zq 1\n"))

      # Обе группы длиннее тысячи — «показать все» не предлагается.
      assert count(view, "#game-log-import-gear-not-ours p") < 2 * IssueGroups.shown()
      assert count(view, "#game-log-import-gear-unresolved p") < 2 * IssueGroups.shown()
      refute has_element?(view, "#game-log-import-gear-not-ours-groups-group-0-all")
      assert has_element?(view, "#game-log-import-gear-not-ours-groups-group-0-more")
    end

    test "«показать все» без отчёта и с чужим номером группы ничего не ломает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "game_log_import_not_ours_expand", %{"group" => "0"})
      render_hook(view, "game_log_import_unresolved_expand", %{"group" => "x"})
      refute has_element?(view, "#game-log-import-report")

      paste(view, File.read!(@plus))
      render_hook(view, "game_log_import_unresolved_expand", %{"group" => "7"})
      render_hook(view, "game_log_import_not_ours_expand", %{})
      assert count(view, "#game-log-import-gear-not-ours-groups p.feat-why") == 34
    end
  end

  describe "(5) чат после лога .билд+" do
    test "реплики после раздела экипировки — не замечания экипировки", %{conn: conn} do
      chat =
        "[CHAT WINDOW TEXT] [Fri Sep 18 00:18:30] [Talk] Хнюпиус: вот он (40 уровней)\n" <>
          "[CHAT WINDOW TEXT] [Fri Sep 18 00:18:41] Build sent to! Хнюпиус\n"

      {:ok, view, _html} = live(conn, ~p"/")
      paste(view, File.read!(@plus) <> chat)

      refute has_element?(view, "#game-log-import-issues")
      assert has_element?(view, "#game-log-import-clean")
      assert has_element?(view, "#game-log-import-gear")
    end

    test "подсказка: у .билд+ экипировка — после «Build sent to!»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      hint = render(element(view, "#game-log-import-hint"))

      assert hint =~ "Build sent to"
      assert hint =~ ".билд+ — до конца списка экипировки после неё"
    end
  end
end
