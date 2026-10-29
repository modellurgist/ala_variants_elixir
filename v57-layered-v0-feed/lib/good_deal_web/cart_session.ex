defmodule GoodDealWeb.CartSession do
  @moduledoc """
  `on_mount` hook assigning the session's storefront `shop` and portal `portal_shop`.
  """
  import Phoenix.Component, only: [assign: 3]

  alias GoodDeal.Shop
  alias GoodDealWeb.Calibration

  # The router hands these to the EnsureCart plug.
  def cart_key, do: "cart_id"

  def portal_cart_key, do: "portal_cart_id"

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:shop, shop(:storefront, session[cart_key()]))
     |> assign(:portal_shop, shop(:portal, session[portal_cart_key()]))}
  end

  def shop(channel, cart_id), do: %Shop{channel: Calibration.channel(channel), cart_id: cart_id}
end
