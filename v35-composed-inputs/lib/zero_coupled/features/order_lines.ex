# The portal's order-lines feature (D6 second consumer): the page-facing
# surface of the SAME `ZeroCoupled.Cart` aggregate the storefront uses —
# the reuse experiment's central probe. B2B semantics differ from the cart
# page's (absolute quantity entry instead of ± steppers; automatic volume
# repricing after every mutation), which is exactly why this is its own
# feature over a shared aggregate rather than a reuse of CartItems.

defmodule ZeroCoupled.Features.OrderLines do
  @moduledoc """
  Slot module for the `:order` slot — a bulk-order draft as a
  `%ZeroCoupled.Cart{}`. Every mutation reprices through the
  `VolumeTier` domain abstraction (`Cart.set_discount/2`, the one
  aggregate generalization D6 required).
  """

  alias ZeroCoupled.Cart
  alias ZeroCoupled.Domain.{ShippingInfo, StockStatus, VolumeTier}

  @doc "Build the slot from mount opts and the composition's pricing config, tier-priced."
  @spec init(keyword()) :: Cart.t()
  def init(opts),
    do: reprice(Cart.new(cart_id: opts[:cart_id], items: opts[:items] || [], config: (opts[:config] || [])[:pricing]))

  @doc "Recompute the volume-tier discount from the current subtotal (tiers from config)."
  @spec reprice(Cart.t()) :: Cart.t()
  def reprice(%Cart{} = cart) do
    {pct, _label} = VolumeTier.call(cart.subtotal.amount, tiers(cart))
    Cart.set_discount(cart, pct)
  end

  @doc "L5 presentation port (`render: :render_data` → `@order`)."
  @spec render_data(Cart.t()) :: map()
  def render_data(%Cart{} = cart) do
    {_pct, tier_label} = VolumeTier.call(cart.subtotal.amount, tiers(cart))

    %{
      item_count: cart.item_count,
      subtotal: cart.subtotal,
      discount: cart.discount,
      tier_label: tier_label,
      shipping_label: ShippingInfo.label(cart.shipping_method, cart.config[:shipping] || %{}),
      shipping_cost: cart.shipping_cost,
      total: cart.total,
      empty?: Cart.empty?(cart)
    }
  end

  defp tiers(%Cart{config: config}), do: config[:volume_tiers] || []

  @doc "Row port: the projected value the order-lines stream carries."
  @spec row(Cart.item()) :: map()
  def row(item) do
    %{
      id: item.id,
      product_id: item.product.id,
      product: %{
        thumbnail: item.product.thumbnail,
        name: item.product.name,
        amount: item.product.amount
      },
      stock_status: StockStatus.call(item.product.stock),
      quantity: item.quantity,
      line_total: Money.new(item.product.amount * item.quantity)
    }
  end
end

defmodule ZeroCoupled.Features.OrderLines.Facts do
  @moduledoc "Typed facts owned by the order-lines feature."

  defmodule LineRemoved do
    @moduledoc false
    @enforce_keys [:line, :line_id]
    defstruct [:line, :line_id]
  end
end

defmodule ZeroCoupled.Features.OrderLines.Intents do
  @moduledoc """
  Intents owned by the `:order` slot, plus its slot-scoped reactions.
  Note the fact vocabulary: `LineRemoved{line, line_id}` — this feature's
  own naming; the portal manifest translates it to the undo feature's
  `%{item, item_id}` port with a `transform:`.
  """
  use ZeroCoupled.Feature.Intents, slot: :order

  alias ZeroCoupled.{Cart, Effects}
  alias ZeroCoupled.Features.OrderLines
  alias ZeroCoupled.Features.OrderLines.Facts
  alias ZeroCoupled.Web.Contracts

  # ── Intents ──────────────────────────────────────────────────────────

  intent :set_line_quantity, params: [item_id: :int, quantity: :int]

  def set_line_quantity(session, %{item_id: item_id, quantity: quantity}) do
    with line when line != nil <- Enum.find(session.order.items, &(&1.id == item_id)),
         delta = max(quantity, 1) - line.quantity,
         {:ok, cart, line} <- Cart.update_quantity(session.order, item_id, delta) do
      cart = OrderLines.reprice(cart)

      {put_slot(session, cart),
       [
         Effects.stream_insert(Contracts.stream_name(:order), OrderLines.row(line)),
         Effects.persist_quantity(cart.cart_id, item_id, line.quantity)
       ]}
    else
      _ -> {session, []}
    end
  end

  intent :remove_line, params: [item_id: :int]

  def remove_line(session, %{item_id: item_id}) do
    case Cart.remove_item(session.order, item_id) do
      {:ok, cart, removed} ->
        {put_slot(session, OrderLines.reprice(cart)),
         [Effects.stream_delete(Contracts.stream_name(:order), OrderLines.row(removed))],
         [%Facts.LineRemoved{line: removed, line_id: item_id}]}

      :error ->
        {session, []}
    end
  end

  @doc """
  A NEW product was persisted as an order line (shell I/O); add it at the
  requested quantity. Repeat adds of an existing product are routed by the
  shell through `set_line_quantity` instead, so aggregate and DB never
  disagree mid-flight.
  """
  def add_line(session, item, quantity) do
    {:ok, cart, _line} = Cart.add_item(session.order, item)
    {:ok, cart, line} = Cart.update_quantity(cart, item.id, max(quantity, 1) - item.quantity)
    cart = OrderLines.reprice(cart)

    {put_slot(session, cart),
     [
       Effects.stream_insert(Contracts.stream_name(:order), OrderLines.row(line)),
       Effects.persist_quantity(cart.cart_id, line.id, line.quantity),
       Effects.flash(:info, "Added to order")
     ]}
  end

  # ── Reactions (slot, payload) → {slot, effects} ─────────────────────

  @doc "Reaction: a removed line comes back (undo restore)."
  def receive_line(%Cart{} = cart, %{item: item}) do
    {:ok, cart, item} = Cart.add_item(cart, item)

    {OrderLines.reprice(cart),
     [Effects.stream_insert(Contracts.stream_name(:order), OrderLines.row(item))]}
  end

  @doc "Reaction: the undo window elapsed — persist the removal for good."
  def confirm_removal(%Cart{} = cart, %{item_id: item_id}) do
    {cart, [Effects.persist_remove(cart.cart_id, item_id)]}
  end

  @doc "Reaction to the cross-process `Broadcast.Facts.StockChanged` fact."
  def set_stock(%Cart{} = cart, %{product_id: product_id, stock: stock}) do
    case Cart.set_stock(cart, product_id, stock) do
      {:ok, cart, item} ->
        {cart, [Effects.stream_insert(Contracts.stream_name(:order), OrderLines.row(item))]}

      :none ->
        {cart, []}
    end
  end
end

defmodule ZeroCoupled.Features.OrderLines.Components do
  @moduledoc "Markup owned by the order-lines feature — thin over the catalog."
  use Phoenix.Component

  import ZeroCoupled.Catalog.ProductLineRow
  import ZeroCoupled.Catalog.ActionButton
  import ZeroCoupled.Catalog.StockBadge
  alias ZeroCoupled.Web.Contracts

  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "projected: %{id, product, stock_status, quantity, line_total}"

  def order_line_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto" price_suffix=" each">
      <:detail>
        <.stock_badge status={@row.stock_status} />
      </:detail>
      <:actions>
        <form phx-change={Contracts.event(:set_line_quantity)} class="flex items-center gap-2">
          <input type="hidden" name="item-id" value={@row.id} />
          <input
            type="number"
            name="quantity"
            value={@row.quantity}
            min="1"
            class="w-20 rounded border border-zinc-300 px-2 py-1 text-sm text-right"
          />
        </form>
        <div class="text-right w-24">
          <div class="font-semibold"><%= @row.line_total %></div>
          <.action_button
            on={Contracts.event(:remove_line)}
            phx-value-item-id={@row.id}
            label="Remove"
            class="text-xs text-red-500"
          />
        </div>
      </:actions>
    </.product_line>
    """
  end
end
