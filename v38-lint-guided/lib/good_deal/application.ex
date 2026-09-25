defmodule GoodDeal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      GoodDealWeb.Telemetry,
      # Start the Ecto repository
      GoodDeal.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: GoodDeal.PubSub},
      # Start Finch
      {Finch, name: GoodDeal.Finch},
      # Start the Endpoint (http/https)
      GoodDealWeb.Endpoint
      # Start a worker by calling: GoodDeal.Worker.start_link(arg)
      # {GoodDeal.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GoodDeal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GoodDealWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
