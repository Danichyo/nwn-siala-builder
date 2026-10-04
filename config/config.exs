# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :build_calculator, :scopes,
  user: [
    default: true,
    module: BuildCalculator.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: BuildCalculator.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :build_calculator,
  ecto_repos: [BuildCalculator.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# ── Редакции ───────────────────────────────────────────────────────────────
#
# Задача 4.2 (VANILLA.md §2): одна кодовая база, две развёртки. Редакция — это
# САЙТ: какой ruleset он считает, на каком языке говорит, как называется и что
# показывает. Механика игры в редакцию не входит — она в ruleset'е.
#
# Какая редакция работает, решает `EDITION` при запуске (`config/runtime.exs`,
# белый список); без переменной — Сиала, строкой ниже. Пресеты — здесь, одним
# списком на редакцию, и больше нигде: читает их только
# `BuildCalculatorWeb.Edition` (там же проверка при запуске — пресет без ключа
# или с чужим ruleset'ом роняет старт, а не запрос), а шаблоны спрашивают у неё
# строку или возможность, никогда не имя редакции.
#
# ⚠️ Имена ruleset'ов стоят здесь, в конфиге, а не в `lib/`: сторож «код
# не спрашивает имя ruleset'а» (VANILLA.md §2 п. 1) считает упоминания в `lib/`,
# и объявление «какой сайт что считает» — настройка развёртки, а не код.
#
# Ключи пресета:
#
#   * `ruleset` — механика сайта. Ядро видит из редакции только его, как
#     «ruleset по умолчанию» (`BuildCalculator.Data.default_version/0`); ссылка
#     с другим ruleset'ом открывается мостиком на сайт той редакции, что его
#     считает (`site`), а не пересчитывается по чужим правилам молча;
#   * `locale` — язык интерфейса (`BuildCalculatorWeb.Locale`: plug и
#     `on_mount`), он же `lang` у `<html>`;
#   * `site` — адрес сайта редакции для мостика с сайта-близнеца; `nil` —
#     сайта нет, мостик говорит об этом без ссылки;
#   * `eyebrow` / `brand_title` — шапка, `product_name` — имя продукта:
#     заголовок вкладки конструктора и хвост заголовка любой другой страницы;
#   * `export_name` — имя, которым подписан текстовый экспорт («Посчитано
#     Siala Build Calculator»). Латиницей и у русского сайта: экспорт —
#     английский формат комьюнити (задача 4.4);
#   * `footer_adapted` / `footer_disclaimer` — фразы футера, которыми сайты
#     различаются. Атрибуция Fandom CC BY-SA вокруг них общая и обязательна
#     обоим (CLAUDE.md §3);
#   * `rules_name` — как ЭТИ правила называет сайт-близнец в мостике, по языку
#     читателя (`"ru"` — фраза «Этот билд — для %{rules}.», `"en"` — «This build
#     is for %{rules}.»);
#   * `export_guide` — вид гида по уровням в текстовом экспорте билда ЭТИХ
#     правил: `:ecb` — два блока формата гильдии Epic Character Builders,
#     `:merged` — одна строка на уровень (`BuildCalculatorWeb.Edition.export_guide/1`,
#     задача 4.4; до неё — ветка по имени ruleset'а в `Builder.Export`);
#   * `accounts_ui`, `import_ui`, `game_log_import_ui`, `guide_first` — флаги
#     интерфейса (`BuildCalculatorWeb.Layouts`). Здесь их УМОЛЧАНИЕ; явный
#     `config :build_calculator, :import_ui, …` перекрывает пресет — так тесты
#     включают спрятанное и получают положительный контроль;
#   * `analytics` — свой счётчик посещений и событий (задача 4.54,
#     `BuildCalculatorWeb.Analytics`): выключен — в таблицы не пишется ничего
#     и в браузер не уходит ничего лишнего. Перекрывается так же.
config :build_calculator, :edition, :siala

config :build_calculator, :editions,
  siala: [
    ruleset: "siala_41",
    locale: "ru",
    site: "https://builder.dondryanich.ru",
    eyebrow: "Сиала · NWN",
    brand_title: "Калькулятор билдов",
    product_name: "Калькулятор билдов Сиалы",
    export_name: "Siala Build Calculator",
    footer_adapted: "переработанных под правила Сиалы",
    footer_disclaimer:
      "Проект не связан с BioWare, Beamdog, Wizards of the Coast, Fandom или администрацией шарда.",
    rules_name: %{"ru" => "шарда Сиала", "en" => "the Siala shard"},
    # Весь уровень одной строкой — Dan 30.08.2026 (задача 3.145): «на Сиале
    # нету пользователей EPIC CHARACTER BUILDERS… когда качаешься и поднимаешь
    # уровень сразу видеть все что надо взять при лвл апе».
    export_guide: :merged,

    # ⚠️ Аккаунты, «Сохранить» и библиотека спрятаны из ИНТЕРФЕЙСА под запуск —
    # решение Dan 10.08.2026 (AGENT_QUEUE §3.23): «для запуска нужны только
    # конструктор и просмотр». Спрятана только разметка: роуты `/users/register`,
    # `/users/log-in`, `/library`, `/builds/new`, `/builds/:id` живы и достижимы по
    # прямому адресу — закрыть их значило бы сломать уже существующие ссылки на
    # сохранённые билды. Возврат — `true` в этой строке.
    #
    # Флаг живёт в конфиге, а не константой в коде, по двум причинам: типизатор
    # Elixir сворачивает `def accounts_ui?, do: false` в `dynamic(false)` и роняет
    # сборку предупреждением о недостижимой ветке `:if`, а тест умеет включить флаг
    # через `Application.put_env/3` — то есть у каждого `refute` появляется
    # положительный контроль (`launch_ui_test.exs`).
    accounts_ui: false,

    # ⚠️ Импорт билда из текста спрятан из ИНТЕРФЕЙСА — задача 3.89, решение Dan
    # 24.08.2026: «спрятать импорт, импортировать билды к нам никто не будет,
    # а вот экспорт может пригодиться — сбилдил и сохранил в текстовом виде на
    # всякий случай». Экспорт этим флагом не задет и остаётся видимым целиком.
    #
    # `BuildCalculatorWeb.Builder.Import` остаётся рабочим модулем, не удалённым
    # кодом: на нём стоит план проверки ванильных чисел через эталонные билды
    # NWN-комьюнити (`docs/VANILLA_SPLIT.md` §4, §7.4). Возврат кнопки и диалога —
    # `true` в этой строке, без правки кода.
    import_ui: false,

    # Вставка СВОЕГО персонажа из лога `.билд` — отдельный сценарий и отдельный
    # флаг (задача 3.111, запрос Dan 26.08.2026), разбор — `Layouts.game_log_import_ui?/0`.
    game_log_import_ui: true,

    # ⚠️ Экран просмотра — ГИД ПО ПРОКАЧКЕ, а не витрина итогов: решение Dan
    # 10.08.2026 (AGENT_QUEUE §3.24). «Когда берешь уровень в игре, надо зайти
    # в билд и посмотреть что же надо прокачать… при прокачке итоговые статы уже
    # не интересны, они уже известны». Поэтому гид стоит первой секцией, а итоги —
    # после него; отсюда же плотность гида (пустые уровни тоньше, выданное классом
    # одной строкой в конце).
    #
    # ⚠️ Это ПЕРЕСМОТР записанного решения, а не починка. CLAUDE.md §6 объяснял
    # порядок так: «ничего не выбирается, поэтому вся страница отдана итогам».
    # Довод верен ровно до тех пор, пока итоги — главное на экране; Dan назвал
    # главным другое. Оба решения записаны, потому что следующий читатель иначе
    # «починит» пересмотренное.
    #
    # `false` в этой строке возвращает прежний порядок (итоги первыми) и прежнюю
    # плотность гида — одной строкой, ничего больше не теряя: починка столкновения
    # `.lv` и разбор итогов списком к флагу НЕ привязаны, они нужны в любом порядке.
    guide_first: true,

    # Счётчик посещений и событий — задача 4.54, Dan 03.10.2026: «в аналитике
    # на самом деле мы можем включить и Сиалу, главное, чтобы мы не логировали
    # билды». Без cookie, без внешних скриптов, в базе своей развёртки; что
    # пишется и чего нет — `BuildCalculator.Analytics`.
    analytics: true
  ],
  vanilla: [
    ruleset: "vanilla",
    locale: "en",
    # Домена у ванили пока нет (VANILLA.md §5, задача 4.21) — мостик с Сиалы
    # говорит «сайта пока нет» без ссылки. Появится домен — адрес сюда.
    site: nil,
    # ⚠️ Имя продукта РАБОЧЕЕ — выбирает Dan (VANILLA.md §5, вопрос 5). Четыре
    # строки ниже — всё, что его несёт: шапка (`eyebrow`, `brand_title`),
    # заголовки вкладок (`product_name`) и подпись экспорта (`export_name`,
    # задача 4.4); больше нигде оно не написано.
    eyebrow: "Neverwinter Nights",
    brand_title: "Build Calculator",
    product_name: "NWN Build Calculator",
    export_name: "NWN Build Calculator",
    footer_adapted: "adapted for this calculator",
    footer_disclaimer:
      "This project is not affiliated with BioWare, Beamdog, Wizards of the Coast or Fandom.",
    rules_name: %{"ru" => "ванильной Neverwinter Nights", "en" => "vanilla Neverwinter Nights"},
    # Формат гильдии Epic Character Builders — стандарт ванильного комьюнити
    # (VANILLA.md §1, §3.7), и его же читает наш импорт текста.
    export_guide: :ecb,
    # Аккаунты выключены, как на Сиале — решение Dan 02.10.2026 (VANILLA.md §5,
    # вопрос 6; предложено координатором в постановке 4.2). Импорт канонического текста на ванили
    # ВИДЕН (VANILLA.md §1: «существует общепринятый стандарт билдов для
    # ванильной версии, его будем поддерживать»), импорта лога `.билд` нет —
    # это команда шарда (Dan 25.09.2026: «это только на Сиале»).
    accounts_ui: false,
    import_ui: true,
    game_log_import_ui: false,
    guide_first: true,
    # Обе редакции — Dan 03.10.2026 (задача 4.54).
    analytics: true
  ]

# Потолок одного сообщения браузера по вебсокету, байт (задача 4.41; числа и доводы —
# `BuildCalculatorWeb.InputLimits`). Худшее законное сообщение — окно вставки,
# заполненное до `maxlength`, ≈ 0,58 МБ; прежние пределы — 10 МБ на кадр и 8 МБ
# на сообщение из кадров. Ставится дважды из одного числа: на кадр — у сокета
# (`endpoint.ex`, `max_frame_size`), на сообщение из нескольких кадров — у Bandit
# ниже: этот ключ в настройках сокета Phoenix не принимает (`Keyword.validate!`),
# а Chrome дробит длинное сообщение на кадры по 131 000 байт, и предел кадра его
# не видит (замер 4.41). `http:` сливается с `dev.exs`, `test.exs` и `runtime.exs`
# по ключам (`Config` сливает списки ключ-значение вглубь).
websocket_max_message_bytes = 2_000_000

config :build_calculator, :websocket_max_message_bytes, websocket_max_message_bytes

# Configure the endpoint
config :build_calculator, BuildCalculatorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [websocket_options: [max_fragmented_message_size: websocket_max_message_bytes]],
  render_errors: [
    formats: [html: BuildCalculatorWeb.ErrorHTML, json: BuildCalculatorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BuildCalculator.PubSub,
  live_view: [signing_salt: "GYnQcv8Z"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :build_calculator, BuildCalculator.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  build_calculator: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  build_calculator: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Задача 4.75: значения этих параметров `Phoenix.Logger` и `Phoenix.LiveView.Logger`
# печатают как `[FILTERED]` — в строках «Parameters:» разбора маршрута, монтирования
# и событий LiveView (уровень `:debug`) и подключения сокета (`:info`). `b` и `code` —
# код билда (`/?b=`, `/b/:code`), `key` — ключ короткой ссылки, `token` — токены входа
# и `_csrf_token`, `text` — вставленный текст импорта и лога `.билд` (это тоже билд).
# ⚠️ Phoenix сравнивает ПОДСТРОКОЙ имени ключа и значения `имя=`: `b` скрывает и
# `ability`, `bonus`, и значение, где есть `b=`, — цена принята, это только лог.
# Строка запроса пути не печатает вовсе (`BuildCalculatorWeb.RequestLog`), остальное
# ловит `BuildCalculatorWeb.LogRedaction`.
config :phoenix, :filter_parameters, ["password", "b", "code", "key", "token", "text"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Интерфейс по умолчанию русский (CLAUDE.md §4), поэтому и локаль gettext — ru.
# Настройка адресована ровно этому бэкенду, а не всему приложению `:gettext`:
# глобальный `config :gettext, :default_locale` перебил бы локаль и у зависимостей.
#
# ⚠️ С задачи 4.2 это только ЗАПАСНАЯ локаль процесса, которому никто не назвал
# язык. Язык страницы решает редакция (`:editions` → `locale` выше):
# `BuildCalculatorWeb.Locale` ставит его plug'ом в пайплайне `:browser`
# и `on_mount` в каждом `live_session` (у LiveView свой процесс).
# 🔴 Переносить эту строку в `runtime.exs` НЕЛЬЗЯ: бэкенд читает её через
# `Application.compile_env`, и значение в рантайме, отличное от собранного,
# роняет запуск релиза (VANILLA.md §3.5).
config :build_calculator, BuildCalculatorWeb.Gettext, default_locale: "ru"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
