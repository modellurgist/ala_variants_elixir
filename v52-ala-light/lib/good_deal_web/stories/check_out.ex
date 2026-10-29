defmodule GoodDealWeb.Stories.CheckOut do
  @moduledoc """
  The shopper checks out: an address, then payment, which runs as a LiveView task, then settling the
  order and leaving for the success page. Its part is the checkout flow; its view is the checkout
  steps. The page hands it the configured payment instances (`charge`, `settle`) and line-item
  builder, which carry app-level choices; the flow, its URLs and its messages are this story's own.
  Out: `:step`, `:form`, `:address`, for the view the page places, and `:pay_requested` when the
  shopper presses Pay, for the cart's lines.
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2, start_async: 3]
  import GoodDeal.Components.Panes, only: [only_on: 1]
  import GoodDeal.Components.Parts, only: [card: 1, primary_button: 1]
  import GoodDeal.Components.Rows, only: [milestones: 1]

  alias GoodDeal.Domain.{Charge, SettleOrder}
  alias GoodDeal.State.Checkout
  alias GoodDeal.Foundation.Products
  alias GoodDealWeb.Paradigms.Steps

  @flow [
    {:address, :submit_address, :payment},
    {:payment, :edit_address, :address},
    {:payment, :pay, :processing},
    {:error, :pay, :processing}
  ]
  @url_edges [{:payment, :address}]
  @step_paths %{address: "/cart/checkout", payment: "/cart/checkout/payment"}
  @blocked %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}

  def parts, do: %{checkout: Checkout}
  def events, do: ~w(validate_address submit_address edit_address pay)

  def ports,
    do: %{
      in: [
        start: :summary,
        pay: :checkout_request,
        goto: :step,
        succeeded: :url,
        failed: :reason
      ],
      out: [step: :step, form: :changeset, address: :address, pay_requested: :event]
    }

  @doc """
  Config: `charge` and `settle` (configured instances), `line_items` (a `BuildLineItems`), and
  `task`, the name the page gives the payment task.
  """
  def mount(s, opts, out) do
    checkout =
      Checkout.new(
        flow: @flow,
        start: :address,
        url_edges: @url_edges,
        stock_levels: &Products.stock_levels/1,
        line_items: opts[:line_items],
        messages: %{postal_code: "must be 4–10 digits"}
      )

    s
    |> assign(
      checkout: checkout,
      charge: {opts[:task], opts[:charge]},
      settle: opts[:settle]
    )
    |> run(&Checkout.show_form(&1, nil), out)
  end

  def handle_event("validate_address", %{"address" => params}, s, out),
    do: run(s, &Checkout.validate(&1, params), out)

  def handle_event("submit_address", %{"address" => params}, s, out),
    do: run(s, &Checkout.submit_address(&1, params), out)

  def handle_event("edit_address", _params, s, out),
    do: run(s, &Checkout.edit_address(&1, nil), out)

  def handle_event("pay", _params, s, out), do: out.(s, {:pay_requested, nil})

  def input(s, :start, summary, out), do: run(s, &Checkout.start(&1, summary), out)
  def input(s, :pay, request, out), do: run(s, &Checkout.pay(&1, request), out)
  def input(s, :goto, step, out), do: run(s, &Checkout.goto(&1, step), out)
  def input(s, :succeeded, reference, out), do: run(s, &Checkout.succeeded(&1, reference), out)
  def input(s, :failed, reason, out), do: run(s, &Checkout.failed(&1, reason), out)

  defp run(s, step, out), do: Steps.run(s, :checkout, step, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :checkout, {:step, step}, out),
    do: s |> Steps.patch(@step_paths, step) |> out.({:step, step})

  defp wire(s, :checkout, {:form, changeset}, out), do: out.(s, {:form, changeset})
  defp wire(s, :checkout, {:address, address}, out), do: out.(s, {:address, address})
  defp wire(s, :checkout, {:blocked, reason}, _out), do: put_flash(s, :error, @blocked[reason])

  # the payment runs as a LiveView task; the page's handle_async/3 routes its outcome back here
  defp wire(s, :checkout, {:ready_to_pay, payment}, _out) do
    {task, charge} = s.assigns.charge
    start_async(s, task, fn -> Charge.call(charge, payment) end)
  end

  defp wire(s, :checkout, {:done, reference}, _out) do
    SettleOrder.run(s.assigns.settle, reference)
    push_navigate(s, to: ~p"/cart/success")
  end

  attr :step, :atom, required: true
  attr :milestones, :list, required: true
  attr :form, :any, required: true
  attr :address, :map, default: nil
  attr :total, :any, required: true
  attr :t, :map, required: true

  def view(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg">
      <.link navigate={~p"/cart"} class="text-sm font-medium text-stone-500 hover:text-stone-800">
        {@t.back}
      </.link>
      <h1 class="py-4 text-3xl font-semibold tracking-tight">{@t.heading}</h1>
      <.milestones
        step={@step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.card>
        <.only_on current={@step} name={:address}>
          <.simple_form for={@form} phx-change="validate_address" phx-submit="submit_address">
            <.input field={@form[:name]} label={@t.name} phx-hook="AutoFocus" id="address_name" />
            <.input field={@form[:line1]} label={@t.line1} />
            <.input field={@form[:city]} label={@t.city} />
            <.input field={@form[:postal_code]} label={@t.postal_code} />
            <:actions>
              <.button phx-disable-with={@t.saving}>{@t.continue}</.button>
            </:actions>
          </.simple_form>
        </.only_on>
        <.only_on current={@step} name={:payment}>
          <div class="space-y-4">
            <div class="rounded-xl bg-stone-50 p-4 text-sm text-stone-700">
              <div class="font-medium">{@address.name}</div>
              <div>{@address.line1}</div>
              <div>{@address.city}, {@address.postal_code}</div>
            </div>
            <div class="flex justify-between border-t border-stone-200 pt-4 text-lg font-semibold">
              <span>{@t.total}</span><span>{@total}</span>
            </div>
            <div class="flex items-center justify-between gap-3">
              <button
                phx-click="edit_address"
                class="text-sm font-medium text-stone-500 hover:text-stone-800"
              >
                {@t.edit_address}
              </button>
              <.primary_button event="pay">{@t.pay} {@total}</.primary_button>
            </div>
          </div>
        </.only_on>
        <.only_on current={@step} name={:processing}>
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
        <.only_on current={@step} name={:error}>
          <div class="space-y-3">
            <p class="rounded-xl bg-red-50 p-4 text-sm text-red-700">{@t.payment_failed}</p>
            <.primary_button event="pay">{@t.try_again}</.primary_button>
          </div>
        </.only_on>
        <.only_on current={@step} name={:complete}>
          <p class="py-6 text-stone-500">{@t.redirecting}</p>
        </.only_on>
      </.card>
    </div>
    """
  end
end
