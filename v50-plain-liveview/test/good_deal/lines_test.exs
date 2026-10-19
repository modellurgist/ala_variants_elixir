defmodule GoodDeal.LinesTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Domain.StockStatus
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

  test "row projects a line with its stock status and total" do
    product = %{id: 7, stock: 2, thumbnail: "t.png", name: "Widget", amount: 1500}
    rule = GoodDeal.Domain.StockStatus.new(low_at: 3)

    assert %{id: 1, product_id: 7, stock_status: :low_stock, quantity: 2, line_total: total} =
             Lines.row(%{id: 1, quantity: 2, product: product}, rule)

    assert total == Money.new(3000)
  end

  test "row carries exactly the display fields, never the stored record's extras" do
    product = %{id: 7, stock: 9, thumbnail: "t.png", name: "Widget", amount: 250, sku: "W-1"}
    line = %{id: 1, quantity: 4, product: product, cart_id: 3, inserted_at: :then}

    assert Lines.row(line, StockStatus.new(low_at: 3)) == %{
             id: 1,
             product_id: 7,
             product: %{thumbnail: "t.png", name: "Widget", amount: 250},
             stock_status: :in_stock,
             quantity: 4,
             line_total: Money.new(1000)
           }
  end

  test "row takes stock status from the configured rule, not a fixed threshold" do
    row = fn stock, low_at ->
      product = %{id: 7, stock: stock, thumbnail: nil, name: "W", amount: 1}

      Lines.row(%{id: 1, quantity: 1, product: product}, StockStatus.new(low_at: low_at)).stock_status
    end

    assert row.(5, 3) == :in_stock
    assert row.(5, 5) == :low_stock
    assert row.(0, 5) == :out_of_stock
    assert row.(-1, 0) == :out_of_stock
    assert row.(1, 0) == :in_stock
  end
end
