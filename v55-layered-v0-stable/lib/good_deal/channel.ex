defmodule GoodDeal.Channel do
  @moduledoc """
  One sales channel's calibration, built by the app layer and passed down whole. A value
  that differs by channel is a field here, so a new input is a new field with a default.
  """

  @enforce_keys [:name]
  defstruct [
    :name,
    :default_shipping_method,
    :low_stock_threshold,
    :postal_code_length,
    :po_number,
    shipping_methods: [],
    promo_codes: %{},
    gift_wrap_price: 0,
    volume_tiers: []
  ]
end
