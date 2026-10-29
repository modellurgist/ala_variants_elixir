defmodule GoodDealWeb.CartLiveTest do
  use GoodDealWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GoodDeal.CatalogFixtures
  import GoodDeal.ShoppingCartFixtures

  alias GoodDeal.{Catalog, ShoppingCart}

  defp open_cart(%{conn: conn}) do
    cart = cart_fixture()

    a =
      cart_item_fixture(cart, name: "Alpha Mug", amount: 1000, stock: 10, thumbnail: "/alpha.png")

    b = cart_item_fixture(cart, name: "Beta Press", amount: 2500, stock: 3)
    conn = init_test_session(conn, %{"cart_id" => cart.id})
    {:ok, lv, _html} = live(conn, ~p"/cart")
    %{conn: conn, lv: lv, cart: cart, a: a, b: b}
  end

  defp click(lv, event, item) do
    lv
    |> element(~s([phx-click="#{event}"][phx-value-item-id="#{item.id}"]))
    |> render_click()
  end

  defp summary(lv), do: lv |> element("#summary") |> render()

  defp item_ids(cart),
    do: shop(:storefront, cart_id: cart.id) |> ShoppingCart.list_cart_items() |> Enum.map(& &1.id)

  describe "items" do
    setup :open_cart

    test "shows each item's name, thumbnail, prices, quantity and stock status",
         %{lv: lv, a: a, b: b} do
      row = lv |> element("#items-#{a.id}") |> render()
      assert row =~ "Alpha Mug"
      assert row =~ ~s(src="/alpha.png")
      assert row =~ "$10.00 each"
      assert row =~ "In stock"
      refute row =~ "Gift-wrapped"

      assert lv |> element("#items-#{b.id}") |> render() =~ "Low stock"
    end

    test "increment and decrement change quantity, totals and persist", %{
      lv: lv,
      cart: cart,
      a: a
    } do
      assert has_element?(lv, ~s(#items-#{a.id} button[phx-value-delta="-1"][disabled]))

      lv
      |> element(~s(#items-#{a.id} button[phx-value-delta="1"]))
      |> render_click()

      assert lv |> element("#items-#{a.id}") |> render() =~ "$20.00"
      assert summary(lv) =~ "$45.00"

      assert [%{quantity: 2}, _] =
               ShoppingCart.list_cart_items(shop(:storefront, cart_id: cart.id))

      refute has_element?(lv, ~s(#items-#{a.id} button[phx-value-delta="-1"][disabled]))

      lv
      |> element(~s(#items-#{a.id} button[phx-value-delta="-1"]))
      |> render_click()

      assert [%{quantity: 1}, _] =
               ShoppingCart.list_cart_items(shop(:storefront, cart_id: cart.id))
    end

    test "gift wrap adds 299 per wrapped item; toggling again removes it", %{lv: lv, a: a} do
      refute summary(lv) =~ "Gift wrap"

      click(lv, "toggle_gift_wrap", a)
      assert lv |> element("#items-#{a.id}") |> render() =~ "Gift-wrapped"
      assert summary(lv) =~ "Gift wrap"
      assert summary(lv) =~ "$2.99"

      click(lv, "toggle_gift_wrap", a)
      refute summary(lv) =~ "Gift wrap"
    end

    test "an empty cart says so and disables checkout", %{conn: conn} do
      cart = cart_fixture()
      conn = init_test_session(conn, %{"cart_id" => cart.id})
      {:ok, lv, html} = live(conn, ~p"/cart")

      assert html =~ "Your cart is empty."
      assert has_element?(lv, "#checkout-button[disabled]")
      assert summary(lv) =~ "Free"
    end

    test "every list is a stream", %{lv: lv} do
      for id <- ~w(cart-items saved-items wishlist-items) do
        assert has_element?(lv, ~s(##{id}[phx-update="stream"]))
      end
    end

    test "items persist across page loads with the same cart", %{conn: conn, lv: lv, a: a} do
      click(lv, "toggle_gift_wrap", a)
      {:ok, _lv, html} = live(conn, ~p"/cart")
      assert html =~ "Alpha Mug"
      assert html =~ "Gift-wrapped"
    end
  end

  describe "removal and undo" do
    setup :open_cart

    test "removing hides the row, recomputes totals and shows the undo banner",
         %{lv: lv, cart: cart, a: a} do
      html = click(lv, "remove_item", a)

      refute has_element?(lv, "#items-#{a.id}")
      assert html =~ "Item removed."
      assert has_element?(lv, "#undo-banner button", "Undo")
      assert summary(lv) =~ "$25.00"
      assert a.id in item_ids(cart)
    end

    test "undo restores the item, flashes, recomputes and clears its gift wrap",
         %{lv: lv, a: a} do
      click(lv, "toggle_gift_wrap", a)
      click(lv, "remove_item", a)

      html = lv |> element("#undo-banner button", "Undo") |> render_click()

      assert html =~ "Item restored"
      refute has_element?(lv, "#undo-banner")
      assert has_element?(lv, "#items-#{a.id}")
      refute lv |> element("#items-#{a.id}") |> render() =~ "Gift-wrapped"
      assert summary(lv) =~ "$35.00"
    end

    test "when the window elapses the removal is persisted and the banner goes",
         %{lv: lv, cart: cart, a: a} do
      click(lv, "remove_item", a)
      send(lv.pid, {:undo_expired, a.id})

      refute has_element?(lv, "#undo-banner")
      refute a.id in item_ids(cart)
    end

    test "the undo window is a real timer", %{lv: lv, cart: cart, a: a} do
      click(lv, "remove_item", a)
      Process.sleep(Application.fetch_env!(:good_deal, :undo_window_ms) + 200)

      refute has_element?(lv, "#undo-banner")
      refute a.id in item_ids(cart)
    end

    test "a stale expiry does not touch the current removal", %{lv: lv, cart: cart, a: a} do
      click(lv, "remove_item", a)
      send(lv.pid, {:undo_expired, -1})

      assert has_element?(lv, "#undo-banner")
      assert a.id in item_ids(cart)
    end

    test "a second removal makes the first final; only the latest can be undone",
         %{lv: lv, cart: cart, a: a, b: b} do
      click(lv, "remove_item", a)
      click(lv, "remove_item", b)
      refute a.id in item_ids(cart)

      lv |> element("#undo-banner button", "Undo") |> render_click()
      assert has_element?(lv, "#items-#{b.id}")
      refute has_element?(lv, "#items-#{a.id}")
    end

    test "undo with nothing pending does nothing", %{lv: lv} do
      refute render_click(lv, "undo_remove", %{}) =~ "Item restored"
    end
  end

  describe "tabs" do
    setup :open_cart

    test "each tab shows its count and switching is UI state only", %{lv: lv, cart: cart, a: a} do
      lv |> element(~s(#items-#{a.id} button[phx-value-delta="1"])) |> render_click()
      assert lv |> element("#tab-items") |> render() =~ "Items (3)"
      assert lv |> element("#tab-saved") |> render() =~ "Saved (0)"
      assert lv |> element("#tab-wishlist") |> render() =~ "Wishlist (0)"

      lv |> element("#tab-saved") |> render_click()
      assert has_element?(lv, ~s(#tab-saved[aria-selected="true"]))
      assert has_element?(lv, "#items-panel.hidden")
      refute has_element?(lv, "#saved-panel.hidden")
      assert length(ShoppingCart.list_cart_items(shop(:storefront, cart_id: cart.id))) == 2
    end

    test "save for later moves an item to Saved and back", %{lv: lv, cart: cart, a: a} do
      assert click(lv, "save_for_later", a) =~ "Saved for later"
      refute has_element?(lv, "#items-#{a.id}")
      assert has_element?(lv, "#saved-#{a.id}")
      assert lv |> element("#tab-saved") |> render() =~ "Saved (1)"
      assert lv |> element("#tab-items") |> render() =~ "Items (1)"
      assert [%{id: id}] = ShoppingCart.list_saved_items(shop(:storefront, cart_id: cart.id))
      assert id == a.id

      assert click(lv, "move_to_cart", a) =~ "Moved to cart"
      assert has_element?(lv, "#items-#{a.id}")
      refute has_element?(lv, "#saved-#{a.id}")
      assert lv |> element("#tab-saved") |> render() =~ "Saved (0)"
    end

    test "saving the same item twice keeps one saved entry", %{lv: lv, a: a} do
      click(lv, "save_for_later", a)
      render_click(lv, "save_for_later", %{"item-id" => a.id})
      assert lv |> element("#tab-saved") |> render() =~ "Saved (1)"
    end
  end

  describe "wishlist" do
    setup :open_cart

    test "toggle a cart item's product in and out of the wishlist", %{lv: lv, a: a} do
      assert click(lv, "toggle_wishlist", a) =~ "Added to wishlist"
      assert lv |> element("#items-#{a.id}") |> render() =~ "Wishlisted"
      assert has_element?(lv, "#wishlist-#{a.product_id}")
      assert lv |> element("#tab-wishlist") |> render() =~ "Wishlist (1)"

      assert click(lv, "toggle_wishlist", a) =~ "Removed from wishlist"
      refute lv |> element("#items-#{a.id}") |> render() =~ "Wishlisted"
      refute has_element?(lv, "#wishlist-#{a.product_id}")
      assert render(lv) =~ "Your wishlist is empty."
    end

    test "remove a product from the wishlist", %{lv: lv, a: a, cart: cart} do
      click(lv, "toggle_wishlist", a)

      lv
      |> element(~s(#wishlist-#{a.product_id} button[phx-click="remove_from_wishlist"]))
      |> render_click()

      refute has_element?(lv, "#wishlist-#{a.product_id}")
      refute lv |> element("#items-#{a.id}") |> render() =~ "Wishlisted"
      refute ShoppingCart.in_wishlist?(shop(:storefront, cart_id: cart.id), a.product_id)
    end

    test "removing a product that is not in the cart from the wishlist", %{conn: conn, cart: cart} do
      product = product_fixture(%{name: "Wished Only"})
      :added = ShoppingCart.toggle_wishlist(shop(:storefront, cart_id: cart.id), product.id)
      {:ok, lv, _} = live(conn, ~p"/cart")

      lv
      |> element(~s(#wishlist-#{product.id} button[phx-click="remove_from_wishlist"]))
      |> render_click()

      refute has_element?(lv, "#wishlist-#{product.id}")
    end

    test "add to cart from the wishlist persists a line and drops the wish", %{
      conn: conn,
      cart: cart
    } do
      product = product_fixture(%{name: "Wished Kettle"})
      :added = ShoppingCart.toggle_wishlist(shop(:storefront, cart_id: cart.id), product.id)
      {:ok, lv, _html} = live(conn, ~p"/cart")

      html =
        lv
        |> element(~s(#wishlist-#{product.id} button[phx-click="add_wishlisted_to_cart"]))
        |> render_click()

      assert html =~ "Added to cart"
      refute has_element?(lv, "#wishlist-#{product.id}")
      assert lv |> element("#cart-items") |> render() =~ "Wished Kettle"

      assert Enum.any?(
               ShoppingCart.list_cart_items(shop(:storefront, cart_id: cart.id)),
               &(&1.product_id == product.id)
             )

      refute ShoppingCart.in_wishlist?(shop(:storefront, cart_id: cart.id), product.id)
    end
  end

  describe "pricing summary" do
    setup :open_cart

    test "shows item count, subtotal, shipping and total", %{lv: lv} do
      html = summary(lv)
      assert html =~ "Items"
      assert html =~ "$35.00"
      assert html =~ "Standard (5–7 days)"
      assert html =~ "$5.99"
      assert html =~ "$40.99"
      refute html =~ "Discount"
    end

    test "a valid promo flashes and shows the discount", %{lv: lv} do
      html = lv |> form("#promo-form", code: "SAVE10") |> render_submit()
      assert html =~ "Promo applied!"
      assert summary(lv) =~ "Discount (SAVE10)"
      assert summary(lv) =~ "-$3.50"
      assert summary(lv) =~ "$37.49"
    end

    test "each promo code takes its own percentage off the subtotal", %{lv: lv} do
      lv |> form("#promo-form", code: "SAVE20") |> render_submit()
      assert summary(lv) =~ "Discount (SAVE20)"
      assert summary(lv) =~ "-$7.00"
      assert summary(lv) =~ "$33.99"

      lv |> form("#promo-form", code: "half") |> render_submit()
      assert summary(lv) =~ "Discount (HALF)"
      assert summary(lv) =~ "-$17.50"
      assert summary(lv) =~ "$23.49"
    end

    test "the total is subtotal less discount plus gift wrap plus shipping", %{lv: lv, a: a} do
      lv |> form("#promo-form", code: "SAVE10") |> render_submit()
      click(lv, "toggle_gift_wrap", a)
      lv |> element(~s(button[phx-value-method="express"])) |> render_click()

      assert summary(lv) =~ "$47.48"
    end

    test "an invalid promo flashes, shows the error inline and changes nothing",
         %{lv: lv, cart: cart} do
      html = lv |> form("#promo-form", code: "BOGUS") |> render_submit()
      assert html =~ "Invalid promo code"
      assert lv |> element("#promo-error") |> render() =~ "Invalid promo code"
      refute summary(lv) =~ "Discount"
      assert ShoppingCart.get_cart!(cart.id).promo_code == nil

      lv |> form("#promo-form", code: "HALF") |> render_submit()
      refute has_element?(lv, "#promo-error")
    end

    test "choosing a shipping method updates the cost and persists", %{lv: lv, cart: cart} do
      lv |> element(~s(button[phx-value-method="express"])) |> render_click()
      assert summary(lv) =~ "Express (2–3 days)"
      assert summary(lv) =~ "$12.99"
      assert ShoppingCart.get_cart!(cart.id).shipping_method == "express"
    end

    test "standard shipping is free at exactly 5,000 and charged at 4,999", %{conn: conn} do
      for {amount, shipping} <- [{4999, "$5.99"}, {5000, "Free"}] do
        cart = cart_fixture()
        cart_item_fixture(cart, amount: amount)
        {:ok, lv, _} = live(init_test_session(conn, %{"cart_id" => cart.id}), ~p"/cart")

        assert lv |> element("#summary div", "Shipping") |> render() =~ shipping
      end
    end

    test "standard shipping is free above the threshold", %{lv: lv, b: b} do
      lv |> element(~s(#items-#{b.id} button[phx-value-delta="1"])) |> render_click()
      assert summary(lv) =~ "Free"
    end
  end

  describe "real-time stock" do
    setup :open_cart

    test "a stock change updates the row in every open cart", %{lv: lv, a: a} do
      other_cart = cart_fixture()
      {:ok, _} = ShoppingCart.add_item(shop(:storefront, cart_id: other_cart.id), a.product_id)

      {:ok, other_lv, _} =
        live(init_test_session(build_conn(), %{"cart_id" => other_cart.id}), ~p"/cart")

      {:ok, _} = Catalog.update_product(a.product, %{stock: 0})

      assert lv |> element("#items-#{a.id}") |> render() =~ "Out of stock"
      assert other_lv |> render() =~ "Out of stock"
    end

    test "saved and wishlisted rows update too", %{lv: lv, a: a, b: b} do
      click(lv, "save_for_later", a)
      click(lv, "toggle_wishlist", b)

      {:ok, _} = Catalog.update_product(a.product, %{stock: 2})
      {:ok, _} = Catalog.update_product(b.product, %{stock: 0})

      assert lv |> element("#saved-#{a.id}") |> render() =~ "Low stock"
      assert lv |> element("#wishlist-#{b.product_id}") |> render() =~ "Out of stock"
    end

    test "changes to a product pending removal leave it hidden", %{lv: lv, a: a} do
      click(lv, "toggle_wishlist", a)
      click(lv, "remove_item", a)
      {:ok, _} = Catalog.update_product(a.product, %{stock: 0})
      refute has_element?(lv, "#items-#{a.id}")
    end

    test "a deleted product disappears from the cart", %{lv: lv, a: a, b: b} do
      click(lv, "toggle_wishlist", b)
      unrelated = product_fixture()
      {:ok, _} = Catalog.update_product(unrelated, %{stock: 0})
      {:ok, _} = Catalog.delete_product(unrelated)
      {:ok, _} = Catalog.delete_product(a.product)

      refute has_element?(lv, "#items-#{a.id}")
      assert has_element?(lv, "#items-#{b.id}")
      assert summary(lv) =~ "$25.00"
    end
  end

  describe "checkout button" do
    setup :open_cart

    test "starts checkout", %{lv: lv} do
      lv |> element("#checkout-button") |> render_click()
      assert_redirect(lv, ~p"/cart/checkout")
    end

    test "with an empty cart flashes and stays", %{conn: conn} do
      cart = cart_fixture()
      {:ok, lv, _} = live(init_test_session(conn, %{"cart_id" => cart.id}), ~p"/cart")

      assert render_click(lv, "checkout", %{}) =~ "Your cart is empty"
    end

    test "makes a pending removal final first", %{lv: lv, cart: cart, a: a} do
      click(lv, "remove_item", a)
      lv |> element("#checkout-button") |> render_click()
      refute a.id in item_ids(cart)
    end
  end

  describe "a cart closed elsewhere" do
    setup :open_cart

    test "an event reloads the page on a new cart and leaves the closed one alone",
         %{conn: conn, lv: lv, cart: cart, a: a} do
      {:ok, _} = ShoppingCart.set_cart_status(cart, :completed)

      assert {:error, {:redirect, %{to: "/cart"}}} =
               lv
               |> element(~s(#items-#{a.id} button[phx-value-delta="1"]))
               |> render_click()

      assert [%{quantity: 1}, _] =
               ShoppingCart.list_cart_items(shop(:storefront, cart_id: cart.id))

      {:ok, _lv, html} = live(conn, ~p"/cart")
      assert html =~ "Your cart is empty"
    end
  end
end
