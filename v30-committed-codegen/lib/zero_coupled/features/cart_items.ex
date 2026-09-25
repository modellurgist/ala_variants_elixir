# The cart-items feature — the page-facing surface of the `ZeroCoupled.Cart`
# aggregate. The aggregate itself stays in its own file (lib/zero_coupled/cart.ex):
# it earns its ~200 lines under the size cap, and this file would breach it.
#
# Three sibling modules (V29's feature-file shape):
#   CartItems            — slot module: init/1 + render_data/1 (the L5 presentation port)
#   CartItems.Intents    — intents owned by the cart slot + slot-scoped reactions
#   CartItems.Components — this feature's own markup

defmodule ZeroCoupled.Features.CartItems do
  @moduledoc """
  Slot module for the `:cart` slot. State is the `%ZeroCoupled.Cart{}`
  aggregate — V28's B1 insight is unchanged: one source of truth for
  items, pricing, gift wrap, shipping, and promo.
  """

  alias ZeroCoupled.Cart
  alias ZeroCoupled.Domain.ShippingInfo

  @doc "Build the slot from mount opts (`cart_id:`, `items:`)."
  @spec init(keyword()) :: Cart.t()
  def init(opts), do: Cart.new(cart_id: opts[:cart_id], items: opts[:items] || [])

  @doc """
  L5 presentation port: the summary surface templates consume, decoupled
  from aggregate field names. Marked in the manifest with
  `render: :render_data`, which assigns it as `@cart`.
  """
  @spec render_data(Cart.t()) :: map()
  def render_data(%Cart{} = cart) do
    %{
      item_count: cart.item_count,
      subtotal: cart.subtotal,
      discount: cart.discount,
      promo_code: cart.promo_code,
      gift_wrap_total: cart.gift_wrap_total,
      shipping_label: ShippingInfo.label(cart.shipping_method),
      shipping_method: cart.shipping_method,
      shipping_cost: cart.shipping_cost,
      total: cart.total,
      empty?: Cart.empty?(cart)
    }
  end
end

defmodule ZeroCoupled.Features.CartItems.Facts do
  @moduledoc """
  Typed facts **owned by this feature** — the only vocabulary it shares
  outward. Emitting a fact with a wrong/missing field is a compile
  error (`@enforce_keys` + struct keys); the page manifest references
  these modules by alias, so a typo'd wire is a compile error too.
  Reactors never see these structs — the manifest projects them
  (`Map.from_struct/1` or a `transform:`).
  """

  defmodule ItemRemoved do
    @moduledoc false
    @enforce_keys [:item, :item_id]
    defstruct [:item, :item_id]
  end

  defmodule ItemSaved do
    @moduledoc false
    @enforce_keys [:item]
    defstruct [:item]
  end

  defmodule PromoApplied do
    @moduledoc false
    defstruct []
  end

  defmodule PromoRejected do
    @moduledoc false
    @enforce_keys [:message]
    defstruct [:message]
  end

  defmodule AddedFromWishlist do
    @moduledoc false
    @enforce_keys [:product_id]
    defstruct [:product_id]
  end
end

defmodule ZeroCoupled.Features.CartItems.Intents do
  @moduledoc """
  Intents owned by the `:cart` slot, plus its slot-scoped reactions.

  Ownership rules in action: these functions *read* any slot but *write*
  only `session.cart` (via `put_slot/2`); everything another feature must
  do in response is emitted as a **typed fact** (a struct from this
  feature's own `Facts` module) and wired in the page manifest.
  """
  use ZeroCoupled.Feature.Intents, slot: :cart

  alias ZeroCoupled.{Cart, Effects}
  alias ZeroCoupled.Features.CartItems.Facts

  # ── Intents (session, args) → {session, effects[, facts]} ───────────

  intent :update_quantity, params: [item_id: :int, delta: :int]

  def update_quantity(session, %{item_id: item_id, delta: delta}) do
    case Cart.update_quantity(session.cart, item_id, delta) do
      {:ok, cart, item} ->
        {put_slot(session, cart),
         [
           Effects.stream_insert(:cart_items, item),
           Effects.persist_quantity(cart.cart_id, item_id, item.quantity)
         ]}

      :error ->
        {session, []}
    end
  end

  intent :remove_item, params: [item_id: :int]

  def remove_item(session, %{item_id: item_id}) do
    case Cart.remove_item(session.cart, item_id) do
      {:ok, cart, removed} ->
        {put_slot(session, cart),
         [
           Effects.stream_delete(:cart_items, removed),
           Effects.push("item-removed", %{id: removed.id})
         ],
         [%Facts.ItemRemoved{item: removed, item_id: item_id}]}

      :error ->
        {session, []}
    end
  end

  intent :save_for_later, params: [item_id: :int]

  def save_for_later(session, %{item_id: item_id}) do
    case Cart.remove_item(session.cart, item_id) do
      {:ok, cart, item} ->
        {put_slot(session, cart),
         [Effects.stream_delete(:cart_items, item), Effects.flash(:info, "Saved for later")],
         [%Facts.ItemSaved{item: item}]}

      :error ->
        {session, []}
    end
  end

  intent :toggle_gift_wrap, params: [item_id: :int]

  def toggle_gift_wrap(session, %{item_id: item_id}) do
    case Cart.toggle_gift_wrap(session.cart, item_id) do
      {:ok, cart, item, _wrapped?} ->
        {put_slot(session, cart), [Effects.stream_insert(:cart_items, item)]}

      :error ->
        {session, []}
    end
  end

  intent :select_shipping, params: [method: :atom]

  def select_shipping(session, %{method: method}) do
    {put_slot(session, Cart.select_shipping(session.cart, method)), []}
  end

  intent :apply_promo, params: [code: :string]

  def apply_promo(session, %{code: code}) do
    case Cart.apply_promo(session.cart, code) do
      {:ok, cart} ->
        {put_slot(session, cart), [Effects.flash(:info, "Promo applied!")],
         [%Facts.PromoApplied{}]}

      {:error, :invalid_code} ->
        {session, [Effects.flash(:error, "Invalid promo code")],
         [%Facts.PromoRejected{message: "Invalid promo code"}]}
    end
  end

  # Irregular intents — dispatched by hand-written page clauses, not
  # `intent` metadata, because they need shell I/O first.

  @doc "PubSub fact from another process: a product's stock changed."
  def set_stock(session, product_id, new_stock) do
    case Cart.set_stock(session.cart, product_id, new_stock) do
      {:ok, cart, item} -> {put_slot(session, cart), [Effects.stream_insert(:cart_items, item)]}
      :none -> {session, []}
    end
  end

  @doc "A wishlisted product was persisted as a cart line (shell I/O); add it."
  def add_wishlisted(session, item, product_id) do
    {:ok, cart, item} = Cart.add_item(session.cart, item)

    {put_slot(session, cart),
     [Effects.stream_insert(:cart_items, item), Effects.flash(:info, "Added to cart")],
     [%Facts.AddedFromWishlist{product_id: product_id}]}
  end

  # ── Reactions (slot, payload) → {slot, effects} ─────────────────────

  @doc "Reaction: an item comes (back) into the cart (undo restore, move-to-cart)."
  def receive_item(%Cart{} = cart, %{item: item}) do
    {:ok, cart, item} = Cart.add_item(cart, item)
    {cart, [Effects.stream_insert(:cart_items, item)]}
  end

  @doc "Reaction: the undo window elapsed — persist the removal for good."
  def confirm_removal(%Cart{} = cart, %{item_id: item_id}) do
    {cart, [Effects.persist_remove(cart.cart_id, item_id)]}
  end
end

defmodule ZeroCoupled.Features.CartItems.Components do
  @moduledoc "Markup owned by the cart-items feature (a cart row and its stock badge)."
  use Phoenix.Component

  alias ZeroCoupled.Domain.StockStatus

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :gift_wrapped, :boolean, required: true
  attr :wishlisted, :boolean, required: true

  def cart_item_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto_auto] items-center gap-4 border-b py-4">
      <img class="w-16 h-16 object-contain" src={@item.product.thumbnail} alt={@item.product.name} />
      <div>
        <div class="font-medium"><%= @item.product.name %></div>
        <div class="text-sm text-zinc-500"><%= Money.new(@item.product.amount) %> each</div>
        <.stock_badge stock={@item.product.stock} />
        <div class="flex items-center gap-3 mt-1">
          <label class="flex items-center gap-1.5 text-xs text-zinc-500 cursor-pointer">
            <input
              type="checkbox"
              checked={@gift_wrapped}
              phx-click="toggle_gift_wrap"
              phx-value-item-id={@item.id}
            /> Gift wrap ($2.99)
          </label>
          <button phx-click="save_for_later" phx-value-item-id={@item.id} class="text-xs text-blue-500">
            Save for later
          </button>
          <button phx-click="toggle_wishlist" phx-value-item-id={@item.id} class="text-xs">
            <span class={(@wishlisted && "text-red-500") || "text-zinc-400"}>
              <%= if @wishlisted, do: "♥ Wishlisted", else: "♡ Wishlist" %>
            </span>
          </button>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click="update_quantity"
          phx-value-item-id={@item.id}
          phx-value-delta="-1"
          disabled={@item.quantity <= 1}
          class="w-8 h-8 rounded border text-lg font-bold disabled:opacity-30"
        >-</button>
        <span class="w-8 text-center font-mono"><%= @item.quantity %></span>
        <button
          phx-click="update_quantity"
          phx-value-item-id={@item.id}
          phx-value-delta="1"
          class="w-8 h-8 rounded border text-lg font-bold"
        >+</button>
      </div>
      <div class="text-right w-24">
        <div class="font-semibold"><%= Money.new(@item.product.amount * @item.quantity) %></div>
        <button phx-click="remove_item" phx-value-item-id={@item.id} class="text-xs text-red-500">
          Remove
        </button>
      </div>
    </div>
    """
  end

  attr :stock, :integer, required: true

  def stock_badge(assigns) do
    assigns = assign(assigns, :status, StockStatus.call(assigns.stock))

    ~H"""
    <span
      :if={@status != :in_stock}
      class={[
        "text-xs font-medium px-1.5 py-0.5 rounded",
        @status == :low_stock && "bg-amber-100 text-amber-700",
        @status == :out_of_stock && "bg-red-100 text-red-700"
      ]}
    >
      <%= if @status == :low_stock, do: "Low stock", else: "Out of stock" %>
    </span>
    """
  end
end
