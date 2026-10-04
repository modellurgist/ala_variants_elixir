defmodule GoodDealWeb.Stories.BrowseCatalog do
  @moduledoc """
  The buyer browses the catalogue with live stock and asks for a quantity of a product. Its part is
  the portal's catalogue; its view is the product rows. Out: `:requested`, a product and quantity
  for the order.
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [stream: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Rows, only: [catalog_row: 1]

  alias GoodDeal.State.PortalCatalog
  alias GoodDeal.Foundation.Products
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{catalog: PortalCatalog}
  def events, do: ~w(add_to_order)
  def ports, do: %{in: [stock: :stock_change], out: [requested: :product_quantity]}

  @doc "Config: `stock_status`, a configured `StockStatus`."
  def mount(s, opts, out) do
    s
    |> assign(:catalog, PortalCatalog.new(stock_status: opts[:stock_status]))
    |> stream(:portal_products, [])
    |> feed(&PortalCatalog.load/2, &Products.list/0, nil, out)
  end

  def handle_event("add_to_order", %{"product-id" => id, "quantity" => q}, s, out),
    do:
      run(
        s,
        &PortalCatalog.request(&1, %{
          product_id: String.to_integer(id),
          quantity: String.to_integer(q)
        }),
        out
      )

  def input(s, :stock, change, out), do: run(s, &PortalCatalog.set_stock(&1, change), out)

  defp run(s, step, out), do: Steps.run(s, :catalog, step, &wire(&1, &2, &3, out))

  defp feed(s, input, source, payload, out),
    do: Steps.feed(s, :catalog, input, source, payload, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :catalog, {:rows, change}, _out),
    do: Steps.stream_change(s, :portal_products, change)

  defp wire(s, :catalog, {:requested, request}, out), do: out.(s, {:requested, request})

  attr :streams, :any, required: true
  attr :t, :map, required: true

  def view(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="portal_products" stream={@streams.portal_products}>
      <.catalog_row id={dom_id} row={row} on_add="add_to_order" t={@t.row} />
    </.stream_list>
    """
  end
end
