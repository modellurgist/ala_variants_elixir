defmodule GoodDeal.Domain.ShippingTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.Shipping

  @methods [
    %{method: :standard, label: "Standard", cost: 599, free_above: 5000},
    %{method: :express, label: "Express", cost: 1299, free_above: nil}
  ]

  defp shipping, do: Shipping.new(@methods)

  describe "cost/3" do
    test "charges the tier's base cost below the free threshold" do
      assert Shipping.cost(shipping(), :standard, 4999) == 599
    end

    test "is free once the subtotal meets free_above" do
      assert Shipping.cost(shipping(), :standard, 5000) == 0
    end

    test "never free when free_above is nil" do
      assert Shipping.cost(shipping(), :express, 100_000) == 1299
    end

    test "no method selected costs nothing" do
      assert Shipping.cost(shipping(), nil, 4999) == 0
    end

    test "an unknown method costs nothing" do
      assert Shipping.cost(shipping(), :drone, 4999) == 0
    end

    test "an empty cart ships free" do
      assert Shipping.cost(shipping(), :standard, 0) == 0
    end
  end

  describe "options/1" do
    test "lists each tier with its amounts as money" do
      assert [standard, express] = Shipping.options(shipping())
      assert standard.cost == Money.new(599) and standard.free_above == Money.new(5000)
      assert express.label == "Express" and express.free_above == nil
    end
  end
end
