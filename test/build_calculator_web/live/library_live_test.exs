defmodule BuildCalculatorWeb.LibraryLiveTest do
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Accounts.Scope

  defp card(build), do: "#build-#{build.id}"

  describe "публичная лента" do
    test "показывает публичный билд и не показывает чужой личный", %{conn: conn} do
      author = user_scope_fixture()
      public = build_fixture(author, %{name: "Открытый", visibility: :public})
      private = build_fixture(author, %{name: "Личный", visibility: :private})

      {:ok, view, _html} = live(conn, ~p"/library")

      assert has_element?(view, card(public))
      refute has_element?(view, card(private))
    end

    test "чужой личный билд не открывается и по прямой ссылке", %{conn: conn} do
      author = user_scope_fixture()
      private = build_fixture(author, %{name: "Личный", visibility: :private})

      stranger = user_fixture()
      conn = log_in_user(conn, stranger)

      {:ok, view, _html} = live(conn, ~p"/builds/#{private}")

      assert has_element?(view, "#view-error")
      refute has_element?(view, "#build-view")
    end

    test "владелец видит свой личный билд", %{conn: conn} do
      user = user_fixture()
      scope = Scope.for_user(user)
      private = build_fixture(scope, %{name: "Личный", visibility: :private})

      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/builds/#{private}")

      assert has_element?(view, "#build-view")
      assert has_element?(view, "#edit-saved")
    end
  end

  describe "мои билды" do
    setup :register_and_log_in_user

    test "секция показывает только свои, любой видимости", %{conn: conn, scope: scope} do
      mine = build_fixture(scope, %{name: "Мой", visibility: :private})
      someone_else = build_fixture(user_scope_fixture(), %{name: "Чужой", visibility: :public})

      {:ok, view, _html} = live(conn, ~p"/library/mine")

      assert has_element?(view, card(mine))
      refute has_element?(view, card(someone_else))
    end
  end

  describe "лента группы" do
    test "участник видит групповой билд, посторонний — нет", %{conn: conn} do
      owner = user_fixture()
      owner_scope = Scope.for_user(owner)
      group = group_fixture(owner_scope, %{name: "Клан"})

      shared =
        build_fixture(owner_scope, %{
          name: "Групповой",
          visibility: :group,
          group_id: group.id
        })

      member = user_fixture()
      {:ok, _} = BuildCalculator.Accounts.join_group(Scope.for_user(member), group.invite_code)

      {:ok, view, _html} = conn |> log_in_user(member) |> live(~p"/library/group/#{group}")
      assert has_element?(view, card(shared))

      # Посторонний не получает даже страницу группы: членство лежит в `where`
      # запроса контекста, а не в проверке после выборки.
      outsider = user_fixture()

      assert {:error, {:live_redirect, %{to: "/groups"}}} =
               build_conn() |> log_in_user(outsider) |> live(~p"/library/group/#{group}")

      # И групповой билд не виден ему ни в ленте, ни по ссылке.
      {:ok, outsider_view, _html} = build_conn() |> log_in_user(outsider) |> live(~p"/library")
      refute has_element?(outsider_view, card(shared))

      {:ok, direct, _html} = build_conn() |> log_in_user(outsider) |> live(~p"/builds/#{shared}")
      assert has_element?(direct, "#view-error")
    end
  end

  describe "фильтры" do
    test "поиск по классу с диапазоном уровней", %{conn: conn} do
      author = user_scope_fixture()

      big =
        build_fixture(author, %{
          name: "Воин надолго",
          visibility: :public,
          code: build_code(levels: List.duplicate(:fighter, 12))
        })

      dip =
        build_fixture(author, %{
          name: "Воин на два уровня",
          visibility: :public,
          code: build_code(levels: List.duplicate(:fighter, 2) ++ List.duplicate(:rogue, 8))
        })

      {:ok, view, _html} = live(conn, ~p"/library")
      assert has_element?(view, card(big))
      assert has_element?(view, card(dip))

      view
      |> form("#library-filters", %{"class" => "fighter", "lmin" => "10", "lmax" => "20"})
      |> render_change()

      assert_patch(view)
      assert has_element?(view, card(big))
      refute has_element?(view, card(dip))

      # Тот же диапазон, но по другому классу — теперь проходит только дип.
      view
      |> form("#library-filters", %{"class" => "rogue", "lmin" => "5", "lmax" => "9"})
      |> render_change()

      assert_patch(view)
      refute has_element?(view, card(big))
      assert has_element?(view, card(dip))
    end

    test "поиск по имени и сброс фильтров", %{conn: conn} do
      author = user_scope_fixture()
      one = build_fixture(author, %{name: "Хитрый вор", visibility: :public})
      two = build_fixture(author, %{name: "Прямой воин", visibility: :public})

      {:ok, view, _html} = live(conn, ~p"/library")

      view |> form("#library-filters", %{"q" => "вор"}) |> render_change()
      assert_patch(view)
      assert has_element?(view, card(one))
      refute has_element?(view, card(two))

      view |> element("#clear-filters") |> render_click()
      assert_patch(view)
      assert has_element?(view, card(one))
      assert has_element?(view, card(two))
    end

    test "фильтр по расе", %{conn: conn} do
      author = user_scope_fixture()
      dwarf = build_fixture(author, %{visibility: :public, code: build_code(race: :dwarf)})
      elf = build_fixture(author, %{visibility: :public, code: build_code(race: :elf)})

      {:ok, view, _html} = live(conn, ~p"/library")

      view |> form("#library-filters", %{"race" => "dwarf"}) |> render_change()
      assert_patch(view)

      assert has_element?(view, card(dwarf))
      refute has_element?(view, card(elf))
    end
  end

  describe "постраничная выдача" do
    test "курсор переносит через границу страницы, не теряя и не повторяя", %{conn: conn} do
      author = user_scope_fixture()
      now = DateTime.utc_now()

      # 21 билд при странице в 20: граница проходит ровно между 20-м и 21-м.
      builds =
        for i <- 1..21 do
          author
          |> build_fixture(%{name: "Билд #{i}", visibility: :public})
          |> touch(DateTime.add(now, -i, :minute))
        end

      [first | _] = builds
      last = List.last(builds)

      {:ok, view, _html} = live(conn, ~p"/library")

      assert has_element?(view, card(first))
      refute has_element?(view, card(last))
      assert has_element?(view, "#next-page")

      view |> element("#next-page") |> render_click()
      assert_patch(view)

      # На второй странице ровно то, что не влезло, и ничего из первой.
      assert has_element?(view, card(last))
      refute has_element?(view, card(first))
      refute has_element?(view, "#next-page")
      assert has_element?(view, "#first-page")

      view |> element("#first-page") |> render_click()
      assert_patch(view)
      assert has_element?(view, card(first))
    end

    test "битый курсор не роняет страницу", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library?cursor=не-курсор")

      assert has_element?(view, "#library-error")
    end

    test "«Назад» возвращает ровно на предыдущую страницу", %{conn: conn} do
      %{first: first, last: last} = feed_of(21)

      {:ok, view, _html} = live(conn, ~p"/library")

      # На первой странице возвращаться некуда.
      refute has_element?(view, "#prev-page")
      refute has_element?(view, "#first-page")

      view |> element("#next-page") |> render_click()
      assert_patch(view)
      assert has_element?(view, "#prev-page")
      refute has_element?(view, "#next-page")

      view |> element("#prev-page") |> render_click()
      assert_patch(view)

      assert has_element?(view, card(first))
      refute has_element?(view, card(last))

      # Вернулись именно в начало ленты, а не «куда-то выше».
      refute has_element?(view, "#prev-page")
      assert has_element?(view, "#next-page")
    end

    test "страница со стрелками восстанавливается по ссылке и по F5", %{conn: conn} do
      %{first: first, last: last} = feed_of(21)

      {:ok, view, _html} = live(conn, ~p"/library")
      view |> element("#next-page") |> render_click()
      path = assert_patch(view)

      # Курсор лежит в адресе, а не в памяти сокета: тот же адрес открывается
      # с нуля и показывает то же самое, со стрелкой назад на месте.
      {:ok, reopened, _html} = live(conn, path)

      assert has_element?(reopened, card(last))
      refute has_element?(reopened, card(first))
      assert has_element?(reopened, "#prev-page")

      reopened |> element("#prev-page") |> render_click()
      assert_patch(reopened)
      assert has_element?(reopened, card(first))
    end

    test "лента в одну страницу не показывает ни одной стрелки", %{conn: conn} do
      author = user_scope_fixture()
      for _ <- 1..3, do: build_fixture(author, %{visibility: :public})

      {:ok, view, _html} = live(conn, ~p"/library")

      refute has_element?(view, "#next-page")
      refute has_element?(view, "#prev-page")
      refute has_element?(view, "#first-page")
    end

    test "фильтр переживает переход вперёд и назад", %{conn: conn} do
      author = user_scope_fixture()
      now = DateTime.utc_now()

      builds =
        for i <- 1..21 do
          author
          |> build_fixture(%{name: "Хитрый #{i}", visibility: :public})
          |> touch(DateTime.add(now, -i, :minute))
        end

      decoy = build_fixture(author, %{name: "Прямой воин", visibility: :public})
      [first | _] = builds
      last = List.last(builds)

      {:ok, view, _html} = live(conn, ~p"/library")
      view |> form("#library-filters", %{"q" => "Хитрый"}) |> render_change()
      assert_patch(view)
      refute has_element?(view, card(decoy))

      view |> element("#next-page") |> render_click()
      path = assert_patch(view)

      # Курсор и фильтр — одно состояние: без фильтра в адресе вторая страница
      # показала бы отфильтрованное место в неотфильтрованной ленте.
      assert path =~ "q=" and path =~ "cursor="
      assert has_element?(view, card(last))
      refute has_element?(view, card(decoy))

      view |> element("#prev-page") |> render_click()
      assert_patch(view)

      assert has_element?(view, card(first))
      refute has_element?(view, card(decoy))
    end
  end

  # 21 публичный билд при странице в 20 — граница ровно между 20-м и 21-м.
  defp feed_of(count) do
    author = user_scope_fixture()
    now = DateTime.utc_now()

    builds =
      for i <- 1..count do
        author
        |> build_fixture(%{name: "Билд #{i}", visibility: :public})
        |> touch(DateTime.add(now, -i, :minute))
      end

    %{author: author, builds: builds, first: List.first(builds), last: List.last(builds)}
  end
end
