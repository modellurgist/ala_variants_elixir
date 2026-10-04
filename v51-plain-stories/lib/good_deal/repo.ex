defmodule GoodDeal.Repo do
  use Ecto.Repo,
    otp_app: :good_deal,
    adapter: Ecto.Adapters.Postgres
end
