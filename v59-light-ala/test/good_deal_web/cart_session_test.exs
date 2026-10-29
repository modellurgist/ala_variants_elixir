defmodule GoodDealWeb.CartSessionTest do
  use ExUnit.Case, async: true

  alias GoodDealWeb.CartSession

  test "shop/2 takes the cart id as an option and refuses a missing or unknown one" do
    assert %GoodDeal.Shop{cart_id: 7, channel: %{name: :portal}} =
             CartSession.shop(:portal, cart_id: 7)

    assert_raise ArgumentError, fn -> CartSession.shop(:storefront, []) end
    assert_raise KeyError, fn -> CartSession.shop(:storefront, cart_id: 7, cart: 7) end
  end
end
