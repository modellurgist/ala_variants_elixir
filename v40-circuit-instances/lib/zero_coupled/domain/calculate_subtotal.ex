defmodule ZeroCoupled.Domain.CalculateSubtotal do
  @moduledoc "Single-function domain abstraction: cart subtotal from items."

  @spec call([%{product: %{amount: integer()}, quantity: integer()}]) :: integer()
  def call(items) do
    items
    |> Enum.map(fn item -> item.product.amount * item.quantity end)
    |> Enum.sum()
  end
end
