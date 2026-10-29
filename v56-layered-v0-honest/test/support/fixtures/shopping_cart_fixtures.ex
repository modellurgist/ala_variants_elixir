defmodule GoodDeal.ShoppingCartFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `GoodDeal.ShoppingCart` context.
  """

  import GoodDeal.CatalogFixtures

  alias GoodDeal.ShoppingCart

  def shop(cart_id, channel \\ :storefront), do: GoodDealWeb.CartSession.shop(channel, cart_id)

  # Builds through the context's checked writes, so a fixture cart obeys the same guards.
  def cart_fixture(attrs \\ %{}) do
    Enum.reduce(attrs, ShoppingCart.get_or_create_open_cart(shop(nil)), fn
      {:promo_code, code}, cart -> ok!(ShoppingCart.apply_promo_code(shop(cart.id), code))
      {:status, status}, cart -> ok!(ShoppingCart.set_cart_status(cart, status))
    end)
  end

  defp ok!({:ok, value}), do: value

  def cart_item_fixture(cart, attrs \\ %{}) do
    {quantity, product_attrs} = Map.pop(Map.new(attrs), :quantity, 1)
    product = product_fixture(product_attrs)
    {:ok, item} = ShoppingCart.add_item(shop(cart.id), product.id, quantity)
    item
  end

  def address_attrs do
    %{name: "Ada Lovelace", line1: "1 Analytical Way", city: "London", postal_code: "N1 9GU"}
  end
end
