defmodule BuildCalculatorWeb.EditionTest do
  @moduledoc """
  Редакция из конфига — задача 4.2 (VANILLA.md §4.2).

  Одна кодовая база, два сайта: какой работает, решает конфиг при запуске
  (`EDITION`), а не код. Здесь ванильная редакция поднимается на конструкторе
  и экране просмотра и сверяется с обещанным: ruleset ванили (кап 40, лимит 3),
  `lang="en"`, ванильный бренд в шапке и вкладке, импорт текста виден, импорта
  лога нет, сиальская ссылка — мостик. У каждого ванильного утверждения —
  положительный контроль на Сиале тем же селектором, иначе `refute` зеленел бы
  и на сломанной странице.

  ⚠️ `async: false` — и это не стиль: `use_edition/1` меняет редакцию
  ПРИЛОЖЕНИЯ через `Application.put_env/3` (`:edition`, `:default_ruleset`,
  флаги интерфейса), а тесты `EDITION` — переменную окружения ОС. Параллельный
  сосед в той же VM увидел бы чужой сайт. Файл маленький намеренно (CLAUDE.md
  §7): всё, что не переключает редакцию, живёт в асинхронных файлах.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BuildCalculatorWeb.EditionHelpers

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Edition
  alias BuildCalculatorWeb.Layouts

  @siala_site "https://builder.dondryanich.ru"

  defp code(version, levels) do
    Encoding.encode(
      Build.new(
        ruleset_version: version,
        race: :human,
        alignment: :lawful_good,
        levels: levels
      )
    )
  end

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # Корневой макет (`<html lang>`, `<title>`) рисует только мёртвый рендер —
  # `live/2` отдаёт уже содержимое LiveView без него.
  defp document(conn, path) do
    conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  end

  # Три события диалога лога `.билд` подряд — открыть, разобрать, принять —
  # прямо по сокету (`render_hook/3`), мимо кнопки: так приходит событие,
  # которого разметка не предлагает.
  defp paste_game_log(view) do
    log = "../../fixtures/game_logs/trina.log" |> Path.expand(__DIR__) |> File.read!()

    render_hook(view, "open_game_log_import", %{})
    render_hook(view, "game_log_import_parse", %{"game_log_import" => %{"text" => log}})
    render_hook(view, "game_log_import_apply", %{})
  end

  # То же для импорта текста: билд Fighter(2) в каноническом формате.
  defp paste_text_build(view) do
    text = """
    Каменный - Fighter(2)
    Human, Lawful Good
    LEVELING GUIDE
    01: Fighter(1): Power Attack
    02: Fighter(2)
    """

    render_hook(view, "open_import", %{})
    render_hook(view, "import_parse", %{"import" => %{"text" => text}})
    render_hook(view, "import_apply", %{})
  end

  defp lang(doc), do: doc |> LazyHTML.query("html") |> LazyHTML.attribute("lang")
  defp title(doc), do: doc |> LazyHTML.query("title") |> LazyHTML.text() |> String.trim()

  describe "ванильная редакция" do
    setup do
      use_edition(:vanilla)
    end

    test "конструктор считает ванильный ruleset: кап 40", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert Edition.ruleset() == "vanilla"
      assert Data.default_version() == "vanilla"
      assert text(view, "#level-step") =~ "/ 40"
    end

    test "лимит классов — 3: четвёртый класс показан с причиной", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code("vanilla", [:fighter, :cleric, :rogue])}")

      assert text(view, "#character-level") == "3"
      assert text(view, "#class-lock-wizard") =~ "limit 3 classes"
    end

    test "страница на английском: lang=\"en\"", %{conn: conn} do
      assert lang(document(conn, ~p"/")) == ["en"]
    end

    test "бренд ванили — в шапке и во вкладке", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert text(view, "#builder-header .brand .eyebrow") == "Neverwinter Nights"
      assert text(view, "#builder-header .brand b") == "Build Calculator"
      assert page_title(view) == "NWN Build Calculator"
      assert title(document(conn, ~p"/")) == "NWN Build Calculator"
      refute text(view, "#builder-header .brand") =~ "Сиала"

      {:ok, sources, _html} = live(conn, ~p"/sources")
      assert page_title(sources) == "Sources · NWN Build Calculator"
    end

    test "футер по-английски, без Сиалы и шарда, атрибуция Fandom на месте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      footer = text(view, "#site-footer")

      assert footer =~ "Game data is based on material from NWN Wiki (Fandom)"
      assert footer =~ "adapted for this calculator"
      assert footer =~ "CC BY-SA 3.0"
      assert footer =~ "not affiliated with BioWare, Beamdog, Wizards of the Coast or Fandom"
      refute footer =~ "Сиал"
      refute footer =~ "шард"
      refute footer =~ ~r/\p{Cyrillic}/u

      assert has_element?(view, ~s(a#footer-fandom-link[href="https://nwn.fandom.com/"]))

      assert has_element?(
               view,
               ~s(a#footer-license-link[href="https://creativecommons.org/licenses/by-sa/3.0/"])
             )

      assert text(view, "#footer-sources-link") == "the Sources page"
    end

    test "импорт текста виден, импорта лога .билд нет, аккаунтов нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert Layouts.import_ui?()
      refute Layouts.game_log_import_ui?()
      refute Layouts.accounts_ui?()

      assert has_element?(view, "#import-button")
      refute has_element?(view, "#game-log-import-button")
      refute has_element?(view, "#save-build")

      # Шапка на месте — `refute` выше ловят скрытие, а не пропавшую шапку.
      assert has_element?(view, "#build-io")
    end

    # Задача 4.4: спрятанное флагом спрятано и от СОБЫТИЯ. Кнопки лога на ванили
    # нет, а событие, присланное по сокету руками, до 4.4 разбирало лог команды
    # шарда и заменяло билд.
    test "импорт лога .билд: событие по сокету ничего не делает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      paste_game_log(view)

      assert text(view, "#character-level") == "0"
      assigns = :sys.get_state(view.pid).socket.assigns
      refute assigns.game_log_import_open?
      assert assigns.game_log_import_report == nil
    end

    # Положительный контроль: те же события на той же ванили, но с включённым
    # флагом, билд меняют — значит, выше их гасит флаг, а не что-то другое
    # (разбор лога ванильным ruleset'ом сам по себе работает).
    test "импорт лога .билд: с включённым флагом те же события билд меняют", %{conn: conn} do
      Application.put_env(:build_calculator, :game_log_import_ui, true)
      {:ok, view, _html} = live(conn, ~p"/")

      paste_game_log(view)

      assert text(view, "#character-level") == "15"
    end

    test "сиальская ссылка на конструкторе — мостик на сайт Сиалы, конструктор пуст", %{
      conn: conn
    } do
      code = code("siala_41", [:fighter, :fighter])
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      assert text(view, "#edition-bridge") =~
               "This build is for the Siala shard. This site does not compute those rules."

      assert has_element?(view, ~s(a#edition-bridge-link[href="#{@siala_site}/?b=#{code}"]))
      assert text(view, "#edition-bridge-link") == "Open it on builder.dondryanich.ru"

      # Под мостиком — пустой конструктор ванили, а не сиальский билд.
      assert text(view, "#character-level") == "0"
      assert text(view, "#level-step") =~ "/ 40"
    end

    test "сиальская ссылка на экране просмотра — тот же мостик, путь /b/", %{conn: conn} do
      code = code("siala_41", [:fighter, :fighter])
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-bridge")
      assert has_element?(view, ~s(a#view-bridge-link[href="#{@siala_site}/b/#{code}"]))
      assert text(view, "#view-bridge-message") =~ "the Siala shard"
      refute has_element?(view, "#build-view")
      refute has_element?(view, "#view-error")
    end

    test "своя ссылка открывается как обычно", %{conn: conn} do
      code = code("vanilla", [:fighter, :fighter])

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      refute has_element?(view, "#edition-bridge")
      assert text(view, "#character-level") == "2"

      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      refute has_element?(view, "#view-bridge")
      assert has_element?(view, "#build-view")
    end

    test "билд без ruleset'а кодируется ванилью — ruleset ядра по умолчанию из редакции" do
      {:ok, %{ruleset: ruleset}} =
        Build.new(levels: [:fighter]) |> Encoding.encode() |> Encoding.decode()

      assert ruleset.version == "vanilla"
    end
  end

  # Положительный контроль: те же селекторы на Сиале отвечают по-сиальски.
  # Без него ванильные `refute` и сравнения строк выше ничего бы не доказывали.
  describe "Сиала — положительный контроль" do
    setup do
      use_edition(:siala)
    end

    test "кап 41, лимит 4, русский язык, сиальский бренд", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code("siala_41", [:fighter, :cleric, :rogue])}")

      assert Data.default_version() == "siala_41"
      assert text(view, "#level-step") =~ "/ 41"
      assert has_element?(view, "#class-card-wizard")
      refute has_element?(view, "#class-lock-wizard")

      assert text(view, "#builder-header .brand .eyebrow") == "Сиала · NWN"
      assert text(view, "#builder-header .brand b") == "Калькулятор билдов"
      assert page_title(view) == "Калькулятор билдов Сиалы"

      doc = document(conn, ~p"/")
      assert lang(doc) == ["ru"]
      assert title(doc) == "Калькулятор билдов Сиалы"

      {:ok, sources, _html} = live(conn, ~p"/sources")
      assert page_title(sources) == "Источники · Калькулятор билдов Сиалы"
    end

    # Задача 4.18: «(Fandom) ,» → «(Fandom),» — пробел перед запятой рисовал
    # перенос строки внутри `<a>`; остальное — прежний текст.
    test "футер Сиалы — прежним текстом", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert text(view, "#site-footer") ==
               "Игровые данные основаны на материалах NWN Wiki (Fandom), переработанных " <>
                 "под правила Сиалы, и распространяются по лицензии CC BY-SA 3.0 — как и наш " <>
                 "производный слой правил. Подробнее — страница «Источники». Проект не связан " <>
                 "с BioWare, Beamdog, Wizards of the Coast, Fandom или администрацией шарда."
    end

    test "импорт лога виден, импорт текста спрятан", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#game-log-import-button")
      refute has_element?(view, "#import-button")
    end

    # Задача 4.4, та же дыра с другой стороны: импорт текста на Сиале спрятан
    # решением 3.89, а событие по сокету его разбирало и применяло.
    test "импорт текста: событие по сокету ничего не делает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      paste_text_build(view)

      assert text(view, "#character-level") == "0"
      assigns = :sys.get_state(view.pid).socket.assigns
      refute assigns.import_open?
      assert assigns.import_report == nil
    end

    test "импорт текста: с включённым флагом те же события билд меняют", %{conn: conn} do
      Application.put_env(:build_calculator, :import_ui, true)
      {:ok, view, _html} = live(conn, ~p"/")

      paste_text_build(view)

      assert text(view, "#character-level") == "2"
    end

    # И лог на самой Сиале — флаг включён, события идут (ворота не сломали
    # то, ради чего кнопка есть).
    test "импорт лога: на Сиале события работают", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      paste_game_log(view)

      assert text(view, "#character-level") == "15"
    end

    test "сиальская ссылка открывается билдом, а не мостиком", %{conn: conn} do
      code = code("siala_41", [:fighter, :fighter])

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      refute has_element?(view, "#edition-bridge")
      assert text(view, "#character-level") == "2"

      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      refute has_element?(view, "#view-bridge")
      assert has_element?(view, "#build-view")
    end

    # И обратно: ванильная ссылка на Сиале — тоже мостик. Сайта у ванили пока
    # нет (`site: nil`), поэтому ссылки в мостике нет, а текст говорит об этом.
    test "ванильная ссылка — мостик без ссылки: сайта ванили пока нет", %{conn: conn} do
      code = code("vanilla", [:fighter, :fighter])

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      assert text(view, "#edition-bridge") ==
               "Этот билд — для ванильной Neverwinter Nights. Этот сайт такие правила " <>
                 "не считает. Сайта с этими правилами пока нет."

      refute has_element?(view, "#edition-bridge-link")
      assert text(view, "#character-level") == "0"
      assert text(view, "#level-step") =~ "/ 41"

      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      assert has_element?(view, "#view-bridge")
      refute has_element?(view, "#view-bridge-link")
      assert has_element?(view, "#view-bridge-new")
    end

    test "билд без ruleset'а кодируется Сиалой" do
      {:ok, %{ruleset: ruleset}} =
        Build.new(levels: [:fighter]) |> Encoding.encode() |> Encoding.decode()

      assert ruleset.version == "siala_41"
    end
  end

  describe "мостик: замена билда гасит его" do
    setup do
      use_edition(:vanilla)
    end

    test "«Сброс» после мостика — мостика больше нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{code("siala_41", [:fighter])}")
      assert has_element?(view, "#edition-bridge")

      view |> element("#reset-button") |> render_click()
      refute has_element?(view, "#edition-bridge")
    end
  end

  describe "EDITION в config/runtime.exs — белый список" do
    setup do
      previous = System.get_env("EDITION")

      on_exit(fn ->
        if previous,
          do: System.put_env("EDITION", previous),
          else: System.delete_env("EDITION")
      end)
    end

    defp runtime_edition(value, env \\ :dev) do
      if value, do: System.put_env("EDITION", value), else: System.delete_env("EDITION")

      "config/runtime.exs"
      |> Config.Reader.read!(env: env)
      |> get_in([:build_calculator, :edition])
    end

    test "имена пресетов становятся атомами, пустое — умолчание из config.exs" do
      assert runtime_edition("vanilla") == :vanilla
      assert runtime_edition("siala") == :siala
      assert runtime_edition(nil) == nil
      assert runtime_edition("") == nil
    end

    test "незнакомое имя роняет запуск словами" do
      assert_raise RuntimeError, ~r/EDITION="classic" names no edition/, fn ->
        runtime_edition("classic")
      end
    end

    test "под mix test переменная не читается — сиальский набор остаётся сиальским" do
      assert runtime_edition("vanilla", :test) == nil
    end

    test "каждый пресет из config.exs принимается белым списком" do
      for {name, _preset} <- Application.fetch_env!(:build_calculator, :editions) do
        assert runtime_edition(Atom.to_string(name)) == name
      end
    end
  end

  describe "configure!/0 проверяет пресеты при запуске" do
    setup do
      editions = Application.fetch_env!(:build_calculator, :editions)
      use_edition(:siala)
      on_exit(fn -> Application.put_env(:build_calculator, :editions, editions) end)
      %{editions: editions}
    end

    test "оба пресета проходят проверку" do
      for {name, _preset} <- Application.fetch_env!(:build_calculator, :editions) do
        Application.put_env(:build_calculator, :edition, name)
        assert Edition.configure!() == :ok
      end
    end

    test "неизвестная редакция роняет запуск" do
      Application.put_env(:build_calculator, :edition, :classic)

      assert_raise ArgumentError, ~r/:classic, which is not one of the presets/, fn ->
        Edition.configure!()
      end
    end

    test "пресет без ключа роняет запуск", %{editions: editions} do
      broken = Keyword.update!(editions, :vanilla, &Keyword.delete(&1, :product_name))
      Application.put_env(:build_calculator, :editions, broken)

      assert_raise ArgumentError, ~r/edition :vanilla misses \[:product_name\]/, fn ->
        Edition.configure!()
      end
    end

    test "ruleset, которого нет в сборке, роняет запуск", %{editions: editions} do
      broken = Keyword.update!(editions, :vanilla, &Keyword.put(&1, :ruleset, "vanilla_2"))
      Application.put_env(:build_calculator, :editions, broken)

      assert_raise ArgumentError, ~r/"vanilla_2", which is not compiled in/, fn ->
        Edition.configure!()
      end
    end

    test "незнакомый вид гида экспорта роняет запуск", %{editions: editions} do
      broken = Keyword.update!(editions, :vanilla, &Keyword.put(&1, :export_guide, :cbc))
      Application.put_env(:build_calculator, :editions, broken)

      assert_raise ArgumentError, ~r/export_guide must be one of \[:ecb, :merged\]/, fn ->
        Edition.configure!()
      end
    end
  end

  # Задача 4.4: подпись экспорта и вид гида — бренд и привычка аудитории, то
  # есть редакция (VANILLA.md §2 п. 3), а не ветка по имени ruleset'а в коде.
  describe "экспорт от имени редакции" do
    setup do
      use_edition(:siala)
    end

    test "вид гида — по ruleset'у билда, у правил без сайта — формат гильдии" do
      assert Edition.export_guide("siala_41") == :merged
      assert Edition.export_guide("vanilla") == :ecb
      assert Edition.export_guide("classic") == :ecb
    end

    test "вид гида не зависит от того, какой сайт работает" do
      use_edition(:vanilla)

      assert Edition.export_guide("siala_41") == :merged
      assert Edition.export_guide("vanilla") == :ecb
    end

    test "подпись экспорта — своя у каждой редакции, латиницей и у русского сайта" do
      assert Edition.export_name() == "Siala Build Calculator"

      use_edition(:vanilla)
      assert Edition.export_name() == "NWN Build Calculator"
    end

    # 🔴 Сторож допущения, на котором стоят переводы задачи 4.4: там, где
    # сиальский текст называет Сиалу («правила Сиалы», «на Сиале»), английский
    # msgid говорит «the rules», а русский `msgstr` сохранил имя — русский
    # каталог считается языком сиальской редакции (шапка раздела 4.4
    # в `priv/gettext/ru/LC_MESSAGES/default.po`). Появится вторая редакция
    # на том же языке — этот тест упадёт раньше, чем её игрок прочтёт «Сиалу»
    # в чужих правилах: такие строки уходят во фразы редакции (`:editions`).
    test "каждый язык интерфейса — только у одной редакции" do
      locales =
        for {_name, preset} <- Application.fetch_env!(:build_calculator, :editions),
            do: preset[:locale]

      assert Enum.uniq(locales) == locales,
             "две редакции говорят на одном языке (#{inspect(locales)}): русские " <>
               "переводы задачи 4.4 называют Сиалу — см. шапку раздела 4.4 в ru/default.po"
    end
  end
end
