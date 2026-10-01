defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal. Its diagram is `ZeroCoupledWeb.PortalDiagram`, checked when the page
  mounts: a second circuit over the same aggregate, domain rules, undo feature and paradigms. Its
  draft is a separate session cart. No catch-all `handle_info`, as on the cart page.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  alias ZeroCoupled.Features.PortalSubmit
  alias ZeroCoupled.Foundation.Broadcast
  alias ZeroCoupled.Paradigms.Circuit
  alias ZeroCoupledWeb.Paradigms.Runner
  alias ZeroCoupledWeb.PortalDiagram
  alias ZeroCoupledWeb.PortalLive.PortalView

  @steps_by_url %{"review" => :review, "submitted" => :submitted}
  @milestones [lines: "Order", review: "Review", submitted: "Done"]

  @impl true
  def mount(_params, %{"portal_cart_id" => cart_id}, socket) do
    circuit = Circuit.validate!(PortalDiagram.circuit(%{cart_id: cart_id}))

    {:ok,
     socket
     |> assign(
       circuit: circuit,
       step: :lines,
       milestones: @milestones,
       undo_pending: false,
       order_id: nil,
       po: nil
     )
     |> assign(po_form: to_form(PortalSubmit.po_form(Circuit.part(circuit, :flow).state)))
     |> Runner.feed(:lines, {:load, cart_id})
     |> Runner.feed(:products, {:load, nil})}
  end

  @impl true
  def handle_params(params, _url, socket),
    do:
      {:noreply,
       Runner.feed(socket, :flow, {:goto, Map.get(@steps_by_url, params["step"], :lines)})}

  @impl true
  def render(assigns), do: PortalView.render(assigns)

  @impl true
  def handle_info({:feed, _, _} = message, socket),
    do: {:noreply, Runner.feed_message(message, socket)}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket) do
    change = %{product_id: id, stock: stock}

    {:noreply,
     socket
     |> Runner.feed(:order, {:set_stock, change})
     |> Runner.feed(:catalog, {:set_stock, change})}
  end

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}
end
