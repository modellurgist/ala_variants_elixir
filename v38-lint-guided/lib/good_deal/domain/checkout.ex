defmodule GoodDeal.Domain.Checkout do
  @moduledoc """
  Domain abstraction for checkout preparation and validation.
  Pure functions — transforms cart items into payment gateway line items.
  Knows nothing about the payment provider, Ecto, or LiveView.
  """

  @type line_item :: %{
          name: String.t(),
          description: String.t(),
          image_url: String.t(),
          unit_amount: integer(),
          currency: String.t(),
          quantity: integer()
        }

  @spec validate([term()]) :: {:ok, [term()]} | {:error, :empty_cart}
  def validate([]), do: {:error, :empty_cart}
  def validate(items) when is_list(items), do: {:ok, items}

  @spec prepare_line_items([%{product: map(), quantity: integer()}]) :: [line_item()]
  def prepare_line_items(cart_items) do
    Enum.map(cart_items, fn item ->
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
