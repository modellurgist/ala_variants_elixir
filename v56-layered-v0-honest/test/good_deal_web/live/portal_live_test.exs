defmodule GoodDealWeb.PortalLiveTest do
  use GoodDealWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GoodDeal.CatalogFixtures
  import GoodDeal.ShoppingCartFixtures, only: [shop: 2]

  alias GoodDeal.{Catalog, Orders, ShoppingCart}

  setup %{conn: conn} do
    a = product_fixture(%{name: "Bulk Widget", amount: 10_000, stock: 50})
    b = product_fixture(%{name: "Bulk Gadget", amount: 5_000, stock: 3})
    c = product_fixture(%{name: "Empty Crate", amount: 1_000, stock: 0})

    conn = get(conn, ~p"/portal")
    cart_id = get_session(conn, "portal_cart_id")
    {:ok, lv, _html} = live(conn, ~p"/portal")

    %{conn: conn, lv: lv, cart_id: cart_id, a: a, b: b, c: c}
  end

  defp add(lv, product, quantity) do
    lv
    |> element("#products-#{product.id} form")
    |> render_submit(%{"product_id" => product.id, "quantity" => quantity})
  end

  defp line(cart_id, product),
    do: ShoppingCart.get_cart_item_for_product(shop(cart_id, :portal), product.id)

  defp summary(lv), do: lv |> element("#summary") |> render()

  describe "order step" do
    test "lists the catalog with stock status; out-of-stock rows cannot be added",
         %{lv: lv, a: a, b: b, c: c} do
      assert lv |> element("#products-#{a.id}") |> render() =~ "In stock"
      assert lv |> element("#products-#{b.id}") |> render() =~ "Low stock"
      assert lv |> element("#products-#{c.id}") |> render() =~ "Out of stock"
      assert has_element?(lv, "#products-#{c.id} button[disabled]", "Add to order")
      refute has_element?(lv, "#products-#{a.id} button[disabled]")
      assert has_element?(lv, ~s(#products-#{a.id} input[name="quantity"][min="1"]))
    end

    test "catalog and lines are streams", %{lv: lv} do
      assert has_element?(lv, ~s(#portal-products[phx-update="stream"]))
      assert has_element?(lv, ~s(#order-lines[phx-update="stream"]))
    end

    test "adding sets the requested quantity and repeat adds accumulate",
         %{lv: lv, cart_id: cart_id, a: a} do
      assert add(lv, a, "2") =~ "Added to order"
      assert line(cart_id, a).quantity == 2

      add(lv, a, "3")
      assert line(cart_id, a).quantity == 5
      assert has_element?(lv, ~s(#order-lines input[name="quantity"][value="5"]))
    end

    test "the added quantity is at least 1", %{lv: lv, cart_id: cart_id, a: a, b: b} do
      add(lv, a, "0")
      add(lv, b, "lots")
      assert line(cart_id, a).quantity == 1
      assert line(cart_id, b).quantity == 1
    end

    test "lines show name, stock status, quantity and line total; changing quantity persists and reprices",
         %{lv: lv, cart_id: cart_id, b: b} do
      add(lv, b, "1")
      item = line(cart_id, b)
      row = lv |> element("#lines-#{item.id}") |> render()
      assert row =~ "Bulk Gadget"
      assert row =~ "Low stock"
      assert row =~ "$50.00"

      lv
      |> element("#lines-#{item.id} form")
      |> render_change(%{"item_id" => item.id, "quantity" => "3"})

      assert line(cart_id, b).quantity == 3
      assert lv |> element("#lines-#{item.id}") |> render() =~ "$150.00"
      assert summary(lv) =~ "$150.00"

      for bad <- ["0", "", "x"] do
        lv
        |> element("#lines-#{item.id} form")
        |> render_change(%{"item_id" => item.id, "quantity" => bad})
      end

      assert line(cart_id, b).quantity == 3
    end

    test "volume pricing applies by tier and reprices across boundaries",
         %{lv: lv, cart_id: cart_id, a: a} do
      add(lv, a, "4")
      refute summary(lv) =~ "volume discount"

      add(lv, a, "2")
      assert summary(lv) =~ "5% volume discount"
      assert summary(lv) =~ "-$30.00"

      item = line(cart_id, a)

      lv
      |> element("#lines-#{item.id} form")
      |> render_change(%{"item_id" => item.id, "quantity" => "20"})

      assert summary(lv) =~ "10% volume discount"

      lv
      |> element("#lines-#{item.id} form")
      |> render_change(%{"item_id" => item.id, "quantity" => "1"})

      refute summary(lv) =~ "volume discount"
    end

    test "the 5% tier starts at exactly 50,000", %{lv: lv} do
      just_under = product_fixture(%{name: "Just Under", amount: 49_999, stock: 50})
      one_cent = product_fixture(%{name: "One Cent", amount: 1, stock: 50})

      add(lv, just_under, "1")
      refute summary(lv) =~ "volume discount"

      add(lv, one_cent, "1")
      assert summary(lv) =~ "5% volume discount"
      assert summary(lv) =~ "-$25.00"
    end

    test "shipping methods are the storefront's", %{lv: lv, cart_id: cart_id, b: b} do
      add(lv, b, "1")
      assert summary(lv) =~ "Free"

      lv |> element(~s(#order-step button[phx-value-method="overnight"])) |> render_click()
      assert summary(lv) =~ "Overnight"
      assert summary(lv) =~ "$24.99"
      assert ShoppingCart.get_cart!(cart_id).shipping_method == "overnight"
    end
  end

  describe "removal and undo" do
    setup %{lv: lv, cart_id: cart_id, a: a} do
      add(lv, a, "2")
      %{item: line(cart_id, a)}
    end

    test "removing a line arms the undo banner; undo restores and reprices",
         %{lv: lv, item: item} do
      html = lv |> element("#lines-#{item.id} button", "Remove") |> render_click()
      assert html =~ "Item removed."
      refute has_element?(lv, "#lines-#{item.id}")
      refute summary(lv) =~ "$200.00"

      html = lv |> element("#undo-banner button", "Undo") |> render_click()
      assert html =~ "Item restored"
      refute has_element?(lv, "#undo-banner")
      assert has_element?(lv, "#lines-#{item.id}")
      assert summary(lv) =~ "$200.00"
    end

    test "the elapsed window persists the removal", %{lv: lv, cart_id: cart_id, a: a, item: item} do
      lv |> element("#lines-#{item.id} button", "Remove") |> render_click()
      send(lv.pid, {:undo_expired, item.id})

      refute has_element?(lv, "#undo-banner")
      assert line(cart_id, a) == nil
    end

    test "only the latest removal is undoable", %{
      lv: lv,
      cart_id: cart_id,
      a: a,
      b: b,
      item: item
    } do
      add(lv, b, "1")
      other = line(cart_id, b)

      lv |> element("#lines-#{item.id} button", "Remove") |> render_click()
      lv |> element("#lines-#{other.id} button", "Remove") |> render_click()
      assert line(cart_id, a) == nil

      lv |> element("#undo-banner button", "Undo") |> render_click()
      assert has_element?(lv, "#lines-#{other.id}")
    end

    test "undo with nothing pending does nothing", %{lv: lv} do
      refute render_click(lv, "undo_remove", %{}) =~ "Item restored"
    end

    test "adding while a removal is pending makes the removal final",
         %{lv: lv, cart_id: cart_id, a: a, item: item} do
      lv |> element("#lines-#{item.id} button", "Remove") |> render_click()
      add(lv, a, "1")

      assert line(cart_id, a).quantity == 1
      refute has_element?(lv, "#undo-banner")
    end
  end

  describe "review and submit" do
    test "reviewing an empty order flashes and stays", %{lv: lv} do
      assert lv |> element("#review-button") |> render_click() =~ "Your order is empty"
      refute has_element?(lv, "#review-step")
    end

    test "reviewing with only a pending removal counts as empty", %{
      lv: lv,
      cart_id: cart_id,
      a: a
    } do
      add(lv, a, "1")
      lv |> element("#order-lines button", "Remove") |> render_click()

      assert lv |> element("#review-button") |> render_click() =~ "Your order is empty"
      assert line(cart_id, a) == nil
    end

    test "review shows totals and a live-validated PO form; Edit lines goes back",
         %{lv: lv, a: a} do
      add(lv, a, "6")
      assert lv |> element("#review-button") |> render() =~ "Review order · $570.00"

      lv |> element("#review-button") |> render_click()
      assert_patch(lv, ~p"/portal/review")
      assert lv |> element("#review-step") |> render() =~ "$570.00"
      assert has_element?(lv, "#order-step.hidden")

      assert lv |> form("#po-form", po: %{number: ""}) |> render_change() =~
               "can&#39;t be blank"

      assert lv |> form("#po-form", po: %{number: "PO-12"}) |> render_change() =~
               "must look like PO-1234"

      lv |> element("button", "Edit lines") |> render_click()
      assert_patch(lv, ~p"/portal")
      refute has_element?(lv, "#review-step")
    end

    test "an invalid PO stays on review", %{lv: lv, cart_id: cart_id, a: a} do
      add(lv, a, "1")
      lv |> element("#review-button") |> render_click()

      assert lv |> form("#po-form", po: %{number: "nope"}) |> render_submit() =~
               "must look like PO-1234"

      assert ShoppingCart.get_cart!(cart_id).status == :open
    end

    test "a valid PO completes the draft, creates the order and lands on Submitted",
         %{lv: lv, cart_id: cart_id, a: a} do
      add(lv, a, "6")
      lv |> element("#review-button") |> render_click()

      html = lv |> form("#po-form", po: %{number: "PO-2026"}) |> render_submit()
      assert_patch(lv, ~p"/portal/submitted")

      assert html =~ "Order submitted"
      assert ShoppingCart.get_cart!(cart_id).status == :completed
      assert [order] = GoodDeal.Repo.all(Orders.Order)
      assert order.po_number == "PO-2026"

      assert lv |> element("#submitted-step") |> render() =~
               GoodDealWeb.ShopComponents.order_reference(order)

      assert lv |> element("#submitted-step") |> render() =~ "PO-2026"
    end
  end

  describe "step URLs" do
    test "back from review is honoured; a forward jump is ignored", %{lv: lv, a: a} do
      add(lv, a, "1")
      lv |> element("#review-button") |> render_click()
      assert_patch(lv, ~p"/portal/review")

      render_patch(lv, ~p"/portal")
      refute has_element?(lv, "#review-step")
      refute has_element?(lv, "#order-step.hidden")

      render_patch(lv, ~p"/portal/review")
      assert_patch(lv, ~p"/portal")
      refute has_element?(lv, "#review-step")

      render_patch(lv, ~p"/portal/submitted")
      assert_patch(lv, ~p"/portal")
    end

    test "after submitting, earlier steps cannot be reopened", %{lv: lv, a: a} do
      add(lv, a, "1")
      lv |> element("#review-button") |> render_click()
      lv |> form("#po-form", po: %{number: "PO-2026"}) |> render_submit()

      render_patch(lv, ~p"/portal")
      assert_patch(lv, ~p"/portal/submitted")
      assert has_element?(lv, "#submitted-step")
    end

    test "loading the review URL lands on review when the draft has lines", %{conn: conn, a: a} do
      {:ok, lv, _} = live(conn, ~p"/portal")
      add(lv, a, "1")

      {:ok, lv, _} = live(conn, ~p"/portal/review")
      assert has_element?(lv, "#review-step")
    end

    test "loading review with an empty draft, or submitted, lands on the order step",
         %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/portal"}}} = live(conn, ~p"/portal/review")
      assert {:error, {:live_redirect, %{to: "/portal"}}} = live(conn, ~p"/portal/submitted")
    end

    test "returning by live navigation after submitting starts a new draft", %{lv: lv, a: a} do
      add(lv, a, "1")
      lv |> element("#review-button") |> render_click()
      lv |> form("#po-form", po: %{number: "PO-2026"}) |> render_submit()

      assert {:error, {:redirect, %{to: "/portal"}}} = live_redirect(lv, to: ~p"/portal")
    end
  end

  describe "live updates" do
    test "stock changes update the catalog row and the affected order line",
         %{conn: conn, lv: lv, cart_id: cart_id, b: b} do
      add(lv, b, "1")
      item = line(cart_id, b)
      {:ok, other_lv, _} = live(conn, ~p"/portal")

      {:ok, _} = Catalog.update_product(b, %{stock: 0})

      assert lv |> element("#products-#{b.id}") |> render() =~ "Out of stock"
      assert lv |> element("#lines-#{item.id}") |> render() =~ "Out of stock"
      assert other_lv |> element("#products-#{b.id}") |> render() =~ "Out of stock"
    end

    test "a change to a product pending removal keeps its line hidden",
         %{lv: lv, cart_id: cart_id, b: b} do
      add(lv, b, "1")
      item = line(cart_id, b)
      lv |> element("#lines-#{item.id} button", "Remove") |> render_click()

      {:ok, _} = Catalog.update_product(b, %{stock: 0})
      refute has_element?(lv, "#lines-#{item.id}")
    end

    test "new and deleted products appear and disappear",
         %{lv: lv, cart_id: cart_id, a: a, c: c} do
      add(lv, a, "1")
      item = line(cart_id, a)

      new = product_fixture(%{name: "Fresh Pallet"})
      assert has_element?(lv, "#products-#{new.id}")

      {:ok, _} = Catalog.delete_product(c)
      refute has_element?(lv, "#products-#{c.id}")

      {:ok, _} = Catalog.delete_product(a)
      refute has_element?(lv, "#products-#{a.id}")
      refute has_element?(lv, "#lines-#{item.id}")
    end
  end
end
