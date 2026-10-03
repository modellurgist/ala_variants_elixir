defmodule ZeroCoupled.Domain.PlaceOrder do
  @moduledoc """
  Records the order for a cart, doing its own I/O through the stores it is
  configured with. With `products` and `announce` configured it also takes the
  bought stock and announces each new level. Config: `orders`, and optionally
  `carts`, `products`, `announce` (a function of product id and stock), and `cart_id` when the
  wiring calls it: then any payload places the order and it answers with the order's id.
  """
  defstruct [:orders, :carts, :products, :announce, :cart_id]

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

  defimpl ZeroCoupled.Ports.Call do
    alias ZeroCoupled.Domain.PlaceOrder

    def call(p, _trigger) do
      {:ok, order} = PlaceOrder.run(p, p.cart_id)
      order.id
    end

    def types(_), do: %{url: :order_id, po: :order_id}
  end
end
