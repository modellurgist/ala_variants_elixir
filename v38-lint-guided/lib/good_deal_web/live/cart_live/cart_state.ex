defmodule GoodDealWeb.CartLive.CartState do
  @moduledoc false

  alias GoodDeal.Domain.{Pricing, Shipping}

  defstruct [
    :cart_id,
    :promo_code,
    :promo_percentage,
    :shipping_method,
    # calibration injected by the composition (shipping tiers, gift-wrap fee);
    # never read from global config here — it flows down from the app layer.
    shipping_methods: [],
    gift_wrap_cents: 0,
    gift_wrap?: false,
    items: [],
    total: Money.new(0),
    subtotal: Money.new(0),
    discount: Money.new(0),
    shipping: Money.new(0),
    gift_wrap: Money.new(0),
    item_count: 0
  ]

  @doc "Build cart state. `calibration` carries the store's shipping tiers and gift-wrap fee."
  def new(cart_id, items, calibration \\ %{}) do
    %__MODULE__{
      cart_id: cart_id,
      items: items,
      shipping_methods: Map.get(calibration, :shipping_methods, []),
      gift_wrap_cents: Map.get(calibration, :gift_wrap_cents, 0)
    }
    |> recompute()
  end

  def recompute(cart) do
    sub = Pricing.subtotal_cents(cart.items)
    {discounted, disc} = Pricing.apply_discount(sub, cart.promo_percentage || 0)
    count = Pricing.item_count(cart.items)

    method = Shipping.find(cart.shipping_methods, cart.shipping_method)
    ship = Shipping.cost(method, discounted)
    gift = if cart.gift_wrap?, do: Pricing.gift_wrap_total(count, cart.gift_wrap_cents), else: 0

    %{
      cart
      | subtotal: Money.new(sub),
        discount: Money.new(disc),
        shipping: Money.new(ship),
        gift_wrap: Money.new(gift),
        total: Money.new(discounted + ship + gift),
        item_count: count
    }
  end
end
