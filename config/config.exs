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
config :build_calculator, :accounts_ui, false

# ⚠️ Импорт билда из текста спрятан из ИНТЕРФЕЙСА — задача 3.89, решение Dan
# 24.08.2026: «спрятать импорт, импортировать билды к нам никто не будет,
# а вот экспорт может пригодиться — сбилдил и сохранил в текстовом виде на
# всякий случай». Экспорт этим флагом не задет и остаётся видимым целиком.
#
# `BuildCalculatorWeb.Builder.Import` остаётся рабочим модулем, не удалённым
# кодом: на нём стоит план проверки ванильных чисел через эталонные билды
# NWN-комьюнити (`docs/VANILLA_SPLIT.md` §4, §7.4). Возврат кнопки и диалога —
# `true` в этой строке, без правки кода.
config :build_calculator, :import_ui, false

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
config :build_calculator, :guide_first, true

# Configure the endpoint
config :build_calculator, BuildCalculatorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
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

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Интерфейс по умолчанию русский (CLAUDE.md §4), поэтому и локаль gettext — ru.
# Настройка адресована ровно этому бэкенду, а не всему приложению `:gettext`:
# глобальный `config :gettext, :default_locale` перебил бы локаль и у зависимостей.
#
# `en` остаётся собранной и рабочей: `Gettext.put_locale("en")` возвращает
# английские сообщения, так что вопрос «только RU или RU/EN» (§9) этим не
# закрыт — только подготовлен.
config :build_calculator, BuildCalculatorWeb.Gettext, default_locale: "ru"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
