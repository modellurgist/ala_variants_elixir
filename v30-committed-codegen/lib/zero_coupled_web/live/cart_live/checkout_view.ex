defmodule ZeroCoupledWeb.CartLive.CheckoutView do
  @moduledoc """
  ActionView for `live_action: :checkout` — the multi-step flow.

  Demonstrates ActionView **sub-state branching**: one action, several
  structurally different screens, chosen by the `CheckoutFlow` slot's
  `step` (not by the URL). The address form validates a changeset live;
  everything else is a straight read of the per-slot assigns
  (`@checkout_slot`, `@cart` render_data) — never `@session`, so
  change tracking skips this view when the checkout wasn't touched.
  """
  use ZeroCoupledWeb, :html

  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-6 py-6">
      <.link navigate={~p"/cart"} class="text-sm text-zinc-500 hover:underline">← Back to cart</.link>
      <h1 class="text-3xl font-semibold py-4">Checkout</h1>
      <.steps step={@checkout_slot.step} />
      <.step_body
        step={@checkout_slot.step}
        checkout={@checkout_slot}
        cart={@cart}
        address_form={@address_form}
      />
    </div>
    """
  end

  defp steps(assigns) do
    ~H"""
    <ol class="flex gap-4 text-sm mb-6">
      <li :for={{s, label} <- [address: "Address", payment: "Payment"]} class={[
        "font-medium",
        active?(@step, s) && "text-zinc-900",
        !active?(@step, s) && "text-zinc-400"
      ]}>
        <%= label %>
      </li>
    </ol>
    """
  end

  defp active?(:address, :address), do: true
  defp active?(step, :payment) when step in [:payment, :processing, :error, :complete], do: true
  defp active?(_, _), do: false

  # Address sub-step — live-validated changeset form.
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

  # Payment sub-step — review + pay.
  defp step_body(%{step: :payment} = assigns) do
    ~H"""
    <div class="space-y-4">
      <.address_summary address={@checkout.address} />
      <div class="flex justify-between font-bold text-xl border-t pt-4">
        <span>Total</span><span><%= @cart.total %></span>
      </div>
      <div class="flex gap-3">
        <button phx-click="edit_address" class="text-sm text-zinc-500 underline">Edit address</button>
        <button phx-click="pay" class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white">
          Pay <%= @cart.total %>
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
      <button phx-click="pay" class="rounded-lg bg-zinc-900 py-2 px-4 text-sm font-semibold text-white">
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

  defp address_summary(assigns) do
    ~H"""
    <div class="rounded border p-4 text-sm text-zinc-700">
      <div class="font-medium"><%= @address.name %></div>
      <div><%= @address.line1 %></div>
      <div><%= @address.city %>, <%= @address.postal_code %></div>
    </div>
    """
  end
end
