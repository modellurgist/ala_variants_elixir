defmodule GoodDeal.PaymentsTest do
  use GoodDeal.DataCase, async: true

  import Mox
  import GoodDeal.ShoppingCartFixtures

  alias GoodDeal.{Payments, ShoppingCart}
  alias GoodDeal.Payments.InProcessProvider

  setup :verify_on_exit!

  test "create_checkout_session/2 sends line items to the configured provider" do
    cart = cart_fixture()
    cart_item_fixture(cart, name: "Mug", amount: 1299, quantity: 2)

    expect(GoodDeal.Payments.MockProvider, :create_checkout_session, fn line_items, opts ->
      assert line_items == [%{name: "Mug", unit_price: 1299, quantity: 2}]
      assert opts[:success_url] == "http://shop/success"
      {:ok, "https://pay.example/session"}
    end)

    assert {:ok, "https://pay.example/session"} =
             Payments.create_checkout_session(
               ShoppingCart.list_cart_items(shop(:storefront, cart_id: cart.id)),
               success_url: "http://shop/success"
             )
  end

  test "the default in-process provider settles at once and returns the success URL" do
    assert {:ok, "http://shop/success"} =
             InProcessProvider.create_checkout_session([], success_url: "http://shop/success")
  end
end
