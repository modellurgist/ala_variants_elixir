defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page as a composition of user stories (Spray's features, §2.2): editing the cart, undoing
  a removal, saving for later, keeping a wishlist, and checking out. `composition/1` builds the page
  (the root story) and its stories, each with its bindings map; `bindings/0` is the page's own map,
  which links one story's outputs to another's inputs. Every port is typed, and `Binder.mount/2` has the
  whole composition checked before the page runs it. The handlers route browser events to the story whose
  view emits them.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  import ZeroCoupled.Catalog.Panes, only: [pane: 1, tabs: 1]
  import ZeroCoupled.Catalog.Parts, only: [card: 1]

  alias ZeroCoupled.Domain.{
    AddLine,
    BuildLineItems,
    CalculateGiftWrapCost,
    CalculateShipping,
    PlaceOrder,
    StartPayment,
    StockStatus,
    ValidatePromo
  }

  alias ZeroCoupled.State.PageUI
  alias ZeroCoupled.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}
  alias ZeroCoupledWeb.{CartSession, StoreConfig}
  alias ZeroCoupledWeb.Paradigms.Binder
  alias ZeroCoupledWeb.Stories.{CheckOut, EditCart, KeepWishlist, SaveForLater, UndoRemoval}

  @promo_codes %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}
  @gift_wrap_unit 299
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
    shared = %{remove: StoreConfig.remove_text(), stock: StoreConfig.stock_texts()}

    @texts
    |> update_in([:cart], &Map.merge(&1, StoreConfig.summary_texts()))
    |> update_in([:cart, :row], &Map.merge(&1, shared))
    |> update_in([:wishlist, :row], &Map.put(&1, :remove, shared.remove))
    |> update_in([:checkout], &Map.put(&1, :total, StoreConfig.summary_texts().total))
    |> put_in([:tabs, :items], StoreConfig.summary_texts().items)
    |> put_in([:cart, :gift_wrap_label], "Gift wrap (#{Money.new(@gift_wrap_unit)})")
  end

  @stories [:edit_cart, :undo, :saved, :wishlist, :check_out]

  def parts, do: %{ui: PageUI}
  def ports, do: %{in: [], out: [mounted: :cart_id]}

  # {source, port} → where it goes on this page; a story's outputs come from {story, port}
  def bindings do
    %{
      {:page, :mounted} => [{:to, :edit_cart, :mounted}, {:to, :check_out, :mounted}],
      {:ui, :tab} => [{:show, :active_tab}],
      {:edit_cart, :summary} => [{:show, :summary}, {:to, :check_out, :summary}],
      {:edit_cart, :removed} => [{:to, :undo, :capture}],
      {:edit_cart, :saved} => [{:to, :saved, :stash}, {:flash, :info, "Saved for later"}],
      {:edit_cart, :line} => [{:to, :wishlist, :toggle}],
      {:edit_cart, :checkout_started} => [{:to, :check_out, :start}],
      {:edit_cart, :checkout_requested} => [{:to, :check_out, :pay}],
      {:undo, :restored} => [{:to, :edit_cart, :receive}, {:flash, :info, "Item restored"}],
      {:undo, :expired} => [{:to, :edit_cart, :confirm_removal}],
      {:saved, :count} => [{:show, :saved_count}],
      {:saved, :moved} => [{:to, :edit_cart, :receive}, {:flash, :info, "Moved to cart"}],
      {:wishlist, :count} => [{:show, :wishlist_count}],
      {:wishlist, :ids} => [{:to, :edit_cart, :wishlist_ids}],
      {:wishlist, :added_to_cart} => [{:to, :edit_cart, :receive}],
      {:check_out, :pay_requested} => [{:to, :edit_cart, :request_checkout}]
    }
  end

  @doc "The page (the root story) and its stories, configured for a cart."
  def composition(cart_id) do
    pricing = %{
      shipping: CalculateShipping.new(StoreConfig.rates()),
      stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at()),
      promo: ValidatePromo.new(@promo_codes),
      gift_wrap: CalculateGiftWrapCost.new(@gift_wrap_unit)
    }

    stories = %{
      edit_cart: EditCart.new(cart_id: cart_id, pricing: pricing),
      undo: UndoRemoval.new(window_ms: StoreConfig.undo_window_ms()),
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
            line_items: BuildLineItems.new(currency: StoreConfig.currency()),
            messages: %{postal_code: "must be 4–10 digits"}
          ],
          start_payment: %StartPayment{
            gateway: Application.get_env(:zero_coupled, :payment_gateway, LedgerGateway),
            urls: %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")},
            cart_key: CartSession.cart_key()
          },
          place_order: %PlaceOrder{
            orders: Orders,
            carts: Carts,
            products: Products,
            announce: &Broadcast.stock_changed/2,
            cart_id: cart_id
          },
          milestones: @milestones
        )
    }

    {Binder.story(__MODULE__, %{ui: PageUI.new(tabs: [:items, :saved, :wishlist])}, bindings()),
     stories}
  end

  @impl true
  def mount(_params, session, socket) do
    cart_id = session[CartSession.cart_key()]

    {:ok,
     socket
     |> assign(
       texts: texts(),
       active_tab: :items,
       summary: nil,
       saved_count: 0,
       wishlist_count: 0
     )
     |> Binder.mount(composition(cart_id))
     |> Binder.send_out(:page, :mounted, cart_id)}
  end

  # the URL names a checkout step (browser back, a reload); the story decides whether to honour it
  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket),
    do:
      {:noreply,
       Binder.input(socket, :check_out, :goto, Map.get(@steps_by_url, params["step"], :address))}

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do:
      {:noreply,
       Binder.run(
         socket,
         :page,
         :ui,
         &PageUI.switch_tab(&1, %{tab: String.to_existing_atom(tab)})
       )}

  def handle_event(name, params, socket),
    do: {:noreply, Binder.event(socket, @stories, name, params)}

  # a story's task reports its outcome to its own inputs
  @impl true
  def handle_async({:story_async, _, _, _} = task, result, socket),
    do: {:noreply, Binder.async_result(socket, task, result)}

  # a story's timer reports to one of its own inputs
  @impl true
  def handle_info({:story_input, story, port, payload}, socket),
    do: {:noreply, Binder.input(socket, story, port, payload)}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
    do: {:noreply, Binder.input(socket, :edit_cart, :stock, %{product_id: id, stock: stock})}

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

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
