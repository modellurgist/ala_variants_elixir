defmodule ZeroCoupledWeb.CartLive.IndexView do
  @moduledoc """
  ActionView for `live_action: :index` — the cart page.

  Holds only **cross-feature composites** (tabs, summary, shipping
  selector, promo form, checkout bar); single-feature markup lives with
  its feature (`CartItems.Components.cart_item_row/1`, …) and is composed
  here.

  V32: this module reads **ports only** — per-slot render_data assigns
  (`@cart`, `@undo`, `@saved`, `@wishlist`), the `@ui_slot` struct, and
  projected stream rows. No domain or feature module is referenced
  (`*.Components` are presentation peers, carved out), no event/hook/id
  literal is restated (`Web.Contracts` is the single source) — both
  enforced by `ComponentPurity`/`ContractPurity`.
  """
  use ZeroCoupledWeb, :html

  alias ZeroCoupled.Features.CartItems.Components, as: CartRows
  alias ZeroCoupled.Features.SavedItems.Components, as: SavedRows
  alias ZeroCoupled.Features.Undo.Components, as: UndoUI
  alias ZeroCoupled.Features.Wishlist.Components, as: WishlistRows
  alias ZeroCoupled.Web.Contracts

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <UndoUI.undo_banner :if={@undo.pending?} />
      <.tabs ui={@ui_slot} cart={@cart} saved={@saved} wishlist={@wishlist} />

      <div class={@ui_slot.active_tab != :items && "hidden"}>
        <div id={Contracts.stream_dom_id(:cart)} phx-update="stream" phx-hook={Contracts.hook(:remove_fade)}>
          <CartRows.cart_item_row
            :for={{dom_id, row} <- @streams.cart_items}
            id={dom_id}
            row={row}
            wishlisted={row.product_id in @wishlist.product_ids}
          />
        </div>
        <.empty :if={@cart.empty?} message="Your cart is empty." />
      </div>

      <div class={@ui_slot.active_tab != :saved && "hidden"}>
        <div id={Contracts.stream_dom_id(:saved)} phx-update="stream">
          <SavedRows.saved_row :for={{dom_id, row} <- @streams.saved_items} id={dom_id} row={row} />
        </div>
        <.empty :if={@saved.count == 0} message="No saved items." />
      </div>

      <div class={@ui_slot.active_tab != :wishlist && "hidden"}>
        <div id={Contracts.stream_dom_id(:wishlist)} phx-update="stream">
          <WishlistRows.wishlist_row :for={{dom_id, row} <- @streams.wishlist_products} id={dom_id} row={row} />
        </div>
        <.empty :if={@wishlist.count == 0} message="Your wishlist is empty." />
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
          {:saved, "Saved", @saved.count},
          {:wishlist, "Wishlist", @wishlist.count}
        ]}
        phx-click={Contracts.event(:switch_tab)}
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
          :for={opt <- @cart.shipping_options}
          class="flex items-center gap-2 p-2 border rounded cursor-pointer text-sm"
        >
          <input
            type="radio"
            name="shipping_method"
            value={opt.method}
            checked={@cart.shipping_method == opt.method}
            phx-click={Contracts.event(:select_shipping)}
            phx-value-method={opt.method}
          />
          <%= opt.label %>
          <span class="text-zinc-400"><%= opt.price_label %></span>
        </label>
      </div>
    </div>
    """
  end

  defp promo_form(assigns) do
    ~H"""
    <form phx-submit={Contracts.event(:apply_promo)} class="flex gap-2 py-4">
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
        phx-click={Contracts.event(:start_checkout)}
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
end
