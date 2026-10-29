defmodule GoodDeal.Domain.ShippingMethodTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.ShippingMethod
  alias GoodDealWeb.Calibration

  defp standard, do: ShippingMethod.find(Calibration.channel(:storefront), "standard")
  defp flat, do: %{standard() | cost: 40, free_above: nil}
  defp capped, do: %{standard() | cost: 40, free_above: 100}

  test "costs its flat rate, waived from free_above" do
    assert ShippingMethod.cost(flat(), 1_000) == 40
    assert ShippingMethod.cost(capped(), 99) == 40
    assert ShippingMethod.cost(capped(), 100) == 0
  end

  test "an empty cart ships free" do
    assert ShippingMethod.cost(flat(), 0) == 0
  end
end
