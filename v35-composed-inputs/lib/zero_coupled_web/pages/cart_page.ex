defmodule ZeroCoupledWeb.CartPage do
  @moduledoc """
  The cart page's hand-written LiveView — irregular events plus thin
  delegation to the **committed** generated glue.

  The composition itself lives in two ordinary files next to this one:
  `CartPage.Manifest` (the diagram — change it first) and
  `CartPage.Generated` (the glue `mix zc.gen` writes from it — reviewed
  in PRs like any other source). This module holds only what a manifest
  cannot express: the mount, the irregular edges (I/O-then-intent
  events, the changeset form, async payment, PubSub/timer messages), and
  the one house pattern, `run/2`. **No web-layer macros.**
  """

  use ZeroCoupledWeb, :live_view

  alias ZeroCoupledWeb.CartPage.Generated
  alias ZeroCoupledWeb.EffectInterpreter
  alias ZeroCoupled.Features.{CartItems, Undo, CheckoutFlow, Wishlist}
  alias ZeroCoupled.Foundation.{Carts, Orders, Products, Broadcast, LedgerGateway}
  alias ZeroCoupled.Web.Contracts

  # Pure API delegated to the generated glue (test/introspection surface).
  defdelegate run_pure(session, fun), to: Generated
  defdelegate run_intent(session, name, args), to: Generated
  defdelegate __manifest__(), to: Generated

  # ── Lifecycle ────────────────────────────────────────────────────────

  @impl true
  def mount(_params, %{"cart_id" => cart_id}, socket) do
    items = Carts.list_items(cart_id)
    if connected?(socket), do: Broadcast.subscribe()

    socket = Generated.mount_session(socket, cart_id: cart_id, items: items)
    cart = socket.assigns.session.cart

    {:ok,
     socket
     |> assign_address_form()
     |> stream(Contracts.stream_name(:cart), Enum.map(items, &CartItems.row(cart, &1)))
     |> stream(Contracts.stream_name(:saved), [])
     |> stream(Contracts.stream_name(:wishlist), [])}
  end

  # URL → flow step (V33): browser back/forward or a typed URL asks the
  # checkout flow for a step; the feature's URL policy decides whether to
  # honor it (goto_step). Steps resolve off the generated flow tables.
  @impl true
  def handle_params(params, _url, socket) do
    with :checkout <- socket.assigns.live_action,
         step when step != nil <- Generated.flow_param_step(:checkout, params),
         true <- step != socket.assigns.session.checkout.step do
      run(socket, &CheckoutFlow.Intents.goto_step(&1, step))
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns), do: Generated.page_render(assigns)

  # ── Irregular events (everything else is generated from `intent` metadata) ──

  # Changeset-validated address form: returns a form, not effects.
  @impl true
  def handle_event("validate_address", %{"address" => params}, socket) do
    changeset = CheckoutFlow.Intents.change_address(socket.assigns.session, params)
    {:noreply, assign(socket, :address_form, to_form(changeset, action: :validate))}
  end

  def handle_event("submit_address", %{"address" => params}, socket) do
    case CheckoutFlow.Intents.submit_address(socket.assigns.session, params) do
      {:ok, session, effects} ->
        {:noreply,
         socket
         |> Generated.put_session(session)
         |> assign_address_form()
         |> EffectInterpreter.apply_all(effects, effect_opts())}

      {:error, changeset} ->
        {:noreply, assign(socket, :address_form, to_form(changeset, action: :validate))}
    end
  end

  # Needs fresh stock levels (I/O) before the pure intent runs.
  def handle_event("pay", _params, socket) do
    cart = socket.assigns.session.cart
    stock = Products.stock_levels(Enum.map(cart.items, & &1.product.id))
    run(socket, &CheckoutFlow.Intents.pay(&1, stock))
  end

  # Persists a new cart line (I/O), then hands the pure composition to the intent.
  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, socket) do
    product_id = String.to_integer(id)
    cart_id = socket.assigns.session.cart.cart_id
    Carts.add_item(cart_id, Products.get!(product_id))
    item = cart_id |> Carts.list_items() |> Enum.find(&(&1.product.id == product_id))
    run(socket, &CartItems.Intents.add_wishlisted(&1, item, product_id))
  end

  # R2 (V35): the wishlist toggle needs a *cart* item. The composition owns
  # cross-slot joins, so the shell resolves the item from the cart slot and
  # passes it in — the wishlist feature never reads `session.cart`.
  def handle_event("toggle_wishlist", %{"item-id" => id}, socket) do
    item_id = String.to_integer(id)
    item = Enum.find(socket.assigns.session.cart.items, &(&1.id == item_id))
    run(socket, &Wishlist.Intents.toggle_wishlist(&1, item))
  end

  # Delegate everything declared as an `intent` to the generated clauses.
  def handle_event(event, params, socket), do: Generated.page_event(event, params, socket, &run/2)

  # ── Async payment ────────────────────────────────────────────────────

  @impl true
  def handle_async(:checkout, {:ok, {:ok, url}}, socket) do
    finalize_order(socket.assigns.session.cart.cart_id)
    run(socket, &CheckoutFlow.Intents.checkout_succeeded(&1, url))
  end

  def handle_async(:checkout, {:ok, {:error, _reason}}, socket),
    do: run(socket, &CheckoutFlow.Intents.checkout_failed/1)

  def handle_async(:checkout, {:exit, _reason}, socket),
    do: run(socket, &CheckoutFlow.Intents.checkout_failed/1)

  # ── Cross-process facts and timers ───────────────────────────────────

  # The undo timer's typed message routes to an *intent* (it emits a fact,
  # so it cannot be a single-level manifest reaction).
  @impl true
  def handle_info(%Undo.Facts.UndoExpired{item_id: item_id}, socket),
    do: run(socket, &Undo.Intents.undo_expired(&1, item_id))

  # Any other declared fact struct (cross-process facts arrive over PubSub
  # as the same typed structs the manifest wires) goes straight through the
  # generated reaction table; undeclared structs fall through silently —
  # they are other pages' vocabulary on a shared topic.
  def handle_info(%mod{} = fact, socket) do
    if mod in Generated.declared_facts(),
      do: run(socket, &Generated.apply_fact(&1, fact)),
      else: {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── The one house pattern ────────────────────────────────────────────

  # Pure composition → assigns → effect interpretation. Passed to the
  # generated page_event/4 so the glue stays free of socket wiring.
  defp run(socket, fun) do
    {session, effects} = Generated.run_pure(socket.assigns.session, fun)

    {:noreply,
     socket
     |> Generated.put_session(session)
     |> EffectInterpreter.apply_all(effects, effect_opts())}
  end

  defp effect_opts do
    [
      payment_gateway: Application.get_env(:zero_coupled, :payment_gateway, LedgerGateway),
      checkout_urls: %{success_url: url(~p"/cart/success"), cancel_url: url(~p"/cart")},
      flow_path: &Generated.flow_path/2
    ]
  end

  # Record the order and draw down stock once payment has settled — the work the
  # app used to do on a provider callback, now that checkout settles inline.
  defp finalize_order(cart_id) do
    Orders.create(cart_id)

    cart_id
    |> Carts.list_items()
    |> Enum.each(fn item ->
      case Products.decrement_stock(item.product.id, item.quantity) do
        {:ok, product} -> Broadcast.stock_changed(item.product.id, product.stock)
        {:error, _} -> :ok
      end
    end)
  end

  defp assign_address_form(socket) do
    changeset = CheckoutFlow.Intents.change_address(socket.assigns.session, %{})
    assign(socket, :address_form, to_form(changeset))
  end
end
