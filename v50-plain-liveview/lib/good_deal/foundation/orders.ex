defmodule GoodDeal.Foundation.Orders do
  @moduledoc """
  Foundation-layer persistence for orders.
  """

  alias GoodDeal.Repo
  alias GoodDeal.Foundation.Schemas.Order
  alias GoodDeal.Foundation.Carts

  @doc """
  Record the order for a cart, whose lines are what `Carts.list_items/1` reads: a held removal is
  made final first, and a saved line stays with the cart, outside the order.
  """
  @spec create(integer()) :: {:ok, Order.t()} | {:error, Ecto.Changeset.t()}
  def create(cart_id) do
    Carts.finalize_holds(cart_id)
    cart = Carts.get(cart_id)
    {:ok, _} = Carts.complete(cart)
    Repo.insert(%Order{cart_id: cart_id})
  end
end
