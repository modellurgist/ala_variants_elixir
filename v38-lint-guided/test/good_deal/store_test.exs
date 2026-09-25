defmodule GoodDeal.Foundation.ProductsTest do
  use GoodDeal.DataCase

  alias GoodDeal.Foundation.Products
  alias GoodDeal.Foundation.Schemas.Product

  import GoodDeal.StoreFixtures

  @invalid_attrs %{name: nil, description: nil, amount: nil, stock: nil, thumbnail: nil}

  test "list/0 returns all products" do
    product = product_fixture()
    assert Products.list() == [product]
  end

  test "get!/1 returns the product with given id" do
    product = product_fixture()
    assert Products.get!(product.id) == product
  end

  test "insert/1 with valid data creates a product" do
    valid_attrs = %{name: "some name", description: "some description", amount: 42, stock: 42, thumbnail: "some thumbnail"}

    assert {:ok, %Product{} = product} = Products.insert(valid_attrs)
    assert product.name == "some name"
    assert product.description == "some description"
    assert product.amount == 42
  end

  test "insert/1 with invalid data returns error changeset" do
    assert {:error, %Ecto.Changeset{}} = Products.insert(@invalid_attrs)
  end

  test "update/2 with valid data updates the product" do
    product = product_fixture()
    assert {:ok, %Product{} = updated} = Products.update(product, %{name: "updated"})
    assert updated.name == "updated"
  end

  test "update/2 with invalid data returns error changeset" do
    product = product_fixture()
    assert {:error, %Ecto.Changeset{}} = Products.update(product, @invalid_attrs)
    assert product == Products.get!(product.id)
  end

  test "delete/1 deletes the product" do
    product = product_fixture()
    assert {:ok, %Product{}} = Products.delete(product)
    assert_raise Ecto.NoResultsError, fn -> Products.get!(product.id) end
  end

  test "changeset/1 returns a product changeset" do
    product = product_fixture()
    assert %Ecto.Changeset{} = Products.changeset(product)
  end

  test "decrement_stock/2 reduces stock and returns updated product" do
    product = product_fixture(%{stock: 10})
    assert {:ok, updated} = Products.decrement_stock(product.id, 3)
    assert updated.stock == 7
  end

  test "decrement_stock/2 fails when stock is insufficient" do
    product = product_fixture(%{stock: 2})
    assert {:error, :insufficient_stock} = Products.decrement_stock(product.id, 5)
  end

  test "stock_levels/1 returns map of product_id to stock" do
    p1 = product_fixture(%{name: "A", stock: 10})
    p2 = product_fixture(%{name: "B", stock: 3})
    levels = Products.stock_levels([p1.id, p2.id])
    assert levels[p1.id] == 10
    assert levels[p2.id] == 3
  end

  test "stock_levels/1 with empty list returns empty map" do
    assert Products.stock_levels([]) == %{}
  end
end

defmodule GoodDeal.Foundation.CartsTest do
  use GoodDeal.DataCase

  alias GoodDeal.Foundation.Carts
  alias GoodDeal.Foundation.Schemas.{Cart, CartItem}

  import GoodDeal.StoreFixtures

  test "create/0 creates an open cart" do
    assert {:ok, %Cart{status: :open}} = Carts.create()
  end

  test "get/1 retrieves a cart by id" do
    {:ok, cart} = Carts.create()
    assert %Cart{status: :open} = Carts.get(cart.id)
  end

  test "get/1 returns nil for missing cart" do
    assert Carts.get(-1) == nil
  end

  test "list_items/1 returns items with preloaded products" do
    {cart, [product_a, _product_b]} = cart_with_items_fixture()
    items = Carts.list_items(cart.id)
    assert length(items) == 2
    first = Enum.find(items, &(&1.product.id == product_a.id))
    assert %CartItem{quantity: 1} = first
    assert first.product.name == "Widget"
  end

  test "add_item/2 inserts a new item with quantity 1" do
    cart = cart_fixture()
    product = product_fixture()
    assert {:ok, %CartItem{quantity: 1}} = Carts.add_item(cart.id, product)
  end

  test "add_item/2 increments quantity on duplicate product" do
    cart = cart_fixture()
    product = product_fixture()
    {:ok, _} = Carts.add_item(cart.id, product)
    {:ok, _} = Carts.add_item(cart.id, product)
    items = Carts.list_items(cart.id)
    assert [%CartItem{quantity: 2}] = items
  end

  test "update_quantity/3 changes item quantity" do
    {cart, [product_a, _]} = cart_with_items_fixture()
    items = Carts.list_items(cart.id)
    item_a = Enum.find(items, &(&1.product.id == product_a.id))

    assert {:ok, updated} = Carts.update_quantity(cart.id, item_a.id, 5)
    assert updated.quantity == 5
  end

  test "remove_item/2 deletes the cart item" do
    {cart, [product_a, _]} = cart_with_items_fixture()
    items = Carts.list_items(cart.id)
    item_a = Enum.find(items, &(&1.product.id == product_a.id))

    assert {1, nil} = Carts.remove_item(cart.id, item_a.id)
    remaining = Carts.list_items(cart.id)
    assert length(remaining) == 1
    refute Enum.any?(remaining, &(&1.id == item_a.id))
  end

  test "complete/1 marks a cart as completed" do
    {:ok, cart} = Carts.create()
    assert {:ok, %Cart{status: :completed}} = Carts.complete(cart)
  end
end

defmodule GoodDeal.Foundation.OrdersTest do
  use GoodDeal.DataCase

  alias GoodDeal.Foundation.{Orders, Carts}
  alias GoodDeal.Foundation.Schemas.Order

  import GoodDeal.StoreFixtures

  test "create/1 marks cart as completed and creates order" do
    {cart, _products} = cart_with_items_fixture()
    assert {:ok, %Order{cart_id: cart_id}} = Orders.create(cart.id)
    assert cart_id == cart.id
    assert Carts.get(cart.id).status == :completed
  end
end

defmodule GoodDeal.Foundation.BroadcastTest do
  use GoodDeal.DataCase

  alias GoodDeal.Foundation.{Products, Broadcast}

  import GoodDeal.StoreFixtures

  test "subscribe and receive notifications" do
    Broadcast.subscribe()
    product = product_fixture()
    Broadcast.notify(:product_created, product)
    assert_received {:product_created, ^product}
  end
end
