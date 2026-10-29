defmodule GoodDeal.Actions.SaveProductTest do
  use GoodDeal.DataCase

  import GoodDeal.StoreFixtures

  alias GoodDeal.Actions.SaveProduct

  describe "save({:new, _, attrs})" do
    test "creates a product" do
      attrs = %{name: "Widget", description: "Shiny", amount: 999, stock: 5, thumbnail: "w.png"}
      assert {:ok, product} = SaveProduct.save({:new, nil, attrs})
      assert product.name == "Widget"
    end

    test "returns changeset error for invalid data" do
      assert {:error, %Ecto.Changeset{}} = SaveProduct.save({:new, nil, %{}})
    end
  end

  describe "save({:edit, product, attrs})" do
    test "updates a product" do
      product = product_fixture()

      assert {:ok, updated} = SaveProduct.save({:edit, product, %{name: "Updated Name"}})
      assert updated.name == "Updated Name"
    end

    test "returns changeset error for invalid update" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = SaveProduct.save({:edit, product, %{name: nil}})
    end
  end
end
