defmodule GoodDeal.State.SavedItems do
  @moduledoc "Lines set aside for later, and the rows that show them."
  defstruct items: []

  @doc "Config: `items`, the stored saved lines."
  def new(opts), do: %__MODULE__{items: opts[:items] || []}
  def count(%__MODULE__{items: items}), do: length(items)
  def rows(%__MODULE__{items: items}), do: Enum.map(items, &row/1)

  def stash(%__MODULE__{} = saved, item) do
    if Enum.any?(saved.items, &(&1.id == item.id)),
      do: saved,
      else: %{saved | items: saved.items ++ [item]}
  end

  @doc "Take a line back out for the cart: `{saved, item}`, or `{saved, nil}` if it isn't here."
  def move_to_cart(%__MODULE__{} = saved, item_id) do
    case Enum.split_with(saved.items, &(&1.id == item_id)) do
      {[item], rest} -> {%{saved | items: rest}, item}
      _ -> {saved, nil}
    end
  end

  def row(item),
    do: %{
      id: item.id,
      product: %{
        thumbnail: item.product.thumbnail,
        name: item.product.name,
        amount: item.product.amount
      }
    }
end
