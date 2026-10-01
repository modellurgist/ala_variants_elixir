defmodule GoodDealWeb.CartLive.Show do
  @moduledoc """
  V9 — Disciplined Monolith, grown to the full storefront requirements.

  ALL logic lives in the LiveView. No external Page module. State is
  organized into three typed struct assigns (`@cart`, `@ui`, `@ckout`).
  Pure helper functions live in `Helpers`. Side-effects are raw tuples
  applied via `apply_effects/2`. The cart page and the checkout steps are
  one LiveView (`live_action` `:index` and `:checkout`).
  """

  use GoodDealWeb, :live_view

  alias GoodDealWeb.CartLive.{CartState, UIState, CheckoutState, Helpers}
  alias GoodDealWeb.{CartSession, CheckoutMetadata}
  alias GoodDeal.Foundation.{Carts, Orders, Products, Broadcast}
  alias GoodDeal.Domain.{Pricing, Checkout, Inventory}
  alias GoodDeal.Domain.Forms.Address

  @undo_window_ms 5_000
  @step_paths %{address: "/cart/checkout", payment: "/cart/checkout/payment"}

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
     |> assign(:address_form, to_form(Address.changeset(%Address{}, %{})))
     |> assign(:low_stock, GoodDeal.Catalog.low_stock_threshold())
     |> stream(:cart_items, Enum.map(items, &Helpers.row(&1, cart, [])))
     |> stream(:saved_items, [])
     |> stream(:wishlist_products, [])}
  end

  # The URL names a checkout step (browser back, a reload). Back from payment to
  # the address is allowed; any other jump is ignored.
  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket) do
    requested = if params["step"] == "payment", do: :payment, else: :address
    ckout = socket.assigns.ckout

    if requested == :address and ckout.step == :payment do
      {:noreply, assign(socket, :ckout, %{ckout | step: :address})}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ── Cart events ────────────────────────────────────────────────────────

  @impl true
  def handle_event("update_quantity", %{"item-id" => id, "delta" => delta}, socket) do
    item_id = String.to_integer(id)
    cart = socket.assigns.cart

    items = Helpers.update_item_quantity(cart.items, item_id, String.to_integer(delta))
    updated = Enum.find(items, &(&1.id == item_id))
    cart = CartState.recompute(%{cart | items: items})

    effects = [
      {:persist_quantity, cart.cart_id, item_id, updated.quantity},
      {:stream_insert, :cart_items, Helpers.row(updated, cart, wishlist_ids(socket))}
    ]

    {:noreply, socket |> assign(:cart, cart) |> apply_effects(effects)}
  end

  def handle_event("remove_item", %{"item-id" => id}, socket) do
    item_id = String.to_integer(id)
    cart = socket.assigns.cart

    case Helpers.pop_item(cart.items, item_id) do
      {nil, _} ->
        {:noreply, socket}

      {removed, remaining} ->
        cart =
          CartState.recompute(%{
            cart
            | items: remaining,
              gift_wrapped: MapSet.delete(cart.gift_wrapped, item_id)
          })

        # only the most recent removal is undoable: an earlier one becomes final now
        previous = socket.assigns.ui.undo
        ref = Process.send_after(self(), {:timer, :undo, removed}, @undo_window_ms)
        ui = %{socket.assigns.ui | undo: %{item: removed, ref: ref}}

        effects =
          if(previous,
            do: [{:cancel_timer, previous.ref}, {:persist_remove, cart.cart_id, previous.item.id}],
            else: []
          ) ++
            [
              {:stream_delete, :cart_items, %{id: item_id}},
              {:push_event, "item_removed", %{id: item_id}}
            ]

        {:noreply, socket |> assign(cart: cart, ui: ui) |> apply_effects(effects)}
    end
  end

  def handle_event("undo_remove", _params, socket) do
    case socket.assigns.ui.undo do
      nil ->
        {:noreply, socket}

      %{item: item, ref: ref} ->
        cart =
          CartState.recompute(%{socket.assigns.cart | items: socket.assigns.cart.items ++ [item]})

        ui = %{socket.assigns.ui | undo: nil}

        effects = [
          {:cancel_timer, ref},
          {:stream_insert, :cart_items, Helpers.row(item, cart, wishlist_ids(socket))},
          {:flash, :info, "Item restored"}
        ]

        {:noreply, socket |> assign(cart: cart, ui: ui) |> apply_effects(effects)}
    end
  end

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, socket) do
    item_id = String.to_integer(id)
    cart = socket.assigns.cart

    case Enum.find(cart.items, &(&1.id == item_id)) do
      nil ->
        {:noreply, socket}

      item ->
        cart =
          CartState.recompute(%{cart | gift_wrapped: Helpers.toggle(cart.gift_wrapped, item_id)})

        row = Helpers.row(item, cart, wishlist_ids(socket))

        {:noreply,
         socket |> assign(:cart, cart) |> apply_effects([{:stream_insert, :cart_items, row}])}
    end
  end

  def handle_event("save_for_later", %{"item-id" => id}, socket) do
    item_id = String.to_integer(id)
    cart = socket.assigns.cart

    case Helpers.pop_item(cart.items, item_id) do
      {nil, _} ->
        {:noreply, socket}

      {item, remaining} ->
        cart = CartState.recompute(%{cart | items: remaining})

        ui = %{
          socket.assigns.ui
          | saved: Enum.uniq_by(socket.assigns.ui.saved ++ [item], & &1.id)
        }

        effects = [
          {:stream_delete, :cart_items, %{id: item_id}},
          {:stream_insert, :saved_items, item},
          {:flash, :info, "Saved for later"}
        ]

        {:noreply, socket |> assign(cart: cart, ui: ui) |> apply_effects(effects)}
    end
  end

  def handle_event("move_to_cart", %{"item-id" => id}, socket) do
    item_id = String.to_integer(id)

    case Helpers.pop_item(socket.assigns.ui.saved, item_id) do
      {nil, _} ->
        {:noreply, socket}

      {item, rest} ->
        cart =
          CartState.recompute(%{socket.assigns.cart | items: socket.assigns.cart.items ++ [item]})

        ui = %{socket.assigns.ui | saved: rest}

        effects = [
          {:stream_delete, :saved_items, item},
          {:stream_insert, :cart_items, Helpers.row(item, cart, wishlist_ids(socket))},
          {:flash, :info, "Moved to cart"}
        ]

        {:noreply, socket |> assign(cart: cart, ui: ui) |> apply_effects(effects)}
    end
  end

  def handle_event("toggle_wishlist", %{"item-id" => id}, socket) do
    item_id = String.to_integer(id)
    cart = socket.assigns.cart

    case Enum.find(cart.items, &(&1.id == item_id)) do
      nil ->
        {:noreply, socket}

      item ->
        product = item.product
        ui = socket.assigns.ui

        {wishlist, effects} =
          if Enum.any?(ui.wishlist, &(&1.id == product.id)) do
            {Enum.reject(ui.wishlist, &(&1.id == product.id)),
             [
               {:stream_delete, :wishlist_products, product},
               {:flash, :info, "Removed from wishlist"}
             ]}
          else
            {ui.wishlist ++ [product],
             [{:stream_insert, :wishlist_products, product}, {:flash, :info, "Added to wishlist"}]}
          end

        ui = %{ui | wishlist: wishlist}
        row = Helpers.row(item, cart, Enum.map(wishlist, & &1.id))

        {:noreply,
         socket
         |> assign(:ui, ui)
         |> apply_effects(effects ++ [{:stream_insert, :cart_items, row}])}
    end
  end

  def handle_event("remove_wishlist", %{"product-id" => id}, socket) do
    product_id = String.to_integer(id)
    ui = socket.assigns.ui
    ui = %{ui | wishlist: Enum.reject(ui.wishlist, &(&1.id == product_id))}

    effects =
      [{:stream_delete, :wishlist_products, %{id: product_id}}] ++
        rows_for_product(socket.assigns.cart, product_id, Enum.map(ui.wishlist, & &1.id))

    {:noreply, socket |> assign(:ui, ui) |> apply_effects(effects)}
  end

  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, socket) do
    product_id = String.to_integer(id)
    cart = socket.assigns.cart
    {:ok, _} = Carts.add_item(cart.cart_id, Products.get!(product_id))
    line = cart.cart_id |> Carts.list_items() |> Enum.find(&(&1.product.id == product_id))

    items = Enum.reject(cart.items, &(&1.id == line.id)) ++ [line]
    cart = CartState.recompute(%{cart | items: items})
    ui = socket.assigns.ui
    ui = %{ui | wishlist: Enum.reject(ui.wishlist, &(&1.id == product_id))}

    effects = [
      {:stream_delete, :wishlist_products, %{id: product_id}},
      {:stream_insert, :cart_items, Helpers.row(line, cart, Enum.map(ui.wishlist, & &1.id))},
      {:flash, :info, "Added to cart"}
    ]

    {:noreply, socket |> assign(cart: cart, ui: ui) |> apply_effects(effects)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    ui = %{socket.assigns.ui | active_tab: String.to_existing_atom(tab)}
    {:noreply, assign(socket, :ui, ui)}
  end

  def handle_event("select_shipping", %{"method" => method}, socket) do
    cart =
      CartState.recompute(%{
        socket.assigns.cart
        | shipping_method: String.to_existing_atom(method)
      })

    {:noreply, assign(socket, :cart, cart)}
  end

  def handle_event("apply_promo", %{"code" => code}, socket) do
    case Pricing.validate_promo(code, GoodDeal.Catalog.promo_codes()) do
      {:ok, pct} ->
        cart =
          CartState.recompute(%{
            socket.assigns.cart
            | promo_code: String.upcase(String.trim(code)),
              promo_percentage: pct
          })

        ui = %{socket.assigns.ui | promo_error: nil}

        {:noreply,
         socket
         |> assign(cart: cart, ui: ui)
         |> apply_effects([{:flash, :info, "Promo applied!"}])}

      {:error, :invalid_code} ->
        ui = %{socket.assigns.ui | promo_error: "Invalid promo code"}

        {:noreply,
         socket |> assign(:ui, ui) |> apply_effects([{:flash, :error, "Invalid promo code"}])}
    end
  end

  # ── Checkout events ────────────────────────────────────────────────────

  def handle_event("start_checkout", _params, socket) do
    if socket.assigns.cart.items == [] do
      {:noreply, apply_effects(socket, [{:flash, :error, "Your cart is empty"}])}
    else
      ckout = %CheckoutState{step: :address, address: socket.assigns.ckout.address}

      {:noreply,
       socket |> assign(:ckout, ckout) |> apply_effects([{:patch, @step_paths.address}])}
    end
  end

  def handle_event("validate_address", %{"address" => params}, socket) do
    changeset = Address.changeset(%Address{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :address_form, to_form(changeset))}
  end

  def handle_event("submit_address", %{"address" => params}, socket) do
    case Ecto.Changeset.apply_action(Address.changeset(%Address{}, params), :insert) do
      {:ok, address} ->
        ckout = %{socket.assigns.ckout | step: :payment, address: address}

        {:noreply,
         socket |> assign(:ckout, ckout) |> apply_effects([{:patch, @step_paths.payment}])}

      {:error, changeset} ->
        {:noreply, assign(socket, :address_form, to_form(changeset))}
    end
  end

  def handle_event("edit_address", _params, socket) do
    ckout = %{socket.assigns.ckout | step: :address}
    {:noreply, socket |> assign(:ckout, ckout) |> apply_effects([{:patch, @step_paths.address}])}
  end

  def handle_event("pay", _params, socket) do
    cart = socket.assigns.cart
    stock = Products.stock_levels(Enum.map(cart.items, & &1.product.id))

    case Checkout.validate(cart.items) do
      {:ok, items} ->
        case Inventory.check_availability(items, stock) do
          :ok ->
            line_items = Checkout.prepare_line_items(items)
            metadata = CheckoutMetadata.for_cart(cart.cart_id)
            ckout = %{socket.assigns.ckout | step: :processing}

            {:noreply,
             socket
             |> assign(:ckout, ckout)
             |> apply_effects([{:start_checkout, line_items, metadata}])}

          {:error, _} ->
            {:noreply, apply_effects(socket, [{:flash, :error, "Some items are out of stock"}])}
        end

      {:error, :empty_cart} ->
        {:noreply, apply_effects(socket, [{:flash, :error, "Your cart is empty"}])}
    end
  end

  # ── Async ──────────────────────────────────────────────────────────────

  @impl true
  def handle_async(:checkout, {:ok, {:ok, _reference}}, socket) do
    finalize_order(socket.assigns.cart.cart_id)
    ckout = %{socket.assigns.ckout | step: :complete}
    {:noreply, socket |> assign(:ckout, ckout) |> apply_effects([{:navigate, ~p"/cart/success"}])}
  end

  def handle_async(:checkout, {:ok, {:error, _}}, socket) do
    {:noreply, assign(socket, :ckout, %{socket.assigns.ckout | step: :error})}
  end

  def handle_async(:checkout, {:exit, _}, socket) do
    {:noreply, assign(socket, :ckout, %{socket.assigns.ckout | step: :error})}
  end

  # ── Timers and PubSub ──────────────────────────────────────────────────

  @impl true
  def handle_info({:timer, :undo, %{id: item_id}}, socket) do
    case socket.assigns.ui.undo do
      %{item: %{id: ^item_id}} ->
        ui = %{socket.assigns.ui | undo: nil}

        {:noreply,
         socket
         |> assign(:ui, ui)
         |> apply_effects([{:persist_remove, socket.assigns.cart.cart_id, item_id}])}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:stock_changed, {product_id, new_stock}}, socket) do
    cart = socket.assigns.cart
    items = Helpers.update_product_stock(cart.items, product_id, new_stock)
    cart = %{cart | items: items}

    effects =
      for item <- items,
          item.product.id == product_id,
          do: {:stream_insert, :cart_items, Helpers.row(item, cart, wishlist_ids(socket))}

    {:noreply, socket |> assign(:cart, cart) |> apply_effects(effects)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Effects ────────────────────────────────────────────────────────────

  defp apply_effects(socket, effects) do
    Enum.reduce(effects, socket, &apply_effect(&2, &1))
  end

  defp apply_effect(socket, {:flash, level, msg}), do: put_flash(socket, level, msg)
  defp apply_effect(socket, {:navigate, path}), do: push_navigate(socket, to: path)
  defp apply_effect(socket, {:patch, path}), do: push_patch(socket, to: path)
  defp apply_effect(socket, {:stream_insert, col, item}), do: stream_insert(socket, col, item)
  defp apply_effect(socket, {:stream_delete, col, item}), do: stream_delete(socket, col, item)

  defp apply_effect(socket, {:push_event, event, payload}) do
    push_event(socket, event, payload)
  end

  defp apply_effect(socket, {:cancel_timer, ref}) do
    Process.cancel_timer(ref)
    socket
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
    amount_cents =
      Enum.reduce(line_items, 0, fn li, acc -> acc + li.unit_amount * li.quantity end)

    currency = hd(line_items).currency

    start_async(socket, :checkout, fn ->
      payment_gateway().charge(amount_cents, currency, metadata)
    end)
  end

  defp payment_gateway do
    Application.get_env(:good_deal, :payment_gateway, GoodDeal.Foundation.LedgerGateway)
  end

  # Record the order and draw down stock once payment has settled.
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

  defp wishlist_ids(socket), do: Enum.map(socket.assigns.ui.wishlist, & &1.id)

  defp rows_for_product(cart, product_id, wishlist_ids) do
    for item <- cart.items,
        item.product.id == product_id,
        do: {:stream_insert, :cart_items, Helpers.row(item, cart, wishlist_ids)}
  end

  # The composition reads the store's calibration and threads it down into the
  # cart state; the domain and feature layers never reach up to it.
  defp store_calibration do
    %{
      shipping_methods: GoodDeal.Catalog.shipping_methods(),
      gift_wrap_cents: GoodDeal.Catalog.gift_wrap_cents()
    }
  end

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(%{live_action: :checkout} = assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">← Back to cart</.link>
      <h1 class="text-3xl font-semibold py-4">Checkout</h1>
      <ol class="flex gap-4 text-sm mb-6">
        <li class="font-medium text-zinc-900">Address</li>
        <li class={[
          "font-medium",
          if(@ckout.step == :address, do: "text-zinc-400", else: "text-zinc-900")
        ]}>
          Payment
        </li>
      </ol>
      <.address_step :if={@ckout.step == :address} form={@address_form} />
      <.payment_step :if={@ckout.step == :payment} address={@ckout.address} total={@cart.total} />
      <div :if={@ckout.step == :processing} class="flex items-center gap-3 text-zinc-500 py-6">
        <.spinner /> Processing payment…
      </div>
      <div :if={@ckout.step == :error} class="space-y-3">
        <p class="text-red-600 text-sm">Payment failed.</p>
        <button
          phx-click="pay"
          class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
        >
          Try again
        </button>
      </div>
      <p :if={@ckout.step == :complete} class="text-zinc-500 py-6">Redirecting…</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <div
        :if={@ui.undo}
        class="flex items-center justify-between bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 mb-4"
      >
        <span class="text-sm text-amber-800">Item removed.</span>
        <button phx-click="undo_remove" class="text-sm font-semibold text-amber-700 underline">
          Undo
        </button>
      </div>

      <nav class="flex gap-2 border-b mb-6 pb-2">
        <button
          :for={
            {tab, label, count} <- [
              {:items, "Items", @cart.item_count},
              {:saved, "Saved", length(@ui.saved)},
              {:wishlist, "Wishlist", length(@ui.wishlist)}
            ]
          }
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
          {label} ({count})
        </button>
      </nav>

      <div class={[@ui.active_tab != :items && "hidden"]}>
        <div id="cart_items" phx-update="stream">
          <.cart_item_row
            :for={{dom_id, row} <- @streams.cart_items}
            id={dom_id}
            row={row}
            stock_status={Inventory.stock_status(row.product.stock, @low_stock)}
          />
        </div>
        <div :if={@cart.items == []} class="py-12 text-center text-zinc-400">
          Your cart is empty.
          <.link navigate={~p"/products"} class="text-blue-500 hover:underline">
            Browse products
          </.link>
        </div>
      </div>

      <div class={[@ui.active_tab != :saved && "hidden"]}>
        <div id="saved_items" phx-update="stream">
          <div
            :for={{dom_id, item} <- @streams.saved_items}
            id={dom_id}
            class="flex justify-between items-center border-b py-3"
          >
            <span class="font-medium">{item.product.name}</span>
            <button phx-click="move_to_cart" phx-value-item-id={item.id} class="text-sm text-blue-600">
              Move to cart
            </button>
          </div>
        </div>
        <div :if={@ui.saved == []} class="py-12 text-center text-zinc-400">No saved items.</div>
      </div>

      <div class={[@ui.active_tab != :wishlist && "hidden"]}>
        <div id="wishlist_products" phx-update="stream">
          <div
            :for={{dom_id, product} <- @streams.wishlist_products}
            id={dom_id}
            class="flex justify-between items-center border-b py-3"
          >
            <span class="font-medium">{product.name}</span>
            <span class="flex gap-3">
              <button
                phx-click="add_wishlisted_to_cart"
                phx-value-product-id={product.id}
                class="text-sm text-blue-600"
              >
                Add to cart
              </button>
              <button
                phx-click="remove_wishlist"
                phx-value-product-id={product.id}
                class="text-sm text-red-500"
              >
                Remove
              </button>
            </span>
          </div>
        </div>
        <div :if={@ui.wishlist == []} class="py-12 text-center text-zinc-400">
          Your wishlist is empty.
        </div>
      </div>

      <.cart_summary cart={@cart} methods={@cart.shipping_methods} />
      <.shipping_selector methods={@cart.shipping_methods} selected={@cart.shipping_method} />
      <.promo_form error={@ui.promo_error} current_code={@cart.promo_code} />

      <div class="py-4">
        <button
          phx-click="start_checkout"
          disabled={@cart.items == []}
          class={[
            "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white",
            @cart.items == [] && "opacity-50 cursor-not-allowed"
          ]}
        >
          Checkout · {@cart.total}
        </button>
      </div>
    </div>
    """
  end

  # ── Function Components ────────────────────────────────────────────────

  defp cart_item_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto_auto] items-center gap-4 border-b py-4">
      <img class="w-16 h-16 object-contain" src={@row.product.thumbnail} alt={@row.product.name} />
      <div>
        <div class="font-medium">{@row.product.name}</div>
        <div class="text-sm text-zinc-500">{Money.new(@row.product.amount)} each</div>
        <.stock_badge status={@stock_status} />
        <div class="flex items-center gap-3 mt-1 text-xs text-zinc-500">
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              type="checkbox"
              checked={@row.gift_wrapped}
              phx-click="toggle_gift_wrap"
              phx-value-item-id={@row.id}
            /> Gift wrap ({Money.new(GoodDeal.Catalog.gift_wrap_cents())})
          </label>
          <button phx-click="save_for_later" phx-value-item-id={@row.id} class="underline">
            Save for later
          </button>
          <button
            phx-click="toggle_wishlist"
            phx-value-item-id={@row.id}
            class={if @row.wishlisted, do: "text-red-500", else: "text-zinc-400"}
          >
            {if @row.wishlisted, do: "♥ Wishlisted", else: "♡ Wishlist"}
          </button>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click="update_quantity"
          phx-value-item-id={@row.id}
          phx-value-delta="-1"
          disabled={@row.quantity <= 1}
          class="w-8 h-8 rounded border text-lg font-bold disabled:opacity-30 hover:bg-zinc-100"
        >
          -
        </button>
        <span class="w-8 text-center font-mono">{@row.quantity}</span>
        <button
          phx-click="update_quantity"
          phx-value-item-id={@row.id}
          phx-value-delta="1"
          class="w-8 h-8 rounded border text-lg font-bold hover:bg-zinc-100"
        >
          +
        </button>
      </div>
      <div class="text-right w-24">
        <div class="font-semibold">{Money.new(@row.product.amount * @row.quantity)}</div>
        <button
          phx-click="remove_item"
          phx-value-item-id={@row.id}
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
      {if @status == :low_stock, do: "Low stock", else: "Out of stock"}
    </span>
    """
  end

  defp cart_summary(assigns) do
    ~H"""
    <div class="space-y-3 py-6 border-t mt-6">
      <div class="flex justify-between text-zinc-600">
        <span>Items</span><span>{@cart.item_count}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Subtotal</span><span>{@cart.subtotal}</span>
      </div>
      <div :if={@cart.promo_code} class="flex justify-between text-green-600">
        <span>Discount ({@cart.promo_code})</span><span>-{@cart.discount}</span>
      </div>
      <div :if={Money.positive?(@cart.gift_wrap)} class="flex justify-between text-zinc-600">
        <span>Gift wrap</span><span>{@cart.gift_wrap}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Shipping ({GoodDeal.Domain.Shipping.find(@methods, @cart.shipping_method).label})</span>
        <span>{if Money.zero?(@cart.shipping), do: "Free", else: @cart.shipping}</span>
      </div>
      <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
        <span>Total</span><span>{@cart.total}</span>
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
        <span>{opt.label}</span>
        <span class="text-zinc-500">
          {if opt.free_above,
            do: "#{Money.new(opt.cost)} (free over #{Money.new(opt.free_above)})",
            else: Money.new(opt.cost)}
        </span>
      </label>
    </fieldset>
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
      <span :if={@error} class="text-red-500 text-sm self-center">{@error}</span>
    </form>
    """
  end

  defp address_step(assigns) do
    ~H"""
    <.simple_form for={@form} phx-change="validate_address" phx-submit="submit_address">
      <.input field={@form[:name]} label="Full name" phx-hook="AutoFocus" id="address_name" />
      <.input field={@form[:line1]} label="Address" />
      <.input field={@form[:city]} label="City" />
      <.input field={@form[:postal_code]} label="Postal code" />
      <:actions>
        <.button phx-disable-with="Saving…">Continue to payment</.button>
      </:actions>
    </.simple_form>
    """
  end

  defp payment_step(assigns) do
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
        <button phx-click="edit_address" class="text-sm text-zinc-500 underline">Edit address</button>
        <button
          phx-click="pay"
          class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
        >
          Pay {@total}
        </button>
      </div>
    </div>
    """
  end

  defp spinner(assigns) do
    ~H"""
    <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
    </svg>
    """
  end
end
