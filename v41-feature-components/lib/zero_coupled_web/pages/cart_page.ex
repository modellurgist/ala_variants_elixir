defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page in the shape `phx.gen.live` produces: the template places the feature instances
  and configures them; `handle_info` passes each instance's announcement on to the instance it
  concerns and says what happened. The store's words and numbers are the attributes.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  alias ZeroCoupled.Features.{Cart, Checkout, SavedItems, Undo, Wishlist}
  alias ZeroCoupled.Foundation.{Broadcast, LedgerGateway}

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
  @blocked %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}

  @impl true
  def mount(_params, %{"cart_id" => cart_id}, socket) do
    {:ok,
     assign(socket,
       cart_id: cart_id,
       pricing: @pricing,
       active_tab: :items,
       item_count: 0,
       saved_count: 0,
       wishlist_count: 0,
       wishlist_ids: [],
       requested_step: :address,
       undo_window_ms: @undo_window_ms,
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

  @impl true
  def handle_info({:cart, :summary, summary}, socket),
    do: {:noreply, assign(socket, item_count: summary.item_count)}

  def handle_info({:cart, :removed, item}, socket),
    do: {:noreply, pass(socket, Undo.Banner, "undo", capture: item)}

  def handle_info({:cart, :saved, item}, socket),
    do:
      {:noreply,
       socket
       |> pass(SavedItems.Panel, "saved", stash: item)
       |> put_flash(:info, "Saved for later")}

  def handle_info({:cart, :line, line}, socket),
    do: {:noreply, pass(socket, Wishlist.Panel, "wishlist", toggle: line)}

  def handle_info({:cart, :promo_applied, _}, socket),
    do: {:noreply, put_flash(socket, :info, "Promo applied!")}

  def handle_info({:cart, :promo_rejected, _}, socket),
    do: {:noreply, put_flash(socket, :error, "Invalid promo code")}

  def handle_info({:undo, :expire, id}, socket),
    do: {:noreply, pass(socket, Undo.Banner, "undo", expire: id)}

  def handle_info({:undo, :expired, id}, socket),
    do: {:noreply, pass(socket, Cart.Panel, "cart", confirm_removal: id)}

  def handle_info({:undo, :restored, item}, socket),
    do:
      {:noreply,
       socket |> pass(Cart.Panel, "cart", receive: item) |> put_flash(:info, "Item restored")}

  def handle_info({:saved, :count, n}, socket), do: {:noreply, assign(socket, saved_count: n)}

  def handle_info({:saved, :moved, item}, socket),
    do:
      {:noreply,
       socket |> pass(Cart.Panel, "cart", receive: item) |> put_flash(:info, "Moved to cart")}

  def handle_info({:wishlist, :count, n}, socket),
    do: {:noreply, assign(socket, wishlist_count: n)}

  def handle_info({:wishlist, :ids, ids}, socket),
    do: {:noreply, assign(socket, wishlist_ids: ids)}

  def handle_info({:wishlist, :added, _}, socket),
    do: {:noreply, put_flash(socket, :info, "Added to wishlist")}

  def handle_info({:wishlist, :dropped, _}, socket),
    do: {:noreply, put_flash(socket, :info, "Removed from wishlist")}

  def handle_info({:wishlist, :taken, product}, socket),
    do:
      {:noreply,
       socket
       |> pass(Cart.Panel, "cart", add_product: product)
       |> put_flash(:info, "Added to cart")}

  def handle_info({:checkout, :blocked, reason}, socket),
    do: {:noreply, put_flash(socket, :error, @blocked[reason])}

  def handle_info({:checkout, :step, step}, socket),
    do: {:noreply, patch(socket, @step_paths, step)}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
    do: {:noreply, pass(socket, Cart.Panel, "cart", set_stock: %{product_id: id, stock: stock})}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp pass(socket, module, id, input),
    do:
      (
        send_update(module, [{:id, id} | input])
        socket
      )

  # the URL follows the flow's step, when the step has one
  defp patch(socket, paths, step) do
    with {:ok, path} <- Map.fetch(paths, step),
         do: push_patch(socket, to: path),
         else: (:error -> socket)
  end

  # the cart's instances stay mounted behind the checkout, so nothing announced while paying is lost
  @impl true
  def render(assigns) do
    ~H"""
    <div class={["max-w-2xl mx-auto px-6", @live_action != :index && "hidden"]}>
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>
      <.live_component
        module={Undo.Banner}
        id="undo"
        window_ms={@undo_window_ms}
        text="Item removed."
      />
      <nav class="flex gap-2 border-b mb-6 pb-2">
        <button
          :for={
            {tab, label, count} <- [
              {:items, "Items", @item_count},
              {:saved, "Saved", @saved_count},
              {:wishlist, "Wishlist", @wishlist_count}
            ]
          }
          phx-click="switch_tab"
          phx-value-tab={tab}
          class={[
            "px-4 py-2 text-sm font-medium rounded-t",
            (@active_tab == tab && "bg-zinc-900 text-white") || "text-zinc-500 hover:text-zinc-700"
          ]}
        >
          {label} ({count})
        </button>
      </nav>
      <div class={@active_tab != :items && "hidden"}>
        <.live_component
          module={Cart.Panel}
          id="cart"
          cart_id={@cart_id}
          pricing={@pricing}
          wishlist_ids={@wishlist_ids}
          gift_wrap_label="Gift wrap ($2.99)"
          empty_text="Your cart is empty."
          invalid_promo_text="Invalid promo code"
        />
        <div class="py-4">
          <button
            phx-click="start_checkout"
            disabled={@item_count == 0}
            class={[
              "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
              @item_count == 0 && "opacity-50 cursor-not-allowed"
            ]}
          >
            Checkout
          </button>
        </div>
      </div>
      <div class={@active_tab != :saved && "hidden"}>
        <.live_component module={SavedItems.Panel} id="saved" empty_text="No saved items." />
      </div>
      <div class={@active_tab != :wishlist && "hidden"}>
        <.live_component module={Wishlist.Panel} id="wishlist" empty_text="Your wishlist is empty." />
      </div>
    </div>
    <div :if={@live_action == :checkout} class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">← Back to cart</.link>
      <h1 class="text-3xl font-semibold py-4">Checkout</h1>
      <.live_component
        module={Checkout.Panel}
        id="checkout"
        cart_id={@cart_id}
        pricing={@pricing}
        flow={@checkout_flow}
        start={:address}
        url_edges={@checkout_url_edges}
        milestones={@milestones}
        requested_step={@requested_step}
        gateway={@gateway}
        urls={@urls}
      />
    </div>
    """
  end
end
