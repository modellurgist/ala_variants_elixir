defmodule GoodDealWeb.Plugs.EnsureCart do
  @moduledoc """
  Makes sure the session holds the id of an open cart under the given key,
  creating a new cart on first visit or once the previous one is completed.
  """
  import Plug.Conn

  alias GoodDeal.ShoppingCart
  alias GoodDealWeb.Calibration

  def init(opts), do: Keyword.fetch!(opts, :key)

  def call(conn, key) do
    cart = ShoppingCart.get_or_create_open_cart(get_session(conn, key), Calibration.new_cart())
    put_session(conn, key, cart.id)
  end
end
