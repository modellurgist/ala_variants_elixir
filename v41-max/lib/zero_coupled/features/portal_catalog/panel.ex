defmodule ZeroCoupled.Features.PortalCatalog.Panel do
  @moduledoc "The orderable products as a UI instance, owning the add forms. Config: `products` (a read function). Input: `set_stock: change`. Announces `{:catalog, :requested, {product, quantity}}`."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.Features.PortalCatalog
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is announced
  @lands_only [:rows]

  @doc "The ports this instance announces, as `{name, port, payload}`."
  def announces, do: Keyword.keys(PortalCatalog.ports().out) -- @lands_only

  def mount(socket),
    do: {:ok, stream(socket, :portal_products, [])}

  def update(%{set_stock: change}, s), do: {:ok, step(s, &PortalCatalog.set_stock(&1, change))}
  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_loaded()}

  defp ensure_loaded(%{assigns: %{state: _}} = s), do: s

  defp ensure_loaded(%{assigns: a} = s),
    do:
      s
      |> assign(state: PortalCatalog.new(stock_status: a.stock_status))
      |> step(&PortalCatalog.load(&1, a.products.()))

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

  defp step(s, fun), do: Instance.step(s, fun, &land/2)
  defp land(s, {:rows, {:reset, rows}}), do: stream(s, :portal_products, rows, reset: true)
  defp land(s, {:rows, {_, row}}), do: stream_insert(s, :portal_products, row)
  defp land(s, out), do: Instance.announce(s, :catalog, out)

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold pb-2">{@t.heading}</h2>
      <div id="portal_products" phx-update="stream">
        <.catalog_row
          :for={{dom_id, row} <- @streams.portal_products}
          id={dom_id}
          row={row}
          target={@myself}
          on_add="add_to_order"
          t={@t.row}
        />
      </div>
    </section>
    """
  end
end
