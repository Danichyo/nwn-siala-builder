import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :build_calculator, BuildCalculator.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "build_calculator_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  # 3.194 (12.09.2026): после перевода LiveView-тестов на `async: true` первый же
  # полный прогон уронил один тест из 4663 — `DBConnection.ConnectionError … request
  # was dropped from queue after 177ms` в `Ecto.Repo.Preloader` (он гонит предзагрузки
  # в `Task`, и две допущенные к одному владельцу-сандбоксу проверки встают в очередь
  # к ОДНОМУ соединению). Дефолт DBConnection — `queue_target` 50 мс / `queue_interval`
  # 1000 мс — рассчитан на прод, а не на 16 параллельных LiveView-монтирований при
  # загруженном на 100 % процессоре. Не гонка в приложении: тот же тест в одиночку
  # и в трёх прогонах агента зелёный. Поднято ожидание, не размер пула — узкое место
  # не число соединений, а очередь к соединению владельца.
  queue_target: 1_000,
  queue_interval: 5_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :build_calculator, BuildCalculatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7xo+wO+xkiDH/587pANIrpdvgzWvjpM6GH3epmOQJfbypvDB2EsXa4jnU/eylrkH",
  server: false

# In test we don't send emails
config :build_calculator, BuildCalculator.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
