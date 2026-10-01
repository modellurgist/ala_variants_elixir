defmodule GoodDeal.Features.CartTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Domain.{GiftWrap, Inventory, Promo, Shipping}
  alias GoodDeal.Features.Cart

  defmodule Store do
    def list_items(_cart_id),
      do: [
        %{
          id: 1,
          quantity: 2,
          product: %{id: 10, name: "Widget", thumbnail: "w", amount: 1000, stock: 3}
        },
        %{
          id: 2,
          quantity: 1,
          product: %{id: 20, name: "Gadget", thumbnail: "g", amount: 2500, stock: 50}
        }
      ]

    def update_quantity(_cart_id, item_id, qty), do: send(self(), {:stored, item_id, qty})
    def remove_item(_cart_id, item_id), do: send(self(), {:removed, item_id})
  end

  defp loaded do
    cart =
      Cart.new(
        cart_id: 7,
        store: Store,
        shipping: Shipping.new([%{method: :standard, label: "S", cost: 599, free_above: 5000}]),
        promo: Promo.new(%{"HALF" => 50}),
        gift_wrap: GiftWrap.new(299),
        stock: Inventory.new(low_at: 5)
      )

    {cart, _} = Cart.load(cart, nil)
    cart
  end

  test "loading resets the rows from the store and prices the cart" do
    {_, [rows: {:reset, [widget, _]}, summary: summary]} = Cart.load(loaded(), nil)
    assert widget.stock_status == :low_stock
    assert summary.total == Money.new(4500)
  end

  test "a quantity change is stored and repriced" do
    {_, outs} = Cart.update_quantity(loaded(), %{item_id: 2, delta: 1})
    assert_received {:stored, 2, 2}
    assert outs[:summary].subtotal == Money.new(7000)
  end

  test "a removal is stored and the line goes out" do
    {cart, outs} = Cart.remove(loaded(), %{item_id: 1})
    assert_received {:removed, 1}
    assert %{id: 1} = outs[:removed]
    assert cart.items |> Enum.map(& &1.id) == [2]
  end

  test "promo codes, shipping and gift wrap reach the summary" do
    {cart, [summary: _, promo_applied: "half"]} = Cart.apply_promo(loaded(), "half")
    {cart, [summary: _]} = Cart.select_shipping(cart, :standard)
    {_, [summary: summary]} = Cart.toggle_gift_wrap(cart, nil)
    assert summary.discount == Money.new(2250)
    assert summary.shipping == Money.new(599)
    assert summary.gift_wrap == Money.new(897)
    assert {_, [promo_rejected: "NOPE"]} = Cart.apply_promo(loaded(), "NOPE")
  end

  test "checkout is requested with the cart's id and lines" do
    assert {_, [checkout_requested: %{cart_id: 7, items: [_, _]}]} =
             Cart.request_checkout(loaded(), nil)
  end
end
