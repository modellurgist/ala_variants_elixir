defmodule GoodDeal.ShoppingCartFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `GoodDeal.ShoppingCart` context.
  """

  import GoodDeal.CatalogFixtures

  alias GoodDeal.ShoppingCart

  def shop(cart_id, channel \\ :storefront), do: GoodDealWeb.CartSession.shop(channel, cart_id)

  def cart_fixture(attrs \\ %{}) do
    channel = GoodDealWeb.Calibration.channel(:storefront)

    {:ok, cart} =
      ShoppingCart.create_cart(
        Map.merge(%{shipping_method: channel.default_shipping_method}, attrs)
      )

    cart
  end

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
