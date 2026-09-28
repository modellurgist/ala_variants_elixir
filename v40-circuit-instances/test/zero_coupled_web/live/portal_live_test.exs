defmodule ZeroCoupledWeb.PortalLiveTest do
  @moduledoc "End-to-end coverage of the portal: browse, order, review, submit. Actions settle as in the cart tests."
  use ZeroCoupledWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZeroCoupled.StoreFixtures

  alias ZeroCoupled.Foundation.Broadcast

  defp open_portal(conn) do
    a = product_fixture(%{name: "Bulk Widget", amount: 10_000, stock: 50})
    b = product_fixture(%{name: "Bulk Gadget", amount: 5_000, stock: 3})

    conn = get(conn, ~p"/portal")
    {:ok, lv, _html} = live(conn, ~p"/portal")
    settle(lv)
    %{lv: lv, conn: conn, product_a: a, product_b: b}
  end

  defp settle(lv) do
    render(lv)
    render(lv)
  end

  defp add(lv, product, quantity) do
    lv
    |> element(~s(#portal_products-#{product.id} form))
    |> render_submit(%{"product-id" => product.id, "quantity" => quantity})

    settle(lv)
  end

  defp click(lv, selector, text \\ nil) do
    lv |> element(selector, text) |> render_click()
    settle(lv)
  end

  defp submit(lv, params) do
    lv |> form("form", params) |> render_submit()
    settle(lv)
  end

  test "browse → add at quantity → tier discount → review → submit", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)

    html = add(lv, a, "6")
    assert html =~ "Added to order"
    assert html =~ "Bulk Widget"
    assert html =~ "5% volume discount"

    click(lv, "button", "Review order")
    assert_patch(lv, ~p"/portal/review")
    assert render(lv) =~ "Purchase order number"

    assert submit(lv, po: %{number: "nope"}) =~ "must look like PO-1234"

    html = submit(lv, po: %{number: "PO-2026"})
    assert_patch(lv, ~p"/portal/submitted")
    assert html =~ "Order submitted"
    assert html =~ "PO-2026"
  end

  test "repeat add of the same product accumulates quantity", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)
    add(lv, a, "2")
    assert add(lv, a, "3") =~ ~s(value="5")
  end

  test "browser back from review honors the edge; forward jump is ignored", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)
    add(lv, a, "1")
    click(lv, "button", "Review order")
    assert_patch(lv, ~p"/portal/review")

    html = render_patch(lv, ~p"/portal")
    assert html =~ "Products"

    html = render_patch(lv, ~p"/portal/review")
    assert html =~ "Products"
  end

  test "a StockChanged fact updates both the catalog row and an order line", %{conn: conn} do
    %{lv: lv, product_b: b} = open_portal(conn)
    add(lv, b, "1")

    send(lv.pid, %Broadcast.Facts.StockChanged{product_id: b.id, stock: 0})
    html = settle(lv)
    assert html =~ "Out of stock"
    assert length(Regex.scan(~r/Out of stock/, html)) == 2
  end

  test "removing a line arms the reused undo banner; undo restores it", %{conn: conn} do
    %{lv: lv, product_a: a} = open_portal(conn)
    add(lv, a, "2")

    assert click(lv, ~s(#order_lines button), "Remove") =~ "Item removed."

    html = click(lv, "button", "Undo")
    refute html =~ "Item removed."
    assert html =~ "Bulk Widget"
  end
end
