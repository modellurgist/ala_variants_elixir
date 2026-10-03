defmodule GoodDealWeb.Stories.BrowseCatalog do
  @moduledoc """
  A business buyer browses the catalog with live stock and adds a product at a quantity. Its part is
  the catalog; its instance stores the new line in the draft. Ports: `mounted`, `stock`; out, the line
  `added` to the draft.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import Phoenix.LiveView, only: [put_flash: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Rows, only: [catalog_row: 1]

  alias GoodDeal.Domain.AddLine
  alias GoodDeal.Foundation.Products
  alias GoodDeal.State.PortalCatalog
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  def parts, do: %{catalog: PortalCatalog}
  def streams, do: [:portal_products]
  def events, do: ["add_to_order"]
  def ports, do: %{in: [mounted: :event, stock: :stock_change], out: [added: :item_quantity]}

  @doc "Config: `stock_status` (a configured `StockStatus`) and `add_line`, the instance that stores a line."
  def new(opts),
    do:
      Story.new(__MODULE__, %{catalog: PortalCatalog.new(stock_status: opts[:stock_status])},
        instances: %{add_line: opts[:add_line]}
      )

  def input(s, me, :mounted, _),
    do: Story.feed(s, me, :catalog, &PortalCatalog.load/2, &Products.list/0, nil)

  def input(s, me, :stock, change),
    do: Story.run(s, me, :catalog, &PortalCatalog.set_stock(&1, change))

  def event(s, me, "add_to_order", %{"product-id" => id, "quantity" => q}),
    do:
      Story.run(
        s,
        me,
        :catalog,
        &PortalCatalog.request(&1, %{product_id: int(id), quantity: int(q)})
      )

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, _me, :catalog, {:rows, change}),
    do: Sinks.stream_change(s, :portal_products, change)

  def wire(s, me, :catalog, {:requested, request}),
    do:
      s
      |> Story.send_out_answer(me, :added, {:add_line, &AddLine.run/2}, request)
      |> put_flash(:info, "Added to order")

  defp int(s) when is_binary(s), do: String.to_integer(s)
  defp int(n) when is_integer(n), do: n

  attr :streams, :map, required: true
  attr :t, :map, required: true, doc: "the catalog's texts, from the page"

  def view(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="portal_products" stream={@streams.portal_products}>
      <.catalog_row id={dom_id} row={row} on_add="add_to_order" t={@t.row} />
    </.stream_list>
    """
  end
end
