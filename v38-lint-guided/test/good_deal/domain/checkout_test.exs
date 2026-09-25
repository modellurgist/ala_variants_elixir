defmodule GoodDeal.Domain.CheckoutTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.Checkout

  describe "validate/1" do
    test "returns ok for non-empty cart" do
      items = [%{product: %{name: "Widget"}, quantity: 1}]
      assert {:ok, ^items} = Checkout.validate(items)
    end

    test "returns error for empty cart" do
      assert {:error, :empty_cart} = Checkout.validate([])
    end
  end

  describe "prepare_line_items/1" do
    test "transforms cart items to gateway-neutral line items" do
      cart_items = [
        %{product: %{name: "Widget", description: "A widget", thumbnail: "w.png", amount: 1000}, quantity: 2},
        %{product: %{name: "Gadget", description: "A gadget", thumbnail: "g.png", amount: 2500}, quantity: 1}
      ]

      line_items = Checkout.prepare_line_items(cart_items)

      assert [first, second] = line_items
      assert first.name == "Widget"
      assert first.unit_amount == 1000
      assert first.currency == "usd"
      assert first.quantity == 2
      assert first.image_url == "w.png"

      assert second.name == "Gadget"
      assert second.quantity == 1
    end
  end
end
