defmodule ZeroCoupled.Domain.CalculateShipping do
  @moduledoc "Single-function domain abstraction: shipping cost by method and subtotal."

  @methods %{
    standard: %{cost: 599, free_above: 5000},
    express: %{cost: 1299, free_above: nil},
    overnight: %{cost: 2499, free_above: nil}
  }

  @spec call(atom(), integer()) :: integer()
  def call(_method, 0), do: 0

  def call(method, subtotal_cents) when subtotal_cents > 0 do
    info = Map.fetch!(@methods, method)

    case info[:free_above] do
      nil -> info.cost
      threshold when subtotal_cents >= threshold -> 0
      _ -> info.cost
    end
  end
end
