defmodule ZeroCoupledWeb.WiringTest do
  @moduledoc """
  Each page's wiring is one route table. This checks that every port each instance sends the page
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

  defp sent_outputs(instances),
    do: for({name, panel} <- instances, port <- panel.sent_port_outputs(), do: {name, port})

  defp check(page, instances) do
    routes = page.routes()
    expected = sent_outputs(instances) ++ [{:undo, :expire}, {:stock, :changed}]

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

  test "the cart page routes everything its instances send" do
    check(ZeroCoupledWeb.CartPage,
      cart: Cart.Panel,
      undo: Undo.Banner,
      saved: SavedItems.Panel,
      wishlist: Wishlist.Panel,
      checkout: Checkout.Panel
    )
  end

  test "the portal page routes everything its instances send" do
    check(ZeroCoupledWeb.PortalPage,
      catalog: PortalCatalog.Panel,
      order: OrderLines.Panel,
      undo: Undo.Banner,
      submit: PortalSubmit.Panel
    )
  end
end

defmodule ZeroCoupledWeb.DrawingTest do
  use ExUnit.Case, async: true

  test "the cart page's diagram is drawn from its route table" do
    chart = ZeroCoupledWeb.Paradigms.Drawing.mermaid(ZeroCoupledWeb.CartPage.routes())
    assert chart =~ ~s(cart -->|"removed → capture"| undo)
    assert chart =~ ~s(wishlist -->|"taken via add_line → receive"| cart)
    assert chart =~ ~s(payment -->|"succeeded → succeeded"| checkout)
  end
end
