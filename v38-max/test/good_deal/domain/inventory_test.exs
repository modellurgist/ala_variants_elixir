defmodule GoodDeal.Domain.InventoryTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.Inventory

  describe "status/2" do
    test "reports in_stock for quantities above the supplied threshold" do
      assert Inventory.status(Inventory.new(low_at: 5), 100) == :in_stock
      assert Inventory.status(Inventory.new(low_at: 5), 6) == :in_stock
    end

    test "reports low_stock at or below the threshold" do
      assert Inventory.status(Inventory.new(low_at: 5), 5) == :low_stock
      assert Inventory.status(Inventory.new(low_at: 5), 1) == :low_stock
    end

    test "reports out_of_stock at zero or below, regardless of threshold" do
      assert Inventory.status(Inventory.new(low_at: 5), 0) == :out_of_stock
      assert Inventory.status(Inventory.new(low_at: 5), -1) == :out_of_stock
    end

    test "honours a different threshold" do
      assert Inventory.status(Inventory.new(low_at: 10), 8) == :low_stock
      assert Inventory.status(Inventory.new(low_at: 10), 11) == :in_stock
    end
  end

  describe "check_availability/2" do
    defp item(product_id, quantity) do
      %{product: %{id: product_id}, quantity: quantity}
    end

    test "all items available returns :ok" do
      items = [item(1, 2), item(2, 3)]
      stock = %{1 => 10, 2 => 5}
      assert Inventory.check_availability(items, stock) == :ok
    end

    test "exact match on stock is available" do
      items = [item(1, 5)]
      stock = %{1 => 5}
      assert Inventory.check_availability(items, stock) == :ok
    end

    test "insufficient stock returns error with unavailable details" do
      items = [item(1, 10), item(2, 1)]
      stock = %{1 => 3, 2 => 5}

      {:error, unavailable} = Inventory.check_availability(items, stock)
      assert length(unavailable) == 1
      assert hd(unavailable).product_id == 1
      assert hd(unavailable).requested == 10
      assert hd(unavailable).available == 3
    end

    test "missing stock entry defaults to 0" do
      items = [item(99, 1)]
      stock = %{}

      {:error, unavailable} = Inventory.check_availability(items, stock)
      assert hd(unavailable).available == 0
    end
  end
end
