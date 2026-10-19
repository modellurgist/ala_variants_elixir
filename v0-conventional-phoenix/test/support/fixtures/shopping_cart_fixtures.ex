defmodule GoodDeal.ShoppingCartFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `GoodDeal.ShoppingCart` context.
  """

  import GoodDeal.CatalogFixtures

  alias GoodDeal.ShoppingCart

  def cart_fixture(attrs \\ %{}) do
    {:ok, cart} = ShoppingCart.create_cart(attrs)
    cart
  end

  def cart_item_fixture(cart, attrs \\ %{}) do
    {quantity, product_attrs} = Map.pop(Map.new(attrs), :quantity, 1)
    product = product_fixture(product_attrs)
    {:ok, item} = ShoppingCart.add_item(cart.id, product.id, quantity)
    item
  end

  def address_attrs do
    %{name: "Ada Lovelace", line1: "1 Analytical Way", city: "London", postal_code: "N1 9GU"}
  end
end
