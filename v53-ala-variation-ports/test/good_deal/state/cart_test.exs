defmodule GoodDeal.State.CartTest do
  use ExUnit.Case, async: true

  import GoodDeal.CartFixtures
  alias GoodDeal.State.{CartLines, CartTotals, Promo}
  alias GoodDeal.Domain.{CalculateShipping, StockStatus}

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
          gift_wrap: &(&1 * 299)
        }
      )

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

    test "a removed line is held in the store, and a line received back is kept" do
      {cart, outs} = CartLines.remove(lines([line_item(1)]), %{item_id: 1})
      assert outs[:changed] == {:aside, :held, 1, 1}
      {_, outs} = CartLines.receive(cart, line_item(1))
      assert outs[:changed] == {:kept, 1, 1}
    end

    test "saving a line for later sends it out as saved, not removed" do
      {_, outs} = CartLines.save_for_later(lines([line_item(1)]), %{item_id: 1})
      assert %{id: 1} = outs[:saved]
      assert outs[:changed] == {:aside, :saved, 1, 1}
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
    # the page's rule, as the cart page configures it: the code is looked up in normal form
    defp save10("SAVE10"), do: {:ok, 10}
    defp save10(_code), do: {:error, :invalid_code}

    test "a valid code answers its discount, with the code in normal form" do
      promo = Promo.new(codes: &save10(String.upcase(String.trim(&1))))
      assert Promo.enter(promo, " save10 ") == {:ok, %{code: "SAVE10", percentage: 10}}
    end

    test "an invalid code is rejected, as is any code in a store with none" do
      assert Promo.enter(Promo.new(codes: &save10/1), "NOPE") == :error
      assert Promo.enter(Promo.new([]), "SAVE10") == :error
    end
  end

  describe "CartTotals" do
    defp priced(lines, wrapped_count \\ 0),
      do: CartTotals.contents(totals(), %{lines: lines, wrapped_count: wrapped_count})

    test "subtotal, item count and total with shipping" do
      s =
        CartTotals.summary(
          priced([line_item(1, amount: 1000, quantity: 2), line_item(2, amount: 500)])
        )

      assert s.subtotal == Money.new(2500)
      assert s.item_count == 3
      assert s.total == Money.new(2500 + 599)
    end

    test "an empty cart is free to ship and says it's empty" do
      s = CartTotals.summary(priced([]))
      assert s.empty?
      assert s.total == Money.new(0)
    end

    test "each wrapped line adds the gift wrap price" do
      s = CartTotals.summary(priced([line_item(1, amount: 6000)], 2))
      assert s.gift_wrap_total == Money.new(598)
      assert s.total == Money.new(6000 + 598)
    end

    test "a discount takes its percentage off the subtotal and names its code" do
      t = priced([line_item(1, amount: 1000)])
      s = CartTotals.summary(CartTotals.discount(t, %{code: "SAVE10", percentage: 10}))
      assert s.discount == Money.new(100)
      assert s.promo_code == "SAVE10"
    end

    test "choosing a shipping method reprices shipping" do
      s =
        CartTotals.summary(
          CartTotals.select_shipping(priced([line_item(1, amount: 1000)]), :express)
        )

      assert s.shipping_method == :express
      assert s.shipping_cost == Money.new(1299)
    end
  end
end
