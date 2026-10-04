defmodule BuildCalculatorWeb.InputLimitsLiveTest do
  @moduledoc """
  Поля ввода и потолок сообщения сокета — задача 4.41 (`BuildCalculatorWeb.InputLimits`).

  Сообщение браузера длиннее `Endpoint.max_message_bytes/0` сервер рвёт вместе
  с соединением. Чтобы законный ввод туда не доставал, у каждого текстового поля,
  чьё значение уходит на сервер, стоит `maxlength`. `phx-auto-recover="ignore"`
  у окон вставки сознательно НЕТ (решение координатора 4.41): петли переподключений
  нет и без него — LiveView бросает форму после одной неудачной попытки, — а с ним
  вставка после обрыва связи в окно не возвращалась.

  Здесь проверяется по DOM-id, что атрибуты стоят, и что запрос поиска сервер
  обрезает сам: `maxlength` держит браузер, а событие можно собрать руками.
  Сторож «у каждого текстового поля в исходниках есть `maxlength`» —
  `InputMaxlengthSourceTest`; здесь же — тот же вопрос к ОТРИСОВКЕ всех страниц
  с полями ввода, то есть к тому, что действительно уходит браузеру.

  ⚠️ `async: false` — блок окна импорта текста включает флаг `:import_ui`
  глобальным `Application.put_env/3` (на Сиале окно спрятано, задача 3.89),
  и параллельный сосед увидел бы чужую шапку — тот же довод, что у
  `BuilderLiveImportTest`.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.InputLimits

  # Поля, которые несут текст на сервер: `textarea` и `input` текстовых типов
  # (тип не указан — текст). У `number` атрибута `maxlength` нет по HTML
  # (браузер его не читает), `hidden`, флажки, переключатели и кнопки
  # пользователь не набирает.
  @not_text ~w(hidden checkbox radio number range color date datetime-local month week time
               file submit button reset image)

  setup do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  defp code(ruleset, levels) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: levels,
      base_abilities: %{str: 13, dex: 15, con: 10, int: 12, wis: 10, cha: 14}
    )
    |> Encoding.encode()
  end

  # Текстовые поля с именем и без `maxlength` в разметке страницы.
  defp unbounded(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("textarea[name], input[name]")
    |> Enum.map(fn node ->
      attrs = node |> LazyHTML.attributes() |> List.first() |> Map.new()
      {LazyHTML.tag(node) |> List.first(), attrs}
    end)
    |> Enum.filter(fn {tag, attrs} ->
      tag == "textarea" or Map.get(attrs, "type", "text") not in @not_text
    end)
    |> Enum.reject(fn {_tag, attrs} -> Map.has_key?(attrs, "maxlength") end)
    |> Enum.map(fn {tag, attrs} -> {tag, attrs["id"], attrs["name"]} end)
  end

  defp text_fields(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("textarea[name], input[name]")
    |> Enum.count(fn node ->
      attrs = node |> LazyHTML.attributes() |> List.first() |> Map.new()
      LazyHTML.tag(node) == ["textarea"] or Map.get(attrs, "type", "text") not in @not_text
    end)
  end

  defp max(n), do: "[maxlength='#{n}']"

  describe "окно лога `.билд` (Сиала)" do
    test "поле несёт maxlength на единицу больше потолка чтения, форма восстанавливается",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # положительный контроль: окно и поле в разметке есть — атрибут проверяется
      # у существующего узла, а не у опечатки в id
      assert has_element?(view, "#game-log-import-text")
      assert has_element?(view, "#game-log-import-form")

      assert InputLimits.game_log_text() == BuildCalculator.GameLog.max_bytes() + 1
      assert has_element?(view, "#game-log-import-text" <> max(InputLimits.game_log_text()))
      refute has_element?(view, "#game-log-import-form[phx-auto-recover]")
    end

    test "вставка длиннее потолка — замечание об обрезке в отчёте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#game-log-import-button") |> render_click()

      view
      |> form("#game-log-import-form", %{
        "game_log_import" => %{"text" => String.duplicate("a", InputLimits.game_log_text())}
      })
      |> render_submit()

      assert render(element(view, "#game-log-import-issues")) =~ "64000"
    end
  end

  describe "окно импорта текста (флаг включён)" do
    setup do
      Application.put_env(:build_calculator, :import_ui, true)
      on_exit(fn -> Application.put_env(:build_calculator, :import_ui, false) end)
      :ok
    end

    test "поле несёт maxlength на единицу больше потолка чтения, форма восстанавливается",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#import-text")
      assert has_element?(view, "#import-form")

      assert InputLimits.import_text() ==
               BuildCalculatorWeb.Builder.Import.Scan.max_bytes() + 1

      assert has_element?(view, "#import-text" <> max(InputLimits.import_text()))
      refute has_element?(view, "#import-form[phx-auto-recover]")
    end

    test "вставка длиннее потолка — замечание об обрезке в отчёте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#import-button") |> render_click()

      view
      |> form("#import-form", %{
        "import" => %{"text" => String.duplicate("a", InputLimits.import_text())}
      })
      |> render_submit()

      assert render(element(view, "#import-issues")) =~ "64000"
    end

    test "у всех текстовых полей конструктора с открытым окном импорта есть maxlength",
         %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code(ruleset, [:fighter])}")
      view |> element("#import-button") |> render_click()

      html = render(view)
      assert text_fields(html) >= 3
      assert unbounded(html) == []
    end
  end

  describe "поля поиска конструктора" do
    test "поиск фитов, навыков и заклинаний", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code(ruleset, [:fighter])}")

      assert has_element?(view, "#feat-search" <> max(InputLimits.short_text()))

      view |> element("#skill-add-toggle") |> render_click()
      assert has_element?(view, "#skill-search" <> max(InputLimits.short_text()))

      {:ok, view, _html} = live(conn, ~p"/?b=#{code(ruleset, [:bard, :bard])}&l=2")
      assert has_element?(view, "#spell-search" <> max(InputLimits.short_text()))
    end

    test "поиски «Вещей»: навык, фит, его значение, оружие обеих рук",
         %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code(ruleset, [:fighter])}")

      view |> element("#gear-toggle") |> render_click()
      view |> element("#gear-skill-add-toggle") |> render_click()
      view |> element("#gear-feat-add-toggle") |> render_click()
      view |> element("#gear-weapon-add-toggle") |> render_click()
      view |> element("#gear-off-weapon-add-toggle") |> render_click()

      for id <- ~w(gear-skill-search gear-feat-search gear-weapon-search gear-off-weapon-search) do
        assert has_element?(view, "##{id}" <> max(InputLimits.short_text())), id
      end

      view |> element("#gear-feat-search-form") |> render_change(%{"q" => "skill focus"})
      view |> element("#gear-pick-skill_focus") |> render_click()

      assert has_element?(
               view,
               "#gear-feat-choice-search-skill_focus" <> max(InputLimits.short_text())
             )

      # и вся отрисовка с открытыми списками — без единого поля без предела
      html = render(view)
      assert text_fields(html) >= 6
      assert unbounded(html) == []
    end
  end

  # `maxlength` держит браузер; событие, собранное руками, его не знает. Поиск
  # сравнивает запрос с каждым именем целиком (500 000 букв — 17,7 с на фитах
  # Сиалы, замер 4.41), поэтому сервер берёт из запроса первые `short_text/0`.
  describe "запрос поиска сервер обрезает сам" do
    setup %{ruleset: ruleset} do
      %{
        long: String.duplicate("a", 10_000),
        short: String.duplicate("a", InputLimits.short_text()),
        code: code(ruleset, [:fighter])
      }
    end

    test "поиск фитов", %{conn: conn, code: code, long: long, short: short} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      view |> element("#feat-search-form") |> render_change(%{"q" => long})

      assert has_element?(view, "#feat-search[value='#{short}']")
    end

    test "поиски «Вещей» — оружие и значение фита (свои пути в коде)", %{
      conn: conn,
      code: code,
      long: long,
      short: short
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      view |> element("#gear-toggle") |> render_click()
      view |> element("#gear-weapon-add-toggle") |> render_click()
      view |> element("#gear-weapon-search-form") |> render_change(%{"q" => long})
      assert has_element?(view, "#gear-weapon-search[value='#{short}']")

      view |> element("#gear-feat-add-toggle") |> render_click()
      view |> element("#gear-feat-search-form") |> render_change(%{"q" => "skill focus"})
      view |> element("#gear-pick-skill_focus") |> render_click()

      view
      |> element("#gear-feat-choice-search-form-skill_focus")
      |> render_change(%{"feat" => "skill_focus", "q" => long})

      assert has_element?(view, "#gear-feat-choice-search-skill_focus[value='#{short}']")
    end

    # Событие руками может нести не строку, а карту (`q[x]=…`): раньше она
    # доходила до `Fuzzy.match/2` и роняла процесс.
    test "не строка — пустой запрос, а не падение", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      render_change(view, "feat_search", %{"q" => %{"x" => "y"}})

      assert has_element?(view, "#feat-search[value='']")
    end
  end

  describe "страницы аккаунтов и библиотеки" do
    test "библиотека, вход и регистрация", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/library")

      assert has_element?(
               view,
               "#library-filters input[name='q']" <> max(InputLimits.short_text())
             )

      assert unbounded(html) == []

      {:ok, view, html} = live(conn, ~p"/users/log-in")

      assert has_element?(
               view,
               "#login-form-magic input[type='email']" <> max(InputLimits.email())
             )

      assert has_element?(
               view,
               "#login-form-password input[type='password']" <> max(InputLimits.password())
             )

      assert text_fields(html) >= 3
      assert unbounded(html) == []

      {:ok, view, html} = live(conn, ~p"/users/register")

      assert has_element?(
               view,
               "#registration-form input[type='email']" <> max(InputLimits.email())
             )

      assert unbounded(html) == []
    end

    test "настройки, группы и форма сохранения (вошедший)", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      {:ok, view, html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#email-form input[type='email']" <> max(InputLimits.email()))

      assert has_element?(
               view,
               "#password-form input[name='user[password]']" <> max(InputLimits.password())
             )

      assert has_element?(
               view,
               "#password-form input[name='user[password_confirmation]']" <>
                 max(InputLimits.password())
             )

      assert unbounded(html) == []

      {:ok, view, html} = live(conn, ~p"/groups")

      assert has_element?(
               view,
               "#join-group-form input[name='join[invite_code]']" <> max(InputLimits.short_text())
             )

      assert unbounded(html) == []

      {:ok, _view, html} =
        live(conn, ~p"/builds/new?b=#{BuildCalculator.LibraryFixtures.build_code()}")

      assert text_fields(html) >= 2
      assert unbounded(html) == []
    end
  end

  # Положительный контроль самого сторожа отрисовки: поле без `maxlength` он
  # называет, поле с ним и не-текстовые поля — нет.
  test "сторож отрисовки видит поле без maxlength" do
    html = """
    <html><body>
      <form><input name="a" type="text"><input name="b"><textarea name="c"></textarea>
      <input name="d" type="search" maxlength="5"><input name="e" type="number">
      <input name="f" type="hidden"><input type="text" id="g"></form>
    </body></html>
    """

    assert unbounded(html) == [{"input", nil, "a"}, {"input", nil, "b"}, {"textarea", nil, "c"}]
    assert text_fields(html) == 4
  end
end
