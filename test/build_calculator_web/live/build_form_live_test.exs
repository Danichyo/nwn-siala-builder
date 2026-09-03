defmodule BuildCalculatorWeb.BuildFormLiveTest do
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Accounts
  alias BuildCalculator.Accounts.Scope
  alias BuildCalculator.Library

  describe "сохранение из конструктора" do
    setup :register_and_log_in_user

    # ⚠️ Кнопка «Сохранить» спрятана задачей 3.23 (решение Dan 10.08.2026), но
    # роут жив — именно так и задумано: скрытая кнопка возвращается одной строкой,
    # а закрытый роут ломает существующие ссылки. Поэтому здесь теперь проверяется
    # то, что после скрытия важнее: форма открывается по прямому адресу и берёт
    # код билда из него. Проверка самой кнопки (и того, что она уносит имя
    # из импорта) переехала в `launch_ui_test.exs`, где флаг включается на время
    # теста.
    test "форма сохранения жива по прямому адресу и берёт код из него", %{conn: conn} do
      code = build_code(levels: List.duplicate(:fighter, 5))

      {:ok, builder, _html} = live(conn, ~p"/?b=#{code}")
      refute has_element?(builder, "#save-build")

      {:ok, form, _html} = live(conn, ~p"/builds/new?b=#{code}")

      assert has_element?(form, "#build-form")
      assert has_element?(form, "#build-preview")
    end

    test "сохраняет билд и открывает его страницу", %{conn: conn, scope: scope} do
      code = build_code(levels: List.duplicate(:fighter, 7))

      {:ok, view, _html} = live(conn, ~p"/builds/new?b=#{code}")

      assert has_element?(view, "#build-preview")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#build-form",
          build: %{name: "Мой воин", description: "проба", visibility: "public"}
        )
        |> render_submit()

      assert path =~ ~r"^/builds/"

      {:ok, page} = Library.list_user_builds(scope, scope.user)
      assert [%{name: "Мой воин", visibility: :public, code: ^code}] = page.entries

      {:ok, show, _html} = live(conn, path)
      assert has_element?(show, "#build-view")
      assert has_element?(show, "#saved-description")
      assert has_element?(show, "#edit-saved")
    end

    test "имя из импортированного текста подставляется в форму", %{conn: conn} do
      # Канонический блок называет билд, и терять это имя по дороге к форме —
      # мелкая ложь того же семейства, что и потерянный фит.
      code = build_code(levels: List.duplicate(:fighter, 3))

      {:ok, view, html} = live(conn, ~p"/builds/new?#{[b: code, name: "Ruby Knight"]}")

      assert has_element?(view, "#build-form")
      assert html =~ "Ruby Knight"
    end

    test "битый код не пускает на форму", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/builds/new?b=не-код")
    end

    test "видимость «группа» без группы: человек видит, ПОЧЕМУ не сохранилось", %{
      conn: conn,
      scope: scope
    } do
      # ⚠️ Раньше ошибка ложилась на `group_id`, а поля с таким именем в форме
      # у человека без групп нет вовсе — сообщению было некуда лечь, и нажатие
      # «Сохранить» выглядело как «ничего не произошло».
      code = build_code()

      {:ok, view, _html} = live(conn, ~p"/builds/new?b=#{code}")

      view
      |> form("#build-form", build: %{name: "В группу", visibility: "group"})
      |> render_submit()

      assert has_element?(view, "#no-groups")
      assert has_element?(view, "#build-group-error", "Выберите группу")

      # И билд действительно не сохранён — сообщение не вместо записи, а о ней.
      assert {:ok, page} = Library.list_user_builds(scope, scope.user)
      assert page.entries == []
    end

    test "группа есть, но не выбрана — ошибка тоже видна", %{conn: conn} do
      _group = group_fixture(user_scope_fixture(), %{name: "Чужие"})
      code = build_code()

      {:ok, view, _html} = live(conn, ~p"/builds/new?b=#{code}")

      view
      |> form("#build-form", build: %{name: "В группу", visibility: "group"})
      |> render_submit()

      assert has_element?(view, "#build-group-error", "Выберите группу")
    end

    test "чужая группа: ошибка видна и не выдаёт, существует ли группа", %{
      conn: conn,
      scope: scope
    } do
      _own = group_fixture(scope, %{name: "Клан"})
      foreign = group_fixture(user_scope_fixture(), %{name: "Чужие"})
      missing = Ecto.UUID.generate()
      code = build_code()

      {:ok, view, _html} = live(conn, ~p"/builds/new?b=#{code}")
      view |> form("#build-form", build: %{visibility: "group"}) |> render_change()
      assert has_element?(view, "#build-group")

      # Через `element/2`, а не `form/3`: чужого id нет среди вариантов селекта,
      # и подделать запрос можно только в обход формы — ровно так, как это
      # сделал бы тот, ради кого проверка и написана.
      for id <- [foreign.id, missing] do
        view
        |> element("#build-form")
        |> render_submit(%{
          "build" => %{"name" => "В чужую", "visibility" => "group", "group_id" => id}
        })

        assert has_element?(
                 view,
                 "#build-group-error",
                 "Такой группы нет или вы в ней не состоите"
               )
      end

      assert {:ok, page} = Library.list_user_builds(scope, scope.user)
      assert page.entries == []
    end

    test "видимость «группа» со своей группой сохраняет", %{conn: conn, scope: scope} do
      group = group_fixture(scope, %{name: "Клан"})
      code = build_code()

      {:ok, view, _html} = live(conn, ~p"/builds/new?b=#{code}")

      view |> form("#build-form", build: %{visibility: "group"}) |> render_change()
      assert has_element?(view, "#build-group")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#build-form",
          build: %{name: "Для клана", visibility: "group", group_id: group.id}
        )
        |> render_submit()

      {:ok, show, _html} = live(conn, path)
      assert has_element?(show, "#saved-visibility")
    end
  end

  describe "гость" do
    test "«Сохранить» отправляет на вход и возвращает к тому же билду", %{conn: conn} do
      code = build_code(levels: List.duplicate(:fighter, 4))

      # Обычный GET, а не live-переход: именно плаг маршрутизатора запоминает
      # адрес целиком — вместе с `?b=<код>`.
      conn = get(conn, ~p"/builds/new?b=#{code}")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) =~ "/builds/new?b="

      user = user_fixture() |> set_password()

      conn =
        conn
        |> recycle()
        |> post(~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      # Вернулись ровно туда, откуда ушли: билд не потерян.
      assert redirected_to(conn) =~ "/builds/new?b="

      {:ok, view, _html} = conn |> recycle() |> live(redirected_to(conn))
      assert has_element?(view, "#build-form")
      assert has_element?(view, "#build-preview")
    end

    test "конструктор и просмотр работают без аккаунта", %{conn: conn} do
      code = build_code()

      # ⚠️ Задача 3.23: у гостя нет ни «Сохранить», ни входа — но оба экрана
      # работают целиком, и ровно это здесь и проверяется. Раньше тест
      # утверждал обратное («кнопки на месте»), и после скрытия его утверждение
      # стало неверным, а не бессмысленным: смысл — «гость не заперт» — остался.
      {:ok, builder, _html} = live(conn, ~p"/?b=#{code}")
      refute has_element?(builder, "#save-build")
      refute has_element?(builder, "#log-in")
      assert has_element?(builder, "#builder-cols")
      assert has_element?(builder, "#totals-panel")

      {:ok, viewer, _html} = live(conn, ~p"/b/#{code}")
      assert has_element?(viewer, "#build-view")
      refute has_element?(viewer, "#save-this-build")
      assert has_element?(viewer, "#open-in-builder")
    end
  end

  describe "правка и удаление" do
    setup :register_and_log_in_user

    test "владелец правит имя и видимость", %{conn: conn, scope: scope} do
      build = build_fixture(scope, %{name: "Старое имя"})

      {:ok, view, _html} = live(conn, ~p"/builds/#{build}/edit")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#build-form", build: %{name: "Новое имя", visibility: "public"})
        |> render_submit()

      {:ok, show, _html} = live(conn, path)
      assert has_element?(show, "#view-title", "Новое имя")
    end

    test "чужой билд не правится", %{conn: conn} do
      other = build_fixture(user_scope_fixture(), %{visibility: :public})

      assert {:error, {:live_redirect, %{to: "/library/mine"}}} =
               live(conn, ~p"/builds/#{other}/edit")
    end

    test "владелец удаляет билд", %{conn: conn, scope: scope} do
      build = build_fixture(scope)

      {:ok, view, _html} = live(conn, ~p"/builds/#{build}/edit")

      assert {:error, {:live_redirect, %{to: "/library/mine"}}} =
               view |> element("#build-delete") |> render_click()

      assert {:error, :not_found} = Library.fetch_build(scope, build.id)
    end
  end

  describe "групповой билд у участника" do
    test "участник открывает групповой билд по прямой ссылке", %{conn: conn} do
      owner = user_fixture()
      owner_scope = Scope.for_user(owner)
      group = group_fixture(owner_scope)

      build =
        build_fixture(owner_scope, %{visibility: :group, group_id: group.id, name: "Общий"})

      member = user_fixture()
      {:ok, _} = Accounts.join_group(Scope.for_user(member), group.invite_code)

      {:ok, view, _html} = conn |> log_in_user(member) |> live(~p"/builds/#{build}")

      assert has_element?(view, "#build-view")
      assert has_element?(view, "#view-title", "Общий")
      refute has_element?(view, "#edit-saved")
    end
  end
end
