defmodule ZeroCoupledWeb.CartLive.CheckoutView do
  @moduledoc "The checkout screens, one per step of the flow the page configured."
  use ZeroCoupledWeb, :html
  import ZeroCoupledWeb.Rows, only: [milestones: 1]

  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">← Back to cart</.link>
      <h1 class="text-3xl font-semibold py-4">Checkout</h1>
      <.milestones
        step={@step}
        milestones={@milestones}
        order={[:address, :payment, :processing, :error, :complete]}
      />
      <.step_body step={@step} address={@address} address_form={@address_form} total={@summary.total} />
    </div>
    """
  end

  defp step_body(%{step: :address} = assigns) do
    ~H"""
    <.simple_form for={@address_form} phx-change="validate_address" phx-submit="submit_address">
      <.input field={@address_form[:name]} label="Full name" phx-hook="AutoFocus" id="address_name" />
      <.input field={@address_form[:line1]} label="Address" />
      <.input field={@address_form[:city]} label="City" />
      <.input field={@address_form[:postal_code]} label="Postal code" />
      <:actions>
        <.button phx-disable-with="Saving…">Continue to payment</.button>
      </:actions>
    </.simple_form>
    """
  end

  defp step_body(%{step: :payment} = assigns) do
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
        <button phx-click="edit_address" class="text-sm text-zinc-500 underline">Edit address</button>
        <button
          phx-click="pay"
          class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
        >
          Pay {@total}
        </button>
      </div>
    </div>
    """
  end

  defp step_body(%{step: :processing} = assigns) do
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

  defp step_body(%{step: :error} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-red-600 text-sm">Payment failed.</p>
      <button
        phx-click="pay"
        class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white"
      >
        Try again
      </button>
    </div>
    """
  end

  defp step_body(%{step: :complete} = assigns) do
    ~H"""
    <p class="text-zinc-500 py-6">Redirecting…</p>
    """
  end
end
