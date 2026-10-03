defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal as a composition of user stories: editing the order's lines, browsing the
  catalog, undoing a removal (the cart page's story, with its own window), and submitting the order.
  `bindings/0` links the stories; each story's own map wires its parts; every type is checked
  when the page mounts. Its draft order is a separate session cart.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  import ZeroCoupled.Catalog.Panes, only: [only_on: 1]
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]

  alias ZeroCoupled.Domain.{AddLine, CalculateShipping, PlaceOrder, StockStatus, VolumeTier}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}
  alias ZeroCoupledWeb.{CartSession, StoreConfig}
  alias ZeroCoupledWeb.Paradigms.Binder
  alias ZeroCoupledWeb.Stories.{BrowseCatalog, EditOrder, SubmitOrder, UndoRemoval}

  @volume_tiers [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]
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
    summary = StoreConfig.summary_texts()
    stock = StoreConfig.stock_texts()

    @texts
    |> put_in([:order, :summary], summary)
    |> update_in(
      [:order, :row],
      &Map.merge(&1, %{remove: StoreConfig.remove_text(), stock: stock})
    )
    |> put_in([:catalog, :row, :stock], stock)
    |> update_in([:submit], &Map.merge(&1, %{total: summary.total, summary: summary}))
  end

  @stories [:order, :undo, :catalog, :submit]

  def parts, do: %{}
  def ports, do: %{in: [], out: [mounted: :cart_id]}

  # {source, port} → where it goes on this page; a story's outputs come from {story, port}
  def bindings do
    %{
      {:page, :mounted} => [
        {:to, :order, :mounted},
        {:to, :catalog, :mounted},
        {:to, :submit, :mounted}
      ],
      {:order, :summary} => [{:to, :submit, :summary}],
      {:order, :removed} => [{:to, :undo, :capture}],
      {:order, :review} => [{:to, :submit, :review}],
      {:undo, :restored} => [{:to, :order, :receive}],
      {:undo, :expired} => [{:to, :order, :confirm_removal}],
      {:catalog, :added} => [{:to, :order, :add}],
      {:submit, :step} => [{:show, :step}]
    }
  end

  @doc "The page (the root story) and its stories, configured for a draft order."
  def composition(cart_id) do
    stock_status = StockStatus.new(low_at: StoreConfig.low_stock_at())

    pricing = %{
      shipping: CalculateShipping.new(StoreConfig.rates()),
      volume: VolumeTier.new(@volume_tiers),
      stock_status: stock_status
    }

    stories = %{
      order: EditOrder.new(cart_id: cart_id, pricing: pricing),
      undo: UndoRemoval.new(window_ms: StoreConfig.undo_window_ms()),
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

    {Binder.story(__MODULE__, %{}, bindings()), stories}
  end

  @impl true
  def mount(_params, session, socket) do
    cart_id = session[CartSession.portal_key()]

    {:ok,
     socket
     |> assign(texts: texts(), step: :lines, milestones: @milestones)
     |> Binder.mount(composition(cart_id))
     |> Binder.send_out(:page, :mounted, cart_id)}
  end

  @impl true
  def handle_params(params, _url, socket),
    do:
      {:noreply,
       Binder.input(socket, :submit, :goto, Map.get(@steps_by_url, params["step"], :lines))}

  @impl true
  def handle_event(name, params, socket),
    do: {:noreply, Binder.event(socket, @stories, name, params)}

  # a story's timer reports to one of its own inputs
  @impl true
  def handle_info({:story_input, story, port, payload}, socket),
    do: {:noreply, Binder.input(socket, story, port, payload)}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket) do
    change = %{product_id: id, stock: stock}

    {:noreply,
     socket |> Binder.input(:order, :stock, change) |> Binder.input(:catalog, :stock, change)}
  end

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

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
