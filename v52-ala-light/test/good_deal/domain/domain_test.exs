defmodule GoodDeal.DomainTest do
  @moduledoc "Covers the single-function domain abstractions (the ALA Lego bricks)."
  use ExUnit.Case, async: true

  import GoodDeal.CartFixtures

  alias GoodDeal.Domain.{
    CalculateSubtotal,
    ApplyDiscount,
    CalculateShipping,
    CheckStock,
    ItemCount,
    ValidateCheckout,
    BuildLineItems,
    StockStatus
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

  # The abstractions are generic and configured once; the test plays the
  # composition and configures each instance.
  @rates %{
    standard: %{label: "Standard", cost: 599, free_above: 5000},
    express: %{label: "Express", cost: 1299, free_above: nil}
  }

  test "CalculateShipping honours free thresholds and per-method costs" do
    shipping = CalculateShipping.new(@rates)
    assert CalculateShipping.call(shipping, :standard, 0) == 0
    assert CalculateShipping.call(shipping, :standard, 100) == 599
    assert CalculateShipping.call(shipping, :standard, 5000) == 0
    assert CalculateShipping.call(shipping, :express, 100) == 1299
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

  test "BuildLineItems shapes payment items" do
    assert [item] =
             BuildLineItems.call(BuildLineItems.new(currency: "usd"), [
               line_item(1, amount: 1000, quantity: 2)
             ])

    assert item.unit_amount == 1000 and item.quantity == 2 and item.currency == "usd"
  end

  test "StockStatus classifies levels" do
    rule = StockStatus.new(low_at: 5)
    assert StockStatus.call(rule, 0) == :out_of_stock
    assert StockStatus.call(rule, 3) == :low_stock
    assert StockStatus.call(rule, 50) == :in_stock
  end

  test "CalculateShipping offers its configured methods and labels" do
    shipping = CalculateShipping.new(@rates)

    assert shipping |> CalculateShipping.options() |> Enum.map(& &1.method) |> Enum.sort() == [
             :express,
             :standard
           ]

    assert CalculateShipping.label(shipping, :express) =~ "Express"
  end
end
