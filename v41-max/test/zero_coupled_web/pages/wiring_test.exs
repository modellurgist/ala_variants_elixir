defmodule ZeroCoupledWeb.WiringTest do
  @moduledoc """
  Each page's wiring is one route table. This checks that every port each instance announces
  (derived from its feature's declared ports), the undo clock's message and the stock broadcast
  all have a route, and that every route's `pass` target names an instance on the page.
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

  defp announced(instances),
    do: for({name, panel} <- instances, port <- panel.announces(), do: {name, port})

  defp check(page, instances) do
    routes = page.routes()
    expected = announced(instances) ++ [{:undo, :expire}, {:stock, :changed}]

    for key <- expected,
        do: assert(Map.has_key?(routes, key), "#{inspect(page)} has no route for #{inspect(key)}")

    placed = Enum.map(instances, &elem(&1, 1))

    for {_key, targets} <- routes,
        {:pass, {component, _id, _input}} <- targets,
        do:
          assert(
            component in placed,
            "#{inspect(page)} routes to #{inspect(component)}, which it doesn't place"
          )
  end

  test "the cart page routes everything its instances announce" do
    check(ZeroCoupledWeb.CartPage,
      cart: Cart.Panel,
      undo: Undo.Banner,
      saved: SavedItems.Panel,
      wishlist: Wishlist.Panel,
      checkout: Checkout.Panel
    )
  end

  test "the portal page routes everything its instances announce" do
    check(ZeroCoupledWeb.PortalPage,
      catalog: PortalCatalog.Panel,
      order: OrderLines.Panel,
      undo: Undo.Banner,
      submit: PortalSubmit.Panel
    )
  end
end
