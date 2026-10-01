defmodule GoodDealWeb.PortalLive.OrderState do
  @moduledoc false

  alias GoodDeal.Domain.{Pricing, Shipping, VolumeTier}

  defstruct [
    :cart_id,
    shipping_method: :standard,
    shipping_methods: [],
    volume_tiers: [],
    items: [],
    tier_label: nil,
    subtotal: Money.new(0),
    discount: Money.new(0),
    shipping: Money.new(0),
    total: Money.new(0),
    item_count: 0
  ]

  def new(cart_id, items, calibration) do
    %__MODULE__{
      cart_id: cart_id,
      items: items,
      shipping_methods: calibration.shipping_methods,
      volume_tiers: calibration.volume_tiers
    }
    |> recompute()
  end

  def recompute(order) do
    sub = Pricing.subtotal_cents(order.items)
    {pct, label} = VolumeTier.discount(order.volume_tiers, sub)
    {discounted, disc} = Pricing.apply_discount(sub, pct)
    ship = Shipping.cost(Shipping.find(order.shipping_methods, order.shipping_method), discounted)

    %{
      order
      | subtotal: Money.new(sub),
        discount: Money.new(disc),
        tier_label: label,
        shipping: Money.new(ship),
        total: Money.new(discounted + ship),
        item_count: Pricing.item_count(order.items)
    }
  end
end
