defmodule GoodDeal.State.OrderTotals do
  @moduledoc """
  A bulk order's priced summary: the last contents it was given (each line's quantity and amount),
  priced by volume tier with the store's configured rules (`shipping`, `volume`) in `summary/1`. Its
  data is its own: the portal has no promo, gift wrap or shipping choice (Spray §6.17.2).
  """
  alias GoodDeal.Domain.{
    ApplyDiscount,
    CalculateShipping,
    CalculateSubtotal,
    ItemCount
  }

  defstruct pricing: %{}, lines: [], shipping_method: :standard

  @doc "Config: `pricing`: the configured `shipping` rule and `volume`, a function of the subtotal returning `{percent, label}`."
  def new(opts), do: %__MODULE__{pricing: opts[:pricing]}

  def contents(%__MODULE__{} = totals, %{lines: lines}), do: %{totals | lines: lines}

  # the order's own pricing: subtotal, its volume tier's discount, then shipping on the subtotal
  def summary(%__MODULE__{pricing: pricing, lines: lines, shipping_method: method}) do
    subtotal = CalculateSubtotal.call(lines)
    {pct, tier_label} = pricing.volume.(subtotal)
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
