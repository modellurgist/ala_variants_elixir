defmodule GoodDeal.Domain.VolumeTierTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.VolumeTier

  @tiers [{1_000, 20, "big"}, {100, 5, "small"}]

  test "picks the highest tier the subtotal reaches" do
    assert VolumeTier.discount(@tiers, 99) == {0, nil}
    assert VolumeTier.discount(@tiers, 100) == {5, "small"}
    assert VolumeTier.discount(@tiers, 999) == {5, "small"}
    assert VolumeTier.discount(@tiers, 1_000) == {20, "big"}
  end

  test "no tiers, no discount" do
    assert VolumeTier.discount([], 1_000_000) == {0, nil}
  end
end
