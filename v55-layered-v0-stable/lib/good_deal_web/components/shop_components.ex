defmodule GoodDealWeb.ShopComponents do
  @moduledoc """
  Store-specific UI components and formatting helpers.
  """
  use Phoenix.Component

  alias GoodDeal.Domain.StockStatus

  @doc """
  Formats an amount in cents as dollars, e.g. `1299` -> `"$12.99"`.
  """
  def price(cents) when is_integer(cents) do
    "$#{div(cents, 100)}." <>
      (cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0"))
  end

  def order_reference(%{id: id}), do: "GD-" <> String.pad_leading(to_string(id), 6, "0")

  attr :product, :map, required: true
  attr :channel, GoodDeal.Channel, required: true

  def stock_badge(assigns) do
    assigns = assign(assigns, :status, StockStatus.of(assigns.channel, assigns.product.stock))

    ~H"""
    <span class={[
      "rounded-full px-2 py-0.5 text-xs font-medium",
      badge_class(@status)
    ]}>
      {badge_label(@status)}
    </span>
    """
  end

  defp badge_label(:in_stock), do: "In stock"
  defp badge_label(:low_stock), do: "Low stock"
  defp badge_label(:out_of_stock), do: "Out of stock"

  defp badge_class(:in_stock), do: "bg-green-100 text-green-800"
  defp badge_class(:low_stock), do: "bg-amber-100 text-amber-800"
  defp badge_class(:out_of_stock), do: "bg-red-100 text-red-800"

  attr :id, :string, default: "summary"
  attr :summary, :map, required: true

  def price_summary(assigns) do
    ~H"""
    <dl id={@id} class="space-y-1 text-sm">
      <div class="flex justify-between">
        <dt>Items</dt>
        <dd>{@summary.item_count}</dd>
      </div>
      <div class="flex justify-between">
        <dt>Subtotal</dt>
        <dd>{price(@summary.subtotal)}</dd>
      </div>
      <div :if={@summary.discount > 0} class="flex justify-between text-green-700">
        <dt>Discount ({@summary.discount_label})</dt>
        <dd>-{price(@summary.discount)}</dd>
      </div>
      <div :if={@summary.gift_wrap > 0} class="flex justify-between">
        <dt>Gift wrap</dt>
        <dd>{price(@summary.gift_wrap)}</dd>
      </div>
      <div class="flex justify-between">
        <dt>Shipping ({@summary.shipping_label})</dt>
        <dd>{if @summary.shipping == 0, do: "Free", else: price(@summary.shipping)}</dd>
      </div>
      <div class="flex justify-between border-t pt-1 font-semibold">
        <dt>Total</dt>
        <dd>{price(@summary.total)}</dd>
      </div>
    </dl>
    """
  end

  attr :methods, :list, required: true
  attr :selected, :string, required: true

  def shipping_picker(assigns) do
    ~H"""
    <fieldset id="shipping-methods" class="space-y-1 text-sm">
      <legend class="font-semibold">Shipping</legend>
      <button
        :for={method <- @methods}
        type="button"
        phx-click="select_shipping"
        phx-value-method={method.id}
        aria-pressed={to_string(method.id == @selected)}
        class={[
          "block w-full rounded border px-2 py-1 text-left",
          method.id == @selected && "border-zinc-900 font-semibold"
        ]}
      >
        {method.label} · {price(method.cost)}
        <span :if={method.free_above}>(free above {price(method.free_above)})</span>
      </button>
    </fieldset>
    """
  end

  attr :pending, :any, required: true

  def undo_banner(assigns) do
    ~H"""
    <div
      :if={@pending}
      id="undo-banner"
      class="my-4 flex items-center justify-between rounded bg-zinc-900 px-4 py-2 text-white"
    >
      <span>Item removed.</span>
      <button type="button" phx-click="undo_remove" class="font-semibold underline">Undo</button>
    </div>
    """
  end
end
