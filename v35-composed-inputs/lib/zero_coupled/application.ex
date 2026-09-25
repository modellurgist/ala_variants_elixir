defmodule ZeroCoupled.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      ZeroCoupledWeb.Telemetry,
      # Start the Ecto repository
      ZeroCoupled.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: ZeroCoupled.PubSub},
      # Start Finch
      {Finch, name: ZeroCoupled.Finch},
      # Start the Endpoint (http/https)
      ZeroCoupledWeb.Endpoint
      # Start a worker by calling: ZeroCoupled.Worker.start_link(arg)
      # {ZeroCoupled.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZeroCoupled.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ZeroCoupledWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
