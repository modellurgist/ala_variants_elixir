defmodule GoodDeal.Actions.SaveProductTest do
  use GoodDeal.DataCase

  import GoodDeal.StoreFixtures

  alias GoodDeal.Actions.SaveProduct

  describe "run(:new, attrs)" do
    test "creates a product and broadcasts" do
      GoodDeal.Foundation.Broadcast.subscribe()

      attrs = %{name: "Widget", description: "Shiny", amount: 999, stock: 5, thumbnail: "w.png"}
      assert {:ok, product} = SaveProduct.run(:new, attrs)
      assert product.name == "Widget"

      assert_receive {:product_created, ^product}
    end

    test "returns changeset error for invalid data" do
      assert {:error, %Ecto.Changeset{}} = SaveProduct.run(:new, %{})
    end
  end

  describe "run(:edit, product, attrs)" do
    test "updates a product and broadcasts" do
      product = product_fixture()
      GoodDeal.Foundation.Broadcast.subscribe()

      assert {:ok, updated} = SaveProduct.run(:edit, product, %{name: "Updated Name"})
      assert updated.name == "Updated Name"

      assert_receive {:product_updated, ^updated}
    end

    test "returns changeset error for invalid update" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = SaveProduct.run(:edit, product, %{name: nil})
    end
  end
end
