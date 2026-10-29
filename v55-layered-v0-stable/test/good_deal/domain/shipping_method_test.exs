defmodule GoodDeal.Domain.ShippingMethodTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.ShippingMethod

  @flat %ShippingMethod{id: "flat", label: "Flat", cost: 40}
  @capped %ShippingMethod{id: "capped", label: "Capped", cost: 40, free_above: 100}

  test "costs its flat rate, waived from free_above" do
    assert ShippingMethod.cost(@flat, 1_000) == 40
    assert ShippingMethod.cost(@capped, 99) == 40
    assert ShippingMethod.cost(@capped, 100) == 0
  end

  test "an empty cart ships free" do
    assert ShippingMethod.cost(@flat, 0) == 0
  end
end
