defmodule GoodDealWeb.Plugs.EnsureCartTest do
  use GoodDealWeb.ConnCase, async: true

  import GoodDeal.ShoppingCartFixtures

  alias GoodDeal.ShoppingCart

  test "first visit stores new open carts for the storefront and the portal", %{conn: conn} do
    conn = get(conn, ~p"/")

    cart_id = get_session(conn, "cart_id")
    portal_cart_id = get_session(conn, "portal_cart_id")

    assert ShoppingCart.get_cart!(cart_id).status == :open
    assert ShoppingCart.get_cart!(portal_cart_id).status == :open
    refute cart_id == portal_cart_id
  end

  test "an open cart in the session is kept, with its items", %{conn: conn} do
    cart = cart_fixture()
    item = cart_item_fixture(cart, quantity: 2)

    conn = conn |> init_test_session(%{"cart_id" => cart.id}) |> get(~p"/")
    assert get_session(conn, "cart_id") == cart.id

    conn = get(recycle(conn), ~p"/")
    assert get_session(conn, "cart_id") == cart.id
    assert [%{id: id, quantity: 2}] = ShoppingCart.list_cart_items(shop(cart.id))
    assert id == item.id
  end

  test "a completed cart is replaced by a new empty one", %{conn: conn} do
    cart = cart_fixture(%{status: :completed})

    conn = conn |> init_test_session(%{"cart_id" => cart.id}) |> get(~p"/")

    new_id = get_session(conn, "cart_id")
    refute new_id == cart.id
    assert ShoppingCart.list_cart_items(shop(new_id)) == []
  end
end
