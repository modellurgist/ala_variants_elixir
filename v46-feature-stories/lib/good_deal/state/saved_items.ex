defmodule GoodDeal.State.SavedItems do
  @moduledoc """
  Lines set aside for later. Ports out: `:rows` (a change to the displayed saved lines),
  `:count`, and `:moved` (a line the shopper wants back in the cart).
  """
  defstruct items: []

  def ports,
    do: %{
      in: [stash: :item, move_to_cart: :event],
      out: [rows: :row_change, moved: :item, count: :count]
    }

  def new(_opts), do: %__MODULE__{}
  def count(%__MODULE__{items: items}), do: length(items)

  def stash(%__MODULE__{} = saved, item) do
    items =
      if Enum.any?(saved.items, &(&1.id == item.id)), do: saved.items, else: saved.items ++ [item]

    saved = %{saved | items: items}
    {saved, [rows: {:added, row(item)}, count: count(saved)]}
  end

  def move_to_cart(%__MODULE__{} = saved, %{item_id: item_id}) do
    case Enum.split_with(saved.items, &(&1.id == item_id)) do
      {[item], rest} ->
        saved = %{saved | items: rest}
        {saved, [rows: {:removed, row(item)}, moved: item, count: count(saved)]}

      _ ->
        {saved, []}
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
