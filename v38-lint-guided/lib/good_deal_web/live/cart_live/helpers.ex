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

  @doc "A displayed cart row: the stored line plus the flags the page shows beside it."
  def row(item, cart, wishlist_ids) do
    %{
      id: item.id,
      product: item.product,
      quantity: item.quantity,
      gift_wrapped: MapSet.member?(cart.gift_wrapped, item.id),
      wishlisted: item.product.id in wishlist_ids
    }
  end

  def toggle(set, id),
    do: if(MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id))
end
