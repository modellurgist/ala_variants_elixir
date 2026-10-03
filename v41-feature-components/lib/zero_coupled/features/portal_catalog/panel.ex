defmodule ZeroCoupled.Features.PortalCatalog.Panel do
  @moduledoc "The orderable products as a UI instance, owning the add forms. Config: `products` (a read function). Input: `set_stock: change`. Sends the page `{:catalog, :requested, {product, quantity}}`."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.Features.PortalCatalog
  alias ZeroCoupledWeb.Paradigms.Instance

  @doc "The ports this instance sends the page, as `{:catalog, port, payload}`."
  def sent_port_outputs, do: [:requested]

  def mount(socket),
    do: {:ok, socket |> stream(:portal_products, []) |> assign(state: PortalCatalog.new([]))}

  def update(%{set_stock: change}, s), do: {:ok, step(s, &PortalCatalog.set_stock(&1, change))}
  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_loaded()}

  defp ensure_loaded(%{assigns: %{loaded: true}} = s), do: s

  defp ensure_loaded(s),
    do: s |> assign(loaded: true) |> step(&PortalCatalog.load(&1, s.assigns.products.()))

  def handle_event("add_to_order", %{"product-id" => id, "quantity" => q}, s),
    do:
      {:noreply,
       step(
         s,
         &PortalCatalog.request(&1, %{
           product_id: String.to_integer(id),
           quantity: String.to_integer(q)
         })
       )}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)
  defp wire(s, {:rows, {:reset, rows}}), do: stream(s, :portal_products, rows, reset: true)
  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :portal_products, row)
  defp wire(s, out), do: Instance.send_port_output(s, :catalog, out)

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold pb-2">Products</h2>
      <div id="portal_products" phx-update="stream">
        <.catalog_row
          :for={{dom_id, row} <- @streams.portal_products}
          id={dom_id}
          row={row}
          target={@myself}
          on_add="add_to_order"
        />
      </div>
    </section>
    """
  end
end
