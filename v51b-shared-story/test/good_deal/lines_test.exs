defmodule GoodDeal.LinesTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Lines

  defp line(id, product_id, quantity),
    do: %{id: id, quantity: quantity, product: %{id: product_id, stock: 10}}

  test "add keeps a line already there; bump never goes below 1" do
    lines = Lines.add([line(1, 7, 2)], line(1, 7, 9))
    assert [%{quantity: 2}] = lines
    assert {:ok, [%{quantity: 1}], %{quantity: 1}} = Lines.bump(lines, 1, -5)
    assert :error = Lines.bump(lines, 99, 1)
  end

  test "remove and set_stock report what they touched" do
    lines = [line(1, 7, 2), line(2, 8, 1)]
    assert {:ok, [%{id: 2}], %{id: 1}} = Lines.remove(lines, 1)
    assert :error = Lines.remove(lines, 99)
    assert {:ok, _, %{product: %{stock: 0}}} = Lines.set_stock(lines, 8, 0)
    assert :none = Lines.set_stock(lines, 99, 0)
  end
end
