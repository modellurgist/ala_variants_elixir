defmodule GoodDealWeb.Stories.CheckOut do
  @moduledoc """
  The shopper checks out: enters an address, pays, and is sent on once the order is settled. Its part
  is the checkout's step machine; its instances charge the payment and settle the order; its view is
  the checkout's steps. Ports: `start` with the cart's summary, the `summary` as it changes, `pay` for
  a cart, `goto` a step the URL names, and the payment's outcome (`succeeded`, `failed`); out,
  `pay_requested` when the shopper presses Pay.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  import GoodDeal.Components.Panes, only: [only_on: 1]
  import GoodDeal.Components.Parts, only: [primary_button: 1]
  import GoodDeal.Components.Rows, only: [milestones: 1]

  alias GoodDeal.Domain.{Charge, SettleOrder}
  alias GoodDeal.State.Checkout
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  @step_paths %{address: "/cart/checkout", payment: "/cart/checkout/payment"}
  @blocked %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}

  def parts, do: %{checkout: Checkout}
  def streams, do: []
  def events, do: ~w(validate_address submit_address edit_address pay)

  def ports,
    do: %{
      in: [
        mounted: :event,
        start: :summary,
        summary: :summary,
        pay: :checkout_request,
        goto: :step,
        succeeded: :reference,
        failed: :reason
      ],
      out: [pay_requested: :event]
    }

  @doc """
  Config: `checkout`, the options of its step machine (see `GoodDeal.State.Checkout`); `charge` and
  `settle`, its configured instances; and the `milestones` it shows.
  """
  def new(opts),
    do:
      Story.new(__MODULE__, %{checkout: Checkout.new(opts[:checkout])},
        instances: %{charge: opts[:charge], settle: opts[:settle]},
        view: [
          step: :address,
          form: nil,
          address: nil,
          summary: nil,
          milestones: opts[:milestones]
        ]
      )

  def input(s, me, :mounted, _), do: Story.run(s, me, :checkout, &Checkout.show_form(&1, nil))
  def input(s, me, :start, summary), do: Story.run(s, me, :checkout, &Checkout.start(&1, summary))
  def input(s, me, :summary, summary), do: Story.show(s, me, :summary, summary)
  def input(s, me, :pay, cart), do: Story.run(s, me, :checkout, &Checkout.pay(&1, cart))
  def input(s, me, :goto, step), do: Story.run(s, me, :checkout, &Checkout.goto(&1, step))

  def input(s, me, :succeeded, reference),
    do: Story.run(s, me, :checkout, &Checkout.succeeded(&1, reference))

  def input(s, me, :failed, reason), do: Story.run(s, me, :checkout, &Checkout.failed(&1, reason))

  def event(s, me, "validate_address", %{"address" => params}),
    do: Story.run(s, me, :checkout, &Checkout.validate(&1, params))

  def event(s, me, "submit_address", %{"address" => params}),
    do: Story.run(s, me, :checkout, &Checkout.submit_address(&1, params))

  def event(s, me, "edit_address", _),
    do: Story.run(s, me, :checkout, &Checkout.edit_address(&1, nil))

  def event(s, me, "pay", _), do: Story.send_out(s, me, :pay_requested, nil)

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, me, :checkout, {:step, step}),
    do: s |> Story.show(me, :step, step) |> Sinks.patch(@step_paths, step)

  def wire(s, me, :checkout, {:form, changeset}),
    do: Story.show(s, me, :form, to_form(changeset, action: :validate))

  def wire(s, me, :checkout, {:address, address}), do: Story.show(s, me, :address, address)
  def wire(s, _me, :checkout, {:blocked, reason}), do: put_flash(s, :error, @blocked[reason])

  def wire(s, me, :checkout, {:ready_to_pay, payment}),
    do: Story.async(s, me, {:charge, &Charge.call/2}, payment, ok: :succeeded, error: :failed)

  def wire(s, me, :checkout, {:done, reference}),
    do:
      s
      |> Story.call(me, {:settle, &SettleOrder.run/2}, reference)
      |> push_navigate(to: ~p"/cart/success")

  attr :story, :map, required: true
  attr :t, :map, required: true, doc: "the checkout's texts, from the page"

  def view(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">{@t.back}</.link>
      <h1 class="text-3xl font-semibold py-4">{@t.heading}</h1>
      <.milestones
        step={@story.view.step}
        milestones={@story.view.milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.only_on current={@story.view.step} name={:address}>
        <.simple_form
          for={@story.view.form}
          phx-change="validate_address"
          phx-submit="submit_address"
        >
          <.input
            field={@story.view.form[:name]}
            label={@t.name}
            phx-hook="AutoFocus"
            id="address_name"
          />
          <.input field={@story.view.form[:line1]} label={@t.line1} />
          <.input field={@story.view.form[:city]} label={@t.city} />
          <.input field={@story.view.form[:postal_code]} label={@t.postal_code} />
          <:actions>
            <.button phx-disable-with={@t.saving}>{@t.continue}</.button>
          </:actions>
        </.simple_form>
      </.only_on>
      <.only_on current={@story.view.step} name={:payment}>
        <div class="space-y-4">
          <div class="rounded border p-4 text-sm text-zinc-700">
            <div class="font-medium">{@story.view.address.name}</div>
            <div>{@story.view.address.line1}</div>
            <div>{@story.view.address.city}, {@story.view.address.postal_code}</div>
          </div>
          <div class="flex justify-between font-bold text-xl border-t pt-4">
            <span>{@t.total}</span><span>{@story.view.summary.total}</span>
          </div>
          <div class="flex gap-3">
            <button phx-click="edit_address" class="text-sm text-zinc-500 underline">
              {@t.edit_address}
            </button>
            <.primary_button event="pay">{@t.pay} {@story.view.summary.total}</.primary_button>
          </div>
        </div>
      </.only_on>
      <.only_on current={@story.view.step} name={:processing}>
        <div class="flex items-center gap-3 text-zinc-500 py-6">
          <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path
              class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
            />
          </svg>
          {@t.processing}
        </div>
      </.only_on>
      <.only_on current={@story.view.step} name={:error}>
        <div class="space-y-3">
          <p class="text-red-600 text-sm">{@t.payment_failed}</p>
          <.primary_button event="pay">{@t.try_again}</.primary_button>
        </div>
      </.only_on>
      <.only_on current={@story.view.step} name={:complete}>
        <p class="text-zinc-500 py-6">{@t.redirecting}</p>
      </.only_on>
    </div>
    """
  end
end
