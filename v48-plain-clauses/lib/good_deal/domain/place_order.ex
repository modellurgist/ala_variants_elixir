defmodule GoodDeal.Domain.PlaceOrder do
  @moduledoc "Records the order for a cart and answers its id, through the orders store it is configured with. Config: `orders`, `cart_id`."
  defstruct [:orders, :cart_id]

  def place(%__MODULE__{orders: orders, cart_id: cart_id}, _approved) do
    {:ok, order} = orders.create(cart_id)
    order.id
  end
end
