defmodule GoodDeal.ShoppingCart.PricingTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Catalog.Product
  alias GoodDeal.ShoppingCart.{CartItem, Pricing}

  defp item(amount, quantity, gift_wrap \\ false) do
    %CartItem{product: %Product{amount: amount}, quantity: quantity, gift_wrap: gift_wrap}
  end

  test "subtotal is the sum of unit price × quantity; total adds standard shipping" do
    summary = Pricing.summary([item(1000, 2), item(500, 1)])

    assert summary.item_count == 3
    assert summary.subtotal == 2500
    assert summary.discount == 0
    assert summary.gift_wrap == 0
    assert summary.shipping == 599
    assert summary.shipping_label == "Standard (5–7 days)"
    assert summary.total == 3099
  end

  test "an empty cart ships free" do
    assert %{subtotal: 0, shipping: 0, total: 0} = Pricing.summary([], shipping_method: "express")
  end

  test "standard shipping is free from 5000, other methods are not" do
    items = [item(5000, 1)]
    assert Pricing.summary(items, shipping_method: "standard").shipping == 0
    assert Pricing.summary(items, shipping_method: "express").shipping == 1299
    assert Pricing.summary(items, shipping_method: "overnight").shipping == 2499
    assert Pricing.summary([item(4999, 1)], shipping_method: "standard").shipping == 599
  end

  test "promo codes discount the subtotal by their percentage" do
    items = [item(3000, 1)]

    assert %{discount: 300, discount_label: "SAVE10"} =
             Pricing.summary(items, promo_code: "SAVE10")

    assert %{discount: 600} = Pricing.summary(items, promo_code: "SAVE20")
    assert %{discount: 1500, total: 2099} = Pricing.summary(items, promo_code: "HALF")
    assert %{discount: 0, discount_label: nil} = Pricing.summary(items, promo_code: "BOGUS")
  end

  test "gift wrap charges 299 per wrapped item when enabled" do
    items = [item(1000, 3, true), item(1000, 1, true), item(1000, 1)]
    assert Pricing.summary(items, gift_wrap: true).gift_wrap == 598
    assert Pricing.summary(items).gift_wrap == 0
    assert Pricing.gift_wrap_price() == 299
  end

  test "total = subtotal − discount + gift wrap + shipping" do
    summary =
      Pricing.summary([item(2000, 1, true)],
        promo_code: "SAVE10",
        gift_wrap: true,
        shipping_method: "express"
      )

    assert summary.total == 2000 - 200 + 299 + 1299
  end

  test "volume tiers apply 5% from 50,000 and 10% from 200,000" do
    opts = [volume_pricing: true]
    assert %{discount: 0, discount_label: nil} = Pricing.summary([item(49_999, 1)], opts)

    assert %{discount: 2500, discount_label: "5% volume discount"} =
             Pricing.summary([item(50_000, 1)], opts)

    assert %{discount: 20_000, discount_label: "10% volume discount"} =
             Pricing.summary([item(100_000, 2)], opts)
  end

  test "lists the store's shipping methods and promo codes" do
    assert Enum.map(Pricing.shipping_methods(), & &1.id) == ["standard", "express", "overnight"]
    assert Pricing.shipping_method("express").label == "Express (2–3 days)"
    assert Pricing.shipping_method("teleport") == nil
    assert Pricing.valid_promo_code?("HALF")
    refute Pricing.valid_promo_code?("half")
  end
end
