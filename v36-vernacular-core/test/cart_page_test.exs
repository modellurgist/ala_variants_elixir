defmodule CartPageTest do
  @moduledoc "Composed-page + shell tests: wiring works, still no framework, no DB."
  use ExUnit.Case, async: true
  import Shop.Fixtures
  alias ShopWeb.{CartPage, CartShell}

  defp page, do: CartPage.new(items: [line_item(1, amount: 1000), line_item(2, amount: 2500)])

  test "remove_item wires the cart removal into undo (cross-feature, one place)" do
    {s, _outs} = {page(), nil} |> then(fn {p, _} -> CartPage.handle(:remove_item, %{item_id: 1}, p) end)
    assert Shop.Cart.find(s.cart, 1) == nil
    assert Shop.Undo.pending?(s.undo)
  end

  test "undo_remove restores the captured item into the cart" do
    {s, _} = CartPage.handle(:remove_item, %{item_id: 1}, page())
    {s, _} = CartPage.handle(:undo_remove, %{}, s)
    assert Shop.Cart.find(s.cart, 1)
    refute Shop.Undo.pending?(s.undo)
  end

  test "toggle_wishlist resolves the product from the cart in the composition" do
    {s, _} = CartPage.handle(:toggle_wishlist, %{item_id: 2}, page())
    assert Shop.Wishlist.member?(s.wishlist, 2)
    # unknown item is a no-op
    {s2, _} = CartPage.handle(:toggle_wishlist, %{item_id: 999}, page())
    assert Shop.Wishlist.count(s2.wishlist) == 0
  end

  test "apply_promo flows through the cart and updates totals" do
    {s, _} = CartPage.handle(:apply_promo, %{code: "SAVE10"}, page())
    assert CartPage.assigns(s).cart.promo_code == "SAVE10"
  end

  test "the shell interprets outcomes into a view (flashes, streams, timers)" do
    {_page, view} = CartShell.dispatch(page(), CartShell.view(), :remove_item, %{item_id: 1})
    assert {:info, "Item removed — undo?"} in view.flashes
    assert Map.has_key?(view.timers, :undo)
    refute Map.has_key?(view.streams[:cart] || %{}, 1)   # removed from the cart stream
  end

  test "start_checkout patches when non-empty, flashes when empty" do
    {_s, view} = CartShell.dispatch(page(), CartShell.view(), :start_checkout, %{})
    assert view.patch == "/cart/checkout"

    empty = CartPage.new(items: [])
    {_s, view} = CartShell.dispatch(empty, CartShell.view(), :start_checkout, %{})
    assert {:error, "Your cart is empty"} in view.flashes
  end
end
