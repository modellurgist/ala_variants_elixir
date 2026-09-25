defmodule FeaturesTest do
  @moduledoc "Each feature tested in isolation — the zero-coupling payoff (no peer, no framework)."
  use ExUnit.Case, async: true
  import Shop.Fixtures
  alias Shop.{Cart, Wishlist, Undo, Checkout, Pricing, Outcome}

  @pricing %{shipping: %{standard: %{cost: 599, free_above: 5000}}, promo: %{"SAVE10" => 10}, gift_wrap: 299}
  defp cart(items), do: Cart.new(items: items, pricing: @pricing)

  test "Pricing is generic and takes calibration as data" do
    assert Pricing.subtotal([%{unit_amount: 1000, quantity: 2}]) == 2000
    assert Pricing.discount(1000, 10) == {900, 100}
    assert Pricing.shipping(:standard, 100, %{standard: %{cost: 599, free_above: 5000}}) == 599
    assert Pricing.shipping(:standard, 6000, %{standard: %{cost: 599, free_above: 5000}}) == 0
    assert Pricing.promo("save10", %{"SAVE10" => 10}) == {:ok, 10}
  end

  test "Cart.remove_item returns the removed item and a stream-delete" do
    c = cart([line_item(1), line_item(2)])
    {c, removed, outs} = Cart.remove_item(c, 1)
    assert removed.id == 1
    assert Cart.find(c, 1) == nil
    assert Enum.any?(outs, &match?(%Outcome.StreamDelete{name: :cart}, &1))
  end

  test "Cart totals compose the domain calcs with injected pricing" do
    t = Cart.totals(cart([line_item(1, amount: 3000, quantity: 1)]))
    assert t.subtotal == 3000 and t.shipping == 599 and t.total == 3599
  end

  test "Wishlist toggles without any cart knowledge (gets a product value)" do
    {wl, outs} = Wishlist.toggle(Wishlist.new(), product(10))
    assert Wishlist.member?(wl, 10)
    assert Enum.any?(outs, &match?(%Outcome.StreamInsert{name: :wishlist}, &1))
  end

  test "Undo captures and restores, arming/cancelling a timer" do
    {u, outs} = Undo.capture(Undo.new(window_ms: 5000), line_item(1))
    assert Undo.pending?(u)
    assert Enum.any?(outs, &match?(%Outcome.StartTimer{name: :undo}, &1))
    {u, item, _} = Undo.take(u)
    assert item.id == 1 and not Undo.pending?(u)
  end

  test "Checkout is a pure step machine gated by cart-emptiness passed in" do
    assert {%{step: :cart}, [%Outcome.Flash{level: :error}]} = Checkout.start(Checkout.new(), true)
    assert {%{step: :address}, [%Outcome.Patch{}]} = Checkout.start(Checkout.new(), false)
    assert {%{step: :payment}, _, :ok} = Checkout.submit_address(%Shop.Checkout{step: :address},
             %{name: "Ada", line1: "1 Ave", city: "London"})
  end
end
