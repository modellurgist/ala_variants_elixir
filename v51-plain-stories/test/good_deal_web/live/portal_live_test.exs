defmodule GoodDealWeb.PortalLiveTest do
  @moduledoc "Acceptance tests for the portal requirements (ported from V39-max; same checks for every full variant)."
  use GoodDealWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GoodDeal.StoreFixtures
  import Ecto.Query

  alias GoodDeal.{Catalog, Repo}
  alias GoodDeal.Foundation.Carts
  alias GoodDeal.Foundation.Schemas.CartItem

  defp open_portal(conn) do
    a = product_fixture(%{name: "Bulk Widget", amount: 10_000, stock: 50})
    b = product_fixture(%{name: "Bulk Gadget", amount: 5_000, stock: 3})

    conn = get(conn, ~p"/portal")
    {:ok, lv, _html} = live(conn, ~p"/portal")
    %{lv: lv, conn: conn, product_a: a, product_b: b}
  end

  test "browse → add at quantity → tier discount → review → submit", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    # Add 6 × $100 from the catalog row's quantity form.
    html =
      lv
      |> element(~s(#portal_products-#{a.id} form))
      |> render_submit(%{"product-id" => a.id, "quantity" => "6"})

    assert html =~ "Added to order"
    assert html =~ "Bulk Widget"
    # $600 subtotal crosses the 5% tier.
    assert html =~ "5% volume discount"

    # Review: milestone chrome comes from the manifest's flow channel.
    lv |> element("button", "Review order") |> render_click()
    assert_patch(lv, ~p"/portal/review")
    assert render(lv) =~ "Purchase order number"

    # Invalid PO stays on the form.
    html = lv |> form("form", po: %{number: "nope"}) |> render_submit()
    assert html =~ "must look like PO-1234"

    # Valid PO submits the order.
    html = lv |> form("form", po: %{number: "PO-2026"}) |> render_submit()
    assert_patch(lv, ~p"/portal/submitted")
    assert html =~ "Order submitted"
    assert html =~ "PO-2026"
  end

  test "repeat add of the same product accumulates quantity", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{a.id} form))
    |> render_submit(%{"product-id" => a.id, "quantity" => "2"})

    html =
      lv
      |> element(~s(#portal_products-#{a.id} form))
      |> render_submit(%{"product-id" => a.id, "quantity" => "3"})

    assert html =~ ~s(value="5")
  end

  test "browser back from review honors the edge; forward jump is ignored", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{a.id} form))
    |> render_submit(%{"product-id" => a.id, "quantity" => "1"})

    lv |> element("button", "Review order") |> render_click()
    assert_patch(lv, ~p"/portal/review")

    # Back: allowed (the :edit_lines edge).
    html = render_patch(lv, ~p"/portal")
    assert html =~ "Products"

    # Forward jump to review via URL: ignored, lines still shown.
    html = render_patch(lv, ~p"/portal/review")
    assert html =~ "Products"
  end

  test "a StockChanged fact updates both the catalog row and an order line", %{conn: conn} do
    %{lv: lv, product_b: b} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{b.id} form))
    |> render_submit(%{"product-id" => b.id, "quantity" => "1"})

    send(lv.pid, {:stock_changed, {b.id, 0}})
    assert render(lv) =~ "Out of stock"
  end

  test "removing a line arms the reused undo banner; undo restores it", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{a.id} form))
    |> render_submit(%{"product-id" => a.id, "quantity" => "2"})

    html = lv |> element(~s(#order_lines button), "Remove") |> render_click()
    assert html =~ "Item removed."

    html = lv |> element("button", "Undo") |> render_click()
    refute html =~ "Item removed."
    assert html =~ "Bulk Widget"
  end

  test "when the undo window elapses the removal is final", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{a.id} form))
    |> render_submit(%{"product-id" => a.id, "quantity" => "2"})

    lv |> element(~s(#order_lines button), "Remove") |> render_click()
    held = :sys.get_state(lv.pid).socket.assigns.undo.pending
    send(lv.pid, {:timer, :undo, held})
    html = render(lv)
    refute html =~ "Item removed."
    refute html =~ ~s(#order_lines-#{held.id})
  end

  test "undoing a removal flashes that the item is back", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{a.id} form))
    |> render_submit(%{"product-id" => a.id, "quantity" => "2"})

    lv |> element(~s(#order_lines button), "Remove") |> render_click()
    html = lv |> element("button", "Undo") |> render_click()
    assert html =~ "Item restored"
  end

  test "submitting while a removal is held doesn't record the held line", %{conn: conn} do
    %{lv: lv, product_a: a, product_b: b} = open_portal(conn)

    for {product, quantity} <- [{a, "2"}, {b, "1"}] do
      lv
      |> element(~s(#portal_products-#{product.id} form))
      |> render_submit(%{"product-id" => product.id, "quantity" => quantity})
    end

    cart_id = :sys.get_state(lv.pid).socket.assigns.order.cart_id
    held = Carts.list_items(cart_id) |> Enum.find(&(&1.product.id == a.id))
    lv |> element(~s(#order_lines-#{held.id} button), "Remove") |> render_click()

    lv |> element("button", "Review order") |> render_click()
    lv |> form("form", po: %{number: "PO-2026"}) |> render_submit()
    assert_patch(lv, ~p"/portal/submitted")

    stored = Repo.all(from ci in CartItem, where: ci.cart_id == ^cart_id)
    assert [%{product_id: product_id}] = stored
    assert product_id == b.id
  end

  test "a removal held when the portal closes stays removed, and is final once the window elapses",
       %{conn: conn} do
    %{lv: lv, conn: conn, product_a: a} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{a.id} form))
    |> render_submit(%{"product-id" => a.id, "quantity" => "2"})

    cart_id = :sys.get_state(lv.pid).socket.assigns.order.cart_id
    [held] = Carts.list_items(cart_id)
    lv |> element(~s(#order_lines button), "Remove") |> render_click()
    close(lv)

    {:ok, lv, _html} = live(conn, ~p"/portal")
    refute has_element?(lv, "#order_lines-#{held.id}")
    close(lv)

    at = DateTime.add(DateTime.utc_now(), -(Catalog.undo_window_ms() + 1_000), :millisecond)
    Repo.update_all(from(ci in CartItem, where: ci.id == ^held.id), set: [removed_at: at])
    {:ok, lv, _html} = live(conn, ~p"/portal")
    refute has_element?(lv, "#order_lines-#{held.id}")
    refute Repo.get(CartItem, held.id)
  end

  # the review button is disabled once the order empties; a click already in flight still arrives
  test "an info and an error flash show together under distinct ids", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    lv
    |> element(~s(#portal_products-#{a.id} form))
    |> render_submit(%{"product-id" => a.id, "quantity" => "2"})

    lv |> element(~s(#order_lines button), "Remove") |> render_click()
    render_click(lv, "go_review", %{})

    assert has_element?(lv, "#flash-info", "Added to order")
    assert has_element?(lv, "#flash-error", "Your order is empty")
  end

  defp close(lv) do
    ref = Process.monitor(lv.pid)
    GenServer.stop(lv.pid, :normal)
    assert_receive {:DOWN, ^ref, _, _, _}
  end
end
