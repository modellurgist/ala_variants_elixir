defmodule GoodDeal.Domain.StockStatusTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.StockStatus

  test "out at zero or below, low up to the threshold, in stock above" do
    assert StockStatus.of(-1, 2) == :out_of_stock
    assert StockStatus.of(0, 2) == :out_of_stock
    assert StockStatus.of(2, 2) == :low_stock
    assert StockStatus.of(3, 2) == :in_stock
  end
end
