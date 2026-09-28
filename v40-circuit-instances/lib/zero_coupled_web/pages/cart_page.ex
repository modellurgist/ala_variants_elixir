defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page. `circuit/1` is its diagram: the feature instances, the UI instances and sinks
  they feed, and the wires between them. The template places the UI instances; the handlers
  only return messages (from instances, timers, jobs, the URL, PubSub) to the circuit. The
  store's literals sit here.
  """
  use ZeroCoupledWeb, :live_view
  alias ZeroCoupled.Features.{Cart, Checkout, PageUI, SavedItems, Undo, Wishlist}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}

  alias ZeroCoupled.Paradigms.{
    Adapter,
    Circuit,
    FromStore,
    ToAssign,
    ToAsync,
    ToComponent,
    ToFlash,
    ToForm,
    ToPatch,
    ToRedirect,
    ToStore,
    ToTimer,
    Via
  }

  alias ZeroCoupledWeb.CartLive.{CartControls, CartPanel, CheckoutForm, SavedPanel, WishlistPanel}
  alias ZeroCoupledWeb.Paradigms.Runner
  import ZeroCoupledWeb.Rows, only: [milestones: 1]

  @pricing [
    shipping: %{
      standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
      overnight: %{label: "Overnight", cost: 2499, free_above: nil}
    },
    promo: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50},
    gift_wrap_unit: 299
  ]
  @gift_wrap_label "Gift wrap ($2.99)"
  @undo_window_ms 5_000
  @checkout_flow [
    {:address, :submit_address, :payment},
    {:payment, :edit_address, :address},
    {:payment, :pay, :processing},
    {:error, :pay, :processing}
  ]
  @checkout_url_edges [{:payment, :address}]
  @step_paths %{address: "/cart/checkout", payment: "/cart/checkout/payment"}
  @steps_by_url %{"payment" => :payment}
  @milestones [address: "Address", payment: "Payment"]

  def circuit(cart_id) do
    Circuit.new(
      lines: %FromStore{read: &Carts.list_items/1},
      cart: Adapter.new(Cart, Cart.new(cart_id: cart_id, pricing: @pricing)),
      undo: Adapter.new(Undo, Undo.new([])),
      saved: Adapter.new(SavedItems, SavedItems.new([])),
      wishlist: Adapter.new(Wishlist, Wishlist.new([])),
      ui: Adapter.new(PageUI, PageUI.new(tabs: [:items, :saved, :wishlist])),
      checkout:
        Adapter.new(
          Checkout,
          Checkout.new(
            flow: @checkout_flow,
            start: :address,
            url_edges: @checkout_url_edges,
            stock_levels: &Products.stock_levels/1
          )
        ),
      cart_rows: %ToComponent{module: CartPanel, id: "cart"},
      saved_rows: %ToComponent{module: SavedPanel, id: "saved"},
      wishlist_rows: %ToComponent{module: WishlistPanel, id: "wishlist"},
      summary: %ToAssign{name: :summary},
      persist: %ToStore{write: &persist/1},
      saved_count: %ToAssign{name: :saved_count},
      wishlist_count: %ToAssign{name: :wishlist_count},
      wishlist_ids: %ToAssign{name: :wishlist_ids},
      promo_ok: %ToAssign{name: :promo_error, value: nil},
      promo_bad: %ToAssign{name: :promo_error, value: "Invalid promo code"},
      undo_armed: %ToAssign{name: :undo_pending, value: true},
      undo_cleared: %ToAssign{name: :undo_pending, value: false},
      undo_clock: %ToTimer{name: :undo, ms: @undo_window_ms, into: {:undo, :expire}},
      add_line: %Via{fun: &add_line(cart_id, &1)},
      tab: %ToAssign{name: :active_tab},
      step: %ToAssign{name: :step},
      url: %ToPatch{paths: @step_paths},
      address_form: %ToForm{name: :address_form},
      address: %ToAssign{name: :address},
      charge: %ToAsync{
        name: :payment,
        fun: &charge/1,
        ok: {:checkout, :succeeded},
        error: {:checkout, :failed}
      },
      finalize: %Via{fun: &finalize(cart_id, &1)},
      go: %ToRedirect{},
      saved_notice: %ToFlash{text: "Saved for later"},
      moved_notice: %ToFlash{text: "Moved to cart"},
      promo_notice: %ToFlash{text: "Promo applied!"},
      promo_error: %ToFlash{level: :error, text: "Invalid promo code"},
      restored_notice: %ToFlash{text: "Item restored"},
      wishlisted_notice: %ToFlash{text: "Added to wishlist"},
      unwishlisted_notice: %ToFlash{text: "Removed from wishlist"},
      added_notice: %ToFlash{text: "Added to cart"},
      blocked_notice: %ToFlash{
        level: :error,
        texts: %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}
      }
    )
    |> Circuit.wire({:lines, :loaded}, {:cart, :load})
    |> Circuit.wire({:cart, :rows}, {:cart_rows, :change})
    |> Circuit.wire({:cart, :summary}, {:summary, :value})
    |> Circuit.wire({:cart, :persist}, {:persist, :value})
    |> Circuit.wire({:cart, :removed}, {:undo, :capture})
    |> Circuit.wire({:cart, :saved}, {:saved, :stash})
    |> Circuit.wire({:cart, :saved}, {:saved_notice, :any})
    |> Circuit.wire({:cart, :promo_applied}, {:promo_ok, :any})
    |> Circuit.wire({:cart, :promo_applied}, {:promo_notice, :any})
    |> Circuit.wire({:cart, :promo_rejected}, {:promo_bad, :any})
    |> Circuit.wire({:cart, :promo_rejected}, {:promo_error, :any})
    |> Circuit.wire({:cart, :line}, {:wishlist, :toggle})
    |> Circuit.wire({:cart, :checkout_requested}, {:checkout, :pay})
    |> Circuit.wire({:undo, :captured}, {:undo_armed, :any})
    |> Circuit.wire({:undo, :timer}, {:undo_clock, :value})
    |> Circuit.wire({:undo, :restored}, {:cart, :receive})
    |> Circuit.wire({:undo, :restored}, {:restored_notice, :any})
    |> Circuit.wire({:undo, :restored}, {:undo_cleared, :any})
    |> Circuit.wire({:undo, :expired}, {:cart, :confirm_removal})
    |> Circuit.wire({:undo, :expired}, {:undo_cleared, :any})
    |> Circuit.wire({:saved, :rows}, {:saved_rows, :change})
    |> Circuit.wire({:saved, :count}, {:saved_count, :value})
    |> Circuit.wire({:saved, :moved}, {:cart, :receive})
    |> Circuit.wire({:saved, :moved}, {:moved_notice, :any})
    |> Circuit.wire({:wishlist, :rows}, {:wishlist_rows, :change})
    |> Circuit.wire({:wishlist, :count}, {:wishlist_count, :value})
    |> Circuit.wire({:wishlist, :ids}, {:wishlist_ids, :value})
    |> Circuit.wire({:wishlist, :added}, {:wishlisted_notice, :any})
    |> Circuit.wire({:wishlist, :dropped}, {:unwishlisted_notice, :any})
    |> Circuit.wire({:wishlist, :taken}, {:add_line, :in})
    |> Circuit.wire({:add_line, :out}, {:cart, :receive})
    |> Circuit.wire({:add_line, :out}, {:added_notice, :any})
    |> Circuit.wire({:ui, :tab}, {:tab, :value})
    |> Circuit.wire({:checkout, :step}, {:step, :value})
    |> Circuit.wire({:checkout, :step}, {:url, :value})
    |> Circuit.wire({:checkout, :form}, {:address_form, :value})
    |> Circuit.wire({:checkout, :address}, {:address, :value})
    |> Circuit.wire({:checkout, :blocked}, {:blocked_notice, :key})
    |> Circuit.wire({:checkout, :payment}, {:charge, :value})
    |> Circuit.wire({:checkout, :done}, {:finalize, :in})
    |> Circuit.wire({:finalize, :out}, {:go, :url})
  end

  @impl true
  def mount(_params, %{"cart_id" => cart_id}, socket) do
    if connected?(socket), do: Broadcast.subscribe()
    circuit = circuit(cart_id)

    {:ok,
     socket
     |> assign(
       circuit: circuit,
       active_tab: :items,
       saved_count: 0,
       wishlist_count: 0,
       wishlist_ids: [],
       promo_error: nil
     )
     |> assign(
       undo_pending: false,
       step: :address,
       milestones: @milestones,
       address: nil,
       gift_wrap_label: @gift_wrap_label
     )
     |> assign(
       address_form: to_form(Checkout.address_form(Circuit.part(circuit, :checkout).state))
     )
     |> Runner.feed(:lines, {:load, cart_id})}
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket),
    do:
      {:noreply,
       Runner.feed(socket, :checkout, {:goto, Map.get(@steps_by_url, params["step"], :address)})}

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:feed, _, _} = message, socket),
    do: {:noreply, Runner.feed_message(message, socket)}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
    do: {:noreply, Runner.feed(socket, :cart, {:set_stock, %{product_id: id, stock: stock}})}

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_async(_name, result, socket), do: {:noreply, Runner.async_result(result, socket)}

  @impl true
  def render(%{live_action: :checkout} = assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">← Back to cart</.link>
      <h1 class="text-3xl font-semibold py-4">Checkout</h1>
      <.milestones
        step={@step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.live_component
        module={CheckoutForm}
        id="checkout"
        step={@step}
        address={@address}
        address_form={@address_form}
        total={@summary.total}
      />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>
      <.live_component
        module={CartControls}
        id="controls_top"
        part={:top}
        active_tab={@active_tab}
        undo_pending={@undo_pending}
        counts={[items: @summary.item_count, saved: @saved_count, wishlist: @wishlist_count]}
      />
      <div class={@active_tab != :items && "hidden"}>
        <.live_component
          module={CartPanel}
          id="cart"
          wishlist_ids={@wishlist_ids}
          empty?={@summary.empty?}
          gift_wrap_label={@gift_wrap_label}
        />
      </div>
      <div class={@active_tab != :saved && "hidden"}>
        <.live_component module={SavedPanel} id="saved" count={@saved_count} />
      </div>
      <div class={@active_tab != :wishlist && "hidden"}>
        <.live_component module={WishlistPanel} id="wishlist" count={@wishlist_count} />
      </div>
      <.live_component
        module={CartControls}
        id="controls_bottom"
        part={:bottom}
        summary={@summary}
        promo_error={@promo_error}
      />
    </div>
    """
  end

  # the page's own wires into the technical domains: persistence, payment, order placement
  defp persist({:quantity, cart_id, item_id, qty}),
    do: Carts.update_quantity(cart_id, item_id, qty)

  defp persist({:remove, cart_id, item_id}), do: Carts.remove_item(cart_id, item_id)

  defp add_line(cart_id, product) do
    Carts.add_item(cart_id, Products.get!(product.id))
    cart_id |> Carts.list_items() |> Enum.find(&(&1.product.id == product.id))
  end

  defp charge({line_items, cart_id}) do
    gateway = Application.get_env(:zero_coupled, :payment_gateway, LedgerGateway)

    gateway.create_checkout_session(line_items, %{"cart_id" => cart_id}, %{
      success_url: url(~p"/cart/success"),
      cancel_url: url(~p"/cart")
    })
  end

  defp finalize(cart_id, url) do
    Orders.create(cart_id)

    for item <- Carts.list_items(cart_id),
        {:ok, product} <- [Products.decrement_stock(item.product.id, item.quantity)] do
      Broadcast.stock_changed(product.id, product.stock)
    end

    url
  end
end
