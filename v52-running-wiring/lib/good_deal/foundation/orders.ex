defmodule GoodDeal.Foundation.Orders do
  @moduledoc """
  Foundation-layer persistence for orders.
  """

  alias GoodDeal.Repo
  alias GoodDeal.Foundation.Schemas.Order
  alias GoodDeal.Foundation.Carts

  @spec create(integer()) :: {:ok, Order.t()} | {:error, Ecto.Changeset.t()}
  def create(cart_id) do
    cart = Carts.get(cart_id)
    {:ok, _} = Carts.complete(cart)
    Repo.insert(%Order{cart_id: cart_id})
  end
end
