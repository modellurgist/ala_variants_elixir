defmodule ZeroCoupledWeb.CartLive.CartPanel do
  @moduledoc "The items tab: owns its stream and the events its rows fire; each click is a push into an input the page's circuit wires."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupledWeb.Rows
  alias ZeroCoupledWeb.Paradigms.Emitter

  def mount(socket), do: {:ok, stream(socket, :cart_items, [])}

  def update(%{change: {:reset, rows}}, socket),
    do: {:ok, stream(socket, :cart_items, rows, reset: true)}

  def update(%{change: {:removed, row}}, socket),
    do: {:ok, stream_delete(socket, :cart_items, row)}

  def update(%{change: {_, row}}, socket), do: {:ok, stream_insert(socket, :cart_items, row)}
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def handle_event("update_quantity", %{"item-id" => id, "delta" => d}, socket),
    do:
      {:noreply,
       Emitter.feed(socket, :cart, {:update_quantity, %{item_id: int(id), delta: int(d)}})}

  def handle_event("remove_item", %{"item-id" => id}, socket),
    do: {:noreply, Emitter.feed(socket, :cart, {:remove, %{item_id: int(id)}})}

  def handle_event("save_for_later", %{"item-id" => id}, socket),
    do: {:noreply, Emitter.feed(socket, :cart, {:save_for_later, %{item_id: int(id)}})}

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, socket),
    do: {:noreply, Emitter.feed(socket, :cart, {:toggle_gift_wrap, %{item_id: int(id)}})}

  def handle_event("toggle_wishlist", %{"item-id" => id}, socket),
    do: {:noreply, Emitter.feed(socket, :cart, {:line, %{item_id: int(id)}})}

  defp int(s), do: String.to_integer(s)

  def render(assigns) do
    ~H"""
    <div>
      <div id="cart_items" phx-update="stream">
        <.cart_item_row
          :for={{dom_id, row} <- @streams.cart_items}
          id={dom_id}
          row={row}
          target={@myself}
          wishlisted={row.product_id in @wishlist_ids}
          gift_wrap_label={@gift_wrap_label}
          on_quantity="update_quantity"
          on_remove="remove_item"
          on_gift_wrap="toggle_gift_wrap"
          on_save="save_for_later"
          on_wishlist="toggle_wishlist"
        />
      </div>
      <div :if={@empty?} class="py-12 text-center text-zinc-400">Your cart is empty.</div>
    </div>
    """
  end
end

defmodule ZeroCoupledWeb.CartLive.SavedPanel do
  @moduledoc "The saved-for-later tab."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupledWeb.Rows
  alias ZeroCoupledWeb.Paradigms.Emitter

  def mount(socket), do: {:ok, stream(socket, :saved_items, [])}

  def update(%{change: {:removed, row}}, socket),
    do: {:ok, stream_delete(socket, :saved_items, row)}

  def update(%{change: {_, row}}, socket), do: {:ok, stream_insert(socket, :saved_items, row)}
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def handle_event("move_to_cart", %{"item-id" => id}, socket),
    do:
      {:noreply, Emitter.feed(socket, :saved, {:move_to_cart, %{item_id: String.to_integer(id)}})}

  def render(assigns) do
    ~H"""
    <div>
      <div id="saved_items" phx-update="stream">
        <.saved_row
          :for={{dom_id, row} <- @streams.saved_items}
          id={dom_id}
          row={row}
          target={@myself}
          on_move="move_to_cart"
        />
      </div>
      <div :if={@count == 0} class="py-12 text-center text-zinc-400">No saved items.</div>
    </div>
    """
  end
end

defmodule ZeroCoupledWeb.CartLive.WishlistPanel do
  @moduledoc "The wishlist tab."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupledWeb.Rows
  alias ZeroCoupledWeb.Paradigms.Emitter

  def mount(socket), do: {:ok, stream(socket, :wishlist_products, [])}

  def update(%{change: {:removed, row}}, socket),
    do: {:ok, stream_delete(socket, :wishlist_products, row)}

  def update(%{change: {_, row}}, socket),
    do: {:ok, stream_insert(socket, :wishlist_products, row)}

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def handle_event("remove_wishlist", %{"product-id" => id}, socket),
    do:
      {:noreply, Emitter.feed(socket, :wishlist, {:remove, %{product_id: String.to_integer(id)}})}

  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, socket),
    do: {:noreply, Emitter.feed(socket, :wishlist, {:take, %{product_id: String.to_integer(id)}})}

  def render(assigns) do
    ~H"""
    <div>
      <div id="wishlist_products" phx-update="stream">
        <.wishlist_row
          :for={{dom_id, row} <- @streams.wishlist_products}
          id={dom_id}
          row={row}
          target={@myself}
          on_add="add_wishlisted_to_cart"
          on_remove="remove_wishlist"
        />
      </div>
      <div :if={@count == 0} class="py-12 text-center text-zinc-400">Your wishlist is empty.</div>
    </div>
    """
  end
end

defmodule ZeroCoupledWeb.CartLive.CartControls do
  @moduledoc "The cart's chrome: undo banner, tabs, summary, shipping, promo, and the checkout button, owning their events."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupledWeb.Rows, only: [undo_banner: 1]
  alias ZeroCoupledWeb.Paradigms.Emitter

  def handle_event("undo_remove", _, socket),
    do: {:noreply, Emitter.feed(socket, :undo, {:restore, nil})}

  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do: {:noreply, Emitter.feed(socket, :ui, {:switch_tab, %{tab: String.to_existing_atom(tab)}})}

  def handle_event("select_shipping", %{"method" => m}, socket),
    do:
      {:noreply,
       Emitter.feed(socket, :cart, {:select_shipping, %{method: String.to_existing_atom(m)}})}

  def handle_event("apply_promo", %{"code" => code}, socket),
    do: {:noreply, Emitter.feed(socket, :cart, {:apply_promo, %{code: code}})}

  def handle_event("start_checkout", _, socket),
    do: {:noreply, Emitter.feed(socket, :checkout, {:start, socket.assigns.summary})}

  attr :summary, :map, required: true
  attr :active_tab, :atom, required: true
  attr :counts, :list, required: true
  attr :promo_error, :string, default: nil
  attr :undo_pending, :boolean, default: false
  slot :inner_block, required: true

  def render(%{part: :top} = assigns) do
    ~H"""
    <div>
      <.undo_banner :if={@undo_pending} on_undo="undo_remove" target={@myself} />
      <nav class="flex gap-2 border-b mb-6 pb-2">
        <button
          :for={{tab, label} <- [items: "Items", saved: "Saved", wishlist: "Wishlist"]}
          phx-click="switch_tab"
          phx-value-tab={tab}
          phx-target={@myself}
          class={[
            "px-4 py-2 text-sm font-medium rounded-t",
            (@active_tab == tab && "bg-zinc-900 text-white") || "text-zinc-500 hover:text-zinc-700"
          ]}
        >
          {label} ({@counts[tab]})
        </button>
      </nav>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
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
        <div
          :if={Money.positive?(@summary.gift_wrap_total)}
          class="flex justify-between text-zinc-600"
        >
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
              phx-target={@myself}
            />
            {opt.label} <span class="text-zinc-400">{opt.price_label}</span>
          </label>
        </div>
      </div>
      <form phx-submit="apply_promo" phx-target={@myself} class="flex gap-2 py-4">
        <input
          type="text"
          name="code"
          placeholder="Promo code"
          value={@summary.promo_code || ""}
          class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
        />
        <button type="submit" class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium">
          Apply
        </button>
        <span :if={@promo_error} class="text-red-500 text-sm self-center">{@promo_error}</span>
      </form>
      <div class="py-4">
        <button
          phx-click="start_checkout"
          phx-target={@myself}
          disabled={@summary.empty?}
          class={[
            "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
            @summary.empty? && "opacity-50 cursor-not-allowed"
          ]}
        >
          Checkout · {@summary.total}
        </button>
      </div>
    </div>
    """
  end
end

defmodule ZeroCoupledWeb.CartLive.CheckoutForm do
  @moduledoc "The checkout's screens, owning the address form and the payment buttons."
  use ZeroCoupledWeb, :live_component
  alias ZeroCoupledWeb.Paradigms.Emitter

  def handle_event("validate_address", %{"address" => p}, socket),
    do: {:noreply, Emitter.feed(socket, :checkout, {:validate, p})}

  def handle_event("submit_address", %{"address" => p}, socket),
    do: {:noreply, Emitter.feed(socket, :checkout, {:submit_address, p})}

  def handle_event("edit_address", _, socket),
    do: {:noreply, Emitter.feed(socket, :checkout, {:edit_address, nil})}

  def handle_event("pay", _, socket),
    do: {:noreply, Emitter.feed(socket, :cart, {:request_checkout, nil})}

  def render(%{step: :address} = assigns) do
    ~H"""
    <div>
      <.simple_form
        for={@address_form}
        phx-change="validate_address"
        phx-submit="submit_address"
        phx-target={@myself}
      >
        <.input field={@address_form[:name]} label="Full name" phx-hook="AutoFocus" id="address_name" />
        <.input field={@address_form[:line1]} label="Address" />
        <.input field={@address_form[:city]} label="City" />
        <.input field={@address_form[:postal_code]} label="Postal code" />
        <:actions>
          <.button phx-disable-with="Saving…">Continue to payment</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def render(%{step: :payment} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="rounded border p-4 text-sm text-zinc-700">
        <div class="font-medium">{@address.name}</div>
        <div>{@address.line1}</div>
        <div>{@address.city}, {@address.postal_code}</div>
      </div>
      <div class="flex justify-between font-bold text-xl border-t pt-4">
        <span>Total</span><span>{@total}</span>
      </div>
      <div class="flex gap-3">
        <button phx-click="edit_address" phx-target={@myself} class="text-sm text-zinc-500 underline">
          Edit address
        </button>
        <button
          phx-click="pay"
          phx-target={@myself}
          class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
        >
          Pay {@total}
        </button>
      </div>
    </div>
    """
  end

  def render(%{step: :processing} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 text-zinc-500 py-6">
      <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
      Processing payment…
    </div>
    """
  end

  def render(%{step: :error} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-red-600 text-sm">Payment failed.</p>
      <button
        phx-click="pay"
        phx-target={@myself}
        class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
      >
        Try again
      </button>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <p class="text-zinc-500 py-6">Redirecting…</p>
    """
  end
end
