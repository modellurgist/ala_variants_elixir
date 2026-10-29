defmodule GoodDeal.Actions.SaveProduct do
  @moduledoc """
  Application-layer action: creates or updates a product.

  Returns a domain result; the caller maps it to framework effects, publishing included.
  """

  alias GoodDeal.Foundation.Products

  @doc "Save a form's request, `{action, product, attrs}`, the shape `RecordEdit` sends."
  @spec save({:new | :edit, term(), map()}) :: {:ok, term()} | {:error, Ecto.Changeset.t()}
  def save({:new, _product, attrs}), do: Products.insert(attrs)
  def save({:edit, product, attrs}), do: Products.update(product, attrs)
end
