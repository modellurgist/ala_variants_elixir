defmodule ZeroCoupledWeb.CartLiveTest do
  @moduledoc "End-to-end tests of the thin shell + effect interpreter + ActionViews."
  use ZeroCoupledWeb.ConnCase

  import Phoenix.LiveViewTest
  import ZeroCoupled.StoreFixtures
  import Mox

  alias ZeroCoupled.Foundation.Carts

  setup :verify_on_exit!

  defp open_cart(conn) do
    {cart, [a, b]} = cart_with_items_fixture()
    conn = init_test_session(conn, %{cart_id: cart.id})
    {:ok, lv, _html} = live(conn, ~p"/cart")
    item_a = Carts.list_items(cart.id) |> Enum.find(&(&1.product.id == a.id))
    %{lv: lv, cart: cart, product_a: a, product_b: b, item_a: item_a}
  end

  defp click(lv, event, item_id) do
    lv
    |> element(~s([phx-click=#{event}][phx-value-item-id="#{item_id}"]))
    |> render_click()
  end

  describe "rendering" do
    test "renders items, shipping and a checkout button", %{conn: conn} do
      %{lv: lv, product_a: a} = open_cart(conn)
      html = render(lv)
      assert html =~ "Your Cart"
      assert html =~ a.name
      assert html =~ "Shipping"
      assert html =~ "Checkout"
    end

    test "empty cart disables checkout", %{conn: conn} do
      cart = cart_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, _lv, html} = live(conn, ~p"/cart")
      assert html =~ "Your cart is empty"
      assert html =~ "disabled"
    end
  end

  describe "cart items" do
    test "increment updates quantity, total and persists", %{conn: conn} do
      %{lv: lv, cart: cart, item_a: item_a, product_a: a} = open_cart(conn)

      html =
        lv
        |> element(~s([phx-click=update_quantity][phx-value-delta="1"][phx-value-item-id="#{item_a.id}"]))
        |> render_click()

      assert html =~ to_string(Money.new(a.amount * 2))
      assert Carts.list_items(cart.id) |> Enum.find(&(&1.id == item_a.id)) |> Map.get(:quantity) == 2
    end

    test "remove shows the undo banner then undo restores", %{conn: conn} do
      %{lv: lv, item_a: item_a, product_a: a} = open_cart(conn)

      html = click(lv, "remove_item", item_a.id)
      refute html =~ a.name
      assert html =~ "Item removed"
      assert html =~ "Undo"

      html = lv |> element("[phx-click=undo_remove]") |> render_click()
      assert html =~ a.name
      assert html =~ "Item restored"
    end

    test "toggle gift wrap adds a gift-wrap line to the summary", %{conn: conn} do
      %{lv: lv, item_a: item_a} = open_cart(conn)
      html = click(lv, "toggle_gift_wrap", item_a.id)
      assert html =~ "Gift wrap"
    end
  end

  describe "tabs, save-for-later and wishlist" do
    test "save for later moves an item to the Saved tab and back", %{conn: conn} do
      %{lv: lv, item_a: item_a} = open_cart(conn)

      assert click(lv, "save_for_later", item_a.id) =~ "Saved for later"

      lv |> element(~s([phx-click=switch_tab][phx-value-tab=saved])) |> render_click()
      assert render(lv) =~ "Move to cart"

      assert click(lv, "move_to_cart", item_a.id) =~ "Moved to cart"
    end

    test "wishlist a cart item, see it in the Wishlist tab, add it back", %{conn: conn} do
      %{lv: lv, item_a: item_a, product_a: a} = open_cart(conn)

      assert click(lv, "toggle_wishlist", item_a.id) =~ "Added to wishlist"

      lv |> element(~s([phx-click=switch_tab][phx-value-tab=wishlist])) |> render_click()
      html = render(lv)
      assert html =~ a.name
      assert html =~ "Add to cart"

      html =
        lv
        |> element(~s([phx-click=add_wishlisted_to_cart][phx-value-product-id="#{a.id}"]))
        |> render_click()

      assert html =~ "Added to cart"
    end
  end

  describe "promo and shipping" do
    test "valid promo shows a discount", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      html = lv |> form("[phx-submit=apply_promo]", %{code: "SAVE10"}) |> render_submit()
      assert html =~ "SAVE10"
      assert html =~ "Promo applied"
    end

    test "invalid promo shows an error", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      html = lv |> form("[phx-submit=apply_promo]", %{code: "BOGUS"}) |> render_submit()
      assert html =~ "Invalid promo code"
    end

    test "selecting express shipping updates the cost", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      html = lv |> element(~s([phx-click=select_shipping][phx-value-method=express])) |> render_click()
      assert html =~ "Express"
    end
  end

  describe "real-time stock" do
    test "a stock_changed fact marks the item out of stock", %{conn: conn} do
      %{lv: lv, product_a: a} = open_cart(conn)
      send(lv.pid, {:stock_changed, a.id, 0})
      assert render(lv) =~ "Out of stock"
    end
  end

  describe "multi-step checkout" do
    test "address → payment → pay → redirect", %{conn: conn} do
      %{lv: lv, cart: cart} = open_cart(conn)

      ZeroCoupled.MockPaymentGateway
      |> expect(:create_checkout_session, fn line_items, metadata, _urls ->
        assert length(line_items) == 2
        assert metadata["cart_id"] == cart.id
        {:ok, "https://pay.example.test/session/test"}
      end)

      # Start checkout → address form
      lv |> element("button", "Checkout") |> render_click()
      assert_patch(lv, ~p"/cart/checkout")
      assert render(lv) =~ "Full name"

      # Invalid address stays on the form with an error
      html =
        lv
        |> form("[phx-submit=submit_address]", address: %{name: "", line1: "", city: "", postal_code: "x"})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "must be"

      # Valid address advances to payment
      lv
      |> form("[phx-submit=submit_address]",
        address: %{name: "Ada", line1: "1 Ave", city: "London", postal_code: "12345"}
      )
      |> render_submit()

      assert_patch(lv, ~p"/cart/checkout/payment")
      assert render(lv) =~ "Pay"

      # Pay → processing → async success → order finalized → redirect
      html = lv |> element("button", "Pay") |> render_click()
      assert html =~ "Processing payment"
      assert_redirect(lv, "https://pay.example.test/session/test")
      assert ZeroCoupled.Foundation.Carts.get(cart.id).status == :completed
    end
  end

  describe "CartLive.Success" do
    test "renders the success message", %{conn: conn} do
      {:ok, cart} = Carts.create()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, _lv, html} = live(conn, ~p"/cart/success")
      assert html =~ "You did it!"
    end
  end
end
