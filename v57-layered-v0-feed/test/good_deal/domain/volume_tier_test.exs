defmodule GoodDeal.Domain.VolumeTierTest do
  use ExUnit.Case, async: true

  import GoodDeal.ChannelFixtures

  alias GoodDeal.Domain.VolumeTier

  defp channel, do: channel_fixture(volume_tiers: [{1_000, 20, "big"}, {100, 5, "small"}])

  test "picks the highest tier the subtotal reaches" do
    assert VolumeTier.discount(channel(), 99) == {0, nil}
    assert VolumeTier.discount(channel(), 100) == {5, "small"}
    assert VolumeTier.discount(channel(), 999) == {5, "small"}
    assert VolumeTier.discount(channel(), 1_000) == {20, "big"}
  end

  test "no tiers, no discount" do
    assert VolumeTier.discount(channel_fixture(), 1_000_000) == {0, nil}
  end
end
