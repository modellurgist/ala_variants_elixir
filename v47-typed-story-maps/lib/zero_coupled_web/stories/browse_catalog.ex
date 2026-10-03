defmodule ZeroCoupledWeb.Stories.BrowseCatalog do
  @moduledoc """
  A business buyer browses the catalog with live stock and adds a product at a quantity. Its part is
  the catalog; its configured `AddLine` stores the line in the draft.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.Panes, only: [stream_list: 1]
  import ZeroCoupled.Catalog.Rows, only: [catalog_row: 1]

  alias ZeroCoupled.Foundation.Products
  alias ZeroCoupled.State.PortalCatalog
  alias ZeroCoupledWeb.Paradigms.Binder

  def parts, do: %{catalog: PortalCatalog}
  def streams, do: [:portal_products]
  def events, do: ["add_to_order"]
  def ports, do: %{in: [mounted: :event, stock: :stock_change], out: [added: :item_quantity]}

  @doc "Config: `stock_status` (a configured `StockStatus`) and `add_line`, the instance that stores a line."
  def new(opts),
    do:
      Binder.story(
        __MODULE__,
        %{catalog: PortalCatalog.new(stock_status: opts[:stock_status])},
        bindings(opts[:add_line])
      )

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings(add_line) do
    %{
      {:in, :mounted} => [
        {:via, &Products.list/0, :products, [{:input, :catalog, &PortalCatalog.load/2}]}
      ],
      {:in, :stock} => [{:input, :catalog, &PortalCatalog.set_stock/2}],
      {:catalog, :rows} => [{:stream, :portal_products}],
      {:catalog, :requested} => [
        {:via, add_line, [{:out, :added}, {:flash, :info, "Added to order"}]}
      ]
    }
  end

  def event(s, me, "add_to_order", %{"product-id" => id, "quantity" => q}),
    do:
      Binder.run(
        s,
        me,
        :catalog,
        &PortalCatalog.request(&1, %{product_id: int(id), quantity: int(q)})
      )

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
