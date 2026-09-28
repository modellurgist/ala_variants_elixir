defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page. `bindings/1` is its diagram: every feature port, and where it lands on this
  page. The handlers below only route browser events, timers, and messages to feature inputs;
  the store's literals (pricing, the undo window, every message) sit here.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  alias ZeroCoupled.Features.{Cart, Checkout, PageUI, SavedItems, Undo, Wishlist}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, LedgerGateway, Orders, Products}
  alias ZeroCoupledWeb.CartLive.{CheckoutView, IndexView}
  alias ZeroCoupledWeb.Paradigms.Binder

  @pricing [
    shipping: %{
      standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
      overnight: %{label: "Overnight", cost: 2499, free_above: nil}
    },
    promo: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50},
    gift_wrap_unit: 299
  ]
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

  # {feature, port} → where it lands here
  def bindings(cart_id) do
    %{
      {:cart, :rows} => [{:stream, :cart_items}],
      {:cart, :summary} => [{:assign, :summary}],
      {:cart, :persist} => [{:call, &Carts.apply_change/1}],
      {:cart, :removed} => [{:input, :undo, &Undo.capture/2}],
      {:cart, :saved} => [
        {:input, :saved, &SavedItems.stash/2},
        {:flash, :info, "Saved for later"}
      ],
      {:cart, :promo_applied} => [{:set, :promo_error, nil}, {:flash, :info, "Promo applied!"}],
      {:cart, :promo_rejected} => [
        {:set, :promo_error, "Invalid promo code"},
        {:flash, :error, "Invalid promo code"}
      ],
      {:undo, :captured} => [{:set, :undo_pending, true}],
      {:undo, :timer} => [{:timer, :undo, @undo_window_ms}],
      {:undo, :restored} => [
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
        {:via, &add_line(cart_id, &1),
         [{:input, :cart, &Cart.receive/2}, {:flash, :info, "Added to cart"}]}
      ],
      {:ui, :tab} => [{:assign, :active_tab}],
      {:checkout, :step} => [{:assign, :step}, {:patch, @step_paths}],
      {:checkout, :form} => [{:form, :address_form}],
      {:checkout, :address} => [{:assign, :address}],
      {:checkout, :blocked} => [
        {:flash_for, :error,
         %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}}
      ],
      {:checkout, :payment} => [{:async, :payment, &charge/1}],
      {:checkout, :done} => [{:via, &finalize(cart_id, &1), [:redirect]}]
    }
  end

  @impl true
  def mount(_params, %{"cart_id" => cart_id}, socket) do
    cart = Cart.new(cart_id: cart_id, items: Carts.list_items(cart_id), pricing: @pricing)
    checkout = Checkout.new(flow: @checkout_flow, start: :address, url_edges: @checkout_url_edges)

    {:ok,
     socket
     |> assign(
       bindings: bindings(cart_id),
       cart: cart,
       undo: Undo.new([]),
       saved: SavedItems.new([]),
       wishlist: Wishlist.new([])
     )
     |> assign(ui: PageUI.new(tabs: [:items, :saved, :wishlist]), checkout: checkout)
     |> assign(
       summary: Cart.summary(cart),
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
       address_form: to_form(Checkout.address_form(checkout))
     )
     |> stream(:cart_items, Cart.rows(cart))
     |> stream(:saved_items, [])
     |> stream(:wishlist_products, [])}
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

  def handle_event("select_shipping", %{"method" => m}, socket),
    do:
      {:noreply,
       run(socket, :cart, &Cart.select_shipping(&1, %{method: String.to_existing_atom(m)}))}

  def handle_event("apply_promo", %{"code" => code}, socket),
    do: {:noreply, run(socket, :cart, &Cart.apply_promo(&1, %{code: code}))}

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

  def handle_event("start_checkout", _params, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.start(&1, socket.assigns.summary))}

  def handle_event("validate_address", %{"address" => params}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.validate(&1, params))}

  def handle_event("submit_address", %{"address" => params}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.submit_address(&1, params))}

  def handle_event("edit_address", _params, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.edit_address(&1, nil))}

  # composed inputs: the wishlist needs the cart line; paying needs the cart and fresh stock
  def handle_event("toggle_wishlist", %{"item-id" => id}, socket),
    do:
      {:noreply,
       run(socket, :wishlist, &Wishlist.toggle(&1, Cart.find(socket.assigns.cart, int(id))))}

  def handle_event("pay", _params, socket) do
    cart = socket.assigns.cart
    stock = Products.stock_levels(Enum.map(Cart.items(cart), & &1.product.id))
    {:noreply, run(socket, :checkout, &Checkout.pay(&1, %{cart: cart, stock: stock}))}
  end

  @impl true
  def handle_async(:payment, {:ok, {:ok, url}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.succeeded(&1, url))}

  def handle_async(:payment, {:ok, {:error, reason}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  def handle_async(:payment, {:exit, reason}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  @impl true
  def handle_info({:timer, :undo, item_id}, socket),
    do: {:noreply, run(socket, :undo, &Undo.expire(&1, item_id))}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
    do: {:noreply, run(socket, :cart, &Cart.set_stock(&1, %{product_id: id, stock: stock}))}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp run(socket, key, step), do: Binder.run(socket, socket.assigns.bindings, key, step)
  defp int(s), do: String.to_integer(s)

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
