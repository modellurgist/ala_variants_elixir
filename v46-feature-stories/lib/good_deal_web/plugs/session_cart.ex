defmodule GoodDealWeb.Plugs.SessionCart do
  @moduledoc """
  Guarantees the connection carries a usable cart under one session key. On every
  request it asks the Carts context for an open cart id (reusing the session's when
  it is still open, minting one otherwise) and writes the result back. The router
  plugs it once per key: the storefront cart and the portal's draft.
  """
  @behaviour Plug

  alias GoodDeal.Foundation.Carts
  alias GoodDealWeb.CartSession

  @impl true
  def init(opts), do: Keyword.get(opts, :key, CartSession.cart_key())

  @impl true
  def call(conn, key) do
    cart_id = Carts.ensure_open(CartSession.current(conn, key))
    CartSession.put(conn, key, cart_id)
  end
end
