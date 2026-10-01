defmodule GoodDeal.Domain.LinesTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.Lines

  defp make_product(attrs) do
    Map.merge(
      %{
        id: 1,
        name: "Widget",
        description: "A widget",
        amount: 1000,
        stock: 10,
        thumbnail: "w.png"
      },
      attrs
    )
  end

  defp make_item(attrs) do
    Map.merge(%{id: 1, quantity: 1, product: make_product(%{})}, attrs)
  end

  describe "update_quantity/3" do
    test "increments the matching item's quantity" do
      items = [make_item(%{id: 1, quantity: 2}), make_item(%{id: 2, quantity: 1})]
      result = Lines.update_quantity(items, 1, 1)

      assert Enum.find(result, &(&1.id == 1)).quantity == 3
      assert Enum.find(result, &(&1.id == 2)).quantity == 1
    end

    test "decrements but clamps at 1" do
      items = [make_item(%{id: 1, quantity: 1})]
      result = Lines.update_quantity(items, 1, -1)

      assert hd(result).quantity == 1
    end

    test "does not change unmatched items" do
      items = [make_item(%{id: 1, quantity: 3})]
      result = Lines.update_quantity(items, 999, 5)

      assert hd(result).quantity == 3
    end
  end

  describe "pop/2" do
    test "removes matching item and returns it" do
      items = [
        make_item(%{id: 1, product: make_product(%{id: 10})}),
        make_item(%{id: 2, product: make_product(%{id: 20})})
      ]

      {removed, remaining} = Lines.pop(items, 1)

      assert removed.id == 1
      assert length(remaining) == 1
      assert hd(remaining).id == 2
    end

    test "returns nil when item not found" do
      items = [make_item(%{id: 1})]
      {removed, remaining} = Lines.pop(items, 999)

      assert removed == nil
      assert length(remaining) == 1
    end

    test "handles empty list" do
      {removed, remaining} = Lines.pop([], 1)

      assert removed == nil
      assert remaining == []
    end
  end

  describe "set_stock/3" do
    test "updates stock on the matching product" do
      items = [
        make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})}),
        make_item(%{id: 2, product: make_product(%{id: 20, stock: 5})})
      ]

      result = Lines.set_stock(items, 10, 3)

      assert Enum.find(result, &(&1.id == 1)).product.stock == 3
      assert Enum.find(result, &(&1.id == 2)).product.stock == 5
    end

    test "does not change anything for unknown product_id" do
      items = [make_item(%{id: 1, product: make_product(%{id: 10, stock: 10})})]
      result = Lines.set_stock(items, 999, 0)

      assert hd(result).product.stock == 10
    end
  end
end
