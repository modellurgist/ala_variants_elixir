defmodule ZeroCoupled.CartFixtures do
  @moduledoc """
  In-memory fixtures for the pure functional core.

  No database, no Ecto — just plain maps shaped like cart items and
  products. This is what makes the core's tests pleasant: build a
  cart item in one line and call a pure function.
  """

  @doc "A cart line item. `id` is the line id; `product_id` defaults to it."
  def line_item(id, opts \\ []) do
    product_id = Keyword.get(opts, :product_id, id)

    %{
      id: id,
      quantity: Keyword.get(opts, :quantity, 1),
      product: product(product_id, opts)
    }
  end

  @doc "A product."
  def product(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Product #{id}"),
      description: Keyword.get(opts, :description, "A fine product"),
      amount: Keyword.get(opts, :amount, 1000),
      stock: Keyword.get(opts, :stock, 10),
      thumbnail: Keyword.get(opts, :thumbnail, "p#{id}.png")
    }
  end
end
