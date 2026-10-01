defmodule GoodDealWeb.CartLiveTest do
  use GoodDealWeb.ConnCase

  import Phoenix.LiveViewTest
  import GoodDeal.StoreFixtures
  import Mox

  alias GoodDeal.Foundation.Carts

  setup :verify_on_exit!

  describe "CartLive.Show" do
    test "renders cart items and total", %{conn: conn} do
      {cart, [product_a, product_b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})

      {:ok, _live, html} = live(conn, ~p"/cart")

      assert html =~ "Your Cart"
      assert html =~ product_a.name
      assert html =~ product_b.name
    end

    test "renders empty cart message", %{conn: conn} do
      cart = cart_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})

      {:ok, _live, html} = live(conn, ~p"/cart")

      assert html =~ "Your cart is empty"
    end

    test "quantity increment updates item", %{conn: conn} do
      {cart, [product_a, _]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      live_view
      |> element(
        ~s([phx-click=update_quantity][phx-value-delta="1"][phx-value-item-id="#{item_a.id}"])
      )
      |> render_click()

      updated = Carts.list_items(cart.id) |> Enum.find(&(&1.id == item_a.id))
      assert updated.quantity == 2
    end

    test "remove item deletes from cart", %{conn: conn} do
      {cart, [product_a, _]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      items = Carts.list_items(cart.id)
      item_a = Enum.find(items, &(&1.product.id == product_a.id))

      html =
        live_view
        |> element(~s([phx-click=remove_item][phx-value-item-id="#{item_a.id}"]))
        |> render_click()

      refute html =~ product_a.name
      assert length(Carts.list_items(cart.id)) == 1
    end

    test "checkout charges, completes the order, and navigates to success", %{conn: conn} do
      {cart, _} = cart_with_items_fixture()

      GoodDeal.MockPaymentGateway
      |> expect(:charge, fn amount, currency, _metadata ->
        assert amount > 0
        assert currency == "usd"
        {:ok, "chg_test"}
      end)

      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      html = live_view |> element("button", "Checkout") |> render_click()
      assert html =~ "Processing payment"

      assert_redirect(live_view, ~p"/cart/success")
      assert Carts.get(cart.id).status == :completed
    end

    test "checkout disabled when empty", %{conn: conn} do
      cart = cart_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})

      {:ok, _, html} = live(conn, ~p"/cart")

      assert html =~ "disabled"
    end

    test "switch tab shows summary", %{conn: conn} do
      {cart, _} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      html = live_view |> element("button", "Summary") |> render_click()

      assert html =~ "Subtotal"
      assert html =~ "Total"
    end

    test "apply valid promo code shows discount", %{conn: conn} do
      {cart, _} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      live_view |> element("button", "Summary") |> render_click()
      html = live_view |> form("form", %{code: "SAVE10"}) |> render_submit()

      assert html =~ "SAVE10"
    end

    test "apply invalid promo code shows error", %{conn: conn} do
      {cart, _} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      html = live_view |> form("form", %{code: "BOGUS"}) |> render_submit()

      assert html =~ "Invalid promo code"
    end

    test "selecting a shipping method adds it to the summary", %{conn: conn} do
      {cart, _} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      live_view |> element("button", "Summary") |> render_click()
      refute has_element?(live_view, ~s([phx-value-method="express"][checked]))

      html =
        live_view
        |> element(~s([phx-click=select_shipping][phx-value-method="express"]))
        |> render_click()

      # the chosen tier is now reflected and its cost ($12.99) shows in the summary
      assert has_element?(live_view, ~s([phx-value-method="express"][checked]))
      assert html =~ "12.99"
    end

    test "toggling gift wrap adds a gift-wrap line", %{conn: conn} do
      {cart, _} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, live_view, _} = live(conn, ~p"/cart")

      live_view |> element("button", "Summary") |> render_click()

      html = live_view |> element(~s([phx-click=toggle_gift_wrap])) |> render_click()

      assert html =~ "Gift wrap"
    end
  end

  describe "CartLive.Success" do
    test "renders success message", %{conn: conn} do
      {:ok, cart} = Carts.create()
      conn = init_test_session(conn, %{cart_id: cart.id})

      {:ok, _live, html} = live(conn, ~p"/cart/success")

      assert html =~ "You did it!"
    end
  end
end
