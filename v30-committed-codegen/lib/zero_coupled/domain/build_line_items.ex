defmodule ZeroCoupled.Domain.BuildLineItems do
  @moduledoc "Single-function domain abstraction: transform cart items into payment line items."

  @spec call([%{product: map(), quantity: integer()}]) :: [map()]
  def call(items) do
    Enum.map(items, fn item ->
      %{
        name: item.product.name,
        description: item.product.description,
        image_url: item.product.thumbnail,
        unit_amount: item.product.amount,
        currency: "usd",
        quantity: item.quantity
      }
    end)
  end
end
