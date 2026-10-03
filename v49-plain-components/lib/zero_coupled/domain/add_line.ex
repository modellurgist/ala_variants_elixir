defmodule ZeroCoupled.Domain.AddLine do
  @moduledoc """
  Puts a product into a stored cart and returns the stored line, doing its own
  I/O through the stores it is configured with. Config: `carts`, `products`, `cart_id`.
  """
  defstruct [:carts, :products, :cart_id]

  @doc "Given `{product, quantity}`, the stored line with the quantity, for whoever sets it."
  def run(%__MODULE__{} = a, {product, quantity}), do: {run(a, product), quantity}

  def run(%__MODULE__{carts: carts, products: products, cart_id: cart_id}, product) do
    carts.add_item(cart_id, products.get!(product.id))
    cart_id |> carts.list_items() |> Enum.find(&(&1.product.id == product.id))
  end
end
