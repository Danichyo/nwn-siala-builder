defmodule BuildCalculatorWeb.GroupLiveTest do
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures

  alias BuildCalculator.Accounts
  alias BuildCalculator.Accounts.Scope

  describe "список групп" do
    setup :register_and_log_in_user

    test "создание группы уводит на её страницу", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/groups")

      assert has_element?(view, "#groups-empty")

      {:error, {:live_redirect, %{to: path}}} =
        view |> form("#create-group-form", group: %{name: "Клан"}) |> render_submit()

      assert path =~ ~r"^/groups/"

      {:ok, show, _html} = live(conn, path)
      assert has_element?(show, "#group-name", "Клан")
      assert has_element?(show, "#invite-code")
      assert has_element?(show, "#rotate-code")
    end

    test "вступление по коду", %{conn: conn} do
      group = group_fixture(user_scope_fixture(), %{name: "Чужой клан"})

      {:ok, view, _html} = live(conn, ~p"/groups")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#join-group-form", join: %{invite_code: group.invite_code})
        |> render_submit()

      assert path == "/groups/#{group.id}"

      {:ok, show, _html} = live(conn, path)
      assert has_element?(show, "#group-name", "Чужой клан")

      # Участник, а не владелец: код менять нельзя, а выйти можно.
      refute has_element?(show, "#rotate-code")
      refute has_element?(show, "#delete-group")
      assert has_element?(show, "#leave-group")
    end

    # Роль приезжает вместе с группой (`Group.caller_role`) — раньше экран
    # добирал её отдельным запросом на каждую строку. Здесь проверяется, что
    # после переезда она не потерялась и что она разная у владельца и участника.
    test "в списке у каждой группы своя роль", %{conn: conn, user: user} do
      scope = Scope.for_user(user)
      own = group_fixture(scope, %{name: "Моя"})
      joined = group_fixture(user_scope_fixture(), %{name: "Чужая"})
      {:ok, _} = Accounts.join_group(scope, joined.invite_code)

      {:ok, view, _html} = live(conn, ~p"/groups")

      assert has_element?(view, "#group-#{own.id}", "владелец")
      assert has_element?(view, "#group-#{joined.id}", "участник")
      refute has_element?(view, "#group-#{joined.id}", "владелец")
    end

    test "неверный код — сообщение, а не падение", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/groups")

      html =
        view |> form("#join-group-form", join: %{invite_code: "нет-такого"}) |> render_submit()

      assert html =~ "код"
    end
  end

  describe "страница группы" do
    setup :register_and_log_in_user

    test "чужая группа не открывается по id", %{conn: conn} do
      group = group_fixture(user_scope_fixture())

      assert {:error, {:live_redirect, %{to: "/groups"}}} = live(conn, ~p"/groups/#{group}")
    end

    test "участник выходит из группы", %{conn: conn, user: user} do
      group = group_fixture(user_scope_fixture())
      {:ok, _} = Accounts.join_group(Scope.for_user(user), group.invite_code)

      {:ok, view, _html} = live(conn, ~p"/groups/#{group}")

      assert {:error, {:live_redirect, %{to: "/groups"}}} =
               view |> element("#leave-group") |> render_click()

      refute Accounts.group_member?(user, group)
    end

    test "последний владелец выйти не может", %{conn: conn, scope: scope} do
      group = group_fixture(scope)

      {:ok, view, _html} = live(conn, ~p"/groups/#{group}")

      html = view |> element("#leave-group") |> render_click()
      assert html =~ "владелец"
    end

    test "владелец убирает участника и меняет код", %{conn: conn, scope: scope} do
      group = group_fixture(scope)
      member = user_fixture()
      {:ok, _} = Accounts.join_group(Scope.for_user(member), group.invite_code)

      {:ok, view, _html} = live(conn, ~p"/groups/#{group}")
      assert has_element?(view, "#member-#{member.id}")

      view |> element("#remove-#{member.id}") |> render_click()
      refute has_element?(view, "#member-#{member.id}")

      old_code = group.invite_code
      view |> element("#rotate-code") |> render_click()
      refute has_element?(view, "#invite-code", old_code)
    end

    test "владелец удаляет группу, её билды становятся личными", %{conn: conn, scope: scope} do
      group = group_fixture(scope)

      build =
        BuildCalculator.LibraryFixtures.build_fixture(scope, %{
          visibility: :group,
          group_id: group.id
        })

      {:ok, view, _html} = live(conn, ~p"/groups/#{group}")

      assert {:error, {:live_redirect, %{to: "/groups"}}} =
               view |> element("#delete-group") |> render_click()

      {:ok, reread} = BuildCalculator.Library.fetch_build(scope, build.id)
      assert reread.visibility == :private
    end
  end
end
