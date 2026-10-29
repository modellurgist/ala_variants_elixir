defmodule GoodDeal.Domain.PricingTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Catalog.Product
  alias GoodDeal.Domain.Pricing
  alias GoodDeal.ShoppingCart.CartItem

  defp item(amount, quantity, gift_wrap \\ false) do
    %CartItem{product: %Product{amount: amount}, quantity: quantity, gift_wrap: gift_wrap}
  end

  defp pricing(overrides \\ []) do
    struct!(
      %Pricing{discount: fn _ -> {0, nil} end, shipping: fn _ -> 7 end, shipping_label: "Post"},
      overrides
    )
  end

  test "sums lines and quantities and adds the configured shipping" do
    assert %{item_count: 3, subtotal: 250, shipping: 7, shipping_label: "Post", total: 257} =
             Pricing.summary(pricing(), [item(100, 2), item(50, 1)])

    assert Pricing.line_total(item(100, 2)) == 200
  end

  test "applies the configured discount percent to the subtotal it is given" do
    discount = fn subtotal -> if subtotal >= 200, do: {25, "quarter"}, else: {0, nil} end

    assert %{discount: 50, discount_label: "quarter", total: 157} =
             Pricing.summary(pricing(discount: discount), [item(200, 1)])

    assert %{discount: 0, discount_label: nil} =
             Pricing.summary(pricing(discount: discount), [item(199, 1)])
  end

  test "charges the gift-wrap price per wrapped line, nothing by default" do
    items = [item(100, 4, true), item(100, 1)]
    assert Pricing.summary(pricing(gift_wrap_price: 10), items).gift_wrap == 10
    assert Pricing.summary(pricing(), items).gift_wrap == 0
  end

  test "shipping sees the subtotal" do
    shipping = fn subtotal -> if subtotal > 100, do: 0, else: 9 end
    assert Pricing.summary(pricing(shipping: shipping), [item(101, 1)]).shipping == 0
    assert Pricing.summary(pricing(shipping: shipping), [item(100, 1)]).shipping == 9
  end
end
