defmodule ZeroCoupled.DomainTest do
  @moduledoc "Covers the single-function domain abstractions (the ALA Lego bricks)."
  use ExUnit.Case, async: true

  import ZeroCoupled.CartFixtures

  alias ZeroCoupled.Domain.{
    CalculateSubtotal,
    ApplyDiscount,
    CalculateShipping,
    CalculateGiftWrapCost,
    CheckStock,
    ItemCount,
    ValidateCheckout,
    ValidatePromo,
    BuildLineItems,
    StockStatus,
    ShippingInfo
  }

  test "CalculateSubtotal sums amount × quantity" do
    assert CalculateSubtotal.call([line_item(1, amount: 1000, quantity: 2)]) == 2000
    assert CalculateSubtotal.call([]) == 0
  end

  test "ApplyDiscount returns {after, discount}" do
    assert ApplyDiscount.call(1000, 10) == {900, 100}
    assert ApplyDiscount.call(1000, nil) == {1000, 0}
    assert ApplyDiscount.call(1000, 0) == {1000, 0}
  end

  test "CalculateShipping honours free thresholds and per-method costs" do
    assert CalculateShipping.call(:standard, 0) == 0
    assert CalculateShipping.call(:standard, 100) == 599
    assert CalculateShipping.call(:standard, 5000) == 0
    assert CalculateShipping.call(:express, 100) == 1299
  end

  test "CalculateGiftWrapCost is per item" do
    assert CalculateGiftWrapCost.call(0) == 0
    assert CalculateGiftWrapCost.call(3) == 897
  end

  test "CheckStock compares quantities to stock levels" do
    items = [line_item(1, product_id: 7, quantity: 2)]
    assert CheckStock.call(items, %{7 => 5}) == :ok
    assert CheckStock.call(items, %{7 => 1}) == {:error, :out_of_stock}
  end

  test "ItemCount totals quantities" do
    assert ItemCount.call([line_item(1, quantity: 2), line_item(2, quantity: 3)]) == 5
  end

  test "ValidateCheckout rejects an empty cart" do
    assert ValidateCheckout.call([]) == {:error, :empty_cart}
    assert {:ok, [_]} = ValidateCheckout.call([line_item(1)])
  end

  test "ValidatePromo normalises and validates codes" do
    assert ValidatePromo.call("save10") == {:ok, 10}
    assert ValidatePromo.call("  HALF ") == {:ok, 50}
    assert ValidatePromo.call("nope") == {:error, :invalid_code}
    assert ValidatePromo.call(nil) == {:error, :invalid_code}
  end

  test "BuildLineItems shapes payment items" do
    assert [item] = BuildLineItems.call([line_item(1, amount: 1000, quantity: 2)])
    assert item.unit_amount == 1000 and item.quantity == 2 and item.currency == "usd"
  end

  test "StockStatus classifies levels" do
    assert StockStatus.call(0) == :out_of_stock
    assert StockStatus.call(3) == :low_stock
    assert StockStatus.call(50) == :in_stock
  end

  test "ShippingInfo exposes method metadata" do
    assert ShippingInfo.method_names() == [:standard, :express, :overnight]
    assert ShippingInfo.label(:express) =~ "Express"
  end
end
