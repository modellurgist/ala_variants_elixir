defmodule GoodDealWeb.CartLive.Show do
  @moduledoc """
  The cart page and its checkout steps. It wires the story the portal places too (drafting the
  order: its lines, undo and stock), one `wire/3` clause per output; what only this page uses (the totals and promo code, the saved items, the wishlist, the checkout flow) it holds and
  calls, using what each call answers. Its configuration is at the top: the store's words and rules,
  the checkout flow, and the instances that carry app-level choices.
  """
  use GoodDealWeb, :live_view
  import GoodDeal.Components.{Panes, Parts}

  import GoodDeal.Components.Rows,
    only: [cart_item_row: 1, milestones: 1, saved_row: 1, wishlist_row: 1]

  alias GoodDeal.Catalog

  alias GoodDeal.Domain.{
    BuildLineItems,
    CalculateShipping,
    Charge,
    SettleOrder,
    StockStatus
  }

  alias GoodDeal.State.{CartTotals, Checkout, PageUI, Promo, SavedItems, Wishlist}
  alias GoodDeal.Foundation.{Carts, LedgerGateway, Orders, Products}
  alias GoodDealWeb.{CartSession, CheckoutMetadata}
  alias GoodDealWeb.Paradigms.{ChangeFeed, Steps}
  alias GoodDealWeb.Stories.{DraftOrder, EditLines, UndoRemoval}

  @steps_by_url %{"payment" => :payment}
  @milestones [address: "Address", payment: "Payment"]
  @flow [
    {:address, :submit_address, :payment},
    {:payment, :edit_address, :address},
    {:payment, :pay, :processing},
    {:error, :pay, :processing}
  ]
  @url_edges [{:payment, :address}]
  @step_paths %{address: "/cart/checkout", payment: "/cart/checkout/payment"}
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

  @doc "Which story each `wire/3` key names, so a test can check every declared port has a clause."
  @parts %{draft: DraftOrder}
  def parts, do: @parts

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session)
    stock_status = StockStatus.new(low_at: Catalog.low_stock_threshold())

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      gift_wrap: &(&1 * Catalog.gift_wrap_cents())
    }

    checkout =
      Checkout.new(
        flow: @flow,
        start: :address,
        url_edges: @url_edges,
        stock_levels: &Products.stock_levels/1,
        line_items: BuildLineItems.new(currency: Catalog.currency()),
        messages: %{postal_code: "must be 4–10 digits"}
      )

    saved = SavedItems.new(items: Carts.list_saved(cart_id))

    {:ok,
     socket
     |> assign(
       texts: texts(),
       milestones: @milestones,
       ui: PageUI.new(tabs: [:items, :saved, :wishlist]),
       promo: Promo.new(codes: &validate_promo/1),
       promo_error: nil,
       totals: CartTotals.new(pricing: pricing),
       saved: saved,
       wishlist: Wishlist.new([]),
       undo_pending: false,
       checkout: checkout,
       charge: %Charge{
         gateway: Application.get_env(:good_deal, :payment_gateway, LedgerGateway),
         metadata: &CheckoutMetadata.for_cart/1
       },
       settle: %SettleOrder{
         orders: Orders,
         carts: Carts,
         products: Products,
         announce: &ChangeFeed.publish([topic: Catalog.changes_topic(), facts: [:stock]], &1),
         cart_id: cart_id
       }
     )
     |> address_form(Checkout.address_form(checkout))
     |> stream(:saved_items, SavedItems.rows(saved))
     |> stream(:wishlist_products, [])
     |> DraftOrder.mount(
       [
         cart_id: cart_id,
         stock_status: stock_status,
         stream: :cart_items,
         timer: :undo,
         window_ms: Catalog.undo_window_ms(),
         changes: Catalog.changes_topic()
       ],
       out(:draft)
     )}
  end

  # the store's promo codes, looked up in normal form
  defp validate_promo(code) when is_binary(code) do
    case Map.get(Catalog.promo_codes(), String.upcase(String.trim(code))) do
      nil -> {:error, :invalid_code}
      pct -> {:ok, pct}
    end
  end

  defp validate_promo(_code), do: {:error, :invalid_code}

  # the URL names a checkout step (browser back, a reload); the flow decides whether to honour it
  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket) do
    step = Map.get(@steps_by_url, params["step"], :address)
    {:noreply, checkout(socket, Checkout.goto(socket.assigns.checkout, step))}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @draft_events DraftOrder.events()

  @impl true
  def handle_event(event, params, socket) when event in @draft_events,
    do: {:noreply, DraftOrder.handle_event(event, params, socket, out(:draft))}

  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do:
      {:noreply,
       assign(socket, :ui, PageUI.switch_tab(socket.assigns.ui, String.to_existing_atom(tab)))}

  def handle_event("select_shipping", %{"method" => m}, socket),
    do:
      {:noreply,
       price(
         socket,
         CartTotals.select_shipping(socket.assigns.totals, String.to_existing_atom(m))
       )}

  def handle_event("apply_promo", %{"code" => code}, socket) do
    case Promo.enter(socket.assigns.promo, code) do
      {:ok, discount} ->
        {:noreply,
         socket
         |> price(CartTotals.discount(socket.assigns.totals, discount))
         |> assign(:promo_error, nil)
         |> put_flash(:info, "Promo applied!")}

      :error ->
        {:noreply,
         socket
         |> assign(:promo_error, "Invalid promo code")
         |> put_flash(:error, "Invalid promo code")}
    end
  end

  def handle_event("move_to_cart", %{"item-id" => id}, socket) do
    case SavedItems.move_to_cart(socket.assigns.saved, String.to_integer(id)) do
      {_saved, nil} ->
        {:noreply, socket}

      {saved, item} ->
        {:noreply,
         socket
         |> assign(:saved, saved)
         |> stream_delete(:saved_items, SavedItems.row(item))
         |> to(:draft, :receive, item)
         |> put_flash(:info, "Moved to cart")}
    end
  end

  def handle_event("remove_wishlist", %{"product-id" => id}, socket) do
    {wishlist, product} = Wishlist.remove(socket.assigns.wishlist, String.to_integer(id))
    {:noreply, if(product, do: wishlist(socket, wishlist, {:removed, product}), else: socket)}
  end

  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, socket) do
    case Wishlist.remove(socket.assigns.wishlist, String.to_integer(id)) do
      {_wishlist, nil} ->
        {:noreply, socket}

      {wishlist, product} ->
        {:noreply,
         socket
         |> wishlist(wishlist, {:removed, product})
         |> to(:draft, :add_product, product)
         |> put_flash(:info, "Added to cart")}
    end
  end

  def handle_event("start_checkout", _params, socket) do
    case Checkout.start(socket.assigns.checkout, socket.assigns.summary) do
      {:ok, checkout} ->
        {:noreply,
         socket
         |> assign(:checkout, checkout)
         |> Steps.patch(@step_paths, checkout.step)
         |> address_form(Checkout.address_form(checkout))}

      {:blocked, reason} ->
        {:noreply, put_flash(socket, :error, @blocked[reason])}
    end
  end

  def handle_event("validate_address", %{"address" => params}, socket),
    do: {:noreply, address_form(socket, Checkout.address_form(socket.assigns.checkout, params))}

  def handle_event("submit_address", %{"address" => params}, socket) do
    case Checkout.submit_address(socket.assigns.checkout, params) do
      {:ok, checkout} -> {:noreply, checkout(socket, checkout)}
      {:error, changeset} -> {:noreply, address_form(socket, changeset)}
    end
  end

  def handle_event("edit_address", _params, socket),
    do: {:noreply, checkout(socket, Checkout.edit_address(socket.assigns.checkout))}

  # paying needs the lines as stored; they answer on `checkout_requested`
  def handle_event("pay", _params, socket),
    do: {:noreply, to(socket, :draft, :request_checkout, nil)}

  @impl true
  def handle_async(:payment, {:ok, {:ok, reference}}, socket) do
    SettleOrder.run(socket.assigns.settle, reference)

    {:noreply,
     socket
     |> checkout(Checkout.succeeded(socket.assigns.checkout))
     |> push_navigate(to: ~p"/cart/success")}
  end

  def handle_async(:payment, {:ok, {:error, _reason}}, socket),
    do: {:noreply, checkout(socket, Checkout.failed(socket.assigns.checkout))}

  def handle_async(:payment, {:exit, _reason}, socket),
    do: {:noreply, checkout(socket, Checkout.failed(socket.assigns.checkout))}

  @impl true
  def handle_info({:timer, :undo, item}, socket),
    do: {:noreply, to(socket, :draft, :expire, item)}

  defp to(socket, key, port, payload),
    do: Steps.to(socket, __MODULE__, @parts, key, port, payload, out(key))

  defp out(key), do: fn s, output -> Steps.out(s, __MODULE__, key, output, &wire/3) end

  # {story, port} → where it wires on this page
  defp wire(s, :draft, {:contents, contents}),
    do: price(s, CartTotals.contents(s.assigns.totals, contents))

  defp wire(s, :draft, {:saved, item}),
    do:
      s
      |> assign(:saved, SavedItems.stash(s.assigns.saved, item))
      |> stream_insert(:saved_items, SavedItems.row(item))
      |> put_flash(:info, "Saved for later")

  defp wire(s, :draft, {:line, line}) do
    case Wishlist.toggle(s.assigns.wishlist, line) do
      {wishlist, nil} ->
        assign(s, :wishlist, wishlist)

      {wishlist, {:added, _} = change} ->
        s |> wishlist(wishlist, change) |> put_flash(:info, "Added to wishlist")

      {wishlist, change} ->
        s |> wishlist(wishlist, change) |> put_flash(:info, "Removed from wishlist")
    end
  end

  defp wire(s, :draft, {:checkout_requested, request}) do
    case Checkout.pay(s.assigns.checkout, request) do
      {:ok, checkout, payment} ->
        charge = s.assigns.charge
        s |> checkout(checkout) |> start_async(:payment, fn -> Charge.call(charge, payment) end)

      {:blocked, reason} ->
        put_flash(s, :error, @blocked[reason])
    end
  end

  defp wire(s, :draft, {:pending, pending}), do: assign(s, :undo_pending, pending)
  defp wire(s, :draft, {:restored, _item}), do: put_flash(s, :info, "Item restored")
  # stock shows only on the lines, which the draft has already updated
  defp wire(s, :draft, {:stock, _change}), do: s

  defp price(s, totals), do: assign(s, totals: totals, summary: CartTotals.summary(totals))

  defp address_form(s, changeset),
    do: assign(s, :address_form, to_form(changeset, action: :validate))

  # a checkout that moved shows its new step, at its URL when the step has one
  defp checkout(s, checkout) do
    s =
      if checkout.step == s.assigns.checkout.step,
        do: s,
        else: Steps.patch(s, @step_paths, checkout.step)

    assign(s, :checkout, checkout)
  end

  defp wishlist(s, wishlist, {change, product}),
    do:
      s
      |> assign(:wishlist, wishlist)
      |> Steps.stream_change(:wishlist_products, {change, Wishlist.row(product)})

  @impl true
  def render(%{live_action: :checkout} = assigns) do
    ~H"""
    <div class="mx-auto max-w-lg">
      <.link navigate={~p"/cart"} class="text-sm font-medium text-stone-500 hover:text-stone-800">
        {@texts.checkout.back}
      </.link>
      <h1 class="py-4 text-3xl font-semibold tracking-tight">{@texts.checkout.heading}</h1>
      <.milestones
        step={@checkout.step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.card>
        <.only_on current={@checkout.step} name={:address}>
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
        <.only_on current={@checkout.step} name={:payment}>
          <div class="space-y-4">
            <div class="rounded-xl bg-stone-50 p-4 text-sm text-stone-700">
              <div class="font-medium">{@checkout.address.name}</div>
              <div>{@checkout.address.line1}</div>
              <div>{@checkout.address.city}, {@checkout.address.postal_code}</div>
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
        <.only_on current={@checkout.step} name={:processing}>
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
        <.only_on current={@checkout.step} name={:error}>
          <div class="space-y-3">
            <p class="rounded-xl bg-red-50 p-4 text-sm text-red-700">
              {@texts.checkout.payment_failed}
            </p>
            <.primary_button event="pay">{@texts.checkout.try_again}</.primary_button>
          </div>
        </.only_on>
        <.only_on current={@checkout.step} name={:complete}>
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
      <UndoRemoval.view pending={@undo_pending} t={@texts.undo} />
      <div class="grid items-start gap-8 lg:grid-cols-[1fr_22rem]">
        <.card>
          <.tabs current={@ui.active_tab} event="switch_tab">
            <:tab name={:items} label={"#{@texts.tabs.items} (#{@summary.item_count})"} />
            <:tab name={:saved} label={"#{@texts.tabs.saved} (#{SavedItems.count(@saved)})"} />
            <:tab
              name={:wishlist}
              label={"#{@texts.tabs.wishlist} (#{Wishlist.count(@wishlist)})"}
            />
          </.tabs>
          <.pane current={@ui.active_tab} name={:items}>
            <EditLines.rows
              streams={@streams}
              stream={:cart_items}
              row={&cart_item_row/1}
              row_attrs={
                %{
                  wishlist_ids: Wishlist.ids(@wishlist),
                  gift_wrap_label: @texts.cart.gift_wrap_label,
                  t: @texts.cart.row
                }
              }
              count={@summary.item_count}
              empty={@texts.cart.empty}
            />
          </.pane>
          <.pane current={@ui.active_tab} name={:saved}>
            <.stream_list :let={{dom_id, row}} id="saved_items" stream={@streams.saved_items}>
              <.saved_row id={dom_id} row={row} t={@texts.saved.row} on_move="move_to_cart" />
            </.stream_list>
            <.none count={SavedItems.count(@saved)} text={@texts.saved.empty} />
          </.pane>
          <.pane current={@ui.active_tab} name={:wishlist}>
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
            <.none count={Wishlist.count(@wishlist)} text={@texts.wishlist.empty} />
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
