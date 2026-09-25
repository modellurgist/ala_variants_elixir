defmodule GoodDeal.Domain.ShippingTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.Shipping

  @methods [
    %{method: :standard, label: "Standard", cost: 599, free_above: 5000},
    %{method: :express, label: "Express", cost: 1299, free_above: nil}
  ]

  describe "cost/2" do
    test "charges the tier's base cost below the free threshold" do
      assert Shipping.cost(%{cost: 599, free_above: 5000}, 4999) == 599
    end

    test "is free once the subtotal meets free_above" do
      assert Shipping.cost(%{cost: 599, free_above: 5000}, 5000) == 0
    end

    test "never free when free_above is nil" do
      assert Shipping.cost(%{cost: 1299, free_above: nil}, 100_000) == 1299
    end

    test "no method selected costs nothing" do
      assert Shipping.cost(nil, 4999) == 0
    end

    test "an empty cart ships free" do
      assert Shipping.cost(%{cost: 599, free_above: 5000}, 0) == 0
    end
  end

  describe "find/2" do
    test "returns the tier map by name" do
      assert Shipping.find(@methods, :express).cost == 1299
    end

    test "nil when absent" do
      assert Shipping.find(@methods, :drone) == nil
    end
  end
end
