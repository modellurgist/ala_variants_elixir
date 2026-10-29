defmodule GoodDealWeb.Plugs.EnsureCart do
  @moduledoc """
  Makes sure the session holds the id of an open cart for the channel under the given key,
  creating a new cart on first visit or once the previous one is completed.
  """
  import Plug.Conn

  alias GoodDeal.ShoppingCart
  alias GoodDealWeb.CartSession

  def init(opts), do: {Keyword.fetch!(opts, :key), Keyword.fetch!(opts, :channel)}

  def call(conn, {key, channel}) do
    shop = CartSession.shop(channel, cart_id: get_session(conn, key))
    cart = ShoppingCart.get_or_create_open_cart(shop)
    put_session(conn, key, cart.id)
  end
end
