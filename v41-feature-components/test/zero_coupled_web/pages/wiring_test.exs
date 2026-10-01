defmodule ZeroCoupledWeb.WiringTest do
  @moduledoc """
  The pages have no catch-all `handle_info`, so an announcement nobody routes would crash the page.
  This sends every port each instance declares it announces (plus the page's other messages) to
  the page, and fails if the page has no clause for it. A clause that exists but can't handle the
  sample payload is still a route, so only a missing clause counts.
  """
  use ExUnit.Case, async: true

  alias ZeroCoupled.Features.{
    Cart,
    Checkout,
    OrderLines,
    PortalCatalog,
    PortalSubmit,
    SavedItems,
    Undo,
    Wishlist
  }

  alias ZeroCoupled.Foundation.Broadcast.Facts

  @socket %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}
  @broadcasts [%Facts.StockChanged{product_id: 1, stock: 1}, %Facts.ProductSaved{product: %{}}]

  defp routed?(page, msg) do
    page.handle_info(msg, @socket)
    true
  rescue
    e in FunctionClauseError -> not (e.module == page and e.function == :handle_info)
    _ -> true
  end

  defp announced(instances),
    do: for({name, panel} <- instances, port <- panel.announces(), do: {name, port, :sample})

  test "the cart page routes everything its instances announce" do
    instances = [
      cart: Cart.Panel,
      undo: Undo.Banner,
      saved: SavedItems.Panel,
      wishlist: Wishlist.Panel,
      checkout: Checkout.Panel
    ]

    for msg <- announced(instances) ++ [{:undo, :expire, 1}] ++ @broadcasts,
        do:
          assert(
            routed?(ZeroCoupledWeb.CartPage, msg),
            "CartPage has no route for #{inspect(msg)}"
          )
  end

  test "the portal page routes everything its instances announce" do
    instances = [
      catalog: PortalCatalog.Panel,
      order: OrderLines.Panel,
      undo: Undo.Banner,
      submit: PortalSubmit.Panel
    ]

    for msg <- announced(instances) ++ [{:undo, :expire, 1}] ++ @broadcasts,
        do:
          assert(
            routed?(ZeroCoupledWeb.PortalPage, msg),
            "PortalPage has no route for #{inspect(msg)}"
          )
  end
end
