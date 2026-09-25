defmodule ZeroCoupled.Domain.ShippingInfo do
  @moduledoc "Single-function domain abstraction: shipping method metadata for display."

  @methods %{
    standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
    express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
    overnight: %{label: "Overnight", cost: 2499, free_above: nil}
  }

  @spec method_names() :: [atom()]
  def method_names, do: [:standard, :express, :overnight]

  @spec label(atom()) :: String.t()
  def label(method), do: @methods[method].label
end
