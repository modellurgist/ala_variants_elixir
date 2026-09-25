defmodule ZeroCoupledWeb.PortalPage do
  @moduledoc """
  The B2B portal's hand-written LiveView (D6 second consumer) — irregular
  events plus thin delegation to the committed generated glue, exactly the
  cart page's shape. Its own session cart (the order draft) comes from the
  `SessionCart` plug under the `:portal_cart_id` key.
  """

  use ZeroCoupledWeb, :live_view

  alias ZeroCoupledWeb.PortalPage.Generated
  alias ZeroCoupledWeb.EffectInterpreter
  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}
  alias ZeroCoupled.Web.Contracts

  # Pure API delegated to the generated glue (test/introspection surface).
  defdelegate run_pure(session, fun), to: Generated
  defdelegate run_intent(session, name, args), to: Generated
  defdelegate __manifest__(), to: Generated

  # ── Lifecycle ────────────────────────────────────────────────────────

  @impl true
  def mount(_params, %{"portal_cart_id" => cart_id}, socket) do
    items = Carts.list_items(cart_id)
    products = Products.list()
    if connected?(socket), do: Broadcast.subscribe()

    socket = Generated.mount_session(socket, cart_id: cart_id, items: items, products: products)

    {:ok,
     socket
     |> assign_po_form()
     |> stream(Contracts.stream_name(:order), Enum.map(items, &OrderLines.row/1))
     |> stream(Contracts.stream_name(:catalog), Enum.map(products, &PortalCatalog.row/1))}
  end

  # URL → flow step (V33): back/forward moves the wizard only where the
  # feature's URL policy allows.
  @impl true
  def handle_params(params, _url, socket) do
    with step when step != nil <- Generated.flow_param_step(:bulk_order, params),
         true <- step != socket.assigns.session.flow.step do
      run(socket, &PortalSubmit.Intents.goto_step(&1, step))
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns), do: Generated.page_render(assigns)

  # ── Irregular events ─────────────────────────────────────────────────

  # Adding needs persistence I/O first; repeat adds of an existing product
  # route through the pure set_line_quantity intent instead (see
  # OrderLines.Intents.add_line).
  @impl true
  def handle_event("add_to_order", %{"product-id" => pid, "quantity" => q}, socket) do
    product_id = String.to_integer(pid)
    quantity = max(String.to_integer(q), 1)
    order = socket.assigns.session.order

    case Enum.find(order.items, &(&1.product.id == product_id)) do
      nil ->
        cart_id = order.cart_id
        Carts.add_item(cart_id, Products.get!(product_id))
        item = cart_id |> Carts.list_items() |> Enum.find(&(&1.product.id == product_id))
        run(socket, &OrderLines.Intents.add_line(&1, item, quantity))

      line ->
        run(socket, fn session ->
          OrderLines.Intents.set_line_quantity(session, %{
            item_id: line.id,
            quantity: line.quantity + quantity
          })
        end)
    end
  end

  # PO form: live validation returns a form, not effects.
  def handle_event("validate_po", %{"po" => params}, socket) do
    changeset = PortalSubmit.Intents.change_po(socket.assigns.session, params)
    {:noreply, assign(socket, :po_form, to_form(changeset, action: :validate))}
  end

  # Submit: validate the PO, persist the order (I/O), then complete the flow.
  def handle_event("submit_order", %{"po" => params}, socket) do
    session = socket.assigns.session

    case PortalSubmit.Intents.validate_po(session, params) do
      {:ok, po} ->
        {:ok, order} = Orders.create(session.order.cart_id)
        run(socket, &PortalSubmit.Intents.complete_submit(&1, po, order.id))

      {:error, changeset} ->
        {:noreply, assign(socket, :po_form, to_form(changeset, action: :validate))}
    end
  end

  # Delegate everything declared as an `intent` to the generated clauses.
  def handle_event(event, params, socket), do: Generated.page_event(event, params, socket, &run/2)

  # ── Cross-process facts and timers ───────────────────────────────────

  @impl true
  def handle_info(%Undo.Facts.UndoExpired{item_id: item_id}, socket),
    do: run(socket, &Undo.Intents.undo_expired(&1, item_id))

  def handle_info(%mod{} = fact, socket) do
    if mod in Generated.declared_facts(),
      do: run(socket, &Generated.apply_fact(&1, fact)),
      else: {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── The one house pattern ────────────────────────────────────────────

  defp run(socket, fun) do
    {session, effects} = Generated.run_pure(socket.assigns.session, fun)

    {:noreply,
     socket
     |> Generated.put_session(session)
     |> EffectInterpreter.apply_all(effects, effect_opts())}
  end

  defp effect_opts, do: [flow_path: &Generated.flow_path/2]

  defp assign_po_form(socket) do
    changeset = PortalSubmit.Intents.change_po(socket.assigns.session, %{})
    assign(socket, :po_form, to_form(changeset))
  end
end
