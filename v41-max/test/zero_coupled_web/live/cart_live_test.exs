defmodule ZeroCoupledWeb.CartLiveTest do
  @moduledoc """
  End-to-end tests of the cart page. A feature instance handles its own events at once, but
  what it sends the page reaches another instance by two messages (instance → page → instance), so a
  test settles the page (two renders) after each action before reading it; async results are
  polled for.
  """
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
    settle(lv)
    item_a = Carts.list_items(cart.id) |> Enum.find(&(&1.product.id == a.id))
    %{lv: lv, cart: cart, product_a: a, product_b: b, item_a: item_a}
  end

  # a browser event is one hop to the circuit and one more back to the instance that shows it
  defp settle(lv) do
    render(lv)
    render(lv)
  end

  defp click(lv, selector) do
    lv |> element(selector) |> render_click()
    settle(lv)
  end

  defp click(lv, event, item_id),
    do: click(lv, ~s([phx-click=#{event}][phx-value-item-id="#{item_id}"]))

  defp submit(lv, selector, params) do
    lv |> form(selector, params) |> render_submit()
    settle(lv)
  end

  defp eventually(lv, text, tries \\ 50) do
    html = render(lv)

    cond do
      html =~ text ->
        html

      tries == 0 ->
        flunk("never rendered #{inspect(text)}")

      true ->
        Process.sleep(10)
        eventually(lv, text, tries - 1)
    end
  end

  @address %{name: "Ada", line1: "1 Ave", city: "London", postal_code: "12345"}

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
      {:ok, lv, _html} = live(conn, ~p"/cart")
      html = settle(lv)
      assert html =~ "Your cart is empty"
      assert html =~ "disabled"
    end
  end

  describe "cart items" do
    test "increment updates quantity, total and persists", %{conn: conn} do
      %{lv: lv, cart: cart, item_a: item_a, product_a: a} = open_cart(conn)

      html =
        click(
          lv,
          ~s([phx-click=update_quantity][phx-value-delta="1"][phx-value-item-id="#{item_a.id}"])
        )

      assert html =~ to_string(Money.new(a.amount * 2))

      assert Carts.list_items(cart.id) |> Enum.find(&(&1.id == item_a.id)) |> Map.get(:quantity) ==
               2
    end

    test "remove shows the undo banner then undo restores", %{conn: conn} do
      %{lv: lv, item_a: item_a, product_a: a} = open_cart(conn)

      html = click(lv, "remove_item", item_a.id)
      refute html =~ a.name
      assert html =~ "Item removed"
      assert html =~ "Undo"

      html = click(lv, "[phx-click=undo_remove]")
      assert html =~ a.name
      assert html =~ "Item restored"
    end

    test "when the undo window elapses the removal is persisted", %{conn: conn} do
      %{lv: lv, cart: cart, item_a: item_a, product_a: a} = open_cart(conn)
      click(lv, "remove_item", item_a.id)
      assert Carts.list_items(cart.id) |> Enum.any?(&(&1.id == item_a.id))

      send(lv.pid, {:undo, :expire, item_a.id})
      html = settle(lv)
      refute html =~ "Undo"
      refute html =~ a.name
      refute Carts.list_items(cart.id) |> Enum.any?(&(&1.id == item_a.id))
    end

    test "a second removal makes the first final; only the latest can be undone", %{conn: conn} do
      %{lv: lv, cart: cart, item_a: item_a, product_a: a, product_b: b} = open_cart(conn)
      item_b = Carts.list_items(cart.id) |> Enum.find(&(&1.product.id == b.id))

      click(lv, "remove_item", item_a.id)
      click(lv, "remove_item", item_b.id)
      render(lv)
      refute Carts.list_items(cart.id) |> Enum.any?(&(&1.id == item_a.id))

      lv |> element("[phx-click=undo_remove]") |> render_click()
      html = render(lv)
      assert html =~ b.name
      refute html =~ a.name
    end

    test "toggle gift wrap adds a gift-wrap line to the summary", %{conn: conn} do
      %{lv: lv, item_a: item_a} = open_cart(conn)
      assert click(lv, "toggle_gift_wrap", item_a.id) =~ "Gift wrap"
    end
  end

  describe "tabs, save-for-later and wishlist" do
    test "save for later moves an item to the Saved tab and back", %{conn: conn} do
      %{lv: lv, item_a: item_a} = open_cart(conn)

      assert click(lv, "save_for_later", item_a.id) =~ "Saved for later"
      assert click(lv, ~s([phx-click=switch_tab][phx-value-tab=saved])) =~ "Move to cart"
      assert click(lv, "move_to_cart", item_a.id) =~ "Moved to cart"
    end

    test "wishlist a cart item, see it in the Wishlist tab, add it back", %{conn: conn} do
      %{lv: lv, item_a: item_a, product_a: a} = open_cart(conn)

      assert click(lv, "toggle_wishlist", item_a.id) =~ "Added to wishlist"

      html = click(lv, ~s([phx-click=switch_tab][phx-value-tab=wishlist]))
      assert html =~ a.name
      assert html =~ "Add to cart"

      assert click(lv, ~s([phx-click=add_wishlisted_to_cart][phx-value-product-id="#{a.id}"])) =~
               "Added to cart"
    end
  end

  describe "promo and shipping" do
    test "valid promo shows a discount", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      html = submit(lv, "[phx-submit=apply_promo]", %{code: "SAVE10"})
      assert html =~ "SAVE10"
      assert html =~ "Promo applied"
    end

    test "invalid promo shows an error", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      assert submit(lv, "[phx-submit=apply_promo]", %{code: "BOGUS"}) =~ "Invalid promo code"
    end

    test "selecting express shipping updates the cost", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      assert click(lv, ~s([phx-click=select_shipping][phx-value-method=express])) =~ "Express"
    end
  end

  describe "real-time stock" do
    test "a stock_changed fact marks the item out of stock", %{conn: conn} do
      %{lv: lv, product_a: a} = open_cart(conn)

      send(lv.pid, %ZeroCoupled.Foundation.Broadcast.Facts.StockChanged{
        product_id: a.id,
        stock: 0
      })

      assert settle(lv) =~ "Out of stock"
    end
  end

  describe "multi-step checkout" do
    test "address → payment → pay → redirect", %{conn: conn} do
      %{lv: lv, cart: cart} = open_cart(conn)

      ZeroCoupled.MockPaymentGateway
      |> expect(:create_checkout_session, fn line_items, metadata, _urls ->
        assert length(line_items) == 2
        assert metadata["cart_id"] == cart.id
        # slow enough that the page is seen processing before the provider answers
        Process.sleep(30)
        {:ok, "https://pay.example.test/session/test"}
      end)

      click(lv, "[phx-click=start_checkout]")
      assert_patch(lv, ~p"/cart/checkout")
      assert render(lv) =~ "Full name"

      html =
        submit(lv, "[phx-submit=submit_address]",
          address: %{name: "", line1: "", city: "", postal_code: "x"}
        )

      assert html =~ "can&#39;t be blank" or html =~ "must be"

      submit(lv, "[phx-submit=submit_address]", address: @address)
      assert_patch(lv, ~p"/cart/checkout/payment")
      assert render(lv) =~ "Pay"

      assert lv |> element("[phx-click=pay]") |> render_click() =~ "Processing payment"
      assert_redirect(lv, "https://pay.example.test/session/test")
      assert ZeroCoupled.Foundation.Carts.get(cart.id).status == :completed
    end

    test "a failed payment offers a retry that pays again", %{conn: conn} do
      %{lv: lv} = open_cart(conn)

      ZeroCoupled.MockPaymentGateway
      |> expect(:create_checkout_session, fn _, _, _ -> {:error, :declined} end)
      |> expect(:create_checkout_session, fn _, _, _ ->
        {:ok, "https://pay.example.test/retry"}
      end)

      click(lv, "[phx-click=start_checkout]")
      submit(lv, "[phx-submit=submit_address]", address: @address)
      click(lv, "[phx-click=pay]")
      eventually(lv, "Payment failed.")

      lv |> element("[phx-click=pay]") |> render_click()
      assert_redirect(lv, "https://pay.example.test/retry")
    end

    test "browser back returns to the address step; a forward URL jump is ignored", %{conn: conn} do
      %{lv: lv} = open_cart(conn)

      click(lv, "[phx-click=start_checkout]")
      assert_patch(lv, ~p"/cart/checkout")
      submit(lv, "[phx-submit=submit_address]", address: @address)
      assert_patch(lv, ~p"/cart/checkout/payment")

      html = render_patch(lv, ~p"/cart/checkout")
      assert html =~ "Full name"

      html = render_patch(lv, ~p"/cart/checkout/payment")
      assert html =~ "Full name"
      refute html =~ "Edit address"
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
