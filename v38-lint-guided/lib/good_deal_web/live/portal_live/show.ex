defmodule GoodDealWeb.PortalLive.Show do
  @moduledoc """
  The B2B bulk-order portal, in the same disciplined-monolith style as the cart
  page: all logic in the LiveView, the order as a typed struct assign, side
  effects as tuples. Steps are `:lines`, `:review` and `:submitted`, each with a URL.
  """

  use GoodDealWeb, :live_view

  alias GoodDealWeb.CartSession
  alias GoodDealWeb.PortalLive.OrderState
  alias GoodDealWeb.CartLive.Helpers
  alias GoodDeal.Foundation.{Broadcast, Carts, Orders, Products}
  alias GoodDeal.Domain.{Inventory, Pricing}
  alias GoodDeal.Domain.Forms.PurchaseOrder

  @undo_window_ms 5_000
  @step_paths %{lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"}

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session, CartSession.portal_key())
    items = Carts.list_items(cart_id)
    order = OrderState.new(cart_id, items, calibration())

    if connected?(socket), do: Broadcast.subscribe()

    {:ok,
     socket
     |> assign(
       order: order,
       step: :lines,
       undo: nil,
       po: nil,
       order_id: nil,
       po_form: to_form(PurchaseOrder.changeset(%PurchaseOrder{}, %{}), as: :po),
       low_stock: GoodDeal.Catalog.low_stock_threshold()
     )
     |> stream(:order_lines, items)
     |> stream(:portal_products, Products.list())}
  end

  # Back from review to the lines is allowed; any other jump by URL is ignored.
  @impl true
  def handle_params(params, _url, socket) do
    requested =
      case params["step"] do
        "review" -> :review
        "submitted" -> :submitted
        _ -> :lines
      end

    if socket.assigns.step == :review and requested == :lines do
      {:noreply, assign(socket, :step, :lines)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_to_order", %{"product-id" => id, "quantity" => q}, socket) do
    product_id = to_int(id)
    quantity = max(to_int(q), 1)
    order = socket.assigns.order
    existing = Enum.find(order.items, &(&1.product.id == product_id))
    target = if existing, do: existing.quantity + quantity, else: quantity

    {:ok, _} = Carts.add_item(order.cart_id, Products.get!(product_id))
    line = order.cart_id |> Carts.list_items() |> Enum.find(&(&1.product.id == product_id))
    {:ok, _} = Carts.update_quantity(order.cart_id, line.id, target)
    line = %{line | quantity: target}

    items = Enum.reject(order.items, &(&1.id == line.id)) ++ [line]
    order = OrderState.recompute(%{order | items: items})

    {:noreply,
     socket
     |> assign(:order, order)
     |> stream_insert(:order_lines, line)
     |> put_flash(:info, "Added to order")}
  end

  def handle_event("set_line_quantity", %{"item-id" => id, "quantity" => q}, socket) do
    item_id = to_int(id)
    quantity = max(to_int(q), 1)
    order = socket.assigns.order

    case Enum.find(order.items, &(&1.id == item_id)) do
      nil ->
        {:noreply, socket}

      line ->
        Carts.update_quantity(order.cart_id, item_id, quantity)
        line = %{line | quantity: quantity}
        items = Enum.map(order.items, &if(&1.id == item_id, do: line, else: &1))
        order = OrderState.recompute(%{order | items: items})
        {:noreply, socket |> assign(:order, order) |> stream_insert(:order_lines, line)}
    end
  end

  def handle_event("remove_line", %{"item-id" => id}, socket) do
    item_id = to_int(id)
    order = socket.assigns.order

    case Helpers.pop_item(order.items, item_id) do
      {nil, _} ->
        {:noreply, socket}

      {removed, rest} ->
        # only the most recent removal is undoable: an earlier one becomes final now
        if previous = socket.assigns.undo do
          Process.cancel_timer(previous.ref)
          Carts.remove_item(order.cart_id, previous.item.id)
        end

        ref = Process.send_after(self(), {:timer, :undo, removed}, @undo_window_ms)

        {:noreply,
         socket
         |> assign(
           order: OrderState.recompute(%{order | items: rest}),
           undo: %{item: removed, ref: ref}
         )
         |> stream_delete(:order_lines, removed)}
    end
  end

  def handle_event("undo_remove", _params, socket) do
    case socket.assigns.undo do
      nil ->
        {:noreply, socket}

      %{item: item, ref: ref} ->
        Process.cancel_timer(ref)

        order =
          OrderState.recompute(%{
            socket.assigns.order
            | items: socket.assigns.order.items ++ [item]
          })

        {:noreply,
         socket
         |> assign(order: order, undo: nil)
         |> stream_insert(:order_lines, item)
         |> put_flash(:info, "Item restored")}
    end
  end

  def handle_event("go_review", _params, socket) do
    if socket.assigns.order.items == [] do
      {:noreply, put_flash(socket, :error, "Your order is empty")}
    else
      {:noreply, socket |> assign(:step, :review) |> push_patch(to: @step_paths.review)}
    end
  end

  def handle_event("edit_lines", _params, socket),
    do: {:noreply, socket |> assign(:step, :lines) |> push_patch(to: @step_paths.lines)}

  def handle_event("validate_po", %{"po" => params}, socket) do
    changeset = PurchaseOrder.changeset(%PurchaseOrder{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :po_form, to_form(changeset, as: :po))}
  end

  def handle_event("submit_order", %{"po" => params}, socket) do
    case Ecto.Changeset.apply_action(PurchaseOrder.changeset(%PurchaseOrder{}, params), :insert) do
      {:ok, po} ->
        {:ok, order} = Orders.create(socket.assigns.order.cart_id)

        {:noreply,
         socket
         |> assign(step: :submitted, po: po, order_id: order.id)
         |> push_patch(to: @step_paths.submitted)
         |> put_flash(:info, "Order submitted")}

      {:error, changeset} ->
        {:noreply, assign(socket, :po_form, to_form(changeset, as: :po))}
    end
  end

  @impl true
  def handle_info({:timer, :undo, %{id: item_id}}, socket) do
    case socket.assigns.undo do
      %{item: %{id: ^item_id}} ->
        Carts.remove_item(socket.assigns.order.cart_id, item_id)
        {:noreply, assign(socket, :undo, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:stock_changed, {product_id, stock}}, socket) do
    order = socket.assigns.order
    items = Helpers.update_product_stock(order.items, product_id, stock)
    socket = assign(socket, :order, %{order | items: items})

    socket =
      Enum.reduce(items, socket, fn item, s ->
        if item.product.id == product_id, do: stream_insert(s, :order_lines, item), else: s
      end)

    product = %{Products.get!(product_id) | stock: stock}
    {:noreply, stream_insert(socket, :portal_products, product)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp to_int(s) when is_binary(s), do: String.to_integer(s)
  defp to_int(n) when is_integer(n), do: n

  defp calibration do
    %{
      shipping_methods: GoodDeal.Catalog.shipping_methods(),
      volume_tiers: GoodDeal.Catalog.volume_tiers()
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <ol class="flex gap-4 text-sm mb-6">
        <li
          :for={{s, label} <- [lines: "Order", review: "Review", submitted: "Done"]}
          class={["font-medium", if(s == @step, do: "text-zinc-900", else: "text-zinc-400")]}
        >
          {label}
        </li>
      </ol>

      <div :if={@step == :lines} class="space-y-8">
        <div
          :if={@undo}
          class="flex items-center justify-between bg-amber-50 border border-amber-200 rounded-lg px-4 py-3"
        >
          <span class="text-sm text-amber-800">Item removed.</span>
          <button phx-click="undo_remove" class="text-sm font-semibold text-amber-700 underline">
            Undo
          </button>
        </div>

        <section>
          <h2 class="text-lg font-semibold pb-2">Your order</h2>
          <div id="order_lines" phx-update="stream">
            <div
              :for={{dom_id, line} <- @streams.order_lines}
              id={dom_id}
              class="grid grid-cols-[1fr_auto_auto_auto] items-center gap-4 border-b py-3"
            >
              <div>
                <div class="font-medium">{line.product.name}</div>
                <.stock_badge status={Inventory.stock_status(line.product.stock, @low_stock)} />
              </div>
              <form phx-change="set_line_quantity">
                <input type="hidden" name="item-id" value={line.id} />
                <input
                  type="number"
                  name="quantity"
                  min="1"
                  value={line.quantity}
                  class="w-20 rounded border px-2 py-1"
                />
              </form>
              <span class="font-semibold">
                {Money.new(Pricing.line_total(line.product.amount, line.quantity))}
              </span>
              <button phx-click="remove_line" phx-value-item-id={line.id} class="text-xs text-red-500">
                Remove
              </button>
            </div>
          </div>
          <div :if={@order.items == []} class="py-8 text-center text-zinc-400">
            No lines yet. Add products below.
          </div>
          <.summary order={@order} />
          <button
            phx-click="go_review"
            disabled={@order.items == []}
            class={[
              "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
              @order.items == [] && "opacity-50 cursor-not-allowed"
            ]}
          >
            Review order · {@order.total}
          </button>
        </section>

        <section>
          <h2 class="text-lg font-semibold pb-2">Products</h2>
          <div id="portal_products" phx-update="stream">
            <div
              :for={{dom_id, product} <- @streams.portal_products}
              id={dom_id}
              class="grid grid-cols-[1fr_auto] items-center gap-4 border-b py-3"
            >
              <div>
                <div class="font-medium">{product.name}</div>
                <div class="text-sm text-zinc-500">{Money.new(product.amount)} each</div>
                <.stock_badge status={Inventory.stock_status(product.stock, @low_stock)} />
              </div>
              <form phx-submit="add_to_order" class="flex gap-2">
                <input type="hidden" name="product-id" value={product.id} />
                <input
                  type="number"
                  name="quantity"
                  min="1"
                  value="10"
                  class="w-20 rounded border px-2 py-1"
                />
                <button
                  type="submit"
                  disabled={product.stock <= 0}
                  class="rounded bg-zinc-900 px-3 py-1 text-sm text-white disabled:opacity-40"
                >
                  Add
                </button>
              </form>
            </div>
          </div>
        </section>
      </div>

      <div :if={@step == :review} class="space-y-4 max-w-lg">
        <.summary order={@order} />
        <.simple_form for={@po_form} phx-change="validate_po" phx-submit="submit_order">
          <.input field={@po_form[:number]} label="Purchase order number" placeholder="PO-1234" />
          <.input field={@po_form[:notes]} label="Notes (optional)" />
          <:actions>
            <button type="button" phx-click="edit_lines" class="text-sm text-zinc-500 underline">
              Back to lines
            </button>
            <.button phx-disable-with="Submitting…">Submit order · {@order.total}</.button>
          </:actions>
        </.simple_form>
      </div>

      <div :if={@step == :submitted} class="py-10 space-y-2">
        <h2 class="text-2xl font-semibold">Order submitted</h2>
        <p class="text-zinc-600">
          Reference <span class="font-mono">#{@order_id}</span> · {@po.number}
        </p>
        <p class="text-zinc-500 text-sm">Total {@order.total} ({@order.item_count} items)</p>
      </div>
    </div>
    """
  end

  defp summary(assigns) do
    ~H"""
    <div class="space-y-1 py-4 border-t mt-4 text-sm">
      <div class="flex justify-between text-zinc-600">
        <span>Items</span><span>{@order.item_count}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Subtotal</span><span>{@order.subtotal}</span>
      </div>
      <div :if={@order.tier_label} class="flex justify-between text-green-700">
        <span>{@order.tier_label}</span><span>-{@order.discount}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Shipping</span>
        <span>{if Money.zero?(@order.shipping), do: "Free", else: @order.shipping}</span>
      </div>
      <div class="flex justify-between items-center py-2 border-t font-bold text-lg">
        <span>Total</span><span>{@order.total}</span>
      </div>
    </div>
    """
  end

  defp stock_badge(assigns) do
    ~H"""
    <span
      :if={@status != :in_stock}
      class={[
        "text-xs font-medium px-1.5 py-0.5 rounded",
        @status == :low_stock && "bg-amber-100 text-amber-700",
        @status == :out_of_stock && "bg-red-100 text-red-700"
      ]}
    >
      {if @status == :low_stock, do: "Low stock", else: "Out of stock"}
    </span>
    """
  end
end
