defmodule ZeroCoupledWeb.PortalLiveTest do
  @moduledoc "End-to-end coverage of the D6 portal: browse → order → review → submit."
  use ZeroCoupledWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZeroCoupled.StoreFixtures

  alias ZeroCoupled.Foundation.Broadcast

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

    send(lv.pid, %Broadcast.Facts.StockChanged{product_id: b.id, stock: 0})
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
end
