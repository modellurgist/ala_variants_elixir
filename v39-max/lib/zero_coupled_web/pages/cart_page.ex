defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page. `bindings/1` is its diagram: every feature port, and where it lands on this
  page; `grounded/0` names the ports it leaves unbound on purpose. The handlers only route
  browser events, timers, and messages to feature inputs. The store's words, pricing, stores,
  and payment are configured here once, as instances the bindings name.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}

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

  alias ZeroCoupled.Features.{Cart, Checkout, PageUI, SavedItems, Undo, Wishlist}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}
  alias ZeroCoupledWeb.{CartSession, StoreConfig}
  alias ZeroCoupledWeb.CartLive.{CheckoutView, IndexView}
  alias ZeroCoupledWeb.Paradigms.Binder

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
    shared = %{remove: StoreConfig.remove_text(), stock: StoreConfig.stock_texts()}

    @texts
    |> update_in([:cart], &Map.merge(&1, StoreConfig.summary_texts()))
    |> update_in([:cart, :row], &Map.merge(&1, shared))
    |> update_in([:wishlist, :row], &Map.put(&1, :remove, shared.remove))
    |> update_in([:checkout], &Map.put(&1, :total, StoreConfig.summary_texts().total))
    |> put_in([:tabs, :items], StoreConfig.summary_texts().items)
    |> put_in([:cart, :gift_wrap_label], "Gift wrap (#{Money.new(@gift_wrap_unit)})")
  end

  # {feature, port} → where it lands here; `:page` is the page itself
  def bindings(cart_id) do
    %{
      {:page, :mounted} => [
        {:via, &Carts.list_items/1, [{:input, :cart, &Cart.load/2}]},
        {:input, :checkout, &Checkout.show_form/2}
      ],
      {:cart, :rows} => [{:stream, :cart_items}],
      {:cart, :summary} => [{:assign, :summary}],
      {:cart, :changed} => [{:call, &Carts.apply_change/1}],
      {:cart, :removed} => [{:input, :undo, &Undo.capture/2}],
      {:cart, :saved} => [
        {:input, :saved, &SavedItems.stash/2},
        {:flash, :info, "Saved for later"}
      ],
      {:cart, :line} => [{:input, :wishlist, &Wishlist.toggle/2}],
      {:cart, :promo_applied} => [{:set, :promo_error, nil}, {:flash, :info, "Promo applied!"}],
      {:cart, :promo_rejected} => [
        {:set, :promo_error, "Invalid promo code"},
        {:flash, :error, "Invalid promo code"}
      ],
      {:cart, :checkout_started} => [{:input, :checkout, &Checkout.start/2}],
      {:cart, :checkout_requested} => [{:input, :checkout, &Checkout.pay/2}],
      {:undo, :captured} => [
        {:set, :undo_pending, true},
        {:start_timer, :undo, StoreConfig.undo_window_ms()}
      ],
      {:undo, :restored} => [
        {:stop_timer, :undo},
        {:input, :cart, &Cart.receive/2},
        {:flash, :info, "Item restored"},
        {:set, :undo_pending, false}
      ],
      {:undo, :expired} => [
        {:input, :cart, &Cart.confirm_removal/2},
        {:set, :undo_pending, false}
      ],
      {:saved, :rows} => [{:stream, :saved_items}],
      {:saved, :count} => [{:assign, :saved_count}],
      {:saved, :moved} => [{:input, :cart, &Cart.receive/2}, {:flash, :info, "Moved to cart"}],
      {:wishlist, :rows} => [{:stream, :wishlist_products}],
      {:wishlist, :count} => [{:assign, :wishlist_count}],
      {:wishlist, :ids} => [{:assign, :wishlist_ids}],
      {:wishlist, :added} => [{:flash, :info, "Added to wishlist"}],
      {:wishlist, :dropped} => [{:flash, :info, "Removed from wishlist"}],
      {:wishlist, :taken} => [
        {:via, %AddLine{carts: Carts, products: Products, cart_id: cart_id},
         [{:input, :cart, &Cart.receive/2}, {:flash, :info, "Added to cart"}]}
      ],
      {:ui, :tab} => [{:assign, :active_tab}],
      {:checkout, :step} => [{:assign, :step}, {:patch, @step_paths}],
      {:checkout, :form} => [{:form, :address_form}],
      {:checkout, :address} => [{:assign, :address}],
      {:checkout, :blocked} => [{:flash_for, :error, @blocked}],
      {:checkout, :ready_to_pay} => [
        {:async, :payment,
         %StartPayment{
           gateway: Application.get_env(:zero_coupled, :payment_gateway, LedgerGateway),
           urls: %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")},
           cart_key: CartSession.cart_key()
         }}
      ],
      {:checkout, :done} => [
        {:call,
         %PlaceOrder{
           orders: Orders,
           carts: Carts,
           products: Products,
           announce: &Broadcast.stock_changed/2,
           cart_id: cart_id
         }},
        :redirect
      ]
    }
  end

  @doc "The feature ports this page leaves unbound on purpose, as `{feature, port}`."
  def grounded, do: []

  @doc "Which feature each binding key names, so a test can check every port is bound or grounded."
  def features,
    do: %{
      cart: Cart,
      undo: Undo,
      saved: SavedItems,
      wishlist: Wishlist,
      ui: PageUI,
      checkout: Checkout
    }

  @impl true
  def mount(_params, session, socket) do
    cart_id = session[CartSession.cart_key()]

    pricing = %{
      shipping: CalculateShipping.new(StoreConfig.rates()),
      stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at()),
      promo: ValidatePromo.new(@promo_codes),
      gift_wrap: CalculateGiftWrapCost.new(@gift_wrap_unit)
    }

    checkout =
      Checkout.new(
        flow: @checkout_flow,
        start: :address,
        url_edges: @checkout_url_edges,
        stock_levels: &Products.stock_levels/1,
        line_items: BuildLineItems.new(currency: StoreConfig.currency()),
        messages: %{postal_code: "must be 4–10 digits"}
      )

    {:ok,
     socket
     |> assign(
       bindings: bindings(cart_id),
       cart: ZeroCoupled.Cart.new(cart_id: cart_id, pricing: pricing),
       undo: Undo.new([]),
       saved: SavedItems.new([]),
       wishlist: Wishlist.new([]),
       ui: PageUI.new(tabs: [:items, :saved, :wishlist]),
       checkout: checkout
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
     |> Binder.deliver(bindings(cart_id), :page, mounted: cart_id)}
  end

  # the URL names a checkout step (browser back, a reload); the feature decides whether to honour it
  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket) do
    step = Map.get(@steps_by_url, params["step"], :address)
    {:noreply, run(socket, :checkout, &Checkout.goto(&1, step))}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def render(%{live_action: :checkout} = assigns), do: CheckoutView.render(assigns)
  def render(assigns), do: IndexView.render(assigns)

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
  def handle_async(:payment, {:ok, {:ok, url}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.succeeded(&1, url))}

  def handle_async(:payment, {:ok, {:error, reason}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  def handle_async(:payment, {:exit, reason}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  @impl true
  def handle_info({:timer, :undo, %{id: id}}, socket),
    do: {:noreply, run(socket, :undo, &Undo.expire(&1, id))}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
    do: {:noreply, run(socket, :cart, &Cart.set_stock(&1, %{product_id: id, stock: stock}))}

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

  defp run(socket, key, step), do: Binder.run(socket, socket.assigns.bindings, key, step)
  defp int(s), do: String.to_integer(s)
end
