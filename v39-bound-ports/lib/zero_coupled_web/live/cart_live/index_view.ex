defmodule ZeroCoupledWeb.CartLive.IndexView do
  @moduledoc "The cart page's markup: the tabs, the three lists, the summary, shipping, promo, checkout."
  use ZeroCoupledWeb, :html
  import ZeroCoupledWeb.Rows

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <.undo_banner :if={@undo_pending} on_undo="undo_remove" />
      <.tabs
        active={@active_tab}
        counts={[items: @summary.item_count, saved: @saved_count, wishlist: @wishlist_count]}
      />

      <div class={@active_tab != :items && "hidden"}>
        <div id="cart_items" phx-update="stream">
          <.cart_item_row
            :for={{dom_id, row} <- @streams.cart_items}
            id={dom_id}
            row={row}
            wishlisted={row.product_id in @wishlist_ids}
            gift_wrap_label="Gift wrap ($2.99)"
            on_quantity="update_quantity"
            on_remove="remove_item"
            on_gift_wrap="toggle_gift_wrap"
            on_save="save_for_later"
            on_wishlist="toggle_wishlist"
          />
        </div>
        <.empty :if={@summary.empty?} message="Your cart is empty." />
      </div>

      <div class={@active_tab != :saved && "hidden"}>
        <div id="saved_items" phx-update="stream">
          <.saved_row
            :for={{dom_id, row} <- @streams.saved_items}
            id={dom_id}
            row={row}
            on_move="move_to_cart"
          />
        </div>
        <.empty :if={@saved_count == 0} message="No saved items." />
      </div>

      <div class={@active_tab != :wishlist && "hidden"}>
        <div id="wishlist_products" phx-update="stream">
          <.wishlist_row
            :for={{dom_id, row} <- @streams.wishlist_products}
            id={dom_id}
            row={row}
            on_add="add_wishlisted_to_cart"
            on_remove="remove_wishlist"
          />
        </div>
        <.empty :if={@wishlist_count == 0} message="Your wishlist is empty." />
      </div>

      <.summary summary={@summary} />
      <.shipping_selector summary={@summary} />
      <.promo_form code={@summary.promo_code} error={@promo_error} />
      <.checkout_bar summary={@summary} />
    </div>
    """
  end

  defp tabs(assigns) do
    ~H"""
    <nav class="flex gap-2 border-b mb-6 pb-2">
      <button
        :for={{tab, label} <- [items: "Items", saved: "Saved", wishlist: "Wishlist"]}
        phx-click="switch_tab"
        phx-value-tab={tab}
        class={[
          "px-4 py-2 text-sm font-medium rounded-t",
          (@active == tab && "bg-zinc-900 text-white") || "text-zinc-500 hover:text-zinc-700"
        ]}
      >
        {label} ({@counts[tab]})
      </button>
    </nav>
    """
  end

  defp summary(assigns) do
    ~H"""
    <div class="space-y-2 py-6 border-t mt-6">
      <div class="flex justify-between text-zinc-600">
        <span>Items</span><span>{@summary.item_count}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Subtotal</span><span>{@summary.subtotal}</span>
      </div>
      <div :if={@summary.promo_code} class="flex justify-between text-green-600">
        <span>Discount ({@summary.promo_code})</span><span>-{@summary.discount}</span>
      </div>
      <div :if={Money.positive?(@summary.gift_wrap_total)} class="flex justify-between text-zinc-600">
        <span>Gift wrap</span><span>{@summary.gift_wrap_total}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Shipping ({@summary.shipping_label})</span>
        <span>
          {if Money.zero?(@summary.shipping_cost), do: "Free", else: @summary.shipping_cost}
        </span>
      </div>
      <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
        <span>Total</span><span>{@summary.total}</span>
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
          :for={opt <- @summary.shipping_options}
          class="flex items-center gap-2 p-2 border rounded cursor-pointer text-sm"
        >
          <input
            type="radio"
            name="shipping_method"
            value={opt.method}
            checked={@summary.shipping_method == opt.method}
            phx-click="select_shipping"
            phx-value-method={opt.method}
          />
          {opt.label}
          <span class="text-zinc-400">{opt.price_label}</span>
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
        value={@code || ""}
        class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
      />
      <button type="submit" class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium">Apply</button>
      <span :if={@error} class="text-red-500 text-sm self-center">{@error}</span>
    </form>
    """
  end

  defp checkout_bar(assigns) do
    ~H"""
    <div class="py-4">
      <button
        phx-click="start_checkout"
        disabled={@summary.empty?}
        class={[
          "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
          @summary.empty? && "opacity-50 cursor-not-allowed"
        ]}
      >
        Checkout · {@summary.total}
      </button>
    </div>
    """
  end

  defp empty(assigns) do
    ~H"""
    <div class="py-12 text-center text-zinc-400">{@message}</div>
    """
  end
end
