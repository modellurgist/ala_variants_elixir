defmodule GoodDeal.CatalogTest do
  use GoodDeal.DataCase, async: true

  alias GoodDeal.Catalog

  describe "products" do
    alias GoodDeal.Catalog.Product

    import GoodDeal.CatalogFixtures

    @invalid_attrs %{name: nil, description: nil, amount: nil, stock: nil, thumbnail: nil}

    test "list_products/0 returns all products" do
      product = product_fixture()
      assert Catalog.list_products() == [product]
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert Catalog.get_product!(product.id) == product
    end

    test "create_product/1 with valid data creates a product" do
      valid_attrs = %{
        name: "some name",
        description: "some description",
        amount: 42,
        stock: 42,
        thumbnail: "some thumbnail"
      }

      assert {:ok, %Product{} = product} = Catalog.create_product(valid_attrs)
      assert product.name == "some name"
      assert product.description == "some description"
      assert product.amount == 42
      assert product.stock == 42
      assert product.thumbnail == "some thumbnail"
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_product(@invalid_attrs)
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()

      update_attrs = %{
        name: "some updated name",
        description: "some updated description",
        amount: 43,
        stock: 43,
        thumbnail: "some updated thumbnail"
      }

      assert {:ok, %Product{} = product} = Catalog.update_product(product, update_attrs)
      assert product.name == "some updated name"
      assert product.description == "some updated description"
      assert product.amount == 43
      assert product.stock == 43
      assert product.thumbnail == "some updated thumbnail"
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = Catalog.update_product(product, @invalid_attrs)
      assert product == Catalog.get_product!(product.id)
    end

    test "delete_product/1 deletes the product" do
      product = product_fixture()
      assert {:ok, %Product{}} = Catalog.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_product!(product.id) end
    end

    test "change_product/1 returns a product changeset" do
      product = product_fixture()
      assert %Ecto.Changeset{} = Catalog.change_product(product)
    end
  end

  describe "validation" do
    import GoodDeal.CatalogFixtures

    test "create_product/0 needs attributes" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_product()
    end

    test "only name and amount are required" do
      assert {:ok, product} = Catalog.create_product(%{name: "Bare", amount: 100})
      assert product.stock == 0

      assert %{name: ["can't be blank"], amount: ["can't be blank"]} =
               errors_on(Catalog.change_product(%Catalog.Product{}, %{}))
    end

    test "amount and stock cannot be negative" do
      changeset = Catalog.change_product(product_fixture(), %{amount: -1, stock: -1})
      assert %{amount: [_], stock: [_]} = errors_on(changeset)
    end
  end

  describe "stock_status/1" do
    alias GoodDeal.Catalog.Product

    test "is out of stock at 0, low stock at 5 or fewer, in stock above" do
      assert Catalog.stock_status(%Product{stock: 0}) == :out_of_stock
      assert Catalog.stock_status(%Product{stock: 1}) == :low_stock
      assert Catalog.stock_status(%Product{stock: 5}) == :low_stock
      assert Catalog.stock_status(%Product{stock: 6}) == :in_stock
    end
  end

  describe "broadcasts" do
    import GoodDeal.CatalogFixtures

    setup do
      Catalog.subscribe()
    end

    test "create, update and delete broadcast the product" do
      product = product_fixture()
      assert_receive {:product_created, %{id: id}} when id == product.id

      {:ok, _} = Catalog.update_product(product, %{stock: 1})
      assert_receive {:product_updated, %{id: ^id, stock: 1}}

      {:ok, _} = Catalog.delete_product(product)
      assert_receive {:product_deleted, %{id: ^id}}
    end

    test "a failed update broadcasts nothing" do
      product = product_fixture()
      assert {:error, _} = Catalog.update_product(product, %{name: nil})
      id = product.id
      refute_receive {:product_updated, %{id: ^id}}, 20
    end
  end
end
