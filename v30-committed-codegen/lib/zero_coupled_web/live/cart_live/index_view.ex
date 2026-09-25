defmodule ZeroCoupledWeb.CartLive.IndexView do
  @moduledoc """
  ActionView for `live_action: :index` — the cart page.

  In V29 this module holds only **cross-feature composites** (tabs,
  summary, shipping selector, promo form, checkout bar) — the rendering
  equivalent of the manifest's wiring. Single-feature markup lives with
  its feature (`CartItems.Components.cart_item_row/1`,
  `Undo.Components.undo_banner/0`, …) and is composed here.

  It reads **per-slot assigns** (`@cart_slot`, `@undo_slot`, …) plus
  `@cart` (the `render_data/1` presentation port). It deliberately never
  reads `@session`: untouched slots are equality-no-op assigns, so
  LiveView's change tracking skips the template regions and
  function-component call sites of features an event didn't touch.
  """
  use ZeroCoupledWeb, :html

  alias ZeroCoupled.Cart
  alias ZeroCoupled.Features.{CartItems, Undo, SavedItems, Wishlist}
  alias ZeroCoupled.Domain.{ShippingInfo, CalculateShipping}

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <Undo.Components.undo_banner :if={Undo.pending?(@undo_slot)} />
      <.tabs ui={@ui_slot} cart={@cart} saved={@saved_slot} wishlist={@wishlist_slot} />

      <div class={@ui_slot.active_tab != :items && "hidden"}>
        <div id="cart_items" phx-update="stream" phx-hook="RemoveFade">
          <CartItems.Components.cart_item_row
            :for={{dom_id, item} <- @streams.cart_items}
            id={dom_id}
            item={item}
            gift_wrapped={Cart.gift_wrapped?(@cart_slot, item.id)}
            wishlisted={Wishlist.member?(@wishlist_slot, item.product.id)}
          />
        </div>
        <.empty :if={@cart.empty?} message="Your cart is empty." />
      </div>

      <div class={@ui_slot.active_tab != :saved && "hidden"}>
        <div id="saved_items" phx-update="stream">
          <SavedItems.Components.saved_row
            :for={{dom_id, item} <- @streams.saved_items}
            id={dom_id}
            item={item}
          />
        </div>
        <.empty :if={SavedItems.count(@saved_slot) == 0} message="No saved items." />
      </div>

      <div class={@ui_slot.active_tab != :wishlist && "hidden"}>
        <div id="wishlist_products" phx-update="stream">
          <Wishlist.Components.wishlist_row
            :for={{dom_id, product} <- @streams.wishlist_products}
            id={dom_id}
            product={product}
          />
        </div>
        <.empty :if={Wishlist.count(@wishlist_slot) == 0} message="Your wishlist is empty." />
      </div>

      <.summary cart={@cart} />
      <.shipping_selector cart={@cart} />
      <.promo_form cart={@cart} ui={@ui_slot} />
      <.checkout_bar cart={@cart} />
    </div>
    """
  end

  # ── Cross-feature composites ─────────────────────────────────────────

  defp tabs(assigns) do
    ~H"""
    <nav class="flex gap-2 border-b mb-6 pb-2">
      <button
        :for={{tab, label, count} <- [
          {:items, "Items", @cart.item_count},
          {:saved, "Saved", SavedItems.count(@saved)},
          {:wishlist, "Wishlist", Wishlist.count(@wishlist)}
        ]}
        phx-click="switch_tab"
        phx-value-tab={tab}
        class={[
          "px-4 py-2 text-sm font-medium rounded-t",
          @ui.active_tab == tab && "bg-zinc-900 text-white",
          @ui.active_tab != tab && "text-zinc-500 hover:text-zinc-700"
        ]}
      >
        <%= label %> (<%= count %>)
      </button>
    </nav>
    """
  end

  defp summary(assigns) do
    ~H"""
    <div class="space-y-2 py-6 border-t mt-6">
      <div class="flex justify-between text-zinc-600"><span>Items</span><span><%= @cart.item_count %></span></div>
      <div class="flex justify-between text-zinc-600"><span>Subtotal</span><span><%= @cart.subtotal %></span></div>
      <div :if={@cart.promo_code} class="flex justify-between text-green-600">
        <span>Discount (<%= @cart.promo_code %>)</span><span>-<%= @cart.discount %></span>
      </div>
      <div :if={Money.positive?(@cart.gift_wrap_total)} class="flex justify-between text-zinc-600">
        <span>Gift wrap</span><span><%= @cart.gift_wrap_total %></span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Shipping (<%= @cart.shipping_label %>)</span>
        <span><%= if Money.zero?(@cart.shipping_cost), do: "Free", else: @cart.shipping_cost %></span>
      </div>
      <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
        <span>Total</span><span><%= @cart.total %></span>
      </div>
    </div>
    """
  end

  defp shipping_selector(assigns) do
    ~H"""
    <div class="py-2">
      <h3 class="text-sm font-semibold text-zinc-700 mb-2">Shipping</h3>
      <div class="flex gap-2">
        <label
          :for={method <- ShippingInfo.method_names()}
          class="flex items-center gap-2 p-2 border rounded cursor-pointer text-sm"
        >
          <input
            type="radio"
            name="shipping_method"
            value={method}
            checked={@cart.shipping_method == method}
            phx-click="select_shipping"
            phx-value-method={method}
          />
          <%= ShippingInfo.label(method) %>
          <span class="text-zinc-400"><%= price_label(method, @cart.subtotal) %></span>
        </label>
      </div>
    </div>
    """
  end

  defp promo_form(assigns) do
    ~H"""
    <form phx-submit="apply_promo" class="flex gap-2 py-4">
      <input
        type="text"
        name="code"
        placeholder="Promo code"
        value={@cart.promo_code || ""}
        class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
      />
      <button type="submit" class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium">Apply</button>
      <span :if={@ui.promo_error} class="text-red-500 text-sm self-center"><%= @ui.promo_error %></span>
    </form>
    """
  end

  defp checkout_bar(assigns) do
    ~H"""
    <div class="py-4">
      <button
        phx-click="start_checkout"
        disabled={@cart.empty?}
        class={[
          "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
          @cart.empty? && "opacity-50 cursor-not-allowed"
        ]}
      >
        Checkout · <%= @cart.total %>
      </button>
    </div>
    """
  end

  defp empty(assigns) do
    ~H"""
    <div class="py-12 text-center text-zinc-400"><%= @message %></div>
    """
  end

  defp price_label(method, subtotal) do
    case CalculateShipping.call(method, subtotal.amount) do
      0 -> "Free"
      cents -> Money.new(cents)
    end
  end
end
