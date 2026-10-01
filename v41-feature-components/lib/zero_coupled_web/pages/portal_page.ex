defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal: the same shape as the cart page over the same aggregate, domain
  rules and undo instance, with its own instances, pricing and flow. Its draft is a separate
  session cart. No catch-all `handle_info`, as on the cart page.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]
  alias ZeroCoupled.Domain.{AddLine, CalculateShipping, PlaceOrder, VolumeTier}
  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}

  @rates %{
    standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
    express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
    overnight: %{label: "Overnight", cost: 2499, free_above: nil}
  }
  @volume_tiers [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]
  @undo_window_ms 5_000
  @flow [
    {:lines, :go_review, :review},
    {:review, :edit_lines, :lines},
    {:review, :submit_order, :submitted}
  ]
  @url_edges [{:review, :lines}]
  @step_paths %{lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"}
  @steps_by_url %{"review" => :review, "submitted" => :submitted}
  @milestones [lines: "Order", review: "Review", submitted: "Done"]
  @blocked %{empty: "Your order is empty"}

  @impl true
  def mount(_params, %{"portal_cart_id" => cart_id}, socket) do
    {:ok,
     assign(socket,
       cart_id: cart_id,
       pricing: %{shipping: CalculateShipping.new(@rates), volume: VolumeTier.new(@volume_tiers)},
       add_line: %AddLine{carts: Carts, products: Products},
       place_order: %PlaceOrder{orders: Orders},
       step: :lines,
       requested_step: :lines,
       summary: nil,
       milestones: @milestones,
       undo_window_ms: @undo_window_ms,
       flow: @flow,
       url_edges: @url_edges
     )}
  end

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, assign(socket, requested_step: Map.get(@steps_by_url, params["step"], :lines))}

  @impl true
  def handle_info({:catalog, :requested, request}, socket),
    do:
      {:noreply,
       socket
       |> pass(OrderLines.Panel, "order", add: request)
       |> put_flash(:info, "Added to order")}

  def handle_info({:order, :summary, summary}, socket),
    do: {:noreply, assign(socket, summary: summary)}

  def handle_info({:order, :removed, item}, socket),
    do: {:noreply, pass(socket, Undo.Banner, "undo", capture: item)}

  def handle_info({:order, :review, summary}, socket),
    do: {:noreply, pass(socket, PortalSubmit.Panel, "submit", review: summary)}

  def handle_info({:undo, :expire, id}, socket),
    do: {:noreply, pass(socket, Undo.Banner, "undo", expire: id)}

  def handle_info({:undo, :expired, id}, socket),
    do: {:noreply, pass(socket, OrderLines.Panel, "order", confirm_removal: id)}

  def handle_info({:undo, :restored, item}, socket),
    do: {:noreply, pass(socket, OrderLines.Panel, "order", receive: item)}

  def handle_info({:submit, :step, step}, socket),
    do: {:noreply, socket |> assign(step: step) |> patch(@step_paths, step)}

  def handle_info({:submit, :blocked, reason}, socket),
    do: {:noreply, put_flash(socket, :error, @blocked[reason])}

  def handle_info({:submit, :reference, _}, socket),
    do: {:noreply, put_flash(socket, :info, "Order submitted")}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket) do
    change = %{product_id: id, stock: stock}

    {:noreply,
     socket
     |> pass(OrderLines.Panel, "order", set_stock: change)
     |> pass(PortalCatalog.Panel, "catalog", set_stock: change)}
  end

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

  defp pass(socket, module, id, input),
    do:
      (
        send_update(module, [{:id, id} | input])
        socket
      )

  defp patch(socket, paths, step) do
    with {:ok, path} <- Map.fetch(paths, step),
         do: push_patch(socket, to: path),
         else: (:error -> socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <div class={["space-y-8", @step != :lines && "hidden"]}>
        <.live_component
          module={Undo.Banner}
          id="undo"
          window_ms={@undo_window_ms}
          text="Item removed."
        />
        <.live_component
          module={OrderLines.Panel}
          id="order"
          cart_id={@cart_id}
          pricing={@pricing}
          store={Carts}
          add_line={@add_line}
          empty_text="No lines yet. Add products below."
        />
        <.live_component module={PortalCatalog.Panel} id="catalog" products={&Products.list/0} />
      </div>
      <.live_component
        module={PortalSubmit.Panel}
        id="submit"
        cart_id={@cart_id}
        place_order={@place_order}
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
