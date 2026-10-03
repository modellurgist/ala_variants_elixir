defmodule GoodDealWeb.CartLive.Show do
  @moduledoc """
  The cart page and its checkout steps, as a composition of user stories (Spray's features, §2.2):
  editing the cart, undoing a removal, saving for later, keeping a wishlist, and checking out. Its
  configuration is at the top: the store's words and rules, and each story built from them. Its
  `wire/3` clauses connect one story's outputs to another's inputs, one clause per output port; each
  story wires its own parts inside it. Browser events go to the story whose view emits them.
  """
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDeal.Components.Panes, only: [pane: 1, tabs: 1]
  import GoodDeal.Components.Parts, only: [card: 1]

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

  alias GoodDeal.State.PageUI
  alias GoodDeal.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}
  alias GoodDealWeb.{CartSession, CheckoutMetadata}
  alias GoodDealWeb.Paradigms.{Steps, Story}
  alias GoodDealWeb.Stories.{CheckOut, EditCart, KeepWishlist, SaveForLater, UndoRemoval}

  @checkout_flow [
    {:address, :submit_address, :payment},
    {:payment, :edit_address, :address},
    {:payment, :pay, :processing},
    {:error, :pay, :processing}
  ]
  @checkout_url_edges [{:payment, :address}]
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

  @doc "Which story (or page value) each `wire/3` key names, so a test can check every output port has a clause."
  @features %{
    edit_cart: EditCart,
    undo: UndoRemoval,
    saved: SaveForLater,
    wishlist: KeepWishlist,
    check_out: CheckOut,
    ui: PageUI
  }
  def features, do: @features

  @stories [:edit_cart, :undo, :saved, :wishlist, :check_out]

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session)

    pricing = %{
      shipping: CalculateShipping.new(Catalog.rates()),
      stock_status: StockStatus.new(low_at: Catalog.low_stock_threshold()),
      promo: ValidatePromo.new(Catalog.promo_codes()),
      gift_wrap: CalculateGiftWrapCost.new(Catalog.gift_wrap_cents())
    }

    stories = %{
      edit_cart: EditCart.new(cart_id: cart_id, pricing: pricing),
      undo: UndoRemoval.new(window_ms: Catalog.undo_window_ms()),
      saved: SaveForLater.new(),
      wishlist:
        KeepWishlist.new(add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id}),
      check_out:
        CheckOut.new(
          checkout: [
            flow: @checkout_flow,
            start: :address,
            url_edges: @checkout_url_edges,
            stock_levels: &Products.stock_levels/1,
            line_items: BuildLineItems.new(currency: Catalog.currency()),
            messages: %{postal_code: "must be 4–10 digits"}
          ],
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
          },
          milestones: @milestones
        )
    }

    {:ok,
     socket
     |> assign(
       texts: texts(),
       ui: PageUI.new(tabs: [:items, :saved, :wishlist]),
       active_tab: :items,
       summary: nil,
       saved_count: 0,
       wishlist_count: 0
     )
     |> Story.mount(stories, &wire/3)
     |> Story.input(:edit_cart, :mounted, cart_id)
     |> Story.input(:check_out, :mounted, nil)}
  end

  # the URL names a checkout step (browser back, a reload); the story decides whether to honour it
  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket),
    do:
      {:noreply,
       Story.input(socket, :check_out, :goto, Map.get(@steps_by_url, params["step"], :address))}

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do:
      {:noreply,
       Steps.run(
         socket,
         :ui,
         &PageUI.switch_tab(&1, %{tab: String.to_existing_atom(tab)}),
         &wire/3
       )}

  def handle_event(name, params, socket),
    do: {:noreply, Story.event(socket, @stories, name, params)}

  # a story's task reports its outcome to its own inputs
  @impl true
  def handle_async({:story_async, _, _, _} = task, result, socket),
    do: {:noreply, Story.async_result(socket, task, result)}

  @impl true
  # a story's timer reports to one of its own inputs
  def handle_info({:story_input, key, port, payload}, socket),
    do: {:noreply, Story.input(socket, key, port, payload)}

  def handle_info({:stock_changed, {product_id, stock}}, socket),
    do:
      {:noreply, Story.input(socket, :edit_cart, :stock, %{product_id: product_id, stock: stock})}

  # the topic also carries catalogue edits, which this page doesn't show
  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}
  def handle_info({:product_updated, _product}, socket), do: {:noreply, socket}

  # {story, port} → where it wires on this page
  defp wire(s, :ui, {:tab, tab}), do: assign(s, :active_tab, tab)

  defp wire(s, :edit_cart, {:summary, summary}),
    do: s |> assign(:summary, summary) |> Story.input(:check_out, :summary, summary)

  defp wire(s, :edit_cart, {:removed, item}), do: Story.input(s, :undo, :capture, item)

  defp wire(s, :edit_cart, {:saved, item}),
    do: s |> Story.input(:saved, :stash, item) |> put_flash(:info, "Saved for later")

  defp wire(s, :edit_cart, {:line, line}), do: Story.input(s, :wishlist, :toggle, line)

  defp wire(s, :edit_cart, {:checkout_started, summary}),
    do: Story.input(s, :check_out, :start, summary)

  defp wire(s, :edit_cart, {:checkout_requested, cart}),
    do: Story.input(s, :check_out, :pay, cart)

  defp wire(s, :undo, {:restored, item}),
    do: s |> Story.input(:edit_cart, :receive, item) |> put_flash(:info, "Item restored")

  defp wire(s, :undo, {:expired, item_id}),
    do: Story.input(s, :edit_cart, :confirm_removal, item_id)

  defp wire(s, :saved, {:count, count}), do: assign(s, :saved_count, count)

  defp wire(s, :saved, {:moved, item}),
    do: s |> Story.input(:edit_cart, :receive, item) |> put_flash(:info, "Moved to cart")

  defp wire(s, :wishlist, {:count, count}), do: assign(s, :wishlist_count, count)
  defp wire(s, :wishlist, {:ids, ids}), do: Story.input(s, :edit_cart, :wishlist_ids, ids)
  defp wire(s, :wishlist, {:added_to_cart, item}), do: Story.input(s, :edit_cart, :receive, item)

  defp wire(s, :check_out, {:pay_requested, _}),
    do: Story.input(s, :edit_cart, :request_checkout, nil)

  @impl true
  def render(%{live_action: :checkout} = assigns) do
    ~H"""
    <CheckOut.view story={@check_out} t={@texts.checkout} />
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="pb-6 text-3xl font-semibold tracking-tight">Your Cart</h1>
      <UndoRemoval.view story={@undo} t={@texts.undo} />
      <div class="grid items-start gap-8 lg:grid-cols-[1fr_22rem]">
        <.card>
          <.tabs current={@active_tab} event="switch_tab">
            <:tab name={:items} label={"#{@texts.tabs.items} (#{@summary.item_count})"} />
            <:tab name={:saved} label={"#{@texts.tabs.saved} (#{@saved_count})"} />
            <:tab name={:wishlist} label={"#{@texts.tabs.wishlist} (#{@wishlist_count})"} />
          </.tabs>
          <.pane current={@active_tab} name={:items}>
            <EditCart.rows story={@edit_cart} streams={@streams} t={@texts.cart} />
          </.pane>
          <.pane current={@active_tab} name={:saved}>
            <SaveForLater.view story={@saved} streams={@streams} t={@texts.saved} />
          </.pane>
          <.pane current={@active_tab} name={:wishlist}>
            <KeepWishlist.view story={@wishlist} streams={@streams} t={@texts.wishlist} />
          </.pane>
        </.card>
        <.card class="lg:sticky lg:top-24">
          <EditCart.totals story={@edit_cart} t={@texts.cart} />
        </.card>
      </div>
    </div>
    """
  end
end
