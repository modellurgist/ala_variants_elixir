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

  # V34: the abstractions are generic; the test supplies the rate/table data
  # the composition (manifest) would — the R3 test-coupling this variant trades
  # for tag-honesty.
  @rates %{standard: %{label: "Standard", cost: 599, free_above: 5000}, express: %{label: "Express", cost: 1299, free_above: nil}}

  test "CalculateShipping honours free thresholds and per-method costs" do
    assert CalculateShipping.call(:standard, 0, @rates) == 0
    assert CalculateShipping.call(:standard, 100, @rates) == 599
    assert CalculateShipping.call(:standard, 5000, @rates) == 0
    assert CalculateShipping.call(:express, 100, @rates) == 1299
  end

  test "CalculateGiftWrapCost is per item at the given unit cost" do
    assert CalculateGiftWrapCost.call(0, 299) == 0
    assert CalculateGiftWrapCost.call(3, 299) == 897
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

  test "ValidatePromo normalises and validates codes against the passed table" do
    table = %{"SAVE10" => 10, "HALF" => 50}
    assert ValidatePromo.call("save10", table) == {:ok, 10}
    assert ValidatePromo.call("  HALF ", table) == {:ok, 50}
    assert ValidatePromo.call("nope", table) == {:error, :invalid_code}
    assert ValidatePromo.call(nil, table) == {:error, :invalid_code}
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

  test "ShippingInfo exposes method metadata from the passed rate table" do
    assert Enum.sort(ShippingInfo.method_names(@rates)) == [:express, :standard]
    assert ShippingInfo.label(:express, @rates) =~ "Express"
  end
end
