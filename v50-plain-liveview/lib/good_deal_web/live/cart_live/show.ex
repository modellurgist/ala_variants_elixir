defmodule GoodDealWeb.CartLive.Show do
  @moduledoc """
  The cart page and its checkout steps, as a plain LiveView. Its configuration is at the top: the
  store's words and rules, and the features and domain instances built from them. Each browser
  event runs one feature step; each feature output wires through one `wire/3` clause, so those
  clauses are the page's wiring, one per declared port, read top to bottom. There is no catch-all:
  an output without a clause crashes the page, and a test checks every declared port has one.
  """
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDeal.Components.{Panes, Parts, Rows}

  alias GoodDeal.Catalog

  alias GoodDeal.Domain.{
    AddLine,
    BuildLineItems,
    CalculateGiftWrapCost,
    CalculateShipping,
    Charge,
    SettleOrder,
    StockStatus,
    ValidatePromo
  }

  alias GoodDeal.State.{Cart, Checkout, PageUI, SavedItems, Undo, Wishlist}
  alias GoodDeal.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}
  alias GoodDealWeb.{CartSession, CheckoutMetadata}
  alias GoodDealWeb.Paradigms.Steps

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
  @blocked %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}
  @texts %{
    cart: %{
      discount: "Discount",
      gift_wrap: "Gift wrap",
      promo_placeholder: "Promo code",
      free_over: "free over",
      apply: "Apply",
      empty: "Your cart is empty.",
      checkout: "Checkout",
      row: %{
        save: "Save for later",
        wishlisted: "♥ Wishlisted",
        wishlist: "♡ Wishlist",
        each: " each"
      }
    },
    tabs: %{saved: "Saved", wishlist: "Wishlist"},
    saved: %{empty: "No saved items.", row: %{move: "Move to cart"}},
    wishlist: %{empty: "Your wishlist is empty.", row: %{add: "Add to cart"}},
    undo: %{text: "Item removed.", undo: "Undo"},
    checkout: %{
      back: "← Back to cart",
      heading: "Checkout",
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
    shared = %{remove: Catalog.remove_text(), stock: Catalog.stock_texts()}

    @texts
    |> update_in([:cart], &Map.merge(&1, Catalog.summary_texts()))
    |> update_in([:cart, :row], &Map.merge(&1, shared))
    |> update_in([:wishlist, :row], &Map.put(&1, :remove, shared.remove))
    |> update_in([:checkout], &Map.put(&1, :total, Catalog.summary_texts().total))
    |> put_in([:tabs, :items], Catalog.summary_texts().items)
    |> put_in([:cart, :gift_wrap_label], "Gift wrap (#{Money.new(Catalog.gift_wrap_cents())})")
  end

  @doc "Which feature each `wire/3` key names, so a test can check every declared port has a clause."
  @features %{
    cart: Cart,
    undo: Undo,
    saved: SavedItems,
    wishlist: Wishlist,
    ui: PageUI,
    checkout: Checkout
  }
  def features, do: @features

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session)

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      stock_status: StockStatus.new(low_at: Catalog.low_stock_threshold()),
      promo: ValidatePromo.new(Catalog.promo_codes()),
      gift_wrap: CalculateGiftWrapCost.new(Catalog.gift_wrap_cents())
    }

    {:ok,
     socket
     |> assign(
       cart: GoodDeal.Cart.new(cart_id: cart_id, pricing: pricing),
       undo: Undo.new([]),
       saved: SavedItems.new([]),
       wishlist: Wishlist.new([]),
       ui: PageUI.new(tabs: [:items, :saved, :wishlist]),
       checkout:
         Checkout.new(
           flow: @checkout_flow,
           start: :address,
           url_edges: @checkout_url_edges,
           stock_levels: &Products.stock_levels/1,
           line_items: BuildLineItems.new(currency: Catalog.currency()),
           messages: %{postal_code: "must be 4–10 digits"}
         ),
       add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
       charge: %Charge{
         gateway: Application.get_env(:good_deal, :payment_gateway, LedgerGateway),
         metadata: &CheckoutMetadata.for_cart/1
       },
       settle: %SettleOrder{
         orders: Orders,
         carts: Carts,
         products: Products,
         announce: &Broadcast.stock_changed/2,
         cart_id: cart_id
       }
     )
     |> assign(
       texts: texts(),
       active_tab: :items,
       saved_count: 0,
       wishlist_count: 0,
       wishlist_ids: [],
       promo_error: nil,
       undo_pending: false,
       step: :address,
       milestones: @milestones,
       address: nil
     )
     |> stream(:cart_items, [])
     |> stream(:saved_items, [])
     |> stream(:wishlist_products, [])
     |> Steps.feed(:cart, &Cart.load/2, &Carts.list_items/1, cart_id, &wire/3)
     |> run(:checkout, &Checkout.show_form(&1, nil))}
  end

  # the URL names a checkout step (browser back, a reload); the feature decides whether to honour it
  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket),
    do:
      {:noreply,
       run(
         socket,
         :checkout,
         &Checkout.goto(&1, Map.get(@steps_by_url, params["step"], :address))
       )}

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_quantity", %{"item-id" => id, "delta" => d}, socket),
    do:
      {:noreply,
       run(socket, :cart, &Cart.update_quantity(&1, %{item_id: int(id), delta: int(d)}))}

  def handle_event("remove_item", %{"item-id" => id}, socket),
    do: {:noreply, run(socket, :cart, &Cart.remove(&1, %{item_id: int(id)}))}

  def handle_event("save_for_later", %{"item-id" => id}, socket),
    do: {:noreply, run(socket, :cart, &Cart.save_for_later(&1, %{item_id: int(id)}))}

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, socket),
    do: {:noreply, run(socket, :cart, &Cart.toggle_gift_wrap(&1, %{item_id: int(id)}))}

  def handle_event("toggle_wishlist", %{"item-id" => id}, socket),
    do: {:noreply, run(socket, :cart, &Cart.line(&1, %{item_id: int(id)}))}

  def handle_event("select_shipping", %{"method" => m}, socket),
    do:
      {:noreply,
       run(socket, :cart, &Cart.select_shipping(&1, %{method: String.to_existing_atom(m)}))}

  def handle_event("apply_promo", %{"code" => code}, socket),
    do: {:noreply, run(socket, :cart, &Cart.apply_promo(&1, %{code: code}))}

  def handle_event("start_checkout", _params, socket),
    do: {:noreply, run(socket, :cart, &Cart.start_checkout(&1, nil))}

  def handle_event("pay", _params, socket),
    do: {:noreply, run(socket, :cart, &Cart.request_checkout(&1, nil))}

  def handle_event("undo_remove", _params, socket),
    do: {:noreply, run(socket, :undo, &Undo.restore(&1, nil))}

  def handle_event("move_to_cart", %{"item-id" => id}, socket),
    do: {:noreply, run(socket, :saved, &SavedItems.move_to_cart(&1, %{item_id: int(id)}))}

  def handle_event("remove_wishlist", %{"product-id" => id}, socket),
    do: {:noreply, run(socket, :wishlist, &Wishlist.remove(&1, %{product_id: int(id)}))}

  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, socket),
    do: {:noreply, run(socket, :wishlist, &Wishlist.take(&1, %{product_id: int(id)}))}

  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do: {:noreply, run(socket, :ui, &PageUI.switch_tab(&1, %{tab: String.to_existing_atom(tab)}))}

  def handle_event("validate_address", %{"address" => params}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.validate(&1, params))}

  def handle_event("submit_address", %{"address" => params}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.submit_address(&1, params))}

  def handle_event("edit_address", _params, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.edit_address(&1, nil))}

  @impl true
  def handle_async(:payment, {:ok, {:ok, reference}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.succeeded(&1, reference))}

  def handle_async(:payment, {:ok, {:error, reason}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  def handle_async(:payment, {:exit, reason}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  @impl true
  def handle_info({:timer, :undo, %{id: id}}, socket),
    do: {:noreply, run(socket, :undo, &Undo.expire(&1, id))}

  def handle_info({:stock_changed, {product_id, stock}}, socket),
    do:
      {:noreply, run(socket, :cart, &Cart.set_stock(&1, %{product_id: product_id, stock: stock}))}

  # the topic also carries catalogue edits, which this page doesn't show
  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}
  def handle_info({:product_updated, _product}, socket), do: {:noreply, socket}

  defp run(socket, key, step), do: Steps.run(socket, key, step, &wire/3)
  defp int(s), do: String.to_integer(s)

  # {feature, port} → where it wires on this page
  defp wire(s, :cart, {:rows, change}), do: Steps.stream_change(s, :cart_items, change)
  defp wire(s, :cart, {:summary, summary}), do: assign(s, :summary, summary)

  defp wire(s, :cart, {:changed, change}) do
    Carts.apply_change(change)
    s
  end

  defp wire(s, :cart, {:removed, item}), do: run(s, :undo, &Undo.capture(&1, item))

  defp wire(s, :cart, {:saved, item}),
    do: s |> run(:saved, &SavedItems.stash(&1, item)) |> put_flash(:info, "Saved for later")

  defp wire(s, :cart, {:line, line}), do: run(s, :wishlist, &Wishlist.toggle(&1, line))

  defp wire(s, :cart, {:promo_applied, _code}),
    do: s |> assign(:promo_error, nil) |> put_flash(:info, "Promo applied!")

  defp wire(s, :cart, {:promo_rejected, _code}),
    do: s |> assign(:promo_error, "Invalid promo code") |> put_flash(:error, "Invalid promo code")

  defp wire(s, :cart, {:checkout_started, summary}),
    do: run(s, :checkout, &Checkout.start(&1, summary))

  defp wire(s, :cart, {:checkout_requested, cart}), do: run(s, :checkout, &Checkout.pay(&1, cart))

  defp wire(s, :undo, {:captured, item}),
    do:
      s |> assign(:undo_pending, true) |> Steps.start_timer(:undo, item, Catalog.undo_window_ms())

  defp wire(s, :undo, {:restored, item}),
    do:
      s
      |> Steps.stop_timer(:undo)
      |> assign(:undo_pending, false)
      |> run(:cart, &Cart.receive(&1, item))
      |> put_flash(:info, "Item restored")

  defp wire(s, :undo, {:expired, item_id}),
    do: s |> assign(:undo_pending, false) |> run(:cart, &Cart.confirm_removal(&1, item_id))

  defp wire(s, :saved, {:rows, change}), do: Steps.stream_change(s, :saved_items, change)
  defp wire(s, :saved, {:count, count}), do: assign(s, :saved_count, count)

  defp wire(s, :saved, {:moved, item}),
    do: s |> run(:cart, &Cart.receive(&1, item)) |> put_flash(:info, "Moved to cart")

  defp wire(s, :wishlist, {:rows, change}), do: Steps.stream_change(s, :wishlist_products, change)
  defp wire(s, :wishlist, {:count, count}), do: assign(s, :wishlist_count, count)
  defp wire(s, :wishlist, {:ids, ids}), do: assign(s, :wishlist_ids, ids)
  defp wire(s, :wishlist, {:added, _product}), do: put_flash(s, :info, "Added to wishlist")
  defp wire(s, :wishlist, {:dropped, _product}), do: put_flash(s, :info, "Removed from wishlist")

  defp wire(s, :wishlist, {:taken, product}),
    do:
      s
      |> Steps.feed(
        :cart,
        &Cart.receive/2,
        &AddLine.run(s.assigns.add_line, &1),
        product,
        &wire/3
      )
      |> put_flash(:info, "Added to cart")

  defp wire(s, :ui, {:tab, tab}), do: assign(s, :active_tab, tab)

  defp wire(s, :checkout, {:step, step}),
    do: s |> assign(:step, step) |> Steps.patch(@step_paths, step)

  defp wire(s, :checkout, {:form, changeset}),
    do: assign(s, :address_form, to_form(changeset, action: :validate))

  defp wire(s, :checkout, {:address, address}), do: assign(s, :address, address)
  defp wire(s, :checkout, {:blocked, reason}), do: put_flash(s, :error, @blocked[reason])

  # the payment runs as a LiveView task; handle_async/3 below routes its outcome
  defp wire(s, :checkout, {:ready_to_pay, payment}) do
    charge = s.assigns.charge
    start_async(s, :payment, fn -> Charge.call(charge, payment) end)
  end

  defp wire(s, :checkout, {:done, reference}) do
    SettleOrder.run(s.assigns.settle, reference)
    push_navigate(s, to: ~p"/cart/success")
  end

  @impl true
  def render(%{live_action: :checkout} = assigns) do
    ~H"""
    <div class="mx-auto max-w-lg">
      <.link navigate={~p"/cart"} class="text-sm font-medium text-stone-500 hover:text-stone-800">
        {@texts.checkout.back}
      </.link>
      <h1 class="py-4 text-3xl font-semibold tracking-tight">{@texts.checkout.heading}</h1>
      <.milestones
        step={@step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.card>
        <.only_on current={@step} name={:address}>
          <.simple_form for={@address_form} phx-change="validate_address" phx-submit="submit_address">
            <.input
              field={@address_form[:name]}
              label={@texts.checkout.name}
              phx-hook="AutoFocus"
              id="address_name"
            />
            <.input field={@address_form[:line1]} label={@texts.checkout.line1} />
            <.input field={@address_form[:city]} label={@texts.checkout.city} />
            <.input field={@address_form[:postal_code]} label={@texts.checkout.postal_code} />
            <:actions>
              <.button phx-disable-with={@texts.checkout.saving}>{@texts.checkout.continue}</.button>
            </:actions>
          </.simple_form>
        </.only_on>
        <.only_on current={@step} name={:payment}>
          <div class="space-y-4">
            <div class="rounded-xl bg-stone-50 p-4 text-sm text-stone-700">
              <div class="font-medium">{@address.name}</div>
              <div>{@address.line1}</div>
              <div>{@address.city}, {@address.postal_code}</div>
            </div>
            <div class="flex justify-between border-t border-stone-200 pt-4 text-lg font-semibold">
              <span>{@texts.checkout.total}</span><span>{@summary.total}</span>
            </div>
            <div class="flex items-center justify-between gap-3">
              <button
                phx-click="edit_address"
                class="text-sm font-medium text-stone-500 hover:text-stone-800"
              >
                {@texts.checkout.edit_address}
              </button>
              <.primary_button event="pay">{@texts.checkout.pay} {@summary.total}</.primary_button>
            </div>
          </div>
        </.only_on>
        <.only_on current={@step} name={:processing}>
          <div class="flex items-center gap-3 py-6 text-stone-500">
            <svg class="h-5 w-5 animate-spin text-brand-700" viewBox="0 0 24 24" fill="none">
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
            {@texts.checkout.processing}
          </div>
        </.only_on>
        <.only_on current={@step} name={:error}>
          <div class="space-y-3">
            <p class="rounded-xl bg-red-50 p-4 text-sm text-red-700">
              {@texts.checkout.payment_failed}
            </p>
            <.primary_button event="pay">{@texts.checkout.try_again}</.primary_button>
          </div>
        </.only_on>
        <.only_on current={@step} name={:complete}>
          <p class="py-6 text-stone-500">{@texts.checkout.redirecting}</p>
        </.only_on>
      </.card>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="pb-6 text-3xl font-semibold tracking-tight">Your Cart</h1>
      <.notice
        shown={@undo_pending}
        text={@texts.undo.text}
        action={@texts.undo.undo}
        event="undo_remove"
      />
      <div class="grid items-start gap-8 lg:grid-cols-[1fr_22rem]">
        <.card>
          <.tabs current={@active_tab} event="switch_tab">
            <:tab name={:items} label={"#{@texts.tabs.items} (#{@summary.item_count})"} />
            <:tab name={:saved} label={"#{@texts.tabs.saved} (#{@saved_count})"} />
            <:tab name={:wishlist} label={"#{@texts.tabs.wishlist} (#{@wishlist_count})"} />
          </.tabs>

          <.pane current={@active_tab} name={:items}>
            <.stream_list :let={{dom_id, row}} id="cart_items" stream={@streams.cart_items}>
              <.cart_item_row
                id={dom_id}
                row={row}
                wishlist_ids={@wishlist_ids}
                gift_wrap_label={@texts.cart.gift_wrap_label}
                t={@texts.cart.row}
                on_quantity="update_quantity"
                on_remove="remove_item"
                on_gift_wrap="toggle_gift_wrap"
                on_save="save_for_later"
                on_wishlist="toggle_wishlist"
              />
            </.stream_list>
            <.none count={@summary.item_count} text={@texts.cart.empty} />
          </.pane>

          <.pane current={@active_tab} name={:saved}>
            <.stream_list :let={{dom_id, row}} id="saved_items" stream={@streams.saved_items}>
              <.saved_row id={dom_id} row={row} t={@texts.saved.row} on_move="move_to_cart" />
            </.stream_list>
            <.none count={@saved_count} text={@texts.saved.empty} />
          </.pane>

          <.pane current={@active_tab} name={:wishlist}>
            <.stream_list
              :let={{dom_id, row}}
              id="wishlist_products"
              stream={@streams.wishlist_products}
            >
              <.wishlist_row
                id={dom_id}
                row={row}
                t={@texts.wishlist.row}
                on_add="add_wishlisted_to_cart"
                on_remove="remove_wishlist"
              />
            </.stream_list>
            <.none count={@wishlist_count} text={@texts.wishlist.empty} />
          </.pane>
        </.card>

        <.card class="lg:sticky lg:top-24">
          <.cart_summary summary={@summary} t={@texts.cart} />
          <.shipping_selector
            summary={@summary}
            heading={@texts.cart.shipping}
            free_over={@texts.cart.free_over}
            event="select_shipping"
          />
          <.promo_form
            code={@summary.promo_code}
            error={@promo_error}
            event="apply_promo"
            t={@texts.cart}
          />
          <.primary_button event="start_checkout" disabled={@summary.empty?} class="mt-6 w-full">
            {@texts.cart.checkout} · {@summary.total}
          </.primary_button>
        </.card>
      </div>
    </div>
    """
  end
end
