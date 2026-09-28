defmodule ZeroCoupledWeb.PortalLive.OrderPanel do
  @moduledoc "The draft order: its lines, the undo banner, the totals and the review button; owns their events."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupledWeb.Rows
  alias ZeroCoupledWeb.Paradigms.Emitter

  def mount(socket), do: {:ok, stream(socket, :order_lines, [])}

  def update(%{change: {:reset, rows}}, socket),
    do: {:ok, stream(socket, :order_lines, rows, reset: true)}

  def update(%{change: {:removed, row}}, socket),
    do: {:ok, stream_delete(socket, :order_lines, row)}

  def update(%{change: {_, row}}, socket), do: {:ok, stream_insert(socket, :order_lines, row)}
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def handle_event("set_line_quantity", %{"item-id" => id, "quantity" => q}, socket),
    do:
      {:noreply,
       Emitter.feed(socket, :order, {:set_quantity, %{item_id: int(id), quantity: int(q)}})}

  def handle_event("remove_line", %{"item-id" => id}, socket),
    do: {:noreply, Emitter.feed(socket, :order, {:remove, %{item_id: int(id)}})}

  def handle_event("undo_remove", _, socket),
    do: {:noreply, Emitter.feed(socket, :undo, {:restore, nil})}

  def handle_event("go_review", _, socket),
    do: {:noreply, Emitter.feed(socket, :flow, {:review, socket.assigns.summary})}

  defp int(s), do: String.to_integer(s)

  def render(assigns) do
    ~H"""
    <section>
      <.undo_banner :if={@undo_pending} on_undo="undo_remove" target={@myself} />
      <h2 class="text-lg font-semibold pb-2">Your order</h2>
      <div id="order_lines" phx-update="stream">
        <.order_line_row
          :for={{dom_id, row} <- @streams.order_lines}
          id={dom_id}
          row={row}
          target={@myself}
          on_quantity="set_line_quantity"
          on_remove="remove_line"
        />
      </div>
      <div :if={@summary.empty?} class="py-8 text-center text-zinc-400">
        No lines yet. Add products below.
      </div>
      <ZeroCoupledWeb.PortalLive.PortalView.summary summary={@summary} />
      <button
        phx-click="go_review"
        phx-target={@myself}
        disabled={@summary.empty?}
        class={[
          "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
          @summary.empty? && "opacity-50 cursor-not-allowed"
        ]}
      >
        Review order · {@summary.total}
      </button>
    </section>
    """
  end
end

defmodule ZeroCoupledWeb.PortalLive.CatalogPanel do
  @moduledoc "The products a buyer can add, owning the add forms."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupledWeb.Rows
  alias ZeroCoupledWeb.Paradigms.Emitter

  def mount(socket), do: {:ok, stream(socket, :portal_products, [])}

  def update(%{change: {:reset, rows}}, socket),
    do: {:ok, stream(socket, :portal_products, rows, reset: true)}

  def update(%{change: {_, row}}, socket), do: {:ok, stream_insert(socket, :portal_products, row)}
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def handle_event("add_to_order", %{"product-id" => id, "quantity" => q}, socket),
    do:
      {:noreply,
       Emitter.feed(
         socket,
         :catalog,
         {:request, %{product_id: String.to_integer(id), quantity: String.to_integer(q)}}
       )}

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

defmodule ZeroCoupledWeb.PortalLive.PoForm do
  @moduledoc "The review step's purchase-order form."
  use ZeroCoupledWeb, :live_component
  alias ZeroCoupledWeb.Paradigms.Emitter

  def handle_event("validate_po", %{"po" => p}, socket),
    do: {:noreply, Emitter.feed(socket, :flow, {:validate, p})}

  def handle_event("submit_order", %{"po" => p}, socket),
    do: {:noreply, Emitter.feed(socket, :flow, {:submit, p})}

  def handle_event("edit_lines", _, socket),
    do: {:noreply, Emitter.feed(socket, :flow, {:edit_lines, nil})}

  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-lg">
      <ZeroCoupledWeb.PortalLive.PortalView.summary summary={@summary} />
      <.simple_form
        for={@po_form}
        phx-change="validate_po"
        phx-submit="submit_order"
        phx-target={@myself}
      >
        <.input field={@po_form[:number]} label="Purchase order number" placeholder="PO-1234" />
        <.input field={@po_form[:notes]} label="Notes (optional)" />
        <:actions>
          <button
            type="button"
            phx-click="edit_lines"
            phx-target={@myself}
            class="text-sm text-zinc-500 underline"
          >
            Back to lines
          </button>
          <.button phx-disable-with="Submitting…">Submit order · {@summary.total}</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
