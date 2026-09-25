defmodule ZeroCoupled.Foundation.Orders do
  @moduledoc """
  Foundation-layer persistence for orders.
  """

  alias ZeroCoupled.Repo
  alias ZeroCoupled.Foundation.Schemas.Order
  alias ZeroCoupled.Foundation.Carts

  @spec create(integer()) :: {:ok, Order.t()} | {:error, Ecto.Changeset.t()}
  def create(cart_id) do
    cart = Carts.get(cart_id)
    {:ok, _} = Carts.complete(cart)
    Repo.insert(%Order{cart_id: cart_id})
  end
end
