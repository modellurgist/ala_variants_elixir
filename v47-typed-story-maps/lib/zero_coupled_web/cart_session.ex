defmodule ZeroCoupledWeb.CartSession do
  @moduledoc "The session keys under which the storefront cart and the portal's order draft live."
  def cart_key, do: "cart_id"
  def portal_key, do: "portal_cart_id"
end
