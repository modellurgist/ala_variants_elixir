defmodule GoodDeal.StoreFixtures do
  @moduledoc """
  Test helpers for creating entities via Foundation persistence modules.
  """

  alias GoodDeal.Foundation.{Products, Carts}

  def product_fixture(attrs \\ %{}) do
    {:ok, product} =
      attrs
      |> Enum.into(%{
        name: "some name",
        description: "some description",
        amount: 42,
        stock: 42,
        thumbnail: "some thumbnail"
      })
      |> Products.insert()

    product
  end

  def cart_fixture do
    {:ok, cart} = Carts.create()
    cart
  end

  def cart_with_items_fixture do
    cart = cart_fixture()
    product_a = product_fixture(%{name: "Widget", amount: 1000, stock: 10, thumbnail: "w.png"})
    product_b = product_fixture(%{name: "Gadget", amount: 2500, stock: 5, thumbnail: "g.png"})
    {:ok, _} = Carts.add_item(cart.id, product_a)
    {:ok, _} = Carts.add_item(cart.id, product_b)
    {cart, [product_a, product_b]}
  end

  def cart_with_many_items_fixture do
    cart = cart_fixture()
    product_a = product_fixture(%{name: "Widget", amount: 1000, stock: 10, thumbnail: "w.png"})
    product_b = product_fixture(%{name: "Gadget", amount: 2500, stock: 5, thumbnail: "g.png"})
    product_c = product_fixture(%{name: "Gizmo", amount: 5000, stock: 3, thumbnail: "z.png"})
    {:ok, _} = Carts.add_item(cart.id, product_a)
    {:ok, _} = Carts.add_item(cart.id, product_b)
    {:ok, _} = Carts.add_item(cart.id, product_c)
    {cart, [product_a, product_b, product_c]}
  end
end
