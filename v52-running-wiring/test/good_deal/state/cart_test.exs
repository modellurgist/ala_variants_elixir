defmodule GoodDeal.State.CartTest do
  use ExUnit.Case, async: true

  import GoodDeal.CartFixtures
  alias GoodDeal.State.{CartLines, CartTotals, Promo}
  alias GoodDeal.Domain.{CalculateGiftWrapCost, CalculateShipping, StockStatus, ValidatePromo}

  @rates %{
    standard: %{label: "Standard", cost: 599, free_above: 5000},
    express: %{label: "Express", cost: 1299, free_above: nil}
  }

  defp lines(items) do
    {cart, _} =
      CartLines.new(cart_id: 1, stock_status: StockStatus.new(low_at: 5))
      |> CartLines.load(items)

    cart
  end

  defp totals,
    do:
      CartTotals.new(
        pricing: %{
          shipping: CalculateShipping.new(@rates),
          gift_wrap: CalculateGiftWrapCost.new(299)
        }
      )

  defp summary({_totals, outputs}), do: outputs[:summary]

  describe "CartLines" do
    test "loading resets the rows and sends the contents" do
      {_, outs} =
        CartLines.load(CartLines.new(cart_id: 1, stock_status: StockStatus.new(low_at: 5)), [
          line_item(1),
          line_item(2)
        ])

      assert {:reset, [%{id: 1}, %{id: 2}]} = outs[:rows]
      assert %{lines: [_, _], wrapped_count: 0} = outs[:contents]
    end

    test "a quantity changes by its delta, never below 1, and the change goes to the store" do
      {cart, outs} = CartLines.update_quantity(lines([line_item(1)]), %{item_id: 1, delta: 1})
      assert outs[:changed] == {:quantity, 1, 1, 2}
      {_, outs} = CartLines.update_quantity(cart, %{item_id: 1, delta: -5})
      assert {:changed, %{quantity: 1}} = outs[:rows]
    end

    test "an unknown line changes nothing" do
      assert {_, []} = CartLines.update_quantity(lines([line_item(1)]), %{item_id: 9, delta: 1})
      assert {_, []} = CartLines.remove(lines([]), %{item_id: 1})
      assert {_, []} = CartLines.toggle_gift_wrap(lines([]), %{item_id: 1})
    end

    test "a removed line leaves with its gift wrap" do
      {cart, _} = CartLines.toggle_gift_wrap(lines([line_item(1), line_item(2)]), %{item_id: 1})
      {_, outs} = CartLines.remove(cart, %{item_id: 1})
      assert %{id: 1} = outs[:removed]

      assert %{lines: [%{quantity: 1, product: %{amount: 1000}}], wrapped_count: 0} =
               outs[:contents]
    end

    test "saving a line for later sends it out as saved, not removed" do
      {_, outs} = CartLines.save_for_later(lines([line_item(1)]), %{item_id: 1})
      assert %{id: 1} = outs[:saved]
      refute Keyword.has_key?(outs, :removed)
    end

    test "receiving a line twice keeps one" do
      {cart, _} = CartLines.receive(lines([]), line_item(1))
      {_, outs} = CartLines.receive(cart, line_item(1))
      assert %{lines: [_]} = outs[:contents]
    end

    test "toggling gift wrap twice unwraps, and the row shows it" do
      {cart, outs} = CartLines.toggle_gift_wrap(lines([line_item(1)]), %{item_id: 1})
      assert {:changed, %{gift_wrapped: true}} = outs[:rows]
      assert outs[:contents].wrapped_count == 1
      {_, outs} = CartLines.toggle_gift_wrap(cart, %{item_id: 1})
      assert outs[:contents].wrapped_count == 0
    end

    test "a stock change shows on the product's line, and is ignored for one not in the cart" do
      cart = lines([line_item(1, product_id: 7, stock: 10)])

      assert {_, [rows: {:changed, %{stock_status: :low_stock}}]} =
               CartLines.set_stock(cart, %{product_id: 7, stock: 2})

      assert {_, []} = CartLines.set_stock(cart, %{product_id: 99, stock: 0})
    end

    test "checkout gets the cart's id and stored lines" do
      {_, outs} = CartLines.request_checkout(lines([line_item(1)]), nil)
      assert {1, [%{id: 1}]} = outs[:checkout_requested]
    end
  end

  describe "Promo" do
    test "a valid code is kept in normal form and its discount goes out" do
      promo = Promo.new(codes: ValidatePromo.new(%{"SAVE10" => 10}))
      {_, outs} = Promo.enter(promo, %{code: " save10 "})
      assert outs == [discount: %{code: "SAVE10", percentage: 10}, applied: "SAVE10"]
    end

    test "an invalid code is rejected, as is any code in a store with none" do
      promo = Promo.new(codes: ValidatePromo.new(%{"SAVE10" => 10}))
      assert {_, [rejected: "NOPE"]} = Promo.enter(promo, %{code: "NOPE"})
      assert {_, [rejected: "SAVE10"]} = Promo.enter(Promo.new([]), %{code: "SAVE10"})
    end
  end

  describe "CartTotals" do
    test "subtotal, item count and total with shipping" do
      s =
        summary(
          CartTotals.contents(totals(), %{
            lines: [line_item(1, amount: 1000, quantity: 2), line_item(2, amount: 500)],
            wrapped_count: 0
          })
        )

      assert s.subtotal == Money.new(2500)
      assert s.item_count == 3
      assert s.total == Money.new(2500 + 599)
    end

    test "an empty cart is free to ship and says it's empty" do
      s = summary(CartTotals.contents(totals(), %{lines: [], wrapped_count: 0}))
      assert s.empty?
      assert s.total == Money.new(0)
    end

    test "each wrapped line adds the gift wrap price" do
      s =
        summary(
          CartTotals.contents(totals(), %{lines: [line_item(1, amount: 6000)], wrapped_count: 2})
        )

      assert s.gift_wrap_total == Money.new(598)
      assert s.total == Money.new(6000 + 598)
    end

    test "a discount takes its percentage off the subtotal and names its code" do
      {t, _} =
        CartTotals.contents(totals(), %{lines: [line_item(1, amount: 1000)], wrapped_count: 0})

      s = summary(CartTotals.discount(t, %{code: "SAVE10", percentage: 10}))
      assert s.discount == Money.new(100)
      assert s.promo_code == "SAVE10"
    end

    test "choosing a shipping method reprices shipping" do
      {t, _} =
        CartTotals.contents(totals(), %{lines: [line_item(1, amount: 1000)], wrapped_count: 0})

      s = summary(CartTotals.select_shipping(t, %{method: :express}))
      assert s.shipping_method == :express
      assert s.shipping_cost == Money.new(1299)
    end

    test "starting checkout hands over the summary" do
      {t, _} = CartTotals.contents(totals(), %{lines: [line_item(1)], wrapped_count: 0})
      assert {_, [checkout_started: %{item_count: 1}]} = CartTotals.start_checkout(t, nil)
    end
  end
end
