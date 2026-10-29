defmodule GoodDeal.Domain.Pricing do
  @moduledoc """
  Prices a list of cart items (with products preloaded). All amounts are in cents.

  The caller configures the channel: `discount` and `shipping` take the subtotal and
  answer `{percent, label}` and a cost; `gift_wrap_price` is 0 where wrapping is not charged.
  The summary carries the `items` it priced, so an order can be placed from it alone.
  """

  @enforce_keys [:discount, :shipping, :shipping_label]
  defstruct [:discount, :shipping, :shipping_label, gift_wrap_price: 0]

  def summary(%__MODULE__{} = pricing, items) do
    subtotal = Enum.sum_by(items, &line_total/1)
    {percent, discount_label} = pricing.discount.(subtotal)
    discount = div(subtotal * percent, 100)
    gift_wrap = Enum.count(items, & &1.gift_wrap) * pricing.gift_wrap_price
    shipping = pricing.shipping.(subtotal)

    %{
      items: items,
      item_count: Enum.sum_by(items, & &1.quantity),
      subtotal: subtotal,
      discount: discount,
      discount_label: discount_label,
      gift_wrap: gift_wrap,
      shipping: shipping,
      shipping_label: pricing.shipping_label,
      total: subtotal - discount + gift_wrap + shipping
    }
  end

  def line_total(item), do: item.product.amount * item.quantity
end
