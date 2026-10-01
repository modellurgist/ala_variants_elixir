defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page in the shape `phx.gen.live` produces: the template places the feature instances
  and configures them; one route table says where each instance's announcement goes and what the
  page says about it. The store's words and numbers are the attributes; its
  pricing, stores and order placement are configured here once. There is no catch-all
  `handle_info`: a message the page doesn't route crashes it, and a test sends every announced
  port to catch a missing clause before a user does.
  """
  use ZeroCoupledWeb, :live_view
  import ZeroCoupled.Catalog.Panes
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}

  alias ZeroCoupled.Domain.{
    AddLine,
    BuildLineItems,
    CalculateGiftWrapCost,
    CalculateShipping,
    PlaceOrder,
    StockStatus,
    ValidatePromo
  }

  alias ZeroCoupledWeb.{CartSession, StoreConfig}

  alias ZeroCoupled.Features.{Cart, Checkout, SavedItems, Undo, Wishlist}
  alias ZeroCoupledWeb.Paradigms.Instance
  alias ZeroCoupled.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}

  @promo_codes %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}
  @gift_wrap_unit 299
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
  @texts %{
    cart: %{
      discount: "Discount",
      gift_wrap: "Gift wrap",
      promo_placeholder: "Promo code",
      free_over: "free over",
      apply: "Apply",
      row: %{
        save: "Save for later",
        wishlisted: "♥ Wishlisted",
        wishlist: "♡ Wishlist",
        each: " each"
      }
    },
    saved: %{row: %{move: "Move to cart"}},
    wishlist: %{row: %{add: "Add to cart"}},
    undo: %{undo: "Undo"},
    checkout: %{
      name: "Full name",
      line1: "Address",
      city: "City",
      postal_code: "Postal code",
      continue: "Continue to payment",
      saving: "Saving…",
      edit_address: "Edit address",
      pay: "Pay",
      payment_failed: "Payment failed.",
      try_again: "Try again",
      processing: "Processing payment…",
      redirecting: "Redirecting…"
    }
  }
  # the page's own words, plus the store's shared ones
  defp texts do
    shared = %{remove: StoreConfig.remove_text(), stock: StoreConfig.stock_texts()}

    @texts
    |> update_in([:cart], &Map.merge(&1, StoreConfig.summary_texts()))
    |> update_in([:cart, :row], &Map.merge(&1, shared))
    |> update_in([:wishlist, :row], &Map.put(&1, :remove, shared.remove))
    |> update_in([:checkout], &Map.put(&1, :total, StoreConfig.summary_texts().total))
    |> put_in([:cart, :gift_wrap_label], "Gift wrap (#{Money.new(@gift_wrap_unit)})")
  end

  @blocked %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}

  @impl true
  def mount(_params, session, socket) do
    cart_id = session[CartSession.cart_key()]

    {:ok,
     assign(socket,
       cart_id: cart_id,
       texts: texts(),
       pricing: %{
         shipping: CalculateShipping.new(StoreConfig.rates()),
         stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at()),
         promo: ValidatePromo.new(@promo_codes),
         gift_wrap: CalculateGiftWrapCost.new(@gift_wrap_unit)
       },
       add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
       line_items: BuildLineItems.new(currency: StoreConfig.currency()),
       form_messages: %{postal_code: "must be 4–10 digits"},
       place_order: %PlaceOrder{
         orders: Orders,
         carts: Carts,
         products: Products,
         announce: &Broadcast.stock_changed/2
       },
       active_tab: :items,
       cart_summary: %{item_count: 0, empty?: true},
       saved_count: 0,
       wishlist_count: 0,
       wishlist_ids: [],
       requested_step: :address,
       undo_window_ms: StoreConfig.undo_window_ms(),
       checkout_flow: @checkout_flow,
       checkout_url_edges: @checkout_url_edges,
       milestones: @milestones,
       gateway: Application.get_env(:zero_coupled, :payment_gateway, LedgerGateway),
       urls: %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")}
     )}
  end

  @impl true
  def handle_params(params, _url, socket),
    do:
      {:noreply, assign(socket, requested_step: Map.get(@steps_by_url, params["step"], :address))}

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do: {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}

  def handle_event("start_checkout", _, socket),
    do: {:noreply, push_patch(socket, to: ~p"/cart/checkout")}

  @routes %{
    {:cart, :summary} => [assign: :cart_summary],
    {:cart, :removed} => [pass: {Undo.Banner, "undo", :capture}],
    {:cart, :saved} => [
      pass: {SavedItems.Panel, "saved", :stash},
      flash: {:info, "Saved for later"}
    ],
    {:cart, :line} => [pass: {Wishlist.Panel, "wishlist", :toggle}],
    {:cart, :promo_applied} => [flash: {:info, "Promo applied!"}],
    {:cart, :promo_rejected} => [flash: {:error, "Invalid promo code"}],
    {:undo, :expire} => [pass: {Undo.Banner, "undo", :expire}],
    {:undo, :expired} => [pass: {Cart.Panel, "cart", :confirm_removal}],
    {:undo, :restored} => [pass: {Cart.Panel, "cart", :receive}, flash: {:info, "Item restored"}],
    {:saved, :count} => [assign: :saved_count],
    {:saved, :moved} => [pass: {Cart.Panel, "cart", :receive}, flash: {:info, "Moved to cart"}],
    {:wishlist, :count} => [assign: :wishlist_count],
    {:wishlist, :ids} => [assign: :wishlist_ids],
    {:wishlist, :added} => [flash: {:info, "Added to wishlist"}],
    {:wishlist, :dropped} => [flash: {:info, "Removed from wishlist"}],
    {:wishlist, :taken} => [
      pass: {Cart.Panel, "cart", :add_product},
      flash: {:info, "Added to cart"}
    ],
    {:checkout, :blocked} => [flash_by: {:error, @blocked}],
    {:checkout, :step} => [patch: @step_paths],
    {:stock, :changed} => [pass: {Cart.Panel, "cart", :set_stock}]
  }

  @doc "The page's wiring: where each instance's announcement goes."
  def routes, do: @routes

  @impl true
  def handle_info({_name, _port, _payload} = announcement, socket),
    do: {:noreply, Instance.route(socket, @routes, announcement)}

  def handle_info(%Broadcast.Facts.StockChanged{} = change, socket),
    do: {:noreply, Instance.route(socket, @routes, {:stock, :changed, change})}

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

  # the cart's instances stay mounted behind the checkout, so nothing announced while paying is lost
  @impl true
  def render(assigns) do
    ~H"""
    <.pane current={@live_action} name={:index} class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>
      <.live_component
        module={Undo.Banner}
        id="undo"
        window_ms={@undo_window_ms}
        text="Item removed."
        t={@texts.undo}
      />
      <.tabs current={@active_tab} event="switch_tab">
        <:tab name={:items} label={"Items (#{@cart_summary.item_count})"} />
        <:tab name={:saved} label={"Saved (#{@saved_count})"} />
        <:tab name={:wishlist} label={"Wishlist (#{@wishlist_count})"} />
      </.tabs>
      <.pane current={@active_tab} name={:items}>
        <.live_component
          module={Cart.Panel}
          id="cart"
          cart_id={@cart_id}
          pricing={@pricing}
          store={Carts}
          add_line={@add_line}
          wishlist_ids={@wishlist_ids}
          gift_wrap_label={@texts.cart.gift_wrap_label}
          empty_text="Your cart is empty."
          invalid_promo_text="Invalid promo code"
          t={@texts.cart}
        />
        <div class="py-4">
          <button
            phx-click="start_checkout"
            disabled={@cart_summary.empty?}
            class={[
              "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
              @cart_summary.empty? && "opacity-50 cursor-not-allowed"
            ]}
          >
            Checkout
          </button>
        </div>
      </.pane>
      <.pane current={@active_tab} name={:saved}>
        <.live_component
          module={SavedItems.Panel}
          id="saved"
          empty_text="No saved items."
          t={@texts.saved}
        />
      </.pane>
      <.pane current={@active_tab} name={:wishlist}>
        <.live_component
          module={Wishlist.Panel}
          id="wishlist"
          empty_text="Your wishlist is empty."
          t={@texts.wishlist}
        />
      </.pane>
    </.pane>
    <.only_on current={@live_action} name={:checkout}>
      <div class="max-w-lg mx-auto px-6 py-6">
        <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">
          ← Back to cart
        </.link>
        <h1 class="text-3xl font-semibold py-4">Checkout</h1>
        <.live_component
          module={Checkout.Panel}
          id="checkout"
          cart_id={@cart_id}
          pricing={@pricing}
          store={Carts}
          stock_levels={&Products.stock_levels/1}
          line_items={@line_items}
          messages={@form_messages}
          place_order={@place_order}
          cart_key={CartSession.cart_key()}
          flow={@checkout_flow}
          start={:address}
          url_edges={@checkout_url_edges}
          milestones={@milestones}
          requested_step={@requested_step}
          gateway={@gateway}
          urls={@urls}
          t={@texts.checkout}
        />
      </div>
    </.only_on>
    """
  end
end
