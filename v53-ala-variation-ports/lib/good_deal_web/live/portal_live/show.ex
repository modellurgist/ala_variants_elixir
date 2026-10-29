defmodule GoodDealWeb.PortalLive.Show do
  @moduledoc """
  The B2B bulk-order portal. It wires the story it shares with the cart page (drafting the order:
  its lines, undo and stock), configured for the portal (its row, its window); what only this page
  uses (the order's totals, the catalogue, the review and submit flow) it holds and calls, using
  what each call answers. Its draft is a separate session cart.
  """
  use GoodDealWeb, :live_view
  import GoodDeal.Components.{Panes, Parts}

  import GoodDeal.Components.Rows,
    only: [catalog_row: 1, milestones: 1, order_line_row: 1, order_summary: 1]

  alias GoodDealWeb.Paradigms.Steps
  alias GoodDeal.Catalog
  alias GoodDeal.Domain.{CalculateShipping, PlaceOrder, StockStatus}
  alias GoodDeal.Foundation.{Orders, Products}
  alias GoodDeal.State.{OrderTotals, PortalCatalog, PortalSubmit}
  alias GoodDealWeb.CartSession
  alias GoodDealWeb.Stories.{DraftOrder, EditLines, UndoRemoval}

  @steps_by_url %{"review" => :review, "submitted" => :submitted}
  @milestones [lines: "Order", review: "Review", submitted: "Done"]
  @flow [
    {:lines, :go_review, :review},
    {:review, :edit_lines, :lines},
    {:review, :submit_order, :submitted}
  ]
  @url_edges [{:review, :lines}]
  @step_paths %{lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"}
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
    |> update_in([:submit], &Map.merge(&1, %{total: summary.total, summary: summary}))
  end

  @doc "Which story each `wire/3` key names, so a test can check every declared port has a clause."
  @parts %{draft: DraftOrder}
  def parts, do: @parts

  @doc """
  Outputs this page has no use for: the drafting story's that its rows offer none of.
  """
  def grounded, do: [draft: :saved, draft: :line, draft: :checkout_requested]

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session, CartSession.portal_key())
    stock_status = StockStatus.new(low_at: Catalog.low_stock_threshold())
    pricing = %{shipping: CalculateShipping.new(Catalog.rates()), volume: &volume_tier/1}
    catalog = PortalCatalog.new(stock_status: stock_status, products: Products.list())

    flow =
      PortalSubmit.new(
        flow: @flow,
        start: :lines,
        url_edges: @url_edges,
        messages: %{number: "must look like PO-1234"}
      )

    {:ok,
     socket
     |> assign(
       texts: texts(),
       milestones: @milestones,
       undo_pending: false,
       totals: OrderTotals.new(pricing: pricing),
       catalog: catalog,
       flow: flow,
       place_order: %PlaceOrder{orders: Orders, cart_id: cart_id}
     )
     |> po_form(PortalSubmit.po_form(flow))
     |> stream(:portal_products, PortalCatalog.rows(catalog))
     |> DraftOrder.mount(
       [
         cart_id: cart_id,
         stock_status: stock_status,
         stream: :order_lines,
         timer: :undo,
         window_ms: Catalog.undo_window_ms(),
         changes: Catalog.changes_topic()
       ],
       out(:draft)
     )}
  end

  # the portal's volume pricing: the highest tier the subtotal reaches, as `{percent, label}`
  defp volume_tier(subtotal) do
    Enum.find_value(Catalog.volume_tiers(), {0, nil}, fn {min, pct, label} ->
      if subtotal >= min, do: {pct, label}
    end)
  end

  @impl true
  def handle_params(params, _url, socket) do
    step = Map.get(@steps_by_url, params["step"], :lines)
    {:noreply, flow(socket, PortalSubmit.goto(socket.assigns.flow, step))}
  end

  @draft_events DraftOrder.events()

  @impl true
  def handle_event(event, params, socket) when event in @draft_events,
    do: {:noreply, DraftOrder.handle_event(event, params, socket, out(:draft))}

  def handle_event("add_to_order", %{"product-id" => id, "quantity" => q}, socket) do
    request = %{product_id: String.to_integer(id), quantity: String.to_integer(q)}

    case PortalCatalog.request(socket.assigns.catalog, request) do
      nil ->
        {:noreply, socket}

      product_quantity ->
        {:noreply,
         socket
         |> to(:draft, :add, product_quantity)
         |> put_flash(:info, "Added to order")}
    end
  end

  def handle_event("go_review", _params, socket) do
    case PortalSubmit.review(socket.assigns.flow, socket.assigns.summary) do
      {:ok, flow} -> {:noreply, flow(socket, flow)}
      {:blocked, reason} -> {:noreply, put_flash(socket, :error, @blocked[reason])}
    end
  end

  def handle_event("edit_lines", _params, socket),
    do: {:noreply, flow(socket, PortalSubmit.edit_lines(socket.assigns.flow))}

  def handle_event("validate_po", %{"po" => params}, socket),
    do: {:noreply, po_form(socket, PortalSubmit.po_form(socket.assigns.flow, params))}

  def handle_event("submit_order", %{"po" => params}, socket) do
    case PortalSubmit.submit(socket.assigns.flow, params) do
      {:ok, flow, po} ->
        order_id = PlaceOrder.place(socket.assigns.place_order, po)

        {:noreply,
         socket
         |> flow(PortalSubmit.complete(flow, order_id))
         |> put_flash(:info, "Order submitted")}

      {:error, changeset} ->
        {:noreply, po_form(socket, changeset)}
    end
  end

  @impl true
  def handle_info({:timer, :undo, item}, socket),
    do: {:noreply, to(socket, :draft, :expire, item)}

  defp to(socket, key, port, payload),
    do: Steps.to(socket, __MODULE__, @parts, key, port, payload, out(key))

  defp out(key), do: fn s, output -> Steps.out(s, __MODULE__, key, output, &wire/3) end

  # {story, port} → where it wires on this page
  defp wire(s, :draft, {:contents, contents}),
    do: price(s, OrderTotals.contents(s.assigns.totals, contents))

  defp wire(s, :draft, {:pending, pending}), do: assign(s, :undo_pending, pending)
  defp wire(s, :draft, {:restored, _item}), do: put_flash(s, :info, "Item restored")

  defp wire(s, :draft, {:stock, change}), do: restock(s, change)

  defp price(s, totals), do: assign(s, totals: totals, summary: OrderTotals.summary(totals))

  defp restock(s, change) do
    {catalog, row} = PortalCatalog.set_stock(s.assigns.catalog, change)
    s = assign(s, :catalog, catalog)
    if row, do: stream_insert(s, :portal_products, row), else: s
  end

  defp po_form(s, changeset), do: assign(s, :po_form, to_form(changeset, action: :validate))

  # a flow that moved shows its new step, at its URL
  defp flow(s, flow) do
    s = if flow.step == s.assigns.flow.step, do: s, else: Steps.patch(s, @step_paths, flow.step)
    assign(s, :flow, flow)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="pb-6 text-3xl font-semibold tracking-tight">Bulk Order Portal</h1>
      <.milestones step={@flow.step} milestones={@milestones} />
      <.only_on current={@flow.step} name={:lines}>
        <UndoRemoval.view pending={@undo_pending} t={@texts.undo} />
        <div class="grid items-start gap-8 lg:grid-cols-[1fr_22rem]">
          <div class="space-y-8">
            <.card title={@texts.order.heading}>
              <EditLines.rows
                streams={@streams}
                stream={:order_lines}
                row={&order_line_row/1}
                row_attrs={%{t: @texts.order.row}}
                count={@summary.item_count}
                empty={@texts.order.empty}
              />
            </.card>
            <.card title={@texts.catalog.heading}>
              <.stream_list
                :let={{dom_id, row}}
                id="portal_products"
                stream={@streams.portal_products}
              >
                <.catalog_row id={dom_id} row={row} on_add="add_to_order" t={@texts.catalog.row} />
              </.stream_list>
            </.card>
          </div>
          <.card class="lg:sticky lg:top-24">
            <.order_summary summary={@summary} t={@texts.order.summary} />
            <.primary_button event="go_review" disabled={@summary.empty?} class="mt-6 w-full">
              {@texts.order.review} · {@summary.total}
            </.primary_button>
          </.card>
        </div>
      </.only_on>
      <.only_on current={@flow.step} name={:review}>
        <.card class="max-w-lg">
          <div class="mb-6">
            <.order_summary summary={@summary} t={@texts.submit.summary} />
          </div>
          <.simple_form for={@po_form} phx-change="validate_po" phx-submit="submit_order">
            <.input
              field={@po_form[:number]}
              label={@texts.submit.po_number}
              placeholder={@texts.submit.po_placeholder}
            />
            <.input field={@po_form[:notes]} label={@texts.submit.notes} />
            <:actions>
              <button
                type="button"
                phx-click="edit_lines"
                class="text-sm font-medium text-stone-500 hover:text-stone-800"
              >
                {@texts.submit.back}
              </button>
              <.button phx-disable-with={@texts.submit.submitting}>
                {@texts.submit.submit} · {@summary.total}
              </.button>
            </:actions>
          </.simple_form>
        </.card>
      </.only_on>
      <.only_on current={@flow.step} name={:submitted}>
        <.card class="max-w-lg">
          <h2 class="pb-2 text-2xl font-semibold">{@texts.submit.submitted}</h2>
          <p class="text-stone-600">
            {@texts.submit.reference} <span class="font-mono">#{@flow.order_id}</span>
            · {@flow.po.number}
          </p>
          <p class="pt-1 text-sm text-stone-500">
            {@texts.submit.total} {@summary.total} ({@summary.item_count} {@texts.submit.items})
          </p>
        </.card>
      </.only_on>
    </div>
    """
  end
end
