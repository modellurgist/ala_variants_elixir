defmodule GoodDeal.Actions.SaveProduct do
  @moduledoc """
  Application-layer action: creates or updates a product and broadcasts.

  Returns a domain result; the caller maps it to framework effects.
  """

  alias GoodDeal.Foundation.{Products, Broadcast}

  @spec run(:new, map()) :: {:ok, term()} | {:error, Ecto.Changeset.t()}
  def run(:new, attrs) do
    case Products.insert(attrs) do
      {:ok, product} ->
        Broadcast.notify(:product_created, product)
        {:ok, product}

      error ->
        error
    end
  end

  @spec run(:edit, term(), map()) :: {:ok, term()} | {:error, Ecto.Changeset.t()}
  def run(:edit, product, attrs) do
    case Products.update(product, attrs) do
      {:ok, product} ->
        Broadcast.notify(:product_updated, product)
        {:ok, product}

      error ->
        error
    end
  end
end
