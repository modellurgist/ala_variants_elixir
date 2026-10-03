defmodule ZeroCoupled.State.Wishlist do
  @moduledoc """
  Products the shopper wants to remember. Ports out: `:rows` (a change to the displayed
  products), `:count`, `:ids` (the product ids, so a list can mark them), `:added` and
  `:dropped` (the product, after a toggle), and `:taken` (a product the shopper wants in the cart).
  """
  defstruct products: []

  def ports,
    do: %{
      in: [toggle: :line, remove: :event, take: :event],
      out: [
        rows: :row_change,
        added: :product,
        dropped: :product,
        taken: :product,
        count: :count,
        ids: :ids
      ]
    }

  def new(_opts), do: %__MODULE__{}
  def count(%__MODULE__{products: p}), do: length(p)
  def ids(%__MODULE__{products: p}), do: Enum.map(p, & &1.id)

  @doc "Toggle a cart line's product. A nil line (nothing selected) is a no-op."
  def toggle(%__MODULE__{} = w, nil), do: {w, []}

  def toggle(%__MODULE__{} = w, %{product: product}) do
    if Enum.any?(w.products, &(&1.id == product.id)) do
      w = %{w | products: Enum.reject(w.products, &(&1.id == product.id))}
      {w, [rows: {:removed, row(product)}, dropped: product] ++ counts(w)}
    else
      w = %{w | products: w.products ++ [product]}
      {w, [rows: {:added, row(product)}, added: product] ++ counts(w)}
    end
  end

  def remove(%__MODULE__{} = w, %{product_id: id}) do
    case take_product(w, id) do
      {nil, w} -> {w, []}
      {product, w} -> {w, [rows: {:removed, row(product)}] ++ counts(w)}
    end
  end

  @doc "The shopper wants this product in the cart: hand it over and forget it here."
  def take(%__MODULE__{} = w, %{product_id: id}) do
    case take_product(w, id) do
      {nil, w} -> {w, []}
      {product, w} -> {w, [rows: {:removed, row(product)}, taken: product] ++ counts(w)}
    end
  end

  defp take_product(w, id) do
    case Enum.split_with(w.products, &(&1.id == id)) do
      {[product], rest} -> {product, %{w | products: rest}}
      _ -> {nil, w}
    end
  end

  defp counts(w), do: [count: count(w), ids: ids(w)]

  def row(product),
    do: %{
      id: product.id,
      product: %{thumbnail: product.thumbnail, name: product.name, amount: product.amount}
    }
end
