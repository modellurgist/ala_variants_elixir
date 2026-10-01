defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page. Its diagram is `ZeroCoupledWeb.CartDiagram`: every instance, its configuration,
  and every wire, checked by `Circuit.validate!/1` when the page mounts. The template places the UI
  instances; the handlers only return messages (from instances, timers, jobs, the URL, PubSub) to
  the circuit. There is no catch-all `handle_info`.
  """
  use ZeroCoupledWeb, :live_view
  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  alias ZeroCoupled.Features.Checkout
  alias ZeroCoupled.Foundation.{Broadcast, LedgerGateway}
  alias ZeroCoupled.Paradigms.Circuit
  alias ZeroCoupledWeb.CartDiagram
  alias ZeroCoupledWeb.CartLive.{CartControls, CartPanel, CheckoutForm, SavedPanel, WishlistPanel}
  alias ZeroCoupledWeb.Paradigms.Runner
  import ZeroCoupledWeb.Rows, only: [milestones: 1]

  @gift_wrap_label "Gift wrap ($2.99)"
  @steps_by_url %{"payment" => :payment}
  @milestones [address: "Address", payment: "Payment"]

  @impl true
  def mount(_params, %{"cart_id" => cart_id}, socket) do
    circuit = Circuit.validate!(CartDiagram.circuit(%{cart_id: cart_id, charge: &charge/1}))

    {:ok,
     socket
     |> assign(
       circuit: circuit,
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
       gift_wrap_label: @gift_wrap_label
     )
     |> assign(
       address_form: to_form(Checkout.address_form(Circuit.part(circuit, :checkout).state))
     )
     |> Runner.feed(:lines, {:load, cart_id})}
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :checkout}} = socket),
    do:
      {:noreply,
       Runner.feed(socket, :checkout, {:goto, Map.get(@steps_by_url, params["step"], :address)})}

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:feed, _, _} = message, socket),
    do: {:noreply, Runner.feed_message(message, socket)}

  def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
    do: {:noreply, Runner.feed(socket, :cart, {:set_stock, %{product_id: id, stock: stock}})}

  # the storefront topic also carries product edits, which this page doesn't show
  def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(_name, result, socket), do: {:noreply, Runner.async_result(result, socket)}

  @impl true
  def render(%{live_action: :checkout} = assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">← Back to cart</.link>
      <h1 class="text-3xl font-semibold py-4">Checkout</h1>
      <.milestones
        step={@step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.live_component
        module={CheckoutForm}
        id="checkout"
        step={@step}
        address={@address}
        address_form={@address_form}
        total={@summary.total}
      />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>
      <.live_component
        module={CartControls}
        id="controls_top"
        part={:top}
        active_tab={@active_tab}
        undo_pending={@undo_pending}
        counts={[items: @summary.item_count, saved: @saved_count, wishlist: @wishlist_count]}
      />
      <div class={@active_tab != :items && "hidden"}>
        <.live_component
          module={CartPanel}
          id="cart"
          wishlist_ids={@wishlist_ids}
          empty?={@summary.empty?}
          gift_wrap_label={@gift_wrap_label}
        />
      </div>
      <div class={@active_tab != :saved && "hidden"}>
        <.live_component module={SavedPanel} id="saved" count={@saved_count} />
      </div>
      <div class={@active_tab != :wishlist && "hidden"}>
        <.live_component module={WishlistPanel} id="wishlist" count={@wishlist_count} />
      </div>
      <.live_component
        module={CartControls}
        id="controls_bottom"
        part={:bottom}
        summary={@summary}
        promo_error={@promo_error}
      />
    </div>
    """
  end

  @doc "The payment job the diagram's async sink runs: the gateway and return URLs are the page's to know."
  def charge({line_items, cart_id}) do
    gateway = Application.get_env(:zero_coupled, :payment_gateway, LedgerGateway)

    gateway.create_checkout_session(line_items, %{"cart_id" => cart_id}, %{
      success_url: url(~p"/cart/success"),
      cancel_url: url(~p"/cart")
    })
  end
end
