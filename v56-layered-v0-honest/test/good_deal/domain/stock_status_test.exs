defmodule GoodDeal.Domain.StockStatusTest do
  use ExUnit.Case, async: true

  import GoodDeal.ChannelFixtures

  alias GoodDeal.Domain.StockStatus

  defp channel, do: channel_fixture(low_stock_threshold: 2)

  test "out at zero or below, low up to the threshold, in stock above" do
    assert StockStatus.of(channel(), -1) == :out_of_stock
    assert StockStatus.of(channel(), 0) == :out_of_stock
    assert StockStatus.of(channel(), 2) == :low_stock
    assert StockStatus.of(channel(), 3) == :in_stock
  end
end
