defmodule GoodDeal.Domain.ProductFacts do
  @moduledoc """
  The facts that travel when a product changes, keyed by the product's id: `:stock` (its new level)
  and `:product` (the saved record, for lists that show whole products). Publisher and subscriber
  both use this one format through `ChangeFeed`, so they share only the product id.
  """

  def ports, do: %{in: [], out: [stock: :stock_change, product: :product]}

  def facts(product),
    do: [stock: %{product_id: product.id, stock: product.stock}, product: product]
end
