defmodule ZeroCoupled.Domain.AddLine do
  @moduledoc """
  Puts a product into a stored cart and returns the stored line, doing its own I/O through the
  stores it is configured with. Config: `carts`, `products`, and `cart_id` when used as a circuit
  instance. As an instance: `add` a product, get the `line`; `add_with_quantity` a
  `{product, quantity}`, get `{line, quantity}`.
  """
  defstruct [:carts, :products, :cart_id]

  def run(%__MODULE__{carts: carts, products: products}, cart_id, product) do
    carts.add_item(cart_id, products.get!(product.id))
    cart_id |> carts.list_items() |> Enum.find(&(&1.product.id == product.id))
  end

  defimpl ZeroCoupled.Ports.Step do
    alias ZeroCoupled.Domain.AddLine

    def push(a, {:add, product}), do: {:emit, [line: AddLine.run(a, a.cart_id, product)], a}

    def push(a, {:add_with_quantity, {product, quantity}}),
      do: {:emit, [line_with_quantity: {AddLine.run(a, a.cart_id, product), quantity}], a}

    def ports(_),
      do: %{
        in: [add: :product, add_with_quantity: :product_quantity],
        out: [line: :item, line_with_quantity: :item_quantity]
      }

    def feeds(_), do: []
  end
end
