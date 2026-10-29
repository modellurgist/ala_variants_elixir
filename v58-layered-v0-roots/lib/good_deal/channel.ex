defmodule GoodDeal.Channel do
  @moduledoc """
  One sales channel's calibration, built by the app layer and passed down whole. A value
  every channel must state is an enforced key; the defaults are offers a channel may lack
  (no promo codes, no volume tiers), where absence refuses or charges full price.
  """

  @enforce_keys [
    :name,
    :shipping_methods,
    :default_shipping_method,
    :gift_wrap_price,
    :low_stock_threshold,
    :postal_code_length,
    :po_number
  ]
  defstruct @enforce_keys ++ [promo_codes: %{}, volume_tiers: []]
end
