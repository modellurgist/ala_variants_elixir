defmodule ZeroCoupled.State.Checkout.Panel do
  @moduledoc """
  Checkout as a UI instance: the step screens and the address form. A cart ready to pay goes out
  for the page to charge, the payment's outcome comes back as `succeeded` or `failed`, and a paid
  cart goes out as `done` for the page to settle. Config: `cart_id`, `total` (the cart's total, from
  its summary), `source` (a read of the stored lines, wired by the page), `stock_levels` (a read function),
  `line_items` (a `BuildLineItems`), `messages` (the address form's), `flow`, `start`,
  `url_edges`, `milestones`, `requested_step` (from the URL; honoured only along `url_edges`).
  Sends the page, under the `name` it's given, `{name, port, payload}` for `:step`, `:blocked`, `:ready_to_pay`, `:done`.
  """
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]
  alias ZeroCoupled.State.Checkout
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is sent
  @wired_here [:form, :address]

  @doc "The ports this instance sends the page, as `{name, port, payload}`."
  def sent_port_outputs, do: Keyword.keys(Checkout.ports().out) -- @wired_here

  def update(%{succeeded: url}, s), do: {:ok, step(s, &Checkout.succeeded(&1, url))}
  def update(%{failed: reason}, s), do: {:ok, step(s, &Checkout.failed(&1, reason))}
  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_started() |> follow_url()}

  defp ensure_started(%{assigns: %{state: _}} = s), do: s

  defp ensure_started(%{assigns: a} = s) do
    checkout =
      Checkout.new(
        flow: a.flow,
        start: a.start,
        url_edges: a.url_edges,
        stock_levels: a.stock_levels,
        line_items: a.line_items,
        messages: a.messages
      )

    s
    |> assign(
      state: checkout,
      address: nil,
      address_form: to_form(Checkout.address_form(checkout)),
      seen_step: nil
    )
    |> step(&Checkout.open(&1, lines(a)))
  end

  defp follow_url(%{assigns: %{requested_step: step, seen_step: step}} = s), do: s

  defp follow_url(%{assigns: %{requested_step: step}} = s),
    do: s |> assign(seen_step: step) |> step(&Checkout.goto(&1, step))

  def handle_event("validate_address", %{"address" => p}, s),
    do: {:noreply, step(s, &Checkout.validate(&1, p))}

  def handle_event("submit_address", %{"address" => p}, s),
    do: {:noreply, step(s, &Checkout.submit_address(&1, p))}

  def handle_event("edit_address", _, s), do: {:noreply, step(s, &Checkout.edit_address(&1, nil))}
  def handle_event("pay", _, s), do: {:noreply, step(s, &Checkout.pay(&1, lines(s.assigns)))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)

  defp wire(s, {:step, step} = out),
    do: s |> assign(step: step) |> Instance.send_port_output(s.assigns.name, out)

  defp wire(s, {:form, changeset}),
    do: assign(s, address_form: to_form(changeset, action: :validate))

  defp wire(s, {:address, address}), do: assign(s, address: address)

  defp wire(s, out), do: Instance.send_port_output(s, s.assigns.name, out)

  # the stored lines, read through the pull port the page wired
  defp lines(%{cart_id: cart_id, source: source}), do: {cart_id, source.(cart_id)}

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
        t={@t}
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
      <.input field={@address_form[:name]} label={@t.name} phx-hook="AutoFocus" id="address_name" />
      <.input field={@address_form[:line1]} label={@t.line1} />
      <.input field={@address_form[:city]} label={@t.city} />
      <.input field={@address_form[:postal_code]} label={@t.postal_code} />
      <:actions><.button phx-disable-with={@t.saving}>{@t.continue}</.button></:actions>
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
        <span>{@t.total}</span><span>{@total}</span>
      </div>
      <div class="flex gap-3">
        <button phx-click="edit_address" phx-target={@myself} class="text-sm text-zinc-500 underline">
          {@t.edit_address}
        </button>
        <button
          phx-click="pay"
          phx-target={@myself}
          class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
        >
          {@t.pay} {@total}
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
      {@t.processing}
    </div>
    """
  end

  defp screen(%{step: :error} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-red-600 text-sm">{@t.payment_failed}</p>
      <button
        phx-click="pay"
        phx-target={@myself}
        class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
      >
        {@t.try_again}
      </button>
    </div>
    """
  end

  defp screen(assigns) do
    ~H"""
    <p class="text-zinc-500 py-6">{@t.redirecting}</p>
    """
  end
end
