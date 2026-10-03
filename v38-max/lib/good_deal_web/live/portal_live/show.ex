defmodule GoodDealWeb.PortalLive.Show do
  @moduledoc """
  The B2B bulk-order portal: the same shape as the cart page over the same aggregate, domain
  rules and undo feature, with its own features, pricing and flow, and its own `wire/3` clauses.
  Its draft is a separate session cart.
  """
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDeal.Components.{Panes, Parts, Rows}

  alias GoodDeal.Catalog
  alias GoodDeal.Domain.{AddLine, CalculateShipping, PlaceOrder, StockStatus, VolumeTier}
  alias GoodDeal.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias GoodDeal.Foundation.{Carts, Orders, Products}
  alias GoodDealWeb.CartSession
  alias GoodDealWeb.Paradigms.Steps

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
    summary = Catalog.summary_texts()
    stock = Catalog.stock_texts()

    @texts
    |> put_in([:order, :summary], summary)
    |> update_in([:order, :row], &Map.merge(&1, %{remove: Catalog.remove_text(), stock: stock}))
    |> put_in([:catalog, :row, :stock], stock)
    |> update_in([:submit], &Map.merge(&1, %{total: summary.total}))
  end

  @doc "Which feature each `wire/3` key names, so a test can check every declared port has a clause."
  def features, do: %{order: OrderLines, undo: Undo, catalog: PortalCatalog, flow: PortalSubmit}

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session, CartSession.portal_key())

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      volume: VolumeTier.new(Catalog.volume_tiers()),
      stock_status: StockStatus.new(low_at: Catalog.low_stock_threshold())
    }

    {:ok,
     socket
     |> assign(
       order: OrderLines.new(cart_id: cart_id, pricing: pricing),
       catalog:
         PortalCatalog.new(stock_status: StockStatus.new(low_at: Catalog.low_stock_threshold())),
       undo: Undo.new([]),
       flow:
         PortalSubmit.new(
           flow: @flow,
           start: :lines,
           url_edges: @url_edges,
           messages: %{number: "must look like PO-1234"}
         ),
       add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
       place_order: %PlaceOrder{orders: Orders, cart_id: cart_id}
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
     |> Steps.feed(:order, &OrderLines.load/2, &Carts.list_items/1, cart_id, &wire/3)
     |> Steps.feed(:catalog, &PortalCatalog.load/2, &Products.list/0, nil, &wire/3)
     |> run(:flow, &PortalSubmit.show_form(&1, nil))}
  end

  @impl true
  def handle_params(params, _url, socket),
    do:
      {:noreply,
       run(socket, :flow, &PortalSubmit.goto(&1, Map.get(@steps_by_url, params["step"], :lines)))}

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

  def handle_info({:stock_changed, {product_id, stock}}, socket) do
    change = %{product_id: product_id, stock: stock}

    {:noreply,
     socket
     |> run(:order, &OrderLines.set_stock(&1, change))
     |> run(:catalog, &PortalCatalog.set_stock(&1, change))}
  end

  # the topic also carries catalogue edits, which this page doesn't show
  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}
  def handle_info({:product_updated, _product}, socket), do: {:noreply, socket}

  defp run(socket, key, step), do: Steps.run(socket, key, step, &wire/3)
  defp int(s) when is_binary(s), do: String.to_integer(s)
  defp int(n) when is_integer(n), do: n

  # {feature, port} → where it wires on this page
  defp wire(s, :order, {:rows, change}), do: Steps.stream_change(s, :order_lines, change)
  defp wire(s, :order, {:summary, summary}), do: assign(s, :summary, summary)

  defp wire(s, :order, {:changed, change}) do
    Carts.apply_change(change)
    s
  end

  defp wire(s, :order, {:removed, item}), do: run(s, :undo, &Undo.capture(&1, item))
  defp wire(s, :order, {:review, summary}), do: run(s, :flow, &PortalSubmit.review(&1, summary))

  defp wire(s, :undo, {:captured, item}),
    do:
      s |> assign(:undo_pending, true) |> Steps.start_timer(:undo, item, Catalog.undo_window_ms())

  defp wire(s, :undo, {:restored, item}),
    do:
      s
      |> Steps.stop_timer(:undo)
      |> assign(:undo_pending, false)
      |> run(:order, &OrderLines.receive(&1, item))

  defp wire(s, :undo, {:expired, item_id}),
    do: s |> assign(:undo_pending, false) |> run(:order, &OrderLines.confirm_removal(&1, item_id))

  defp wire(s, :catalog, {:rows, change}), do: Steps.stream_change(s, :portal_products, change)

  defp wire(s, :catalog, {:requested, request}),
    do:
      s
      |> Steps.feed(
        :order,
        &OrderLines.add/2,
        &AddLine.run(s.assigns.add_line, &1),
        request,
        &wire/3
      )
      |> put_flash(:info, "Added to order")

  defp wire(s, :flow, {:step, step}),
    do: s |> assign(:step, step) |> Steps.patch(@step_paths, step)

  defp wire(s, :flow, {:form, changeset}),
    do: assign(s, :po_form, to_form(changeset, action: :validate))

  defp wire(s, :flow, {:blocked, reason}), do: put_flash(s, :error, @blocked[reason])

  defp wire(s, :flow, {:approved, po}),
    do:
      s
      |> assign(:po, po)
      |> Steps.feed(
        :flow,
        &PortalSubmit.complete/2,
        &PlaceOrder.place(s.assigns.place_order, &1),
        po,
        &wire/3
      )

  defp wire(s, :flow, {:reference, order_id}),
    do: s |> assign(:order_id, order_id) |> put_flash(:info, "Order submitted")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <.only_on current={@step} name={:lines}>
        <div class="space-y-8">
          <.notice
            shown={@undo_pending}
            text={@texts.undo.text}
            action={@texts.undo.undo}
            event="undo_remove"
          />
          <section>
            <h2 class="text-lg font-semibold pb-2">{@texts.order.heading}</h2>
            <.stream_list :let={{dom_id, row}} id="order_lines" stream={@streams.order_lines}>
              <.order_line_row
                id={dom_id}
                row={row}
                on_quantity="set_line_quantity"
                on_remove="remove_line"
                t={@texts.order.row}
              />
            </.stream_list>
            <.none count={@summary.item_count} text={@texts.order.empty} />
            <.order_summary summary={@summary} t={@texts.order.summary} />
            <.primary_button event="go_review" disabled={@summary.empty?}>
              {@texts.order.review} · {@summary.total}
            </.primary_button>
          </section>
          <section>
            <h2 class="text-lg font-semibold pb-2">{@texts.catalog.heading}</h2>
            <.stream_list :let={{dom_id, row}} id="portal_products" stream={@streams.portal_products}>
              <.catalog_row
                id={dom_id}
                row={row}
                on_add="add_to_order"
                t={@texts.catalog.row}
              />
            </.stream_list>
          </section>
        </div>
      </.only_on>
      <.only_on current={@step} name={:review}>
        <div class="space-y-4 max-w-lg">
          <.order_summary summary={@summary} t={@texts.order.summary} />
          <.simple_form for={@po_form} phx-change="validate_po" phx-submit="submit_order">
            <.input
              field={@po_form[:number]}
              label={@texts.submit.po_number}
              placeholder={@texts.submit.po_placeholder}
            />
            <.input field={@po_form[:notes]} label={@texts.submit.notes} />
            <:actions>
              <button type="button" phx-click="edit_lines" class="text-sm text-zinc-500 underline">
                {@texts.submit.back}
              </button>
              <.button phx-disable-with={@texts.submit.submitting}>
                {@texts.submit.submit} · {@summary.total}
              </.button>
            </:actions>
          </.simple_form>
        </div>
      </.only_on>
      <.only_on current={@step} name={:submitted}>
        <div class="py-10 space-y-2">
          <h2 class="text-2xl font-semibold">{@texts.submit.submitted}</h2>
          <p class="text-zinc-600">
            {@texts.submit.reference} <span class="font-mono">#{@order_id}</span> · {@po.number}
          </p>
          <p class="text-zinc-500 text-sm">
            {@texts.submit.total} {@summary.total} ({@summary.item_count} {@texts.submit.items})
          </p>
        </div>
      </.only_on>
    </div>
    """
  end
end
