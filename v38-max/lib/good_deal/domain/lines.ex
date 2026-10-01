defmodule GoodDeal.Domain.Lines do
  @moduledoc "Operations on a list of cart lines (`%{id, quantity, product}`), each returning the new list."

  @minimum 1

  def update_quantity(items, item_id, delta) do
    Enum.map(items, fn item ->
      if item.id == item_id,
        do: %{item | quantity: max(@minimum, item.quantity + delta)},
        else: item
    end)
  end

  @doc "Whether a line is at the smallest quantity it can have."
  def at_minimum?(%{quantity: quantity}), do: quantity <= @minimum

  def pop(items, item_id) do
    case Enum.split_with(items, &(&1.id == item_id)) do
      {[removed | _], remaining} -> {removed, remaining}
      {[], remaining} -> {nil, remaining}
    end
  end

  def set_stock(items, product_id, stock) do
    Enum.map(items, fn item ->
      if item.product.id == product_id,
        do: %{item | product: %{item.product | stock: stock}},
        else: item
    end)
  end
end
