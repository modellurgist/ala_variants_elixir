defmodule GoodDealWeb.CartLive.Show do
  @moduledoc """
  The cart page, as a plain LiveView. Its configuration is at the top: the store's rules and words,
  and the features and domain instances built from them. Each browser event runs one feature step;
  each feature output lands through one `land/3` clause, so those clauses are the page's wiring, one
  per port, read top to bottom. There is no catch-all clause: an output without one crashes the page,
  and a test checks every declared port has one.
  """
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDealWeb.Parts

  alias GoodDeal.Catalog
  alias GoodDeal.Domain.{Charge, GiftWrap, Inventory, Promo, SettleOrder, Shipping}
  alias GoodDeal.Features.{Cart, Checkout}
  alias GoodDeal.Foundation.{Broadcast, Carts, Orders, Products}
  alias GoodDealWeb.{CartSession, CheckoutMetadata}
  alias GoodDealWeb.Paradigms.Steps

  @blocked %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}
  @texts %{
    heading: "Your Cart",
    tabs: %{items: "Items", summary: "Summary"},
    row: %{
      each: " each",
      remove: "Remove",
      stock: %{low_stock: "Low stock", out_of_stock: "Out of stock"}
    },
    empty: "Your cart is empty.",
    browse: "Browse products",
    shipping: %{heading: "Shipping", free_over: "free over"},
    gift_wrap_toggle: "Add gift wrapping",
    summary: %{
      items: "Items",
      subtotal: "Subtotal",
      discount: "Discount",
      shipping: "Shipping",
      gift_wrap: "Gift wrap",
      total: "Total"
    },
    promo: %{placeholder: "Promo code", apply: "Apply"},
    checkout: "Checkout",
    processing: "Processing payment...",
    failed: "Checkout failed.",
    try_again: "Try again"
  }

  @impl true
  def mount(_params, session, socket) do
    cart_id = CartSession.fetch(session)

    {:ok,
     socket
     |> assign(
       cart:
         Cart.new(
           cart_id: cart_id,
           store: Carts,
           shipping: Shipping.new(Catalog.shipping_methods()),
           promo: Promo.new(Catalog.promo_codes()),
           gift_wrap: GiftWrap.new(Catalog.gift_wrap_cents()),
           stock: Inventory.new(low_at: Catalog.low_stock_threshold())
         ),
       checkout:
         Checkout.new(
           stock_levels: &Products.stock_levels/1,
           line_items: GoodDeal.Domain.Checkout.new(currency: Catalog.currency())
         ),
       charge: %Charge{
         gateway:
           Application.get_env(:good_deal, :payment_gateway, GoodDeal.Foundation.LedgerGateway),
         metadata: &CheckoutMetadata.for_cart/1
       },
       settle: %SettleOrder{
         orders: Orders,
         carts: Carts,
         products: Products,
         announce: &Broadcast.stock_changed/2
       }
     )
     |> assign(texts: @texts, active_tab: :items, promo_error: nil, status: :idle)
     |> stream(:cart_items, [])
     |> run(:cart, &Cart.load(&1, nil))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_quantity", %{"item-id" => id, "delta" => d}, socket),
    do:
      {:noreply,
       run(socket, :cart, &Cart.update_quantity(&1, %{item_id: int(id), delta: int(d)}))}

  def handle_event("remove_item", %{"item-id" => id}, socket),
    do: {:noreply, run(socket, :cart, &Cart.remove(&1, %{item_id: int(id)}))}

  def handle_event("select_shipping", %{"method" => method}, socket),
    do: {:noreply, run(socket, :cart, &Cart.select_shipping(&1, String.to_existing_atom(method)))}

  def handle_event("toggle_gift_wrap", _params, socket),
    do: {:noreply, run(socket, :cart, &Cart.toggle_gift_wrap(&1, nil))}

  def handle_event("apply_promo", %{"code" => code}, socket),
    do: {:noreply, run(socket, :cart, &Cart.apply_promo(&1, code))}

  def handle_event("checkout", _params, socket),
    do: {:noreply, run(socket, :cart, &Cart.request_checkout(&1, nil))}

  def handle_event("switch_tab", %{"tab" => tab}, socket),
    do: {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}

  @impl true
  def handle_async(:checkout, {:ok, {:ok, reference}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.succeeded(&1, reference))}

  def handle_async(:checkout, {:ok, {:error, reason}}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  def handle_async(:checkout, {:exit, reason}, socket),
    do: {:noreply, run(socket, :checkout, &Checkout.failed(&1, reason))}

  @impl true
  def handle_info({:stock_changed, {product_id, stock}}, socket),
    do:
      {:noreply, run(socket, :cart, &Cart.set_stock(&1, %{product_id: product_id, stock: stock}))}

  # the products topic also carries catalogue edits, which this page doesn't show
  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}
  def handle_info({:product_updated, _product}, socket), do: {:noreply, socket}

  defp run(socket, key, step), do: Steps.run(socket, key, step, &land/3)
  defp int(s), do: String.to_integer(s)

  # {feature, port} → where it lands on this page
  defp land(s, :cart, {:rows, change}), do: Steps.stream_change(s, :cart_items, change)
  defp land(s, :cart, {:summary, summary}), do: assign(s, :summary, summary)

  defp land(s, :cart, {:removed, %{id: id}}),
    do: s |> push_event("item_removed", %{id: id}) |> put_flash(:info, "Item removed")

  defp land(s, :cart, {:promo_applied, _code}),
    do: s |> assign(:promo_error, nil) |> put_flash(:info, "Promo code applied!")

  defp land(s, :cart, {:promo_rejected, _code}),
    do: s |> assign(:promo_error, "Invalid promo code") |> put_flash(:error, "Invalid promo code")

  defp land(s, :cart, {:checkout_requested, order}),
    do: run(s, :checkout, &Checkout.pay(&1, order))

  defp land(s, :checkout, {:status, status}), do: assign(s, :status, status)
  defp land(s, :checkout, {:blocked, reason}), do: put_flash(s, :error, @blocked[reason])

  defp land(s, :checkout, {:ready_to_pay, payment}),
    do:
      s
      |> put_flash(:info, "Processing payment...")
      |> start_async(:checkout, fn -> Charge.call(s.assigns.charge, payment) end)

  defp land(s, :checkout, {:failed, _reason}),
    do: put_flash(s, :error, "Checkout failed. Please try again.")

  defp land(s, :checkout, {:done, cart_id}) do
    SettleOrder.run(s.assigns.settle, cart_id)
    push_navigate(s, to: ~p"/cart/success")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">{@texts.heading}</h1>

      <.tabs current={@active_tab} event="switch_tab">
        <:tab name={:items} label={@texts.tabs.items} />
        <:tab name={:summary} label={@texts.tabs.summary} />
      </.tabs>

      <.pane current={@active_tab} name={:items}>
        <div id="cart_items" phx-update="stream">
          <.line_row
            :for={{dom_id, row} <- @streams.cart_items}
            id={dom_id}
            row={row}
            on_quantity="update_quantity"
            on_remove="remove_item"
            t={@texts.row}
          />
        </div>
        <.none count={@summary.item_count}>
          {@texts.empty}
          <.link navigate={~p"/products"} class="text-blue-500 hover:underline">
            {@texts.browse}
          </.link>
        </.none>
      </.pane>

      <.only_on current={@active_tab} name={:summary}>
        <.shipping_selector
          options={@summary.shipping_options}
          selected={@summary.shipping_method}
          event="select_shipping"
          t={@texts.shipping}
        />
        <.toggle on={@summary.gift_wrap?} event="toggle_gift_wrap" label={@texts.gift_wrap_toggle} />
        <.cart_summary summary={@summary} t={@texts.summary} />
      </.only_on>

      <.promo_form
        code={@summary.promo_code}
        error={@promo_error}
        event="apply_promo"
        t={@texts.promo}
      />

      <div class="py-4">
        <.only_on current={@status} name={:idle}>
          <.primary_button event="checkout" disabled={@summary.empty?}>
            {@texts.checkout}
          </.primary_button>
        </.only_on>
        <.only_on current={@status} name={:processing}>
          <.working text={@texts.processing} />
        </.only_on>
        <.only_on current={@status} name={:error}>
          <div class="space-y-2">
            <p class="text-red-600 text-sm">{@texts.failed}</p>
            <.primary_button event="checkout">{@texts.try_again}</.primary_button>
          </div>
        </.only_on>
      </div>
    </div>
    """
  end
end
