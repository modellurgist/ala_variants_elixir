defmodule GoodDealWeb.PortalLive.Show do
  @moduledoc """
  The B2B bulk-order portal, as a composition of user stories: editing the order's lines, browsing the
  catalog, undoing a removal (the same story as the cart page's, with its own window), and submitting
  the order. Its `wire/3` clauses connect the stories; each story wires its own parts. Its draft is a
  separate session cart.
  """
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDeal.Components.Panes, only: [only_on: 1]
  import GoodDeal.Components.Rows, only: [milestones: 1]

  alias GoodDeal.Catalog
  alias GoodDeal.Domain.{AddLine, CalculateShipping, PlaceOrder, StockStatus, VolumeTier}
  alias GoodDeal.Foundation.{Carts, Orders, Products}
  alias GoodDealWeb.CartSession
  alias GoodDealWeb.Paradigms.Story
  alias GoodDealWeb.Stories.{BrowseCatalog, EditOrder, SubmitOrder, UndoRemoval}

  @flow [
    {:lines, :go_review, :review},
    {:review, :edit_lines, :lines},
    {:review, :submit_order, :submitted}
  ]
  @url_edges [{:review, :lines}]
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

  @doc "Which story each `wire/3` key names, so a test can check every output port has a clause."
  @features %{order: EditOrder, undo: UndoRemoval, catalog: BrowseCatalog, submit: SubmitOrder}
  def features, do: @features

  @stories [:order, :undo, :catalog, :submit]

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session, CartSession.portal_key())
    stock_status = StockStatus.new(low_at: Catalog.low_stock_threshold())

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      volume: VolumeTier.new(Catalog.volume_tiers()),
      stock_status: stock_status
    }

    stories = %{
      order: EditOrder.new(cart_id: cart_id, pricing: pricing),
      undo: UndoRemoval.new(window_ms: Catalog.undo_window_ms()),
      catalog:
        BrowseCatalog.new(
          stock_status: stock_status,
          add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id}
        ),
      submit:
        SubmitOrder.new(
          flow: [
            flow: @flow,
            start: :lines,
            url_edges: @url_edges,
            messages: %{number: "must look like PO-1234"}
          ],
          place_order: %PlaceOrder{orders: Orders, cart_id: cart_id}
        )
    }

    {:ok,
     socket
     |> assign(texts: texts(), step: :lines, milestones: @milestones)
     |> Story.mount(stories, &wire/3)
     |> Story.input(:order, :mounted, cart_id)
     |> Story.input(:catalog, :mounted, nil)
     |> Story.input(:submit, :mounted, nil)}
  end

  @impl true
  def handle_params(params, _url, socket),
    do:
      {:noreply,
       Story.input(socket, :submit, :goto, Map.get(@steps_by_url, params["step"], :lines))}

  @impl true
  def handle_event(name, params, socket),
    do: {:noreply, Story.event(socket, @stories, name, params)}

  @impl true
  # a story's timer reports to one of its own inputs
  def handle_info({:story_input, key, port, payload}, socket),
    do: {:noreply, Story.input(socket, key, port, payload)}

  def handle_info({:stock_changed, {product_id, stock}}, socket) do
    change = %{product_id: product_id, stock: stock}

    {:noreply,
     socket |> Story.input(:order, :stock, change) |> Story.input(:catalog, :stock, change)}
  end

  # the topic also carries catalogue edits, which this page doesn't show
  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}
  def handle_info({:product_updated, _product}, socket), do: {:noreply, socket}

  # {story, port} → where it wires on this page
  defp wire(s, :order, {:summary, summary}), do: Story.input(s, :submit, :summary, summary)

  defp wire(s, :order, {:removed, item}), do: Story.input(s, :undo, :capture, item)
  defp wire(s, :order, {:review, summary}), do: Story.input(s, :submit, :review, summary)
  defp wire(s, :undo, {:restored, item}), do: Story.input(s, :order, :receive, item)
  defp wire(s, :undo, {:expired, item_id}), do: Story.input(s, :order, :confirm_removal, item_id)
  defp wire(s, :catalog, {:added, line}), do: Story.input(s, :order, :add, line)
  defp wire(s, :submit, {:step, step}), do: assign(s, :step, step)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <.only_on current={@step} name={:lines}>
        <div class="space-y-8">
          <UndoRemoval.view story={@undo} t={@texts.undo} />
          <EditOrder.view story={@order} streams={@streams} t={@texts.order} />
          <BrowseCatalog.view streams={@streams} t={@texts.catalog} />
        </div>
      </.only_on>
      <SubmitOrder.view story={@submit} step={@step} t={@texts.submit} />
    </div>
    """
  end
end
