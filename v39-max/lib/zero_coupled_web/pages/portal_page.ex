defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal: a second page over the same cart aggregate, domain rules, and undo
  feature, with its own bindings, pricing, and flow. Its draft order is a separate session cart.
  As on the cart page, `bindings/1` is the diagram and `grounded/0` the ports left unbound.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  alias ZeroCoupled.Domain.{AddLine, CalculateShipping, PlaceOrder, StockStatus, VolumeTier}
  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupledWeb.{CartSession, StoreConfig}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}
  alias ZeroCoupledWeb.Paradigms.Binder
  alias ZeroCoupledWeb.PortalLive.PortalView

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
    order: %{
      heading: "Your order",
      review: "Review order",
      empty: "No lines yet. Add products below.",
      row: %{each: " each"}
    },
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
    undo: %{text: "Item removed.", undo: "Undo"}
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
    |> update_in([:submit], &Map.merge(&1, %{total: summary.total}))
  end

  def bindings(cart_id) do
    %{
      {:page, :mounted} => [
        {:via, &Carts.list_items/1, [{:input, :order, &OrderLines.load/2}]},
        {:via, &Products.list/0, [{:input, :catalog, &PortalCatalog.load/2}]},
        {:input, :flow, &PortalSubmit.show_form/2}
      ],
      {:order, :rows} => [{:stream, :order_lines}],
      {:order, :summary} => [{:assign, :summary}],
      {:order, :changed} => [{:call, &Carts.apply_change/1}],
      {:order, :removed} => [{:input, :undo, &Undo.capture/2}],
      {:order, :review} => [{:input, :flow, &PortalSubmit.review/2}],
      {:undo, :captured} => [
        {:set, :undo_pending, true},
        {:start_timer, :undo, StoreConfig.undo_window_ms()}
      ],
      {:undo, :restored} => [
        {:stop_timer, :undo},
        {:input, :order, &OrderLines.receive/2},
        {:set, :undo_pending, false}
      ],
      {:undo, :expired} => [
        {:input, :order, &OrderLines.confirm_removal/2},
        {:set, :undo_pending, false}
      ],
      {:catalog, :rows} => [{:stream, :portal_products}],
      {:catalog, :requested} => [
        {:via, %AddLine{carts: Carts, products: Products, cart_id: cart_id},
         [{:input, :order, &OrderLines.add/2}, {:flash, :info, "Added to order"}]}
      ],
      {:flow, :step} => [{:assign, :step}, {:patch, @step_paths}],
      {:flow, :form} => [{:form, :po_form}],
      {:flow, :blocked} => [{:flash_for, :error, %{empty: "Your order is empty"}}],
      {:flow, :approved} => [
        {:assign, :po},
        {:via, %PlaceOrder{orders: Orders, cart_id: cart_id},
         [{:input, :flow, &PortalSubmit.complete/2}]}
      ],
      {:flow, :reference} => [{:assign, :order_id}, {:flash, :info, "Order submitted"}]
    }
  end

  @doc "The feature ports this page leaves unbound on purpose, as `{feature, port}`."
  def grounded, do: []

  @doc "Which feature each binding key names, so a test can check every port is bound or grounded."
  def features,
    do: %{order: OrderLines, undo: Undo, catalog: PortalCatalog, flow: PortalSubmit}

  @impl true
  def mount(_params, session, socket) do
    cart_id = session[CartSession.portal_key()]

    pricing = %{
      shipping: CalculateShipping.new(StoreConfig.rates()),
      volume: VolumeTier.new(@volume_tiers),
      stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at())
    }

    {:ok,
     socket
     |> assign(
       bindings: bindings(cart_id),
       order: OrderLines.new(cart_id: cart_id, pricing: pricing),
       catalog:
         PortalCatalog.new(stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at())),
       undo: Undo.new([]),
       flow:
         PortalSubmit.new(
           flow: @flow,
           start: :lines,
           url_edges: @url_edges,
           messages: %{number: "must look like PO-1234"}
         )
     )
     |> assign(
       texts: texts(),
       step: :lines,
       milestones: @milestones,
       undo_pending: false,
       order_id: nil,
       po: nil
     )
     |> stream(:order_lines, [])
     |> stream(:portal_products, [])
     |> Binder.deliver(bindings(cart_id), :page, mounted: cart_id)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    step = Map.get(@steps_by_url, params["step"], :lines)
    {:noreply, run(socket, :flow, &PortalSubmit.goto(&1, step))}
  end

  @impl true
  def render(assigns), do: PortalView.render(assigns)

  @impl true
  def handle_event("add_to_order", %{"product-id" => id, "quantity" => q}, socket),
    do:
      {:noreply,
       run(socket, :catalog, &PortalCatalog.request(&1, %{product_id: int(id), quantity: int(q)}))}

  def handle_event("set_line_quantity", %{"item-id" => id, "quantity" => q}, socket),
    do:
      {:noreply,
       run(socket, :order, &OrderLines.set_quantity(&1, %{item_id: int(id), quantity: int(q)}))}

  def handle_event("remove_line", %{"item-id" => id}, socket),
    do: {:noreply, run(socket, :order, &OrderLines.remove(&1, %{item_id: int(id)}))}

  def handle_event("undo_remove", _params, socket),
    do: {:noreply, run(socket, :undo, &Undo.restore(&1, nil))}

  def handle_event("go_review", _params, socket),
    do: {:noreply, run(socket, :order, &OrderLines.request_review(&1, nil))}

  def handle_event("edit_lines", _params, socket),
    do: {:noreply, run(socket, :flow, &PortalSubmit.edit_lines(&1, nil))}

  def handle_event("validate_po", %{"po" => params}, socket),
    do: {:noreply, run(socket, :flow, &PortalSubmit.validate(&1, params))}

  def handle_event("submit_order", %{"po" => params}, socket),
    do: {:noreply, run(socket, :flow, &PortalSubmit.submit(&1, params))}

  @impl true
  def handle_info({:timer, :undo, %{id: id}}, socket),
    do: {:noreply, run(socket, :undo, &Undo.expire(&1, id))}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket) do
    change = %{product_id: id, stock: stock}

    {:noreply,
     socket
     |> run(:order, &OrderLines.set_stock(&1, change))
     |> run(:catalog, &PortalCatalog.set_stock(&1, change))}
  end

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

  defp run(socket, key, step), do: Binder.run(socket, socket.assigns.bindings, key, step)
  defp int(s), do: String.to_integer(s)
end
