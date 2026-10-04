defmodule BuildCalculator.Repo do
  use Ecto.Repo,
    otp_app: :build_calculator,
    adapter: Ecto.Adapters.Postgres
end
