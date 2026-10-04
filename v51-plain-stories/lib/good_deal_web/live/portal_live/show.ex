defmodule GoodDealWeb.PortalLive.Show do
  @moduledoc """
  The B2B bulk-order portal: the same shape as the cart page, composing its own stories (editing the
  order, browsing the catalogue, submitting it) and the cart's undo story with its own window. Its
  draft is a separate session cart. Each browser event goes to the story whose view fires it; each
  story output wires through one `wire/3` clause.
  """
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDeal.Components.{Panes, Parts, Rows}

  alias GoodDeal.Catalog
  alias GoodDeal.Domain.{CalculateShipping, StockStatus, VolumeTier}
  alias GoodDealWeb.CartSession
  alias GoodDealWeb.Stories.{BrowseCatalog, EditOrder, SubmitOrder, UndoRemoval}

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
    summary = Catalog.summary_texts()
    stock = Catalog.stock_texts()

    @texts
    |> put_in([:order, :summary], summary)
    |> update_in([:order, :row], &Map.merge(&1, %{remove: Catalog.remove_text(), stock: stock}))
    |> put_in([:catalog, :row, :stock], stock)
    |> update_in([:submit], &Map.merge(&1, %{total: summary.total, summary: summary}))
  end

  @doc "Which story each `wire/3` key names, so a test can check every declared port has a clause."
  @parts %{order: EditOrder, undo: UndoRemoval, catalog: BrowseCatalog, submit: SubmitOrder}
  def parts, do: @parts

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session, CartSession.portal_key())
    stock_status = StockStatus.new(low_at: Catalog.low_stock_threshold())

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      volume: VolumeTier.new(Catalog.volume_tiers()),
      stock_status: stock_status
    }

    {:ok,
     socket
     |> assign(
       texts: texts(),
       step: :lines,
       milestones: @milestones,
       undo_pending: false,
       order_id: nil,
       po: nil
     )
     |> UndoRemoval.mount([timer: :undo, window_ms: Catalog.undo_window_ms()], out(:undo))
     |> EditOrder.mount([cart_id: cart_id, pricing: pricing], out(:order))
     |> BrowseCatalog.mount([stock_status: stock_status], out(:catalog))
     |> SubmitOrder.mount([cart_id: cart_id], out(:submit))}
  end

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, to(socket, :submit, :goto, Map.get(@steps_by_url, params["step"], :lines))}

  @order_events EditOrder.events()
  @undo_events UndoRemoval.events()
  @catalog_events BrowseCatalog.events()
  @submit_events SubmitOrder.events()

  # each story handles the events its own view fires
  @impl true
  def handle_event(event, params, socket) when event in @order_events,
    do: {:noreply, EditOrder.handle_event(event, params, socket, out(:order))}

  def handle_event(event, params, socket) when event in @undo_events,
    do: {:noreply, UndoRemoval.handle_event(event, params, socket, out(:undo))}

  def handle_event(event, params, socket) when event in @catalog_events,
    do: {:noreply, BrowseCatalog.handle_event(event, params, socket, out(:catalog))}

  def handle_event(event, params, socket) when event in @submit_events,
    do: {:noreply, SubmitOrder.handle_event(event, params, socket, out(:submit))}

  @impl true
  def handle_info({:timer, :undo, item}, socket), do: {:noreply, to(socket, :undo, :expire, item)}

  def handle_info({:stock_changed, {product_id, stock}}, socket) do
    change = %{product_id: product_id, stock: stock}
    {:noreply, socket |> to(:order, :stock, change) |> to(:catalog, :stock, change)}
  end

  # the topic also carries catalogue edits, which this page doesn't show
  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}
  def handle_info({:product_updated, _product}, socket), do: {:noreply, socket}

  defp to(socket, key, port, payload), do: @parts[key].input(socket, port, payload, out(key))
  defp out(key), do: &wire(&1, key, &2)

  # {story, port} → where it wires on this page
  defp wire(s, :order, {:summary, summary}), do: assign(s, :summary, summary)
  defp wire(s, :order, {:removed, item}), do: to(s, :undo, :capture, item)
  defp wire(s, :order, {:review, summary}), do: to(s, :submit, :review, summary)
  defp wire(s, :undo, {:pending, pending}), do: assign(s, :undo_pending, pending)
  defp wire(s, :undo, {:restored, item}), do: to(s, :order, :receive, item)
  defp wire(s, :undo, {:expired, item_id}), do: to(s, :order, :confirm_removal, item_id)

  defp wire(s, :catalog, {:requested, request}),
    do: s |> to(:order, :add, request) |> put_flash(:info, "Added to order")

  defp wire(s, :submit, {:step, step}), do: assign(s, :step, step)

  defp wire(s, :submit, {:form, changeset}),
    do: assign(s, :po_form, to_form(changeset, action: :validate))

  defp wire(s, :submit, {:po, po}), do: assign(s, :po, po)
  defp wire(s, :submit, {:reference, order_id}), do: assign(s, :order_id, order_id)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="pb-6 text-3xl font-semibold tracking-tight">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <.only_on current={@step} name={:lines}>
        <UndoRemoval.view pending={@undo_pending} t={@texts.undo} />
        <div class="grid items-start gap-8 lg:grid-cols-[1fr_22rem]">
          <div class="space-y-8">
            <.card title={@texts.order.heading}>
              <EditOrder.rows streams={@streams} summary={@summary} t={@texts.order} />
            </.card>
            <.card title={@texts.catalog.heading}>
              <BrowseCatalog.view streams={@streams} t={@texts.catalog} />
            </.card>
          </div>
          <.card class="lg:sticky lg:top-24">
            <EditOrder.totals summary={@summary} t={@texts.order} />
          </.card>
        </div>
      </.only_on>
      <SubmitOrder.view
        step={@step}
        form={@po_form}
        summary={@summary}
        order_id={@order_id}
        po={@po}
        t={@texts.submit}
      />
    </div>
    """
  end
end
