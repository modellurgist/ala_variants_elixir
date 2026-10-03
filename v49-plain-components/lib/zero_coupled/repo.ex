defmodule ZeroCoupled.Repo do
  use Ecto.Repo,
    otp_app: :zero_coupled,
    adapter: Ecto.Adapters.Postgres
end
