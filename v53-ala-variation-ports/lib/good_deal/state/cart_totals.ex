defmodule GoodDeal.State.CartTotals do
  @moduledoc """
  The cart's priced summary. It keeps the last of three things it is told (the cart's contents, each
  line's quantity and amount and the wrapped count; the promo discount; the chosen shipping method)
  and prices them with the store's configured rules (`shipping`, `gift_wrap`) in `summary/1`.
  """
  alias GoodDeal.Domain.{
    ApplyDiscount,
    CalculateShipping,
    CalculateSubtotal,
    ItemCount
  }

  defstruct pricing: %{}, lines: [], wrapped_count: 0, discount: nil, method: :standard

  @doc "Config: `pricing`: the configured `shipping` rule and optionally `gift_wrap`, a function of the wrapped count."
  def new(opts), do: %__MODULE__{pricing: opts[:pricing]}

  def contents(%__MODULE__{} = totals, %{lines: lines, wrapped_count: count}),
    do: %{totals | lines: lines, wrapped_count: count}

  def discount(%__MODULE__{} = totals, discount), do: %{totals | discount: discount}
  def select_shipping(%__MODULE__{} = totals, method), do: %{totals | method: method}

  def summary(%__MODULE__{pricing: pricing} = t) do
    subtotal = CalculateSubtotal.call(t.lines)
    {after_discount, discount} = ApplyDiscount.call(subtotal, t.discount && t.discount.percentage)
    gift_wrap = gift_wrap(pricing, t.wrapped_count)
    shipping = CalculateShipping.call(pricing.shipping, t.method, subtotal)

    %{
      empty?: t.lines == [],
      item_count: ItemCount.call(t.lines),
      subtotal: Money.new(subtotal),
      discount: Money.new(discount),
      promo_code: t.discount && t.discount.code,
      gift_wrap_total: Money.new(gift_wrap),
      shipping_method: t.method,
      shipping_label: CalculateShipping.label(pricing.shipping, t.method),
      shipping_cost: Money.new(shipping),
      shipping_options:
        for rate <- CalculateShipping.options(pricing.shipping) do
          %{
            method: rate.method,
            label: rate.label,
            cost: Money.new(rate.cost),
            free_above: rate.free_above && Money.new(rate.free_above)
          }
        end,
      total: Money.new(after_discount + gift_wrap + shipping)
    }
  end

  # a store may configure no gift wrap
  defp gift_wrap(%{gift_wrap: wrap}, count), do: wrap.(count)
  defp gift_wrap(_pricing, _count), do: 0
end
