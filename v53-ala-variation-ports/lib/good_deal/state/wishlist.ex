defmodule GoodDeal.State.Wishlist do
  @moduledoc "Products the shopper wants to remember, and the rows that show them."
  defstruct products: []

  def new(_opts), do: %__MODULE__{}
  def count(%__MODULE__{products: p}), do: length(p)
  def ids(%__MODULE__{products: p}), do: Enum.map(p, & &1.id)

  @doc """
  Toggle a cart line's product: `{wishlist, {:added | :removed, product}}`, or `{wishlist, nil}` for
  a nil line (nothing selected).
  """
  def toggle(%__MODULE__{} = w, nil), do: {w, nil}

  def toggle(%__MODULE__{} = w, %{product: product}) do
    case remove(w, product.id) do
      {w, nil} -> {%{w | products: w.products ++ [product]}, {:added, product}}
      {w, product} -> {w, {:removed, product}}
    end
  end

  @doc "Forget a product: `{wishlist, product}`, or `{wishlist, nil}` if it isn't here."
  def remove(%__MODULE__{} = w, product_id) do
    case Enum.split_with(w.products, &(&1.id == product_id)) do
      {[product], rest} -> {%{w | products: rest}, product}
      _ -> {w, nil}
    end
  end

  def row(product),
    do: %{
      id: product.id,
      product: %{thumbnail: product.thumbnail, name: product.name, amount: product.amount}
    }
end
