defmodule ZeroCoupled.Actions.SaveProduct do
  @moduledoc """
  Application-layer action: create or update a product, then broadcast
  the fact so any live pages can update. Returns a domain result; the
  page's wiring delivers it to the form's state.
  """

  alias ZeroCoupled.Foundation.{Products, Broadcast}

  @spec run(:new, map()) :: {:ok, term()} | {:error, Ecto.Changeset.t()}
  def run(:new, attrs) do
    with {:ok, product} <- Products.insert(attrs) do
      Broadcast.product_saved(product)
      {:ok, product}
    end
  end

  @spec run(:edit, term(), map()) :: {:ok, term()} | {:error, Ecto.Changeset.t()}
  def run(:edit, product, attrs) do
    with {:ok, product} <- Products.update(product, attrs) do
      Broadcast.product_saved(product)
      {:ok, product}
    end
  end

  @doc "Save a form's request, `{action, product, attrs}`, the shape `RecordEdit` sends."
  def save({:new, _product, attrs}), do: run(:new, attrs)
  def save({:edit, product, attrs}), do: run(:edit, product, attrs)
end
