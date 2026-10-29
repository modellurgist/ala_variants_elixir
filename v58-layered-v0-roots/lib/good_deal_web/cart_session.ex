defmodule GoodDealWeb.CartSession do
  @moduledoc """
  The session keys for each channel's cart, and the `%Shop{}` a page or plug builds from one.
  """

  alias GoodDeal.Shop
  alias GoodDealWeb.Calibration

  # The router hands these to the EnsureCart plug.
  def cart_key, do: "cart_id"

  def portal_cart_key, do: "portal_cart_id"

  def shop(channel, cart_id), do: %Shop{channel: Calibration.channel(channel), cart_id: cart_id}

  def session_shop(session, :storefront), do: shop(:storefront, session[cart_key()])
  def session_shop(session, :portal), do: shop(:portal, session[portal_cart_key()])
end
