defmodule BuildCalculatorWeb.BuilderGameLogImportTest do
  @moduledoc """
  Task 3.111, second pass: the constructor's own paste-a-log dialog.

  `BuildCalculatorWeb.Builder.GameLogImportTest` already pins the parsing and
  assembly by itself; this file pins the other half the task asked for —
  "интерфейс куда лог вставлять" — end to end, through the same two-step
  dialog the text importer already uses (paste, see the report, accept).

  File kept separate from `builder_live_test.exs` for the same reason
  `builder_gear_feats_test.exs` already is: that file is 200+ KB and gets
  edited by neighbouring tasks.
  """

  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  defp fixture(name) do
    "../../fixtures/game_logs/#{name}.log" |> Path.expand(__DIR__) |> File.read!()
  end

  defp paste(view, text) do
    view
    |> form("#game-log-import-form", %{"game_log_import" => %{"text" => text}})
    |> render_submit()
  end

  describe "the dialog" do
    test "is closed until asked for, and shows the beta notice before anything is pasted", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#game-log-import-dialog[hidden]")
      view |> element("#game-log-import-button") |> render_click()
      refute has_element?(view, "#game-log-import-dialog[hidden]")

      # Видна ДО вставки — просьба Dan дословная, «могут быть проблемы с
      # переносом» — а не спрятана за разбором.
      assert has_element?(view, "#game-log-import-beta-notice")
      refute has_element?(view, "#game-log-import-report")

      # Задача 3.174: тоже видна ДО вставки, тем же приёмом, что и бета-
      # уведомление рядом, — иначе игрок узнаёт про кодировку только после
      # того, как пустые строки уже приехали в разборе.
      encoding_notice = render(element(view, "#game-log-import-encoding-notice"))
      assert encoding_notice =~ "windows-1251"

      # Ориентир для игрока, а не требование к точным границам вставки
      # (CLAUDE.md: «вставьте блок целиком, лишнее мы отбросим»).
      hint = render(element(view, "#game-log-import-hint"))
      assert hint =~ "Command detected"
      assert hint =~ "Build sent to"
    end

    test "nothing is applied until a report exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      assert has_element?(view, "#game-log-import-apply[disabled]")

      paste(view, fixture("hnyupius"))

      refute has_element?(view, "#game-log-import-apply[disabled]")

      # Билд-конструктор ничего не тронут, пока не нажали «Открыть».
      assert render(element(view, "#character-level")) =~ "0"
    end

    test "closes on its own close button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      refute has_element?(view, "#game-log-import-dialog[hidden]")

      view |> element("#game-log-import-close") |> render_click()
      assert has_element?(view, "#game-log-import-dialog[hidden]")
    end
  end

  describe "all six real dumps read into a report" do
    for {name, levels, split_ids} <- [
          {"brunna", "40", ["split-wizard", "split-pale_master"]},
          {"hnyupius", "40", ["split-fighter", "split-dwarven_defender", "split-weapon_master"]},
          {"moxie", "41", ["split-monk", "split-cleric", "split-rogue", "split-ranger"]},
          {"babuka", "41", ["split-barbarian", "split-fighter", "split-weapon_master"]},
          {"frah_hall", "41", ["split-sorcerer", "split-wizard", "split-druid", "split-bard"]},
          {"froim", "41", ["split-paladin", "split-ranger", "split-rogue", "split-fighter"]}
        ] do
      test "#{name}.log parses, reports, and applies into the ladder", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/")

        view |> element("#game-log-import-button") |> render_click()
        paste(view, fixture(unquote(name)))

        assert has_element?(view, "#game-log-import-report")
        assert render(element(view, "#game-log-import-read-levels")) =~ unquote(levels)

        # ⚠️ Здесь стояло: «Единственный систематический пробел на каждой
        # из трёх фикстур — отключённое на Сиале ванильное владение простым
        # оружием — назван словами, а не проглочен», и проверялось слово
        # «отключён». Пробел был НАШЕЙ ошибкой, а не дефектом лога, и закрыт
        # 26.08.2026 (задача 3.112): шард фит не выключал. Осталось то, чего
        # лог правда не несёт, — мировоззрение; оно и проверяется, чтобы
        # блок отчёта не превратился в необязательный.
        issues = render(element(view, "#game-log-import-issues"))
        assert issues =~ "мировоззрение"
        refute issues =~ "отключён"

        view |> element("#game-log-import-apply") |> render_click()

        assert has_element?(view, "#game-log-import-dialog[hidden]")
        assert render(element(view, "#character-level")) =~ unquote(levels)

        for split_id <- unquote(split_ids) do
          assert has_element?(view, "##{split_id}")
        end
      end
    end
  end

  describe "hnyupius.log: order survives the trip through the dialog" do
    test "Fighter's 10th level still lands at character level 21 once applied", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture("hnyupius"))
      view |> element("#game-log-import-apply") |> render_click()

      # Открывает уровень 21 (следующий свободный после переноса), где стоит
      # именно Fighter — то, что доказывает: лестница не съехала.
      view |> element("#level-21") |> render_click()
      assert render(element(view, "#character-level")) =~ "40"
      assert has_element?(view, "#split-fighter")
    end
  end

  describe "hnyupius_alignment.log: ALIGNMENT: reaches the build header (task 3.173)" do
    test "the report has nothing left to complain about, and alignment shows in the header", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, fixture("hnyupius_alignment"))

      assert render(element(view, "#game-log-import-read-levels")) =~ "40"

      # The same character as `hnyupius.log` (see that fixture's own
      # `test/fixtures/game_logs/README.md` row) used to leave exactly one
      # issue behind — "мировоззрение" — the one thing the old dump could
      # not carry. This is the first fixture where reading the line closes
      # it: nothing left in `groups` at all, so the report shows the
      # "nothing left to complain about" line instead of the issues block.
      refute has_element?(view, "#game-log-import-issues")
      assert has_element?(view, "#game-log-import-clean")

      view |> element("#game-log-import-apply") |> render_click()

      assert has_element?(view, "#game-log-import-dialog[hidden]")
      assert render(element(view, "#character-level")) =~ "40"

      # The header (`#class-split`, `Labels.race_ru/2 · Labels.alignment_name/1`)
      # is where a player actually SEES the alignment that reached the build —
      # `build.alignment == :lawful_good` alone would not tell us the wiring
      # from `GameLogImport` through `put_build/2` to the template is intact.
      header = render(element(view, "#class-split"))
      assert header =~ "Lawful Good"
      refute header =~ "мировоззрение не выбрано"
    end
  end

  describe "the beta notice's own wording" do
    test "names the feature as beta before the player pastes anything", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      notice = render(element(view, "#game-log-import-beta-notice"))
      assert notice =~ "бета" or notice =~ "Бета"
    end
  end

  describe "garbage input stays honest, never applies a phantom build" do
    test "a paste with nothing recognisable leaves apply disabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-log-import-button") |> render_click()
      paste(view, "просто какой-то текст без структуры лога")

      assert has_element?(view, "#game-log-import-report")
      assert has_element?(view, "#game-log-import-apply[disabled]")
    end
  end
end
