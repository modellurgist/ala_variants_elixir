defmodule GoodDeal.Features.CheckoutTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Features.Checkout

  @line %{
    quantity: 2,
    product: %{id: 10, name: "W", description: "", thumbnail: "w", amount: 1000}
  }

  defp checkout(levels),
    do:
      Checkout.new(
        stock_levels: fn _ids -> levels end,
        line_items: GoodDeal.Domain.Checkout.new(currency: "usd")
      )

  test "an empty or short cart is blocked" do
    assert {_, [blocked: :empty]} = Checkout.pay(checkout(%{}), %{cart_id: 1, items: []})

    assert {_, [blocked: :out_of_stock]} =
             Checkout.pay(checkout(%{10 => 1}), %{cart_id: 1, items: [@line]})
  end

  test "a payable cart goes out as line items, then settles or fails" do
    assert {c, [status: :processing, ready_to_pay: {[%{currency: "usd", quantity: 2}], 1}]} =
             Checkout.pay(checkout(%{10 => 5}), %{cart_id: 1, items: [@line]})

    assert {_, [status: :complete, done: 1]} = Checkout.succeeded(c, "ref")
    assert {_, [status: :error, failed: :declined]} = Checkout.failed(c, :declined)
  end
end
