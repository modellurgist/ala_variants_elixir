defmodule GoodDealWeb.Calibration do
  @moduledoc """
  The store's §7 numbers and words, one `%Channel{}` per channel. Pages put a channel in
  each `%Shop{}` they hand to the contexts and domain rules, which hold none of their own.
  """

  alias GoodDeal.Channel
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

  def channel(:storefront),
    do: shared(:storefront, promo_codes: @promo_codes, gift_wrap_price: @gift_wrap_price)

  # The portal offers no gift wrap.
  def channel(:portal), do: shared(:portal, gift_wrap_price: 0, volume_tiers: @volume_tiers)

  # A regex can't live in a module attribute on newer OTP releases.
  defp shared(name, own) do
    struct!(
      Channel,
      [
        name: name,
        shipping_methods: @shipping_methods,
        default_shipping_method: @default_shipping,
        low_stock_threshold: @low_stock_threshold,
        postal_code_length: @postal_code_length,
        po_number: %{format: ~r/^PO-\d{4,}$/, message: "must look like PO-1234"}
      ] ++ own
    )
  end

  def pricing(%Channel{} = channel, cart) do
    method = ShippingMethod.find(channel, cart.shipping_method)

    %Pricing{
      discount: discount(channel, cart),
      gift_wrap_price: channel.gift_wrap_price,
      shipping: &ShippingMethod.cost(method, &1),
      shipping_label: method.label
    }
  end

  defp discount(%Channel{name: :storefront} = channel, cart),
    do: fn _subtotal -> PromoCode.discount(channel, cart.promo_code) end

  defp discount(%Channel{name: :portal} = channel, _cart), do: &VolumeTier.discount(channel, &1)
end
