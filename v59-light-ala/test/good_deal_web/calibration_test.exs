defmodule GoodDealWeb.CalibrationTest do
  use ExUnit.Case, async: true

  alias GoodDealWeb.Calibration

  test "an override replaces one value and keeps the channel's others" do
    channel = Calibration.channel(:portal, gift_wrap_price: 50)

    assert channel.gift_wrap_price == 50
    assert channel.volume_tiers == Calibration.channel(:portal).volume_tiers
  end

  test "an override naming no channel field raises" do
    assert_raise KeyError, fn -> Calibration.channel(:storefront, gift_wrap: 50) end
  end

  test "pricing takes overrides the same way" do
    cart = %GoodDeal.ShoppingCart.Cart{shipping_method: "express"}
    pricing = Calibration.pricing(Calibration.channel(:storefront), cart, gift_wrap_price: 0)

    assert pricing.gift_wrap_price == 0
    assert pricing.shipping_label == "Express (2–3 days)"
  end
end
