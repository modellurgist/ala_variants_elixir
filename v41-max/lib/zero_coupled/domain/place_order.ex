defmodule ZeroCoupled.Domain.PlaceOrder do
  @moduledoc """
  Records the order for a cart, doing its own I/O through the stores it is
  configured with. With `products` and `announce` configured it also takes the
  bought stock and announces each new level. Config: `orders`, and optionally
  `carts`, `products`, `announce` (a function of product id and stock).
  """
  defstruct [:orders, :carts, :products, :announce]

  @spec run(%__MODULE__{}, term()) :: {:ok, map()}
  def run(%__MODULE__{orders: orders} = p, cart_id) do
    {:ok, order} = orders.create(cart_id)
    take_stock(p, cart_id)
    {:ok, order}
  end

  defp take_stock(%__MODULE__{products: nil}, _cart_id), do: :ok

  defp take_stock(%__MODULE__{carts: carts, products: products, announce: announce}, cart_id) do
    for item <- carts.list_items(cart_id),
        {:ok, product} <- [products.decrement_stock(item.product.id, item.quantity)] do
      announce.(product.id, product.stock)
    end

    :ok
  end
end
