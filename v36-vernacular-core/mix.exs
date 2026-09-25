defmodule Shop.MixProject do
  use Mix.Project

  def project do
    [app: :shop, version: "0.1.0", elixir: "~> 1.15", elixirc_paths: paths(Mix.env()), deps: []]
  end

  def application, do: [extra_applications: [:logger]]
  defp paths(:test), do: ["lib", "test/support"]
  defp paths(_), do: ["lib"]
end
