defmodule GoodDealWeb.CartLive.Helpers do
  @moduledoc false

  def update_item_quantity(items, item_id, delta) do
    Enum.map(items, fn item ->
      if item.id == item_id,
        do: %{item | quantity: max(1, item.quantity + delta)},
        else: item
    end)
  end

  def pop_item(items, item_id) do
    case Enum.split_with(items, &(&1.id == item_id)) do
      {[removed | _], remaining} -> {removed, remaining}
      {[], remaining} -> {nil, remaining}
    end
  end

  def update_product_stock(items, product_id, new_stock) do
    Enum.map(items, fn item ->
      if item.product.id == product_id,
        do: %{item | product: %{item.product | stock: new_stock}},
        else: item
    end)
  end
end
