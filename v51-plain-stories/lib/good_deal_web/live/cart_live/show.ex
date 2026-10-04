defmodule GoodDealWeb.CartLive.Show do
  @moduledoc """
  The cart page and its checkout steps, as a plain LiveView composing five user stories (Spray's
  Features layer). Its configuration is at the top: the store's words and rules, the instances that
  carry app-level choices, and the names of the timer and task the stories start. Each browser event
  goes to the story whose view fires it; each story output wires through one `wire/3` clause, so
  those clauses are the page's wiring between stories, read top to bottom. A story's own parts are
  wired inside it. A test checks every declared port and event has a clause.
  """
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDeal.Components.{Panes, Parts}

  alias GoodDeal.Catalog

  alias GoodDeal.Domain.{
    BuildLineItems,
    CalculateGiftWrapCost,
    CalculateShipping,
    Charge,
    SettleOrder,
    StockStatus,
    ValidatePromo
  }

  alias GoodDeal.State.PageUI
  alias GoodDeal.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}
  alias GoodDealWeb.{CartSession, CheckoutMetadata}
  alias GoodDealWeb.Paradigms.Steps
  alias GoodDealWeb.Stories.{CheckOut, EditCart, KeepWishlist, SaveForLater, UndoRemoval}

  @steps_by_url %{"payment" => :payment}
  @milestones [address: "Address", payment: "Payment"]
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

  @doc "Which story or state each `wire/3` key names, so a test can check every declared port has a clause."
  @parts %{
    edit_cart: EditCart,
    undo: UndoRemoval,
    saved: SaveForLater,
    wishlist: KeepWishlist,
    check_out: CheckOut,
    ui: PageUI
  }
  def parts, do: @parts

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session)

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      stock_status: StockStatus.new(low_at: Catalog.low_stock_threshold()),
      promo: ValidatePromo.new(Catalog.promo_codes()),
      gift_wrap: CalculateGiftWrapCost.new(Catalog.gift_wrap_cents())
    }

    payment = [
      line_items: BuildLineItems.new(currency: Catalog.currency()),
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
    ]

    {:ok,
     socket
     |> assign(
       texts: texts(),
       milestones: @milestones,
       ui: PageUI.new(tabs: [:items, :saved, :wishlist]),
       active_tab: :items,
       saved_count: 0,
       wishlist_count: 0,
       wishlist_ids: [],
       promo_error: nil,
       undo_pending: false,
       step: :address,
       address: nil
     )
     |> UndoRemoval.mount([timer: :undo, window_ms: Catalog.undo_window_ms()], out(:undo))
     |> SaveForLater.mount([], out(:saved))
     |> KeepWishlist.mount([], out(:wishlist))
     |> EditCart.mount([cart_id: cart_id, pricing: pricing], out(:edit_cart))
     |> CheckOut.mount([task: :payment] ++ payment, out(:check_out))}
  end

  # the URL names a checkout step (browser back, a reload); the story decides whether to honour it
  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket),
    do:
      {:noreply, to(socket, :check_out, :goto, Map.get(@steps_by_url, params["step"], :address))}

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @edit_cart_events EditCart.events()
  @undo_events UndoRemoval.events()
  @saved_events SaveForLater.events()
  @wishlist_events KeepWishlist.events()
  @check_out_events CheckOut.events()

  # each story handles the events its own view fires
  @impl true
  def handle_event(event, params, socket) when event in @edit_cart_events,
    do: {:noreply, EditCart.handle_event(event, params, socket, out(:edit_cart))}

  def handle_event(event, params, socket) when event in @undo_events,
    do: {:noreply, UndoRemoval.handle_event(event, params, socket, out(:undo))}

  def handle_event(event, params, socket) when event in @saved_events,
    do: {:noreply, SaveForLater.handle_event(event, params, socket, out(:saved))}

  def handle_event(event, params, socket) when event in @wishlist_events,
    do: {:noreply, KeepWishlist.handle_event(event, params, socket, out(:wishlist))}

  def handle_event(event, params, socket) when event in @check_out_events,
    do: {:noreply, CheckOut.handle_event(event, params, socket, out(:check_out))}

  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do: {:noreply, run(socket, :ui, &PageUI.switch_tab(&1, %{tab: String.to_existing_atom(tab)}))}

  @impl true
  def handle_async(:payment, {:ok, {:ok, reference}}, socket),
    do: {:noreply, to(socket, :check_out, :succeeded, reference)}

  def handle_async(:payment, {:ok, {:error, reason}}, socket),
    do: {:noreply, to(socket, :check_out, :failed, reason)}

  def handle_async(:payment, {:exit, reason}, socket),
    do: {:noreply, to(socket, :check_out, :failed, reason)}

  @impl true
  def handle_info({:timer, :undo, item}, socket), do: {:noreply, to(socket, :undo, :expire, item)}

  def handle_info({:stock_changed, {product_id, stock}}, socket),
    do: {:noreply, to(socket, :edit_cart, :stock, %{product_id: product_id, stock: stock})}

  # the topic also carries catalogue edits, which this page doesn't show
  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}
  def handle_info({:product_updated, _product}, socket), do: {:noreply, socket}

  defp to(socket, key, port, payload), do: @parts[key].input(socket, port, payload, out(key))
  defp out(key), do: &wire(&1, key, &2)
  defp run(socket, key, step), do: Steps.run(socket, key, step, &wire/3)

  # {story, port} → where it wires on this page
  defp wire(s, :edit_cart, {:summary, summary}), do: assign(s, :summary, summary)
  defp wire(s, :edit_cart, {:promo_error, message}), do: assign(s, :promo_error, message)
  defp wire(s, :edit_cart, {:removed, item}), do: to(s, :undo, :capture, item)

  defp wire(s, :edit_cart, {:saved, item}),
    do: s |> to(:saved, :stash, item) |> put_flash(:info, "Saved for later")

  defp wire(s, :edit_cart, {:line, line}), do: to(s, :wishlist, :toggle, line)

  defp wire(s, :edit_cart, {:checkout_started, summary}),
    do: to(s, :check_out, :start, summary)

  defp wire(s, :edit_cart, {:checkout_requested, request}), do: to(s, :check_out, :pay, request)

  defp wire(s, :undo, {:pending, pending}), do: assign(s, :undo_pending, pending)

  defp wire(s, :undo, {:restored, item}),
    do: s |> to(:edit_cart, :receive, item) |> put_flash(:info, "Item restored")

  defp wire(s, :undo, {:expired, item_id}), do: to(s, :edit_cart, :confirm_removal, item_id)

  defp wire(s, :saved, {:count, count}), do: assign(s, :saved_count, count)

  defp wire(s, :saved, {:moved, item}),
    do: s |> to(:edit_cart, :receive, item) |> put_flash(:info, "Moved to cart")

  defp wire(s, :wishlist, {:count, count}), do: assign(s, :wishlist_count, count)
  defp wire(s, :wishlist, {:ids, ids}), do: assign(s, :wishlist_ids, ids)

  defp wire(s, :wishlist, {:taken, product}),
    do: s |> to(:edit_cart, :add_product, product) |> put_flash(:info, "Added to cart")

  defp wire(s, :ui, {:tab, tab}), do: assign(s, :active_tab, tab)
  defp wire(s, :check_out, {:step, step}), do: assign(s, :step, step)

  defp wire(s, :check_out, {:form, changeset}),
    do: assign(s, :address_form, to_form(changeset, action: :validate))

  defp wire(s, :check_out, {:address, address}), do: assign(s, :address, address)
  defp wire(s, :check_out, {:pay_requested, _}), do: to(s, :edit_cart, :request_checkout, nil)

  @impl true
  def render(%{live_action: :checkout} = assigns) do
    ~H"""
    <CheckOut.view
      step={@step}
      milestones={@milestones}
      form={@address_form}
      address={@address}
      total={@summary.total}
      t={@texts.checkout}
    />
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="pb-6 text-3xl font-semibold tracking-tight">Your Cart</h1>
      <UndoRemoval.view pending={@undo_pending} t={@texts.undo} />
      <div class="grid items-start gap-8 lg:grid-cols-[1fr_22rem]">
        <.card>
          <.tabs current={@active_tab} event="switch_tab">
            <:tab name={:items} label={"#{@texts.tabs.items} (#{@summary.item_count})"} />
            <:tab name={:saved} label={"#{@texts.tabs.saved} (#{@saved_count})"} />
            <:tab name={:wishlist} label={"#{@texts.tabs.wishlist} (#{@wishlist_count})"} />
          </.tabs>
          <.pane current={@active_tab} name={:items}>
            <EditCart.rows
              streams={@streams}
              summary={@summary}
              wishlist_ids={@wishlist_ids}
              t={@texts.cart}
            />
          </.pane>
          <.pane current={@active_tab} name={:saved}>
            <SaveForLater.view streams={@streams} count={@saved_count} t={@texts.saved} />
          </.pane>
          <.pane current={@active_tab} name={:wishlist}>
            <KeepWishlist.view streams={@streams} count={@wishlist_count} t={@texts.wishlist} />
          </.pane>
        </.card>
        <.card class="lg:sticky lg:top-24">
          <EditCart.totals summary={@summary} promo_error={@promo_error} t={@texts.cart} />
        </.card>
      </div>
    </div>
    """
  end
end
