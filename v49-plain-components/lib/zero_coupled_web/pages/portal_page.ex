defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal: the same shape as the cart page over the same aggregate, domain
  rules and undo instance, with its own instances, pricing and flow. Its draft is a separate
  session cart. No catch-all `handle_info`, as on the cart page.
  """
  use ZeroCoupledWeb, :live_view
  import ZeroCoupled.Catalog.Panes, only: [pane: 1]
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]
  alias ZeroCoupled.Domain.{AddLine, CalculateShipping, PlaceOrder, StockStatus, VolumeTier}
  alias ZeroCoupledWeb.{CartSession, StoreConfig}
  alias ZeroCoupled.State.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}

  @volume_tiers [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]
  @flow [
    {:lines, :go_review, :review},
    {:review, :edit_lines, :lines},
    {:review, :submit_order, :submitted}
  ]
  @url_edges [{:review, :lines}]
  @step_paths %{lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"}
  @steps_by_url %{"review" => :review, "submitted" => :submitted}
  @milestones [lines: "Order", review: "Review", submitted: "Done"]
  @texts %{
    order: %{heading: "Your order", review: "Review order", row: %{each: " each"}},
    catalog: %{heading: "Products", row: %{add: "Add", default_quantity: 10}},
    submit: %{
      po_number: "Purchase order number",
      po_placeholder: "PO-1234",
      notes: "Notes (optional)",
      back: "Back to lines",
      submit: "Submit order",
      submitting: "Submitting…",
      submitted: "Order submitted",
      reference: "Reference",
      items: "items"
    },
    undo: %{undo: "Undo"}
  }

  # the page's own words, plus the store's shared ones
  defp texts do
    summary = StoreConfig.summary_texts()
    stock = StoreConfig.stock_texts()

    @texts
    |> put_in([:order, :summary], summary)
    |> update_in(
      [:order, :row],
      &Map.merge(&1, %{remove: StoreConfig.remove_text(), stock: stock})
    )
    |> put_in([:catalog, :row, :stock], stock)
    |> update_in([:submit], &Map.merge(&1, %{summary: summary, total: summary.total}))
  end

  @blocked %{empty: "Your order is empty"}

  @impl true
  def mount(_params, session, socket) do
    cart_id = session[CartSession.portal_key()]

    {:ok,
     assign(socket,
       cart_id: cart_id,
       texts: texts(),
       pricing: %{
         shipping: CalculateShipping.new(StoreConfig.rates()),
         volume: VolumeTier.new(@volume_tiers),
         stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at())
       },
       stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at()),
       instances: %{
         add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
         place_order: %PlaceOrder{orders: Orders, cart_id: cart_id}
       },
       step: :lines,
       requested_step: :lines,
       summary: nil,
       milestones: @milestones,
       undo_window_ms: StoreConfig.undo_window_ms(),
       flow: @flow,
       url_edges: @url_edges
     )}
  end

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, assign(socket, requested_step: Map.get(@steps_by_url, params["step"], :lines))}

  # {instance, port, payload} → where it goes on this page: one clause per port each instance sends
  # storing the line is I/O; LiveView's task carries the stored line to the order
  @impl true
  def handle_info({:catalog, :requested, request}, socket) do
    add_line = socket.assigns.instances.add_line

    {:noreply,
     socket
     |> start_async(:add_line, fn -> AddLine.run(add_line, request) end)
     |> put_flash(:info, "Added to order")}
  end

  def handle_info({:order, :summary, summary}, socket),
    do: {:noreply, assign(socket, :summary, summary)}

  def handle_info({:order, :changed, change}, socket) do
    Carts.apply_change(change)
    {:noreply, socket}
  end

  def handle_info({:order, :removed, item}, socket) do
    send_update(Undo.Banner, id: "undo", capture: item)
    {:noreply, socket}
  end

  def handle_info({:order, :review, summary}, socket) do
    send_update(PortalSubmit.Panel, id: "submit", review: summary)
    {:noreply, socket}
  end

  def handle_info({:undo, :expire, item}, socket) do
    send_update(Undo.Banner, id: "undo", expire: item)
    {:noreply, socket}
  end

  def handle_info({:undo, :expired, item_id}, socket) do
    send_update(OrderLines.Panel, id: "order", confirm_removal: item_id)
    {:noreply, socket}
  end

  def handle_info({:undo, :restored, item}, socket) do
    send_update(OrderLines.Panel, id: "order", receive: item)
    {:noreply, socket}
  end

  def handle_info({:submit, :step, step}, socket) when is_map_key(@step_paths, step),
    do: {:noreply, socket |> assign(:step, step) |> push_patch(to: @step_paths[step])}

  def handle_info({:submit, :step, step}, socket), do: {:noreply, assign(socket, :step, step)}

  def handle_info({:submit, :blocked, reason}, socket),
    do: {:noreply, put_flash(socket, :error, @blocked[reason])}

  # placing the order is I/O; LiveView's task carries the order's id to the submission
  def handle_info({:submit, :approved, po}, socket) do
    place_order = socket.assigns.instances.place_order
    {:noreply, start_async(socket, :place_order, fn -> PlaceOrder.place(place_order, po) end)}
  end

  def handle_info({:submit, :reference, _order_id}, socket),
    do: {:noreply, put_flash(socket, :info, "Order submitted")}

  # one stock fact goes to both instances that show stock
  def handle_info(%Broadcast.Facts.StockChanged{} = change, socket) do
    send_update(OrderLines.Panel, id: "order", set_stock: change)
    send_update(PortalCatalog.Panel, id: "catalog", set_stock: change)
    {:noreply, socket}
  end

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

  # a task's outcome goes back to the instance that asked
  @impl true
  def handle_async(:add_line, {:ok, line}, socket) do
    send_update(OrderLines.Panel, id: "order", add: line)
    {:noreply, socket}
  end

  def handle_async(:place_order, {:ok, order_id}, socket) do
    send_update(PortalSubmit.Panel, id: "submit", complete: order_id)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="pb-6 text-3xl font-semibold tracking-tight">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <.pane current={@step} name={:lines} class="space-y-8">
        <.live_component
          module={Undo.Banner}
          id="undo"
          name={:undo}
          window_ms={@undo_window_ms}
          text="Item removed."
          t={@texts.undo}
        />
        <.live_component
          module={OrderLines.Panel}
          id="order"
          name={:order}
          cart_id={@cart_id}
          pricing={@pricing}
          source={&Carts.list_items/1}
          empty_text="No lines yet. Add products below."
          t={@texts.order}
        />
        <div class="grid gap-8 lg:grid-cols-[1fr_22rem]">
          <.live_component
            module={PortalCatalog.Panel}
            id="catalog"
            name={:catalog}
            products={&Products.list/0}
            stock_status={@stock_status}
            t={@texts.catalog}
          />
        </div>
      </.pane>
      <.live_component
        module={PortalSubmit.Panel}
        id="submit"
        name={:submit}
        messages={%{number: "must look like PO-1234"}}
        t={@texts.submit}
        flow={@flow}
        start={:lines}
        url_edges={@url_edges}
        summary={@summary}
        requested_step={@requested_step}
      />
    </div>
    """
  end
end
