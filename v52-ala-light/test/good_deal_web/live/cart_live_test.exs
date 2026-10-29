defmodule GoodDealWeb.CartLiveTest do
  @moduledoc "Acceptance tests for the storefront requirements (ported from V39-max; same checks for every full variant)."
  use GoodDealWeb.ConnCase

  import Phoenix.LiveViewTest
  import GoodDeal.StoreFixtures
  import Mox
  import Ecto.Query

  alias GoodDeal.{Catalog, Repo}
  alias GoodDeal.Foundation.{Carts, Products}
  alias GoodDeal.Foundation.Schemas.CartItem

  setup :verify_on_exit!

  defp open_cart(conn) do
    {cart, [a, b]} = cart_with_items_fixture()
    conn = init_test_session(conn, %{cart_id: cart.id})
    {:ok, lv, _html} = live(conn, ~p"/cart")
    item_a = Carts.list_items(cart.id) |> Enum.find(&(&1.product.id == a.id))
    %{lv: lv, cart: cart, product_a: a, product_b: b, item_a: item_a}
  end

  # the page reopened on the same cart, as a reload would
  defp open_cart_in(conn) do
    {cart, [a, _b]} = cart_with_items_fixture()
    conn = init_test_session(conn, %{cart_id: cart.id})
    {:ok, lv, _html} = live(conn, ~p"/cart")
    item_a = Carts.list_items(cart.id) |> Enum.find(&(&1.product.id == a.id))
    %{conn: conn, lv: lv, cart: cart, product_a: a, item_a: item_a}
  end

  # the rows as stored, held or not: what a read that forgets the hold would see
  defp stored(cart_id), do: Repo.all(from ci in CartItem, where: ci.cart_id == ^cart_id)

  defp held_since(item_id, ms_ago) do
    at = DateTime.add(DateTime.utc_now(), -ms_ago, :millisecond)
    Repo.update_all(from(ci in CartItem, where: ci.id == ^item_id), set: [removed_at: at])
  end

  defp close(lv) do
    ref = Process.monitor(lv.pid)
    GenServer.stop(lv.pid, :normal)
    assert_receive {:DOWN, ^ref, _, _, _}
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
        |> element(
          ~s([phx-click=update_quantity][phx-value-delta="1"][phx-value-item-id="#{item_a.id}"])
        )
        |> render_click()

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

      html = lv |> element("[phx-click=undo_remove]") |> render_click()
      assert html =~ a.name
      assert html =~ "Item restored"
    end

    test "switching a tab shows its pane; UI state only", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      html = lv |> element(~s([phx-click=switch_tab][phx-value-tab=saved])) |> render_click()
      assert html =~ "No saved items"
    end

    test "when the undo window elapses the removal is persisted", %{conn: conn} do
      %{lv: lv, cart: cart, item_a: item_a, product_a: a} = open_cart(conn)
      click(lv, "remove_item", item_a.id)
      assert stored(cart.id) |> Enum.any?(&(&1.id == item_a.id))

      send(lv.pid, {:timer, :undo, item_a})
      html = render(lv)
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

    test "a removal held when the page closes stays removed, and is final once the window elapses",
         %{conn: conn} do
      {cart, [a, _b]} = cart_with_items_fixture()
      conn = init_test_session(conn, %{cart_id: cart.id})
      {:ok, lv, _html} = live(conn, ~p"/cart")
      item_a = Carts.list_items(cart.id) |> Enum.find(&(&1.product.id == a.id))

      click(lv, "remove_item", item_a.id)
      close(lv)

      {:ok, lv, html} = live(conn, ~p"/cart")
      refute html =~ a.name
      close(lv)

      held_since(item_a.id, Catalog.undo_window_ms() + 1_000)
      {:ok, _lv, html} = live(conn, ~p"/cart")
      refute html =~ a.name
      refute stored(cart.id) |> Enum.any?(&(&1.id == item_a.id))
    end

    test "toggle gift wrap adds a gift-wrap line to the summary", %{conn: conn} do
      %{lv: lv, item_a: item_a} = open_cart(conn)
      html = click(lv, "toggle_gift_wrap", item_a.id)
      assert html =~ "Gift wrap"
      assert html =~ "2.99"
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

    test "a saved item stays in the Saved tab and out of the cart after a reload", %{conn: conn} do
      %{conn: conn, lv: lv, cart: cart, item_a: item_a, product_a: a} = open_cart_in(conn)

      click(lv, "save_for_later", item_a.id)
      close(lv)

      {:ok, lv, _html} = live(conn, ~p"/cart")
      refute has_element?(lv, "#cart_items", a.name)
      assert has_element?(lv, "#saved_items", a.name)
      refute Carts.list_items(cart.id) |> Enum.any?(&(&1.id == item_a.id))
    end

    test "moving a saved item to the cart brings it back as a line that stays", %{conn: conn} do
      %{conn: conn, lv: lv, cart: cart, item_a: item_a, product_a: a} = open_cart_in(conn)

      click(lv, "save_for_later", item_a.id)
      close(lv)
      {:ok, lv, _html} = live(conn, ~p"/cart")

      assert click(lv, "move_to_cart", item_a.id) =~ "Moved to cart"
      assert has_element?(lv, "#cart_items", a.name)
      refute has_element?(lv, "#saved_items", a.name)
      close(lv)

      {:ok, lv, _html} = live(conn, ~p"/cart")
      assert has_element?(lv, "#cart_items", a.name)
      refute has_element?(lv, "#saved_items", a.name)
      assert Carts.list_items(cart.id) |> Enum.any?(&(&1.id == item_a.id))
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

    test "a promo code is accepted in any case with surrounding spaces", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      html = lv |> form("[phx-submit=apply_promo]", %{code: "  half "}) |> render_submit()
      assert html =~ "HALF"
      assert html =~ "Promo applied"
    end

    test "invalid promo shows an error", %{conn: conn} do
      %{lv: lv} = open_cart(conn)
      html = lv |> form("[phx-submit=apply_promo]", %{code: "BOGUS"}) |> render_submit()
      assert html =~ "Invalid promo code"
    end

    test "selecting express shipping updates the cost", %{conn: conn} do
      %{lv: lv} = open_cart(conn)

      html =
        lv |> element(~s([phx-click=select_shipping][phx-value-method=express])) |> render_click()

      assert html =~ "Express"
    end
  end

  describe "real-time stock" do
    test "a stock fact marks the item out of stock", %{conn: conn} do
      %{lv: lv, product_a: a} = open_cart(conn)

      GoodDealWeb.Paradigms.ChangeFeed.publish(
        [topic: GoodDeal.Catalog.changes_topic(), facts: [:stock]],
        %{a | stock: 0}
      )

      assert render(lv) =~ "Out of stock"
    end

    test "a staff stock edit at /products reaches an open cart", %{conn: conn} do
      %{lv: lv, product_a: a} = open_cart(conn)
      {:ok, products, _} = live(conn, ~p"/products/#{a}/show/edit")

      products |> form("#product-form", product: %{stock: 0}) |> render_submit()

      assert render(lv) =~ "Out of stock"
    end
  end

  describe "multi-step checkout" do
    test "address → payment → pay → redirect", %{conn: conn} do
      %{lv: lv, cart: cart} = open_cart(conn)

      GoodDeal.MockPaymentGateway
      |> expect(:charge, fn amount, currency, metadata ->
        assert amount == 3500
        assert currency == "usd"
        assert metadata["cart_id"] == cart.id
        {:ok, "chg_test"}
      end)

      # Start checkout → address form
      lv |> element("button", "Checkout") |> render_click()
      assert_patch(lv, ~p"/cart/checkout")
      assert render(lv) =~ "Full name"

      # Invalid address stays on the form with an error
      html =
        lv
        |> form("[phx-submit=submit_address]",
          address: %{name: "", line1: "", city: "", postal_code: "x"}
        )
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
      assert_redirect(lv, ~p"/cart/success")
      assert GoodDeal.Foundation.Carts.get(cart.id).status == :completed
    end

    test "paying while a removal is held neither charges, deducts nor records the held line",
         %{conn: conn} do
      %{lv: lv, cart: cart, item_a: item_a, product_a: a, product_b: b} = open_cart(conn)
      test_pid = self()

      GoodDeal.MockPaymentGateway
      |> expect(:charge, fn amount, _, _ ->
        send(test_pid, {:charged, amount})
        {:ok, "chg_held"}
      end)

      click(lv, "remove_item", item_a.id)
      lv |> element("button", "Checkout") |> render_click()

      lv
      |> form("[phx-submit=submit_address]",
        address: %{name: "Ada", line1: "1 Ave", city: "London", postal_code: "12345"}
      )
      |> render_submit()

      lv |> element("button", "Pay") |> render_click()
      assert_redirect(lv, ~p"/cart/success")

      assert_received {:charged, 2500}
      assert Products.get!(a.id).stock == 10
      assert Products.get!(b.id).stock == 4
      assert [%{product_id: product_id}] = stored(cart.id)
      assert product_id == b.id
    end

    test "paying with an item saved for later neither charges, deducts nor records it",
         %{conn: conn} do
      %{lv: lv, cart: cart, item_a: item_a, product_a: a, product_b: b} = open_cart(conn)
      test_pid = self()

      GoodDeal.MockPaymentGateway
      |> expect(:charge, fn amount, _, _ ->
        send(test_pid, {:charged, amount})
        {:ok, "chg_saved"}
      end)

      click(lv, "save_for_later", item_a.id)
      lv |> element("button", "Checkout") |> render_click()

      lv
      |> form("[phx-submit=submit_address]",
        address: %{name: "Ada", line1: "1 Ave", city: "London", postal_code: "12345"}
      )
      |> render_submit()

      lv |> element("button", "Pay") |> render_click()
      assert_redirect(lv, ~p"/cart/success")

      assert_received {:charged, 2500}
      assert Products.get!(a.id).stock == 10
      assert Products.get!(b.id).stock == 4
      assert [%{product_id: product_id}] = Carts.list_items(cart.id)
      assert product_id == b.id
    end

    test "a failed payment offers a retry that pays again", %{conn: conn} do
      %{lv: lv} = open_cart(conn)

      GoodDeal.MockPaymentGateway
      |> expect(:charge, fn _, _, _ -> {:error, :declined} end)
      |> expect(:charge, fn _, _, _ -> {:ok, "chg_retry"} end)

      lv |> element("button", "Checkout") |> render_click()

      lv
      |> form("[phx-submit=submit_address]",
        address: %{name: "Ada", line1: "1 Ave", city: "London", postal_code: "12345"}
      )
      |> render_submit()

      lv |> element("button", "Pay") |> render_click()
      assert render_async(lv) =~ "Payment failed."

      lv |> element("button", "Try again") |> render_click()
      assert_redirect(lv, ~p"/cart/success")
    end

    # V33: the URL is live for flow steps — browser back honors the
    # declared backward edge; a forward jump (skipping validation) is
    # ignored and the session stays authoritative. (In V30 the URL changed
    # per step but navigation to it did nothing — a latent stale-URL bug.)
    test "browser back returns to the address step; a forward URL jump is ignored", %{conn: conn} do
      %{lv: lv} = open_cart(conn)

      lv |> element("button", "Checkout") |> render_click()
      assert_patch(lv, ~p"/cart/checkout")

      lv
      |> form("[phx-submit=submit_address]",
        address: %{name: "Ada", line1: "1 Ave", city: "London", postal_code: "12345"}
      )
      |> render_submit()

      assert_patch(lv, ~p"/cart/checkout/payment")

      # Back button: /cart/checkout → the address step (edit edge).
      html = render_patch(lv, ~p"/cart/checkout")
      assert html =~ "Full name"

      # Forward to /cart/checkout/payment from address: ignored.
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
