defmodule ZeroCoupledWeb.Stories.CheckOut do
  @moduledoc """
  The shopper checks out: enters an address, pays, and is sent on once the order is placed. Its part
  is the checkout's step machine; its configured `StartPayment` and `PlaceOrder` do the I/O; its view
  is the checkout's steps.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]
  import ZeroCoupled.Catalog.{Panes, Parts}

  alias ZeroCoupled.State.Checkout
  alias ZeroCoupledWeb.Paradigms.Binder

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
        succeeded: :url,
        failed: :reason
      ],
      out: [pay_requested: :event]
    }

  @doc """
  Config: `checkout`, the options of its step machine (see `ZeroCoupled.State.Checkout`); its
  `start_payment` and `place_order` instances; and the `milestones` it shows.
  """
  def new(opts),
    do:
      Binder.story(
        __MODULE__,
        %{checkout: Checkout.new(opts[:checkout])},
        bindings(opts[:start_payment], opts[:place_order]),
        step: :address,
        form: nil,
        address: nil,
        summary: nil,
        milestones: opts[:milestones]
      )

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings(start_payment, place_order) do
    %{
      {:in, :mounted} => [{:input, :checkout, &Checkout.show_form/2}],
      {:in, :start} => [{:input, :checkout, &Checkout.start/2}],
      {:in, :summary} => [{:show, :summary}],
      {:in, :pay} => [{:input, :checkout, &Checkout.pay/2}],
      {:in, :goto} => [{:input, :checkout, &Checkout.goto/2}],
      {:in, :succeeded} => [{:input, :checkout, &Checkout.succeeded/2}],
      {:in, :failed} => [{:input, :checkout, &Checkout.failed/2}],
      {:checkout, :step} => [{:show, :step}, {:patch, @step_paths}],
      {:checkout, :form} => [{:form, :form}],
      {:checkout, :address} => [{:show, :address}],
      {:checkout, :blocked} => [{:flash_for, :error, @blocked}],
      {:checkout, :ready_to_pay} => [{:async, start_payment, :succeeded, :failed}],
      {:checkout, :done} => [{:call, place_order}, :redirect]
    }
  end

  def event(s, me, "validate_address", %{"address" => params}),
    do: Binder.run(s, me, :checkout, &Checkout.validate(&1, params))

  def event(s, me, "submit_address", %{"address" => params}),
    do: Binder.run(s, me, :checkout, &Checkout.submit_address(&1, params))

  def event(s, me, "edit_address", _),
    do: Binder.run(s, me, :checkout, &Checkout.edit_address(&1, nil))

  def event(s, me, "pay", _), do: Binder.send_out(s, me, :pay_requested, nil)

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
