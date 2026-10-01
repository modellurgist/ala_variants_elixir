defmodule ZeroCoupled.Features.Checkout.Panel do
  @moduledoc """
  Checkout as a UI instance: the step screens, the address form, the payment job and the order
  it places when paid. Config: `cart_id`, `pricing` (a `Pricing`), `store` (the cart store),
  `stock_levels` (a read function), `place_order` (a `PlaceOrder`), `flow`, `start`, `url_edges`, `milestones`, `gateway`, `urls`, `requested_step` (from the URL; honoured only along
  `url_edges`). Announces `{:checkout, :blocked, reason}` and `{:checkout, :step, step}`.
  """
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]
  alias ZeroCoupled.Cart
  alias ZeroCoupled.Domain.PlaceOrder
  alias ZeroCoupled.Features.Checkout
  alias ZeroCoupledWeb.Paradigms.Instance

  @doc "The ports this instance announces, as `{:checkout, port, payload}`."
  def announces, do: [:step, :blocked]

  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_started() |> follow_url()}

  defp ensure_started(%{assigns: %{state: _}} = s), do: s

  defp ensure_started(%{assigns: a} = s) do
    checkout =
      Checkout.new(
        flow: a.flow,
        start: a.start,
        url_edges: a.url_edges,
        stock_levels: a.stock_levels
      )

    cart = load_cart(a)

    s
    |> assign(
      state: checkout,
      total: cart.total,
      address: nil,
      address_form: to_form(Checkout.address_form(checkout)),
      seen_step: nil
    )
    |> step(&Checkout.start(&1, %{empty?: Cart.empty?(cart)}))
  end

  defp follow_url(%{assigns: %{requested_step: step, seen_step: step}} = s), do: s

  defp follow_url(%{assigns: %{requested_step: step}} = s),
    do: s |> assign(seen_step: step) |> step(&Checkout.goto(&1, step))

  def handle_event("validate_address", %{"address" => p}, s),
    do: {:noreply, step(s, &Checkout.validate(&1, p))}

  def handle_event("submit_address", %{"address" => p}, s),
    do: {:noreply, step(s, &Checkout.submit_address(&1, p))}

  def handle_event("edit_address", _, s), do: {:noreply, step(s, &Checkout.edit_address(&1, nil))}
  def handle_event("pay", _, s), do: {:noreply, step(s, &Checkout.pay(&1, load_cart(s.assigns)))}

  def handle_async(:payment, {:ok, {:ok, url}}, s),
    do: {:noreply, step(s, &Checkout.succeeded(&1, url))}

  def handle_async(:payment, {:ok, {:error, reason}}, s),
    do: {:noreply, step(s, &Checkout.failed(&1, reason))}

  def handle_async(:payment, {:exit, reason}, s),
    do: {:noreply, step(s, &Checkout.failed(&1, reason))}

  defp step(s, fun), do: Instance.step(s, fun, &land/2)

  defp land(s, {:step, step} = out),
    do: s |> assign(step: step) |> Instance.announce(:checkout, out)

  defp land(s, {:form, changeset}),
    do: assign(s, address_form: to_form(changeset, action: :validate))

  defp land(s, {:address, address}), do: assign(s, address: address)

  defp land(s, {:payment, {line_items, cart_id}}),
    do: start_async(s, :payment, fn -> charge(s.assigns, line_items, cart_id) end)

  defp land(s, {:done, url}), do: redirect(finalize(s), external: url)
  defp land(s, out), do: Instance.announce(s, :checkout, out)

  defp load_cart(%{cart_id: cart_id, pricing: pricing, store: store}),
    do: Cart.new(cart_id: cart_id, items: store.list_items(cart_id), pricing: pricing)

  defp charge(%{gateway: gateway, urls: urls}, line_items, cart_id),
    do: gateway.create_checkout_session(line_items, %{"cart_id" => cart_id}, urls)

  # paid: the order exists, the cart is complete, and every bought product's stock drops
  defp finalize(%{assigns: %{cart_id: cart_id, place_order: place_order}} = s) do
    {:ok, _order} = PlaceOrder.run(place_order, cart_id)
    s
  end

  def render(assigns) do
    ~H"""
    <div>
      <.milestones
        step={@step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.screen
        step={@step}
        address={@address}
        address_form={@address_form}
        total={@total}
        myself={@myself}
      />
    </div>
    """
  end

  defp screen(%{step: :address} = assigns) do
    ~H"""
    <.simple_form
      for={@address_form}
      phx-change="validate_address"
      phx-submit="submit_address"
      phx-target={@myself}
    >
      <.input field={@address_form[:name]} label="Full name" phx-hook="AutoFocus" id="address_name" />
      <.input field={@address_form[:line1]} label="Address" />
      <.input field={@address_form[:city]} label="City" />
      <.input field={@address_form[:postal_code]} label="Postal code" />
      <:actions><.button phx-disable-with="Saving…">Continue to payment</.button></:actions>
    </.simple_form>
    """
  end

  defp screen(%{step: :payment} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="rounded border p-4 text-sm text-zinc-700">
        <div class="font-medium">{@address.name}</div>
        <div>{@address.line1}</div>
        <div>{@address.city}, {@address.postal_code}</div>
      </div>
      <div class="flex justify-between font-bold text-xl border-t pt-4">
        <span>Total</span><span>{@total}</span>
      </div>
      <div class="flex gap-3">
        <button phx-click="edit_address" phx-target={@myself} class="text-sm text-zinc-500 underline">
          Edit address
        </button>
        <button
          phx-click="pay"
          phx-target={@myself}
          class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
        >
          Pay {@total}
        </button>
      </div>
    </div>
    """
  end

  defp screen(%{step: :processing} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 text-zinc-500 py-6">
      <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
      Processing payment…
    </div>
    """
  end

  defp screen(%{step: :error} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-red-600 text-sm">Payment failed.</p>
      <button
        phx-click="pay"
        phx-target={@myself}
        class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
      >
        Try again
      </button>
    </div>
    """
  end

  defp screen(assigns) do
    ~H"""
    <p class="text-zinc-500 py-6">Redirecting…</p>
    """
  end
end
