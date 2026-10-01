defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal: the same shape as the cart page over the same aggregate, domain
  rules and undo instance, with its own instances, pricing and flow. Its draft is a separate
  session cart. No catch-all `handle_info`, as on the cart page.
  """
  use ZeroCoupledWeb, :live_view
  import ZeroCoupled.Catalog.Panes, only: [pane: 1]
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]
  alias ZeroCoupled.Domain.{AddLine, CalculateShipping, PlaceOrder, StockStatus, VolumeTier}
  alias ZeroCoupledWeb.{CartSession, StoreConfig}
  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupledWeb.Paradigms.Instance
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}

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
    order: %{heading: "Your order", review: "Review order", row: %{each: " each"}},
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
    undo: %{undo: "Undo"}
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
    |> update_in([:submit], &Map.merge(&1, %{summary: summary, total: summary.total}))
  end

  @blocked %{empty: "Your order is empty"}

  @impl true
  def mount(_params, session, socket) do
    cart_id = session[CartSession.portal_key()]

    {:ok,
     assign(socket,
       cart_id: cart_id,
       texts: texts(),
       pricing: %{
         shipping: CalculateShipping.new(StoreConfig.rates()),
         volume: VolumeTier.new(@volume_tiers),
         stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at())
       },
       stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at()),
       add_line: %AddLine{carts: Carts, products: Products},
       place_order: %PlaceOrder{orders: Orders},
       step: :lines,
       requested_step: :lines,
       summary: nil,
       milestones: @milestones,
       undo_window_ms: StoreConfig.undo_window_ms(),
       flow: @flow,
       url_edges: @url_edges
     )}
  end

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, assign(socket, requested_step: Map.get(@steps_by_url, params["step"], :lines))}

  @routes %{
    {:catalog, :requested} => [
      pass: {OrderLines.Panel, "order", :add},
      flash: {:info, "Added to order"}
    ],
    {:order, :summary} => [assign: :summary],
    {:order, :removed} => [pass: {Undo.Banner, "undo", :capture}],
    {:order, :review} => [pass: {PortalSubmit.Panel, "submit", :review}],
    {:undo, :expire} => [pass: {Undo.Banner, "undo", :expire}],
    {:undo, :expired} => [pass: {OrderLines.Panel, "order", :confirm_removal}],
    {:undo, :restored} => [pass: {OrderLines.Panel, "order", :receive}],
    {:submit, :step} => [assign: :step, patch: @step_paths],
    {:submit, :blocked} => [flash_by: {:error, @blocked}],
    {:submit, :reference} => [flash: {:info, "Order submitted"}],
    {:stock, :changed} => [
      pass: {OrderLines.Panel, "order", :set_stock},
      pass: {PortalCatalog.Panel, "catalog", :set_stock}
    ]
  }

  @doc "The page's wiring: where each instance's announcement goes."
  def routes, do: @routes

  @impl true
  def handle_info({_name, _port, _payload} = announcement, socket),
    do: {:noreply, Instance.route(socket, @routes, announcement)}

  def handle_info(%Broadcast.Facts.StockChanged{} = change, socket),
    do: {:noreply, Instance.route(socket, @routes, {:stock, :changed, change})}

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <.pane current={@step} name={:lines} class="space-y-8">
        <.live_component
          module={Undo.Banner}
          id="undo"
          window_ms={@undo_window_ms}
          text="Item removed."
          t={@texts.undo}
        />
        <.live_component
          module={OrderLines.Panel}
          id="order"
          cart_id={@cart_id}
          pricing={@pricing}
          store={Carts}
          add_line={@add_line}
          empty_text="No lines yet. Add products below."
          t={@texts.order}
        />
        <.live_component
          module={PortalCatalog.Panel}
          id="catalog"
          products={&Products.list/0}
          stock_status={@stock_status}
          t={@texts.catalog}
        />
      </.pane>
      <.live_component
        module={PortalSubmit.Panel}
        id="submit"
        cart_id={@cart_id}
        place_order={@place_order}
        messages={%{number: "must look like PO-1234"}}
        t={@texts.submit}
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
