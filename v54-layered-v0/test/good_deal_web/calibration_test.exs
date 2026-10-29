defmodule GoodDealWeb.CalibrationTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Catalog.Product
  alias GoodDeal.Domain.{Pricing, PromoCode, ShippingMethod, StockStatus}
  alias GoodDeal.ShoppingCart.{Cart, CartItem}
  alias GoodDealWeb.Calibration

  defp item(amount, quantity, gift_wrap \\ false) do
    %CartItem{product: %Product{amount: amount}, quantity: quantity, gift_wrap: gift_wrap}
  end

  defp cart(attrs), do: struct(Cart, Map.merge(Calibration.new_cart(), Map.new(attrs)))

  defp storefront(items, cart_attrs \\ []),
    do: Pricing.summary(Calibration.storefront_pricing(cart(cart_attrs)), items)

  defp portal(items, cart_attrs \\ []),
    do: Pricing.summary(Calibration.portal_pricing(cart(cart_attrs)), items)

  test "subtotal is the sum of unit price × quantity; total adds standard shipping" do
    summary = storefront([item(1000, 2), item(500, 1)])

    assert summary.item_count == 3
    assert summary.subtotal == 2500
    assert summary.discount == 0
    assert summary.gift_wrap == 0
    assert summary.shipping == 599
    assert summary.shipping_label == "Standard (5–7 days)"
    assert summary.total == 3099
  end

  test "an empty cart ships free" do
    assert %{subtotal: 0, shipping: 0, total: 0} = storefront([], shipping_method: "express")
  end

  test "standard shipping is free from 5000, other methods are not" do
    items = [item(5000, 1)]
    assert storefront(items, shipping_method: "standard").shipping == 0
    assert storefront(items, shipping_method: "express").shipping == 1299
    assert storefront(items, shipping_method: "overnight").shipping == 2499
    assert storefront([item(4999, 1)], shipping_method: "standard").shipping == 599
  end

  test "promo codes discount the subtotal by their percentage" do
    items = [item(3000, 1)]

    assert %{discount: 300, discount_label: "SAVE10"} = storefront(items, promo_code: "SAVE10")
    assert %{discount: 600} = storefront(items, promo_code: "SAVE20")
    assert %{discount: 1500, total: 2099} = storefront(items, promo_code: "HALF")
    assert %{discount: 0, discount_label: nil} = storefront(items, promo_code: "BOGUS")
  end

  test "gift wrap charges 299 per wrapped item on the storefront, not on the portal" do
    items = [item(1000, 3, true), item(1000, 1, true), item(1000, 1)]
    assert storefront(items).gift_wrap == 598
    assert portal(items).gift_wrap == 0
    assert Calibration.gift_wrap_price() == 299
  end

  test "total = subtotal − discount + gift wrap + shipping" do
    summary =
      storefront([item(2000, 1, true)], promo_code: "SAVE10", shipping_method: "express")

    assert summary.total == 2000 - 200 + 299 + 1299
  end

  test "volume tiers apply 5% from 50,000 and 10% from 200,000 on the portal" do
    assert %{discount: 0, discount_label: nil} = portal([item(49_999, 1)])

    assert %{discount: 2500, discount_label: "5% volume discount"} = portal([item(50_000, 1)])

    assert %{discount: 20_000, discount_label: "10% volume discount"} =
             portal([item(100_000, 2)])
  end

  test "lists the store's shipping methods and promo codes" do
    methods = Calibration.shipping_methods()
    assert Enum.map(methods, & &1.id) == ["standard", "express", "overnight"]
    assert ShippingMethod.find(methods, "express").label == "Express (2–3 days)"
    assert ShippingMethod.find(methods, "teleport") == nil
    assert PromoCode.valid?(Calibration.promo_codes(), "HALF")
    refute PromoCode.valid?(Calibration.promo_codes(), "half")
  end

  test "stock is out at 0, low at 5 or fewer, in stock above" do
    threshold = Calibration.low_stock_threshold()
    assert StockStatus.of(0, threshold) == :out_of_stock
    assert StockStatus.of(1, threshold) == :low_stock
    assert StockStatus.of(5, threshold) == :low_stock
    assert StockStatus.of(6, threshold) == :in_stock
  end
end
