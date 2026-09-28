defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal: a second circuit over the same cart aggregate, domain rules, undo
  feature and paradigms, with its own instances, pricing, and flow. Its draft is a separate
  session cart.
  """
  use ZeroCoupledWeb, :live_view
  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}

  alias ZeroCoupled.Paradigms.{
    Adapter,
    Circuit,
    FromStore,
    ToAssign,
    ToComponent,
    ToFlash,
    ToForm,
    ToPatch,
    ToStore,
    ToTimer,
    Via
  }

  alias ZeroCoupledWeb.Paradigms.Runner
  alias ZeroCoupledWeb.PortalLive.{CatalogPanel, OrderPanel, PortalView}

  @pricing [
    shipping: %{
      standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
      overnight: %{label: "Overnight", cost: 2499, free_above: nil}
    },
    volume_tiers: [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]
  ]
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

  def circuit(cart_id) do
    Circuit.new(
      lines: %FromStore{read: &Carts.list_items/1},
      products: %FromStore{read: fn _ -> Products.list() end},
      order: Adapter.new(OrderLines, OrderLines.new(cart_id: cart_id, pricing: @pricing)),
      catalog: Adapter.new(PortalCatalog, PortalCatalog.new([])),
      undo: Adapter.new(Undo, Undo.new([])),
      flow:
        Adapter.new(
          PortalSubmit,
          PortalSubmit.new(flow: @flow, start: :lines, url_edges: @url_edges)
        ),
      order_rows: %ToComponent{module: OrderPanel, id: "order"},
      catalog_rows: %ToComponent{module: CatalogPanel, id: "catalog"},
      summary: %ToAssign{name: :summary},
      persist: %ToStore{write: &persist/1},
      undo_armed: %ToAssign{name: :undo_pending, value: true},
      undo_cleared: %ToAssign{name: :undo_pending, value: false},
      undo_clock: %ToTimer{name: :undo, ms: @undo_window_ms, into: {:undo, :expire}},
      ensure_line: %Via{fun: &ensure_line(cart_id, &1)},
      step: %ToAssign{name: :step},
      url: %ToPatch{paths: @step_paths},
      po_form: %ToForm{name: :po_form},
      po: %ToAssign{name: :po},
      place_order: %Via{fun: &place_order(cart_id, &1)},
      order_id: %ToAssign{name: :order_id},
      added_notice: %ToFlash{text: "Added to order"},
      submitted_notice: %ToFlash{text: "Order submitted"},
      blocked_notice: %ToFlash{level: :error, texts: %{empty: "Your order is empty"}}
    )
    |> Circuit.wire({:lines, :loaded}, {:order, :load})
    |> Circuit.wire({:products, :loaded}, {:catalog, :load})
    |> Circuit.wire({:order, :rows}, {:order_rows, :change})
    |> Circuit.wire({:order, :summary}, {:summary, :value})
    |> Circuit.wire({:order, :persist}, {:persist, :value})
    |> Circuit.wire({:order, :removed}, {:undo, :capture})
    |> Circuit.wire({:undo, :captured}, {:undo_armed, :any})
    |> Circuit.wire({:undo, :timer}, {:undo_clock, :value})
    |> Circuit.wire({:undo, :restored}, {:order, :receive})
    |> Circuit.wire({:undo, :restored}, {:undo_cleared, :any})
    |> Circuit.wire({:undo, :expired}, {:order, :confirm_removal})
    |> Circuit.wire({:undo, :expired}, {:undo_cleared, :any})
    |> Circuit.wire({:catalog, :rows}, {:catalog_rows, :change})
    |> Circuit.wire({:catalog, :requested}, {:ensure_line, :in})
    |> Circuit.wire({:ensure_line, :out}, {:order, :add})
    |> Circuit.wire({:ensure_line, :out}, {:added_notice, :any})
    |> Circuit.wire({:flow, :step}, {:step, :value})
    |> Circuit.wire({:flow, :step}, {:url, :value})
    |> Circuit.wire({:flow, :form}, {:po_form, :value})
    |> Circuit.wire({:flow, :blocked}, {:blocked_notice, :key})
    |> Circuit.wire({:flow, :approved}, {:po, :value})
    |> Circuit.wire({:flow, :approved}, {:place_order, :in})
    |> Circuit.wire({:place_order, :out}, {:flow, :complete})
    |> Circuit.wire({:flow, :reference}, {:order_id, :value})
    |> Circuit.wire({:flow, :reference}, {:submitted_notice, :any})
  end

  @impl true
  def mount(_params, %{"portal_cart_id" => cart_id}, socket) do
    if connected?(socket), do: Broadcast.subscribe()
    circuit = circuit(cart_id)

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

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp persist({:quantity, cart_id, item_id, qty}),
    do: Carts.update_quantity(cart_id, item_id, qty)

  defp persist({:remove, cart_id, item_id}), do: Carts.remove_item(cart_id, item_id)

  # a requested product becomes a persisted line; the order feature settles its quantity
  defp ensure_line(cart_id, {product, quantity}) do
    Carts.add_item(cart_id, Products.get!(product.id))
    {cart_id |> Carts.list_items() |> Enum.find(&(&1.product.id == product.id)), quantity}
  end

  defp place_order(cart_id, _po) do
    {:ok, order} = Orders.create(cart_id)
    order.id
  end
end
