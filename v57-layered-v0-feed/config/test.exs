import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :good_deal, GoodDeal.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "good_deal_v57_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :good_deal, GoodDealWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ymL1NhSE3YV1hcguJOpmB9IBn5OfbQnxVMK9fKA4YCJHkIuC7DhQ/J6fNwT914t8",
  server: false

# In test we don't send emails
config :good_deal, GoodDeal.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :good_deal, :payment_provider, GoodDeal.Payments.MockProvider
config :good_deal, :undo_window_ms, 1_000
