defmodule GoodDealWeb.PortalLive.Show do
  @moduledoc """
  The B2B bulk-order portal: the same shape as the cart page, composing its own stories (pricing
  the order, browsing the catalogue, submitting it) and two of the cart's, editing the lines and
  undoing a removal, each configured for the portal (its row, its window). Its
  draft is a separate session cart. Each browser event goes to the story whose view fires it; each
  story output wires through one `wire/3` clause.
  """
  use GoodDealWeb, :live_view
  import GoodDeal.Components.{Panes, Parts}
  import GoodDeal.Components.Rows, only: [milestones: 1, order_line_row: 1]

  alias GoodDealWeb.Paradigms.{ChangeFeed, Steps}
  alias GoodDeal.Catalog
  alias GoodDeal.Domain.{CalculateShipping, StockStatus}
  alias GoodDealWeb.CartSession
  alias GoodDealWeb.Stories.{BrowseCatalog, EditLines, PriceOrder, SubmitOrder, UndoRemoval}

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
  @parts %{
    edit_lines: EditLines,
    price: PriceOrder,
    undo: UndoRemoval,
    catalog: BrowseCatalog,
    submit: SubmitOrder,
    feed: ChangeFeed
  }
  def parts, do: @parts

  @doc """
  Outputs this page has no use for: the shared editing story's that its rows offer none of, and a
  saved product's other fields, which it doesn't show.
  """
  def grounded,
    do: [edit_lines: :saved, edit_lines: :line, edit_lines: :checkout_requested, feed: :product]

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session, CartSession.portal_key())
    stock_status = StockStatus.new(low_at: Catalog.low_stock_threshold())

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      volume: &volume_tier/1
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
     |> PriceOrder.mount([pricing: pricing], out(:price))
     |> EditLines.mount(
       [
         cart_id: cart_id,
         stock_status: stock_status,
         stream: :order_lines,
         hold_ms: Catalog.undo_window_ms()
       ],
       out(:edit_lines)
     )
     |> BrowseCatalog.mount([stock_status: stock_status], out(:catalog))
     |> SubmitOrder.mount([cart_id: cart_id], out(:submit))
     |> ChangeFeed.mount([topic: Catalog.changes_topic(), facts: [:stock]], out(:feed))}
  end

  # the portal's volume pricing: the highest tier the subtotal reaches, as `{percent, label}`
  defp volume_tier(subtotal) do
    Enum.find_value(Catalog.volume_tiers(), {0, nil}, fn {min, pct, label} ->
      if subtotal >= min, do: {pct, label}
    end)
  end

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, to(socket, :submit, :goto, Map.get(@steps_by_url, params["step"], :lines))}

  @edit_lines_events EditLines.events()
  @price_events PriceOrder.events()
  @undo_events UndoRemoval.events()
  @catalog_events BrowseCatalog.events()
  @submit_events SubmitOrder.events()

  # each story handles the events its own view fires
  @impl true
  def handle_event(event, params, socket) when event in @edit_lines_events,
    do: {:noreply, EditLines.handle_event(event, params, socket, out(:edit_lines))}

  def handle_event(event, params, socket) when event in @price_events,
    do: {:noreply, PriceOrder.handle_event(event, params, socket, out(:price))}

  def handle_event(event, params, socket) when event in @undo_events,
    do: {:noreply, UndoRemoval.handle_event(event, params, socket, out(:undo))}

  def handle_event(event, params, socket) when event in @catalog_events,
    do: {:noreply, BrowseCatalog.handle_event(event, params, socket, out(:catalog))}

  def handle_event(event, params, socket) when event in @submit_events,
    do: {:noreply, SubmitOrder.handle_event(event, params, socket, out(:submit))}

  @impl true
  def handle_info({:timer, :undo, item}, socket), do: {:noreply, to(socket, :undo, :expire, item)}

  defp to(socket, key, port, payload),
    do: Steps.to(socket, __MODULE__, @parts, key, port, payload, out(key))

  defp out(key), do: fn s, output -> Steps.out(s, __MODULE__, key, output, &wire/3) end

  # {story, port} → where it wires on this page
  defp wire(s, :edit_lines, {:contents, contents}), do: to(s, :price, :contents, contents)
  defp wire(s, :edit_lines, {:removed, item}), do: to(s, :undo, :capture, item)
  defp wire(s, :price, {:summary, summary}), do: assign(s, :summary, summary)
  defp wire(s, :price, {:review, summary}), do: to(s, :submit, :review, summary)
  defp wire(s, :undo, {:pending, pending}), do: assign(s, :undo_pending, pending)

  defp wire(s, :undo, {:restored, item}),
    do: s |> to(:edit_lines, :receive, item) |> put_flash(:info, "Item restored")

  defp wire(s, :undo, {:expired, item_id}), do: to(s, :edit_lines, :confirm_removal, item_id)

  defp wire(s, :catalog, {:requested, request}),
    do: s |> to(:edit_lines, :add, request) |> put_flash(:info, "Added to order")

  defp wire(s, :submit, {:step, step}), do: assign(s, :step, step)

  defp wire(s, :submit, {:form, changeset}),
    do: assign(s, :po_form, to_form(changeset, action: :validate))

  defp wire(s, :submit, {:po, po}), do: assign(s, :po, po)
  defp wire(s, :submit, {:reference, order_id}), do: assign(s, :order_id, order_id)

  defp wire(s, :feed, {:stock, change}),
    do: s |> to(:edit_lines, :stock, change) |> to(:catalog, :stock, change)

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
              <BrowseCatalog.view streams={@streams} t={@texts.catalog} />
            </.card>
          </div>
          <.card class="lg:sticky lg:top-24">
            <PriceOrder.totals summary={@summary} t={@texts.order} />
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
