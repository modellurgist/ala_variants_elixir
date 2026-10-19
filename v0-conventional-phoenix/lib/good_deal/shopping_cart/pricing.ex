defmodule GoodDeal.ShoppingCart.Pricing do
  @moduledoc """
  Prices a list of cart items (with products preloaded). All amounts are in cents.
  """

  @shipping_methods [
    %{id: "standard", label: "Standard (5–7 days)", cost: 599, free_above: 5000},
    %{id: "express", label: "Express (2–3 days)", cost: 1299, free_above: nil},
    %{id: "overnight", label: "Overnight", cost: 2499, free_above: nil}
  ]

  @promo_codes %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}

  @gift_wrap_price 299

  # Highest tier first.
  @volume_tiers [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]

  def shipping_methods, do: @shipping_methods

  def shipping_method(id), do: Enum.find(@shipping_methods, &(&1.id == id))

  def gift_wrap_price, do: @gift_wrap_price

  def valid_promo_code?(code), do: Map.has_key?(@promo_codes, code)

  @doc """
  Builds the pricing summary.

  Options:
    * `:promo_code` - storefront promo code, if any
    * `:shipping_method` - one of the `shipping_methods/0` ids
    * `:gift_wrap` - whether gift wrap is charged (storefront)
    * `:volume_pricing` - whether volume tiers apply (portal)
  """
  def summary(items, opts \\ []) do
    subtotal = subtotal(items)
    {percent, discount_label} = discount_rate(subtotal, opts)
    discount = div(subtotal * percent, 100)
    gift_wrap = if opts[:gift_wrap], do: gift_wrap_total(items), else: 0
    method = shipping_method(opts[:shipping_method] || "standard")
    shipping = shipping_cost(method, subtotal)

    %{
      item_count: Enum.sum_by(items, & &1.quantity),
      subtotal: subtotal,
      discount: discount,
      discount_label: discount_label,
      gift_wrap: gift_wrap,
      shipping: shipping,
      shipping_label: method.label,
      total: subtotal - discount + gift_wrap + shipping
    }
  end

  def line_total(item), do: item.product.amount * item.quantity

  defp subtotal(items), do: Enum.sum_by(items, &line_total/1)

  defp gift_wrap_total(items), do: Enum.count(items, & &1.gift_wrap) * @gift_wrap_price

  defp discount_rate(subtotal, opts) do
    cond do
      opts[:volume_pricing] -> volume_tier(subtotal)
      percent = @promo_codes[opts[:promo_code]] -> {percent, opts[:promo_code]}
      true -> {0, nil}
    end
  end

  defp volume_tier(subtotal) do
    Enum.find_value(@volume_tiers, {0, nil}, fn {min, percent, label} ->
      if subtotal >= min, do: {percent, label}
    end)
  end

  defp shipping_cost(_method, 0), do: 0
  defp shipping_cost(%{free_above: min}, subtotal) when is_integer(min) and subtotal >= min, do: 0
  defp shipping_cost(%{cost: cost}, _subtotal), do: cost
end
