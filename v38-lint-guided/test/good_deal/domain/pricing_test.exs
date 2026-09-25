defmodule GoodDeal.Domain.PricingTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.Pricing

  describe "line_total/2" do
    test "multiplies unit amount by quantity" do
      assert Pricing.line_total(1000, 3) == 3000
    end

    test "handles zero quantity" do
      assert Pricing.line_total(500, 0) == 0
    end
  end

  describe "cart_total/1" do
    test "sums line totals across items" do
      items = [
        %{product: %{amount: 1000}, quantity: 2},
        %{product: %{amount: 2500}, quantity: 1}
      ]

      total = Pricing.cart_total(items)
      assert total == Money.new(4500)
    end

    test "returns zero for empty cart" do
      assert Pricing.cart_total([]) == Money.new(0)
    end
  end

  describe "validate_promo/2" do
    @codes %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}

    test "recognizes SAVE10 against the supplied codes" do
      assert Pricing.validate_promo("SAVE10", @codes) == {:ok, 10}
    end

    test "is case-insensitive" do
      assert Pricing.validate_promo("save20", @codes) == {:ok, 20}
    end

    test "rejects unknown codes" do
      assert Pricing.validate_promo("BOGUS", @codes) == {:error, :invalid_code}
    end
  end

  describe "discounted_total/2" do
    test "no discount when percentage is nil" do
      items = [%{product: %{amount: 1000}, quantity: 2}]
      assert Pricing.discounted_total(items, nil) == {Money.new(2000), Money.new(0)}
    end

    test "applies percentage discount" do
      items = [%{product: %{amount: 1000}, quantity: 2}]
      assert Pricing.discounted_total(items, 10) == {Money.new(1800), Money.new(200)}
    end
  end

  describe "item_count/1" do
    test "sums quantities" do
      items = [%{quantity: 2}, %{quantity: 3}]
      assert Pricing.item_count(items) == 5
    end
  end

  describe "gift_wrap_total/2" do
    test "multiplies item count by the supplied per-item fee" do
      assert Pricing.gift_wrap_total(3, 299) == 897
    end

    test "is zero for an empty cart" do
      assert Pricing.gift_wrap_total(0, 299) == 0
    end
  end
end
