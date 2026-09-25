defmodule GoodDeal.Catalog do
  @moduledoc """
  The store's calibration — the numbers that make this *this* shop, gathered in
  one place at the composition so the domain abstractions (`Shipping`,
  `Pricing`) can stay generic and reusable. Reading this module tells you the
  product's tunable requirements: shipping tiers and rates, the gift-wrap fee.

  Calibration lives here and flows *down* into the domain as arguments; no
  domain or feature module reaches up to read it (that would be an upward
  dependency). The composition passes it in.
  """

  @doc "Shipping tiers, in display order. `free_above: nil` means never free."
  def shipping_methods do
    [
      %{method: :standard, label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      %{method: :express, label: "Express (2–3 days)", cost: 1299, free_above: nil},
      %{method: :overnight, label: "Overnight", cost: 2499, free_above: nil}
    ]
  end

  @doc "Gift-wrap fee per item, in cents."
  def gift_wrap_cents, do: 299

  @doc "Promo codes this store honours, mapping code to percent off."
  def promo_codes, do: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}

  @doc "At or below this stock count, an item counts as low stock."
  def low_stock_threshold, do: 5
end
