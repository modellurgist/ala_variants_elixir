defmodule GoodDealWeb.CartSession do
  @moduledoc """
  `on_mount` hook assigning the session's storefront cart id and portal draft id.
  """
  import Phoenix.Component, only: [assign: 3]

  # The router hands these to the EnsureCart plug.
  def cart_key, do: "cart_id"

  def portal_cart_key, do: "portal_cart_id"

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:cart_id, session[cart_key()])
     |> assign(:portal_cart_id, session[portal_cart_key()])}
  end
end
