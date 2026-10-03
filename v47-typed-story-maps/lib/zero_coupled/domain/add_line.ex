defmodule ZeroCoupled.Domain.AddLine do
  @moduledoc """
  Puts a product into a stored cart and returns the stored line, doing its own
  I/O through the stores it is configured with. Config: `carts`, `products`, `cart_id`. Through
  the `Call` port, a product gives back its line, and `{product, quantity}` gives back
  `{line, quantity}`.
  """
  defstruct [:carts, :products, :cart_id]

  def run(%__MODULE__{carts: carts, products: products, cart_id: cart_id}, product) do
    carts.add_item(cart_id, products.get!(product.id))
    cart_id |> carts.list_items() |> Enum.find(&(&1.product.id == product.id))
  end

  defimpl ZeroCoupled.Ports.Call do
    alias ZeroCoupled.Domain.AddLine
    def call(a, {product, quantity}), do: {AddLine.run(a, product), quantity}
    def call(a, product), do: AddLine.run(a, product)
    def types(_), do: %{product: :item, product_quantity: :item_quantity}
  end
end
