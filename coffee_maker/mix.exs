defmodule CoffeeMaker.MixProject do
  use Mix.Project

  # The coffee-maker ALA domain, extracted from the ala_lab study as a
  # dependency-free library. The LiveView that drives it in a Phoenix app is
  # kept under `reference/` (not compiled here) because it needs a Phoenix host;
  # see the README.
  def project do
    [
      app: :coffee_maker,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: ["lib"],
      deps: []
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
