defmodule Shop.Wishlist do
  @moduledoc "The wishlist feature — private struct, pure functions, no peer knowledge."
  alias Shop.Outcome

  defstruct products: []

  def new, do: %__MODULE__{}
  def member?(%__MODULE__{products: p}, id), do: Enum.any?(p, &(&1.id == id))
  def count(%__MODULE__{products: p}), do: length(p)

  @doc "Toggle a product (the composition hands us the product — we never read the cart)."
  def toggle(%__MODULE__{} = wl, product) do
    if member?(wl, product.id) do
      {%{wl | products: Enum.reject(wl.products, &(&1.id == product.id))},
       [Outcome.stream_delete(:wishlist, product), Outcome.flash(:info, "Removed from wishlist")]}
    else
      {%{wl | products: wl.products ++ [product]},
       [Outcome.stream_insert(:wishlist, product), Outcome.flash(:info, "Added to wishlist")]}
    end
  end

  def drop(%__MODULE__{} = wl, product_id) do
    case Enum.find(wl.products, &(&1.id == product_id)) do
      nil -> {wl, []}
      p -> {%{wl | products: Enum.reject(wl.products, &(&1.id == product_id))}, [Outcome.stream_delete(:wishlist, p)]}
    end
  end
end
