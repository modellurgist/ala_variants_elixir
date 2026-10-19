defmodule GoodDealWeb.CartSession do
  @moduledoc """
  `on_mount` hook assigning the session's storefront cart id and portal draft id.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:cart_id, session["cart_id"])
     |> assign(:portal_cart_id, session["portal_cart_id"])}
  end
end
