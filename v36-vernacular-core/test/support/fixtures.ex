defmodule Shop.Fixtures do
  @moduledoc "Plain in-memory fixtures — no DB, no framework."
  def product(id, opts \\ []),
    do: %{id: id, name: opts[:name] || "Product #{id}", amount: opts[:amount] || 1000, thumbnail: "p#{id}.png"}

  def line_item(id, opts \\ []),
    do: %{id: id, quantity: opts[:quantity] || 1, product: product(opts[:product_id] || id, opts)}
end
