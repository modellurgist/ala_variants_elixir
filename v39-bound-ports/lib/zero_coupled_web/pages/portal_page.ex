defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B bulk-order portal: a second page over the same cart aggregate, domain rules, and undo
  feature, with its own bindings, pricing, and flow. Its draft order is a separate session cart.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}
  alias ZeroCoupledWeb.Paradigms.Binder
  alias ZeroCoupledWeb.PortalLive.PortalView

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

  def bindings(cart_id) do
    %{
      {:order, :rows} => [{:stream, :order_lines}],
      {:order, :summary} => [{:assign, :summary}],
      {:order, :persist} => [{:call, &Carts.apply_change/1}],
      {:order, :removed} => [{:input, :undo, &Undo.capture/2}],
      {:undo, :captured} => [{:set, :undo_pending, true}],
      {:undo, :timer} => [{:timer, :undo, @undo_window_ms}],
      {:undo, :restored} => [
        {:input, :order, &OrderLines.receive/2},
        {:set, :undo_pending, false}
      ],
      {:undo, :expired} => [
        {:input, :order, &OrderLines.confirm_removal/2},
        {:set, :undo_pending, false}
      ],
      {:catalog, :rows} => [{:stream, :portal_products}],
      {:catalog, :requested} => [
        {:via, &ensure_line(cart_id, &1),
         [{:input, :order, &OrderLines.add/2}, {:flash, :info, "Added to order"}]}
      ],
      {:flow, :step} => [{:assign, :step}, {:patch, @step_paths}],
      {:flow, :form} => [{:form, :po_form}],
      {:flow, :blocked} => [{:flash_for, :error, %{empty: "Your order is empty"}}],
      {:flow, :approved} => [
        {:assign, :po},
        {:via, &place_order(cart_id, &1), [{:input, :flow, &PortalSubmit.complete/2}]}
      ],
      {:flow, :reference} => [{:assign, :order_id}, {:flash, :info, "Order submitted"}]
    }
  end

  @impl true
  def mount(_params, %{"portal_cart_id" => cart_id}, socket) do
    order = OrderLines.new(cart_id: cart_id, items: Carts.list_items(cart_id), pricing: @pricing)
    catalog = PortalCatalog.new(products: Products.list())
    flow = PortalSubmit.new(flow: @flow, start: :lines, url_edges: @url_edges)

    {:ok,
     socket
     |> assign(
       bindings: bindings(cart_id),
       order: order,
       catalog: catalog,
       undo: Undo.new([]),
       flow: flow
     )
     |> assign(
       summary: OrderLines.summary(order),
       step: :lines,
       milestones: @milestones,
       undo_pending: false,
       order_id: nil,
       po: nil
     )
     |> assign(po_form: to_form(PortalSubmit.po_form(flow)))
     |> stream(:order_lines, OrderLines.rows(order))
     |> stream(:portal_products, PortalCatalog.rows(catalog))}
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
    do: {:noreply, run(socket, :flow, &PortalSubmit.review(&1, socket.assigns.summary))}

  def handle_event("edit_lines", _params, socket),
    do: {:noreply, run(socket, :flow, &PortalSubmit.edit_lines(&1, nil))}

  def handle_event("validate_po", %{"po" => params}, socket),
    do: {:noreply, run(socket, :flow, &PortalSubmit.validate(&1, params))}

  def handle_event("submit_order", %{"po" => params}, socket),
    do: {:noreply, run(socket, :flow, &PortalSubmit.submit(&1, params))}

  @impl true
  def handle_info({:timer, :undo, item_id}, socket),
    do: {:noreply, run(socket, :undo, &Undo.expire(&1, item_id))}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket) do
    change = %{product_id: id, stock: stock}

    {:noreply,
     socket
     |> run(:order, &OrderLines.set_stock(&1, change))
     |> run(:catalog, &PortalCatalog.set_stock(&1, change))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp run(socket, key, step), do: Binder.run(socket, socket.assigns.bindings, key, step)
  defp int(s), do: String.to_integer(s)

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
