defmodule BuildCalculatorWeb.LaunchUiTest do
  @moduledoc """
  Шапка под запуск (задача 3.23, решение Dan 10.08.2026): «для запуска нужны
  только конструктор и просмотр».

  ⚠️ **Спрятан интерфейс, а не фича.** Поэтому здесь два вида проверок, и оба
  обязательны:

  1. **кнопок нет** — иначе однажды они вернутся молча, вместе с чьей-нибудь
     правкой шаблона;
  2. **роуты живы и всё остальное на месте** — иначе `refute` зеленел бы и
     на закрытом маршруте, и на опечатке в селекторе, и на снесённой шапке.

  Третья проверка — **положительный контроль самого механизма**: флаг
  `config :build_calculator, :accounts_ui` включается на время теста, и кнопки
  обязаны появиться. Без него «нет в DOM» ничего не доказывает: `refute` был бы
  зелёным и при опечатке в id. Именно ради этого флаг лежит в конфиге, а не
  константой в коде (`BuildCalculatorWeb.Layouts.accounts_ui?/0`).

  ⚠️ `async: false` — тест меняет глобальный `Application.put_env/3`, и параллельный
  сосед увидел бы чужую шапку.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculatorWeb.Layouts

  @hidden ["#register", "#log-in", "#nav-library", "#save-build", "#save-this-build"]

  setup do
    # Сторож: если кто-то вернёт кнопки, поменяв флаг, а не разметку, тесты
    # ниже покраснеют осмысленно, а не «не нашли элемент».
    refute Layouts.accounts_ui?()
    :ok
  end

  describe "конструктор" do
    test "ни одного входа в аккаунты и библиотеку", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      for id <- @hidden, do: refute(has_element?(view, id))
      refute has_element?(view, "#account")
    end

    test "а всё, ради чего пришли, на месте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      # Положительный контроль к проверке выше: шапка не исчезла целиком, и
      # каждый оставшийся род вещей адресуется своим id.
      assert has_element?(view, "#builder-header")
      assert has_element?(view, "#mode-switch")
      assert has_element?(view, "#mode-view")
      assert has_element?(view, "#level-step")
      assert has_element?(view, "#character-level")
      assert has_element?(view, "#drop-level")
      assert has_element?(view, "#build-io")
      assert has_element?(view, "#export-button")

      # ⚠️ `#import-button` ушла отсюда 24.08.2026 (задача 3.89) — импорт спрятан
      # своим собственным флагом (`Layouts.import_ui?()`, по умолчанию выключен,
      # независимо от `accounts_ui?()`). Экспорт рядом остаётся, как и просил
      # владелец; обе стороны флага импорта — в `ImportUiTest`.
      assert has_element?(view, "#reset-button")
      assert has_element?(view, "#theme-toggle")
      assert has_element?(view, "#builder-cols")
    end

    test "шаринг билда аккаунта не требует и остался", %{conn: conn} do
      # ⚠️ «Сохранить» — это личная библиотека, а не «поделиться». Если бы
      # скрытие унесло и ссылки, запуск потерял бы главный способ обмена.
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      assert has_element?(view, "#share")
      assert has_element?(view, "#share-link")
      assert has_element?(view, "#short-link-button")
    end
  end

  describe "экран просмотра" do
    test "«Сохранить у себя» скрыт, остальные действия целы", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/#{build_code()}")

      refute has_element?(view, "#save-this-build")
      refute has_element?(view, "#log-in")
      refute has_element?(view, "#nav-library")

      assert has_element?(view, "#build-view")
      assert has_element?(view, "#open-in-builder")
      assert has_element?(view, "#copy-text")
      assert has_element?(view, "#show-text")
      assert has_element?(view, "#theme-toggle")
    end
  end

  describe "футер с атрибуцией" do
    # 🔴 Его прятать нельзя ни при каком упрощении шапки: это выполнение
    # требования CC BY-SA к материалам Fandom, а не украшение.
    test "остаётся на конструкторе и на просмотре", %{conn: conn} do
      for path <- [~p"/?b=#{build_code()}", ~p"/b/#{build_code()}"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "#site-footer")
        assert has_element?(view, "#footer-fandom-link")
        assert has_element?(view, "#footer-license-link")
        assert has_element?(view, "#footer-sources-link")
      end
    end
  end

  describe "роуты живы — спрятан только интерфейс" do
    test "вход и регистрация открываются по прямому адресу", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/users/log-in")
      assert {:ok, _view, _html} = live(conn, ~p"/users/register")
    end

    test "публичная лента открывается по прямому адресу", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")
      assert has_element?(view, "#site-header")
    end

    test "сохранение билда живо: гостя встречает вход и запоминает адрес с кодом", %{conn: conn} do
      code = build_code(levels: List.duplicate(:fighter, 4))
      conn = get(conn, ~p"/builds/new?b=#{code}")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) =~ "/builds/new?b="
    end

    test "страница сохранённого билда открывается — старые ссылки не сломаны", %{conn: conn} do
      build =
        build_fixture(user_scope_fixture(), %{visibility: :public})

      {:ok, view, _html} = live(conn, ~p"/builds/#{build}")
      assert has_element?(view, "#build-view")
    end
  end

  describe "вошедший пользователь" do
    setup :register_and_log_in_user

    test "видит себя и выход, но не вход с регистрацией", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      # Половина вошедшего осталась сознательно: спрятать её значило бы запереть
      # человека в сессии без выхода.
      assert has_element?(view, "#account")
      assert has_element?(view, "#account-email")
      assert has_element?(view, "#log-out")

      refute has_element?(view, "#log-in")
      refute has_element?(view, "#register")
      refute has_element?(view, "#save-build")

      # ⚠️ И навигации по библиотеке у него тоже нет: «Мои билды» с «Группами»
      # ведут в тот же спрятанный раздел, что «Библиотека». Половинчатое скрытие
      # хуже отсутствующего — шапка выглядела бы убранной, а входы остались бы.
      refute has_element?(view, "#nav-library")
      refute has_element?(view, "#nav-mine")
      refute has_element?(view, "#nav-groups")
    end

    test "но библиотека жива и переключатель разделов внутри неё цел", %{conn: conn} do
      # Положительный контроль к проверке выше: попавший по прямому адресу
      # человек навигацию не теряет — она внутри страницы, а не в шапке.
      {:ok, view, _html} = live(conn, ~p"/library/mine")

      assert has_element?(view, "#library-sections")
    end
  end

  describe "флаг возвращает кнопки — положительный контроль скрытия" do
    setup do
      Application.put_env(:build_calculator, :accounts_ui, true)
      on_exit(fn -> Application.put_env(:build_calculator, :accounts_ui, false) end)
      :ok
    end

    test "в конструкторе снова есть вход, библиотека и «Сохранить»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      assert has_element?(view, "#log-in")
      assert has_element?(view, "#register")
      assert has_element?(view, "#nav-library")
      assert has_element?(view, "#save-build")
    end

    test "и вошедший снова видит свои разделы", %{conn: conn} do
      conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> log_in_user(user_fixture())

      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      assert has_element?(view, "#nav-mine")
      assert has_element?(view, "#nav-groups")
    end

    test "на просмотре снова есть «Сохранить у себя»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/#{build_code()}")

      assert has_element?(view, "#save-this-build")
    end

    test "«Сохранить» несёт код билда, а с импорта — и имя", %{conn: conn} do
      # ⚠️ Проверка переехала сюда из `builder_live_test.exs` вместе со скрытием
      # кнопки: `save_url/1` — единственное место, где имя из канонического
      # текста доживает до чего-то наблюдаемого (конструктор его не печатает).
      # Оставлять её на скрытой кнопке было нельзя, а выбрасывать — значило бы
      # потерять единственный тест на то, что имя не теряется по дороге.
      #
      # ⚠️ Второй флаг здесь местный, а не описи блока: сам импорт спрятан
      # НЕЗАВИСИМО от аккаунтов (задача 3.89), и этому тесту нужны оба сразу —
      # `accounts_ui` уже включён `setup` описи, `import_ui` включаем и гасим
      # только тут, чтобы не задевать три соседних теста, которым импорт не нужен.
      Application.put_env(:build_calculator, :import_ui, true)
      on_exit(fn -> Application.put_env(:build_calculator, :import_ui, false) end)

      pasted = """
      Каменный - Fighter(2)
      Гном (Dwarf), Lawful Good
      STR: 16 (16)
      LEVELING GUIDE
      01: Fighter(1)
      02: Fighter(2)
      """

      {:ok, view, _html} = live(conn, ~p"/")

      assert view |> element("#save-build") |> render() =~ "/builds/new?b="

      view |> element("#import-button") |> render_click()

      view
      |> form("#import-form", %{"import" => %{"text" => pasted}})
      |> render_submit()

      view |> element("#import-apply") |> render_click()

      assert has_element?(view, "#save-build[href*='name=']")
    end
  end

  describe "кнопка темы" do
    test "одна пара направлений, «Авто» больше нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      # ⚠️ В DOM их две, а видна ровно одна — выбирает CSS по `data-theme` на
      # `<html>`, потому что тему знает только клиент. Тестом это не проверить
      # (`Phoenix.LiveViewTest` не применяет CSS), поэтому здесь держится
      # структура, а «видна одна» замерена в браузере — 1440/1280/768/390/360,
      # обе темы, плюс смена темы ОС на ходу.
      assert has_element?(view, "#theme-toggle")
      assert has_element?(view, ~s(#theme-to-dark[data-phx-theme="dark"]))
      assert has_element?(view, ~s(#theme-to-light[data-phx-theme="light"]))

      # «Авто» спрятана, и цена принята сознательно: вернуться к системной теме
      # из интерфейса больше нечем (только она снимала ключ `phx:theme`).
      refute has_element?(view, ~s(#theme-toggle button[data-phx-theme="system"]))
    end

    test "у каждой кнопки русская подпись, и она называет ДЕЙСТВИЕ", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      # Традиция выбрана одна и держится целиком: и иконка, и подпись — про то,
      # что случится по клику, а не про текущее состояние. Смешение («луна» +
      # «светлая тема») читалось бы как противоречие.
      assert has_element?(view, ~s(#theme-to-dark[title="Включить тёмную тему"]))
      assert has_element?(view, ~s(#theme-to-dark[aria-label="Включить тёмную тему"]))
      assert has_element?(view, ~s(#theme-to-light[title="Включить светлую тему"]))
      assert has_element?(view, ~s(#theme-to-light[aria-label="Включить светлую тему"]))
    end

    test "есть на всех трёх шапках, а не только в конструкторе", %{conn: conn} do
      for path <- [~p"/?b=#{build_code()}", ~p"/b/#{build_code()}", ~p"/library"] do
        {:ok, view, _html} = live(conn, path)
        assert has_element?(view, "#theme-to-dark")
      end
    end
  end

  describe "шаг уровня" do
    test "кнопка «−» подписана словами для клавиатуры и скринридера", %{conn: conn} do
      # В подписи стоит «−», потому что слово «уровень» уже слева от кнопки,
      # внутри той же рамки. Значит действие обязано быть названо словами хотя бы
      # в `aria-label` — иначе для скринридера кнопка называется «минус».
      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code()}")

      assert has_element?(view, ~s(#drop-level[aria-label="Убрать последний уровень"]))
      assert has_element?(view, ~s(#drop-level[title="Убрать последний уровень"]))
    end

    test "на пустом билде шаг недоступен, на непустом работает", %{conn: conn} do
      {:ok, empty, _html} = live(conn, ~p"/")
      assert has_element?(empty, "#drop-level[disabled]")

      {:ok, view, _html} = live(conn, ~p"/?b=#{build_code(levels: [:fighter, :fighter])}")
      refute has_element?(view, "#drop-level[disabled]")

      view |> element("#drop-level") |> render_click()
      assert render(element(view, "#character-level")) =~ "1"
    end
  end
end
