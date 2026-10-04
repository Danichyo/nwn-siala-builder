defmodule BuildCalculator.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Редакция (задача 4.2): проверить пресеты и отдать ядру ruleset
    # по умолчанию ДО того, как поднимется эндпоинт. Кривой пресет роняет
    # запуск здесь, а не первый запрос.
    :ok = BuildCalculatorWeb.Edition.configure!()

    # Задача 4.75: ни кода билда, ни самого билда в логе — первичный фильтр
    # `:logger` ставится до первого процесса приложения: отчёт о падении
    # любого из них (LiveView держит в состоянии весь билд) идёт уже через него.
    :ok = BuildCalculatorWeb.LogRedaction.install()

    # Задача 4.76: строка о подключении сокета — одна, без параметров клиента
    # (`BuildCalculatorWeb.SocketLog`); своя строка Phoenix выключена в эндпоинте.
    :ok = BuildCalculatorWeb.SocketLog.attach()

    children = [
      BuildCalculatorWeb.Telemetry,
      BuildCalculator.Repo,
      {DNSCluster, query: Application.get_env(:build_calculator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BuildCalculator.PubSub},
      # Аналитика (задача 4.54): соль дня — только в памяти, и задачи записи —
      # с потолком, чтобы отказ базы не копил процессы без конца
      # (`BuildCalculator.Analytics`). До эндпоинта: первый же визит их спросит.
      BuildCalculator.Analytics.Salt,
      # Задача 4.75: счётчики «не больше N за окно» — потолки строк аналитики
      # и новых коротких ссылок (`BuildCalculator.RateLimit`).
      BuildCalculator.RateLimit,
      {Task.Supervisor, name: BuildCalculator.Analytics.Tasks, max_children: 100},
      # Start a worker by calling: BuildCalculator.Worker.start_link(arg)
      # {BuildCalculator.Worker, arg},
      # Start to serve requests, typically the last entry
      BuildCalculatorWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BuildCalculator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BuildCalculatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
