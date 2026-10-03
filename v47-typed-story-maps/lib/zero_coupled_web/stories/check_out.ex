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
    <div class="mx-auto max-w-lg">
      <.link navigate={~p"/cart"} class="text-sm font-medium text-stone-500 hover:text-stone-800">
        {@t.back}
      </.link>
      <h1 class="py-4 text-3xl font-semibold tracking-tight">{@t.heading}</h1>
      <.milestones
        step={@story.view.step}
        milestones={@story.view.milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.card>
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
            <div class="rounded-xl bg-stone-50 p-4 text-sm text-stone-700">
              <div class="font-medium">{@story.view.address.name}</div>
              <div>{@story.view.address.line1}</div>
              <div>{@story.view.address.city}, {@story.view.address.postal_code}</div>
            </div>
            <div class="flex justify-between border-t border-stone-200 pt-4 text-lg font-semibold">
              <span>{@t.total}</span><span>{@story.view.summary.total}</span>
            </div>
            <div class="flex items-center justify-between gap-3">
              <button
                phx-click="edit_address"
                class="text-sm font-medium text-stone-500 hover:text-stone-800"
              >
                {@t.edit_address}
              </button>
              <.primary_button event="pay">{@t.pay} {@story.view.summary.total}</.primary_button>
            </div>
          </div>
        </.only_on>
        <.only_on current={@story.view.step} name={:processing}>
          <div class="flex items-center gap-3 py-6 text-stone-500">
            <svg class="h-5 w-5 animate-spin text-brand-700" viewBox="0 0 24 24" fill="none">
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              />
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
            <p class="rounded-xl bg-red-50 p-4 text-sm text-red-700">{@t.payment_failed}</p>
            <.primary_button event="pay">{@t.try_again}</.primary_button>
          </div>
        </.only_on>
        <.only_on current={@story.view.step} name={:complete}>
          <p class="py-6 text-stone-500">{@t.redirecting}</p>
        </.only_on>
      </.card>
    </div>
    """
  end
end
