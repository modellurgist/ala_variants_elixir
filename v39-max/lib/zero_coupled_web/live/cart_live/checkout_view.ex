defmodule ZeroCoupledWeb.CartLive.CheckoutView do
  @moduledoc "The checkout screens, one per step of the flow the page configured."
  use ZeroCoupledWeb, :html
  import ZeroCoupled.Catalog.Rows, only: [milestones: 1]
  import ZeroCoupled.Catalog.{Panes, Parts}

  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">
        {@texts.checkout.back}
      </.link>
      <h1 class="text-3xl font-semibold py-4">{@texts.checkout.heading}</h1>
      <.milestones
        step={@step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.only_on current={@step} name={:address}>
        <.simple_form for={@address_form} phx-change="validate_address" phx-submit="submit_address">
          <.input
            field={@address_form[:name]}
            label={@texts.checkout.name}
            phx-hook="AutoFocus"
            id="address_name"
          />
          <.input field={@address_form[:line1]} label={@texts.checkout.line1} />
          <.input field={@address_form[:city]} label={@texts.checkout.city} />
          <.input field={@address_form[:postal_code]} label={@texts.checkout.postal_code} />
          <:actions>
            <.button phx-disable-with={@texts.checkout.saving}>{@texts.checkout.continue}</.button>
          </:actions>
        </.simple_form>
      </.only_on>
      <.only_on current={@step} name={:payment}>
        <div class="space-y-4">
          <div class="rounded border p-4 text-sm text-zinc-700">
            <div class="font-medium">{@address.name}</div>
            <div>{@address.line1}</div>
            <div>{@address.city}, {@address.postal_code}</div>
          </div>
          <div class="flex justify-between font-bold text-xl border-t pt-4">
            <span>{@texts.checkout.total}</span><span>{@summary.total}</span>
          </div>
          <div class="flex gap-3">
            <button phx-click="edit_address" class="text-sm text-zinc-500 underline">
              {@texts.checkout.edit_address}
            </button>
            <.primary_button event="pay">{@texts.checkout.pay} {@summary.total}</.primary_button>
          </div>
        </div>
      </.only_on>
      <.only_on current={@step} name={:processing}>
        <div class="flex items-center gap-3 text-zinc-500 py-6">
          <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path
              class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
            />
          </svg>
          {@texts.checkout.processing}
        </div>
      </.only_on>
      <.only_on current={@step} name={:error}>
        <div class="space-y-3">
          <p class="text-red-600 text-sm">{@texts.checkout.payment_failed}</p>
          <.primary_button event="pay">{@texts.checkout.try_again}</.primary_button>
        </div>
      </.only_on>
      <.only_on current={@step} name={:complete}>
        <p class="text-zinc-500 py-6">{@texts.checkout.redirecting}</p>
      </.only_on>
    </div>
    """
  end
end
