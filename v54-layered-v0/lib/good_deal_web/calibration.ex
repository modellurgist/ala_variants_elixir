defmodule GoodDealWeb.Calibration do
  @moduledoc """
  The store's §7 numbers and words, one place for both channels. Pages hand these to the
  contexts and domain rules, which hold none of their own.
  """

  alias GoodDeal.Domain.{Pricing, PromoCode, ShippingMethod, VolumeTier}

  @shipping_methods [
    %ShippingMethod{id: "standard", label: "Standard (5–7 days)", cost: 599, free_above: 5000},
    %ShippingMethod{id: "express", label: "Express (2–3 days)", cost: 1299},
    %ShippingMethod{id: "overnight", label: "Overnight", cost: 2499}
  ]
  @default_shipping "standard"

  @promo_codes %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}

  @gift_wrap_price 299

  # Highest tier first.
  @volume_tiers [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]

  @low_stock_threshold 5

  @postal_code_length [min: 3, max: 10]

  def shipping_methods, do: @shipping_methods

  def new_cart, do: %{shipping_method: @default_shipping}

  def promo_codes, do: @promo_codes

  def gift_wrap_price, do: @gift_wrap_price

  def low_stock_threshold, do: @low_stock_threshold

  def postal_code_length, do: @postal_code_length

  # A regex can't live in a module attribute on newer OTP releases.
  def po_number, do: %{format: ~r/^PO-\d{4,}$/, message: "must look like PO-1234"}

  def storefront_pricing(cart) do
    method = shipping_method(cart)

    %Pricing{
      discount: fn _subtotal -> PromoCode.discount(@promo_codes, cart.promo_code) end,
      gift_wrap_price: @gift_wrap_price,
      shipping: &ShippingMethod.cost(method, &1),
      shipping_label: method.label
    }
  end

  def portal_pricing(cart) do
    method = shipping_method(cart)

    %Pricing{
      discount: &VolumeTier.discount(@volume_tiers, &1),
      shipping: &ShippingMethod.cost(method, &1),
      shipping_label: method.label
    }
  end

  defp shipping_method(cart), do: ShippingMethod.find(@shipping_methods, cart.shipping_method)
end
