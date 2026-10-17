defmodule GoodDeal.State.OrderTotals do
  @moduledoc """
  A bulk order's priced summary: the last contents it was given (each line's quantity and amount),
  priced by volume tier with the store's configured rules (`shipping`, `volume`). Its data is its
  own: the portal has no promo, gift wrap or shipping choice (Spray §6.17.2). Every change sends the
  new `:summary`; `:review` hands the summary to whoever runs the review step.
  """
  alias GoodDeal.Domain.{
    ApplyDiscount,
    CalculateShipping,
    CalculateSubtotal,
    ItemCount,
    VolumeTier
  }

  defstruct pricing: %{}, lines: [], shipping_method: :standard

  def ports,
    do: %{
      in: [contents: :contents, request_review: :event],
      out: [summary: :summary, review: :summary]
    }

  @doc "Config: `pricing`, the configured `shipping` and `volume` rules."
  def new(opts), do: %__MODULE__{pricing: opts[:pricing]}

  def contents(%__MODULE__{} = totals, %{lines: lines}) do
    totals = %{totals | lines: lines}
    {totals, [summary: summary(totals)]}
  end

  @doc "The buyer wants to review the order: its summary goes out."
  def request_review(%__MODULE__{} = totals, _), do: {totals, [review: summary(totals)]}

  # the order's own pricing: subtotal, its volume tier's discount, then shipping on the subtotal
  defp summary(%__MODULE__{pricing: pricing, lines: lines, shipping_method: method}) do
    subtotal = CalculateSubtotal.call(lines)
    {pct, tier_label} = VolumeTier.call(pricing.volume, subtotal)
    {after_discount, discount} = ApplyDiscount.call(subtotal, pct)
    shipping = CalculateShipping.call(pricing.shipping, method, subtotal)

    %{
      empty?: lines == [],
      item_count: ItemCount.call(lines),
      subtotal: Money.new(subtotal),
      discount: Money.new(discount),
      tier_label: tier_label,
      shipping_label: CalculateShipping.label(pricing.shipping, method),
      shipping_cost: Money.new(shipping),
      total: Money.new(after_discount + shipping)
    }
  end
end
