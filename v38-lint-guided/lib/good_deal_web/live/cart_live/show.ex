defmodule GoodDealWeb.CartLive.Show do
  @moduledoc """
  V9 — Disciplined Monolith.

  ALL logic lives in the LiveView. No external Page module. State is
  organized into three typed struct assigns (`@cart`, `@ui`, `@ckout`).
  Pure helper functions live in `Helpers`. Side-effects are raw tuples
  applied via `apply_effects/2`.
  """

  use GoodDealWeb, :live_view

  alias GoodDealWeb.CartLive.{CartState, UIState, CheckoutState, Helpers}
  alias GoodDealWeb.{CartSession, CheckoutMetadata}
  alias GoodDeal.Foundation.{Carts, Orders, Products, Broadcast}
  alias GoodDeal.Domain.{Pricing, Checkout, Inventory}

  # ── Lifecycle ──────────────────────────────────────────────────────────

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session)
    items = Carts.list_items(cart_id)
    cart = CartState.new(cart_id, items, store_calibration())

    if connected?(socket), do: Broadcast.subscribe()

    {:ok,
     socket
     |> assign(:cart, cart)
     |> assign(:ui, %UIState{})
     |> assign(:ckout, %CheckoutState{})
     |> assign(:low_stock, GoodDeal.Catalog.low_stock_threshold())
     |> stream(:cart_items, items)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ── Events ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("update_quantity", %{"item-id" => id, "delta" => delta}, socket) do
    item_id = String.to_integer(id)
    d = String.to_integer(delta)
    cart = socket.assigns.cart

    items = Helpers.update_item_quantity(cart.items, item_id, d)
    updated_item = Enum.find(items, &(&1.id == item_id))
    cart = CartState.recompute(%{cart | items: items})

    effects = [
      {:persist_quantity, cart.cart_id, item_id, updated_item.quantity},
      {:stream_insert, :cart_items, updated_item}
    ]

    {:noreply, socket |> assign(:cart, cart) |> apply_effects(effects)}
  end

  def handle_event("remove_item", %{"item-id" => id}, socket) do
    item_id = String.to_integer(id)
    cart = socket.assigns.cart

    {removed, remaining} = Helpers.pop_item(cart.items, item_id)
    cart = CartState.recompute(%{cart | items: remaining})

    effects =
      if removed do
        [
          {:persist_remove, cart.cart_id, item_id},
          {:stream_delete, :cart_items, removed},
          {:push_event, "item_removed", %{id: item_id}},
          {:flash, :info, "Item removed"}
        ]
      else
        []
      end

    {:noreply, socket |> assign(:cart, cart) |> apply_effects(effects)}
  end

  def handle_event("checkout", _params, socket) do
    cart = socket.assigns.cart
    stock = Products.stock_levels(Enum.map(cart.items, & &1.product.id))

    case Checkout.validate(cart.items) do
      {:ok, items} ->
        case Inventory.check_availability(items, stock) do
          :ok ->
            line_items = Checkout.prepare_line_items(items)
            metadata = CheckoutMetadata.for_cart(cart.cart_id)
            ckout = %{socket.assigns.ckout | status: :processing}

            effects = [
              {:start_checkout, line_items, metadata},
              {:flash, :info, "Processing payment..."}
            ]

            {:noreply, socket |> assign(:ckout, ckout) |> apply_effects(effects)}

          {:error, _} ->
            {:noreply, apply_effects(socket, [{:flash, :error, "Some items are out of stock"}])}
        end

      {:error, :empty_cart} ->
        {:noreply, apply_effects(socket, [{:flash, :error, "Your cart is empty"}])}
    end
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    ui = %{socket.assigns.ui | active_tab: String.to_existing_atom(tab)}
    {:noreply, assign(socket, :ui, ui)}
  end

  def handle_event("select_shipping", %{"method" => method}, socket) do
    cart = CartState.recompute(%{socket.assigns.cart | shipping_method: String.to_existing_atom(method)})
    {:noreply, assign(socket, :cart, cart)}
  end

  def handle_event("toggle_gift_wrap", _params, socket) do
    cart = socket.assigns.cart
    cart = CartState.recompute(%{cart | gift_wrap?: not cart.gift_wrap?})
    {:noreply, assign(socket, :cart, cart)}
  end

  def handle_event("apply_promo", %{"code" => code}, socket) do
    case Pricing.validate_promo(code, GoodDeal.Catalog.promo_codes()) do
      {:ok, pct} ->
        cart =
          CartState.recompute(%{
            socket.assigns.cart
            | promo_code: code,
              promo_percentage: pct
          })

        ui = %{socket.assigns.ui | promo_error: nil}

        effects = [{:flash, :info, "Promo code applied!"}]

        {:noreply, socket |> assign(:cart, cart) |> assign(:ui, ui) |> apply_effects(effects)}

      {:error, :invalid_code} ->
        ui = %{socket.assigns.ui | promo_error: "Invalid promo code"}

        effects = [{:flash, :error, "Invalid promo code"}]

        {:noreply, socket |> assign(:ui, ui) |> apply_effects(effects)}
    end
  end

  # ── Async ──────────────────────────────────────────────────────────────

  @impl true
  def handle_async(:checkout, {:ok, {:ok, _reference}}, socket) do
    finalize_order(socket.assigns.cart.cart_id)
    ckout = %{socket.assigns.ckout | status: :complete}
    {:noreply, socket |> assign(:ckout, ckout) |> apply_effects([{:navigate, ~p"/cart/success"}])}
  end

  def handle_async(:checkout, {:ok, {:error, _}}, socket) do
    ckout = %{socket.assigns.ckout | status: :error}

    {:noreply,
     socket
     |> assign(:ckout, ckout)
     |> apply_effects([{:flash, :error, "Checkout failed. Please try again."}])}
  end

  def handle_async(:checkout, {:exit, _}, socket) do
    ckout = %{socket.assigns.ckout | status: :error}

    {:noreply,
     socket
     |> assign(:ckout, ckout)
     |> apply_effects([{:flash, :error, "Checkout failed. Please try again."}])}
  end

  # ── PubSub ─────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:stock_changed, {product_id, new_stock}}, socket) do
    cart = socket.assigns.cart
    items = Helpers.update_product_stock(cart.items, product_id, new_stock)
    updated = Enum.find(items, &(&1.product.id == product_id))
    cart = %{cart | items: items}

    effects = if updated, do: [{:stream_insert, :cart_items, updated}], else: []

    {:noreply, socket |> assign(:cart, cart) |> apply_effects(effects)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Effects ────────────────────────────────────────────────────────────

  defp apply_effects(socket, effects) do
    Enum.reduce(effects, socket, &apply_effect(&2, &1))
  end

  defp apply_effect(socket, {:flash, level, msg}), do: put_flash(socket, level, msg)
  defp apply_effect(socket, {:navigate, path}), do: push_navigate(socket, to: path)
  defp apply_effect(socket, {:stream_insert, col, item}), do: stream_insert(socket, col, item)
  defp apply_effect(socket, {:stream_delete, col, item}), do: stream_delete(socket, col, item)

  defp apply_effect(socket, {:push_event, event, payload}) do
    push_event(socket, event, payload)
  end

  defp apply_effect(socket, {:persist_quantity, cart_id, item_id, qty}) do
    Carts.update_quantity(cart_id, item_id, qty)
    socket
  end

  defp apply_effect(socket, {:persist_remove, cart_id, item_id}) do
    Carts.remove_item(cart_id, item_id)
    socket
  end

  defp apply_effect(socket, {:start_checkout, line_items, metadata}) do
    amount_cents = Enum.reduce(line_items, 0, fn li, acc -> acc + li.unit_amount * li.quantity end)
    currency = hd(line_items).currency

    start_async(socket, :checkout, fn ->
      payment_gateway().charge(amount_cents, currency, metadata)
    end)
  end

  defp payment_gateway do
    Application.get_env(:good_deal, :payment_gateway, GoodDeal.Foundation.LedgerGateway)
  end

  # Record the order and draw down stock once payment has settled — the work the
  # app used to do on a provider callback, now that checkout settles inline.
  defp finalize_order(cart_id) do
    Orders.create(cart_id)

    cart_id
    |> Carts.list_items()
    |> Enum.each(fn item ->
      case Products.decrement_stock(item.product.id, item.quantity) do
        {:ok, product} -> Broadcast.notify(:stock_changed, {item.product.id, product.stock})
        {:error, _} -> :ok
      end
    end)
  end

  # The composition reads the store's calibration and threads it down into the
  # cart state; the domain and feature layers never reach up to it.
  defp store_calibration do
    %{shipping_methods: GoodDeal.Catalog.shipping_methods(), gift_wrap_cents: GoodDeal.Catalog.gift_wrap_cents()}
  end

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <nav class="flex gap-2 border-b mb-6 pb-2">
        <button
          :for={tab <- [:items, :summary]}
          phx-click="switch_tab"
          phx-value-tab={tab}
          class={[
            "px-4 py-2 text-sm font-medium rounded-t",
            if(@ui.active_tab == tab,
              do: "bg-zinc-900 text-white",
              else: "text-zinc-500 hover:text-zinc-700"
            )
          ]}
        >
          <%= Phoenix.Naming.humanize(tab) %>
        </button>
      </nav>

      <div class={[@ui.active_tab != :items && "hidden"]}>
        <div id="cart_items" phx-update="stream">
          <.cart_item_row
            :for={{dom_id, cart_item} <- @streams.cart_items}
            id={dom_id}
            cart_item={cart_item}
            stock_status={Inventory.stock_status(cart_item.product.stock, @low_stock)}
          />
        </div>
        <.empty_cart_message :if={@cart.items == []} />
      </div>

      <div :if={@ui.active_tab == :summary}>
        <.shipping_selector methods={@cart.shipping_methods} selected={@cart.shipping_method} />
        <.gift_wrap_toggle on={@cart.gift_wrap?} />
        <.cart_summary
          subtotal={@cart.subtotal}
          discount={@cart.discount}
          shipping={@cart.shipping}
          gift_wrap={@cart.gift_wrap}
          total={@cart.total}
          item_count={@cart.item_count}
          promo_code={@cart.promo_code}
          shipping_method={@cart.shipping_method}
          gift_wrap?={@cart.gift_wrap?}
        />
      </div>

      <.promo_form error={@ui.promo_error} current_code={@cart.promo_code} />
      <.checkout_section status={@ckout.status} empty={@cart.items == []} />
    </div>
    """
  end

  # ── Function Components ────────────────────────────────────────────────

  defp cart_item_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto_auto] items-center gap-4 border-b py-4">
      <img
        class="w-16 h-16 object-contain"
        src={@cart_item.product.thumbnail}
        alt={@cart_item.product.name}
      />
      <div>
        <div class="font-medium"><%= @cart_item.product.name %></div>
        <div class="text-sm text-zinc-500"><%= Money.new(@cart_item.product.amount) %> each</div>
        <.stock_badge status={@stock_status} />
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click="update_quantity"
          phx-value-item-id={@cart_item.id}
          phx-value-delta="-1"
          disabled={@cart_item.quantity <= 1}
          class="w-8 h-8 rounded border text-lg font-bold disabled:opacity-30 hover:bg-zinc-100"
        >
          -
        </button>
        <span class="w-8 text-center font-mono"><%= @cart_item.quantity %></span>
        <button
          phx-click="update_quantity"
          phx-value-item-id={@cart_item.id}
          phx-value-delta="1"
          class="w-8 h-8 rounded border text-lg font-bold hover:bg-zinc-100"
        >
          +
        </button>
      </div>
      <div class="text-right w-24">
        <div class="font-semibold">
          <%= Money.new(@cart_item.product.amount * @cart_item.quantity) %>
        </div>
        <button
          phx-click="remove_item"
          phx-value-item-id={@cart_item.id}
          class="text-xs text-red-500 hover:text-red-700"
        >
          Remove
        </button>
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
      <%= if @status == :low_stock, do: "Low stock", else: "Out of stock" %>
    </span>
    """
  end

  defp empty_cart_message(assigns) do
    ~H"""
    <div class="py-12 text-center text-zinc-400">
      Your cart is empty.
      <.link navigate={~p"/products"} class="text-blue-500 hover:underline">Browse products</.link>
    </div>
    """
  end

  defp cart_summary(assigns) do
    ~H"""
    <div class="space-y-3 py-6">
      <div class="flex justify-between text-zinc-600">
        <span>Items</span><span><%= @item_count %></span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Subtotal</span><span><%= @subtotal %></span>
      </div>
      <div :if={@promo_code} class="flex justify-between text-green-600">
        <span>Discount (<%= @promo_code %>)</span><span>-<%= @discount %></span>
      </div>
      <div :if={@shipping_method} class="flex justify-between text-zinc-600">
        <span>Shipping</span><span><%= @shipping %></span>
      </div>
      <div :if={@gift_wrap?} class="flex justify-between text-zinc-600">
        <span>Gift wrap</span><span><%= @gift_wrap %></span>
      </div>
      <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
        <span>Total</span><span><%= @total %></span>
      </div>
    </div>
    """
  end

  defp shipping_selector(assigns) do
    ~H"""
    <fieldset class="py-4 border-t">
      <legend class="text-sm font-medium text-zinc-700 pb-2">Shipping</legend>
      <label :for={opt <- @methods} class="flex items-center gap-2 py-1 text-sm">
        <input
          type="radio"
          name="shipping_method"
          value={opt.method}
          checked={@selected == opt.method}
          phx-click="select_shipping"
          phx-value-method={opt.method}
        />
        <span><%= opt.label %></span>
        <span class="text-zinc-500">
          <%= if opt.free_above, do: "#{Money.new(opt.cost)} (free over #{Money.new(opt.free_above)})", else: Money.new(opt.cost) %>
        </span>
      </label>
    </fieldset>
    """
  end

  defp gift_wrap_toggle(assigns) do
    ~H"""
    <label class="flex items-center gap-2 py-3 border-t text-sm">
      <input type="checkbox" checked={@on} phx-click="toggle_gift_wrap" />
      <span>Add gift wrapping</span>
    </label>
    """
  end

  defp promo_form(assigns) do
    ~H"""
    <form phx-submit="apply_promo" class="flex gap-2 py-4">
      <input
        type="text"
        name="code"
        placeholder="Promo code"
        value={@current_code || ""}
        class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
      />
      <button
        type="submit"
        class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium hover:bg-zinc-300"
      >
        Apply
      </button>
      <span :if={@error} class="text-red-500 text-sm self-center"><%= @error %></span>
    </form>
    """
  end

  defp checkout_section(assigns) do
    ~H"""
    <div class="py-4">
      <button
        :if={@status == :idle}
        phx-click="checkout"
        disabled={@empty}
        class={[
          "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700",
          "py-2 px-3 text-sm font-semibold leading-6 text-white active:text-white/80",
          @empty && "opacity-50 cursor-not-allowed"
        ]}
      >
        Checkout
      </button>
      <div :if={@status == :processing} class="flex items-center gap-3 text-zinc-500 py-2">
        <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
          <circle
            class="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="4"
          />
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
        Processing payment...
      </div>
      <div :if={@status == :error} class="space-y-2">
        <p class="text-red-600 text-sm">Checkout failed.</p>
        <button
          phx-click="checkout"
          class="rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white"
        >
          Try again
        </button>
      </div>
    </div>
    """
  end
end
