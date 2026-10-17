defmodule GoodDeal.Domain.SettleOrder do
  @moduledoc """
  Once a cart is paid: records the order, takes the bought stock, and announces each new level,
  doing its own I/O through the stores it is configured with. Config: `orders`, `carts`,
  `products`, `announce` (a function of product id and stock), `cart_id`.
  """
  defstruct [:orders, :carts, :products, :announce, :cart_id]

  def run(%__MODULE__{cart_id: cart_id} = s, _payment_reference) do
    {:ok, order} = s.orders.create(cart_id)

    for item <- s.carts.list_items(cart_id),
        {:ok, product} <- [s.products.decrement_stock(item.product.id, item.quantity)] do
      s.announce.(product.id, product.stock)
    end

    {:ok, order}
  end
end
