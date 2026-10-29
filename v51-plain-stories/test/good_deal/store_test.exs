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
    valid_attrs = %{
      name: "some name",
      description: "some description",
      amount: 42,
      stock: 42,
      thumbnail: "some thumbnail"
    }

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

  test "a held line is left out of list_items/1 until kept again" do
    {cart, [product_a, _]} = cart_with_items_fixture()
    item_a = find_item(cart.id, product_a)

    Carts.apply_change({:held, cart.id, item_a.id})
    refute cart.id |> Carts.list_items() |> Enum.any?(&(&1.id == item_a.id))

    Carts.apply_change({:kept, cart.id, item_a.id})
    assert cart.id |> Carts.list_items() |> Enum.any?(&(&1.id == item_a.id))
  end

  test "finalize_holds/2 deletes only lines held for at least the window" do
    {cart, [product_a, product_b]} = cart_with_items_fixture()
    [item_a, item_b] = for p <- [product_a, product_b], do: find_item(cart.id, p)
    Carts.apply_change({:held, cart.id, item_a.id})
    Carts.apply_change({:held, cart.id, item_b.id})
    hours_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

    Repo.update_all(from(ci in CartItem, where: ci.id == ^item_a.id),
      set: [removed_at: hours_ago]
    )

    assert {1, _} = Carts.finalize_holds(cart.id, 60_000)
    assert [%{id: id}] = Repo.all(from ci in CartItem, where: ci.cart_id == ^cart.id)
    assert id == item_b.id
  end

  test "adding a product whose line is held makes the hold final and starts a fresh line" do
    {cart, [product_a, _]} = cart_with_items_fixture()
    item_a = find_item(cart.id, product_a)
    Carts.update_quantity(cart.id, item_a.id, 4)
    Carts.apply_change({:held, cart.id, item_a.id})

    assert {:ok, _} = Carts.add_item(cart.id, product_a)
    fresh = find_item(cart.id, product_a)
    assert fresh.quantity == 1
    refute fresh.id == item_a.id
  end

  test "a saved line is read by list_saved/1, not list_items/1, until kept again" do
    {cart, [product_a, _]} = cart_with_items_fixture()
    item_a = find_item(cart.id, product_a)
    id = item_a.id

    Carts.apply_change({:saved, cart.id, id})
    Carts.apply_change({:saved, cart.id, id})
    refute cart.id |> Carts.list_items() |> Enum.any?(&(&1.id == id))
    assert [%{id: ^id, product: %{name: "Widget"}}] = Carts.list_saved(cart.id)

    Carts.apply_change({:kept, cart.id, id})
    assert cart.id |> Carts.list_items() |> Enum.any?(&(&1.id == id))
    assert Carts.list_saved(cart.id) == []
  end

  test "adding a product whose line is saved brings that line back into the cart, one more" do
    {cart, [product_a, _]} = cart_with_items_fixture()
    item_a = find_item(cart.id, product_a)
    Carts.update_quantity(cart.id, item_a.id, 3)
    Carts.apply_change({:saved, cart.id, item_a.id})

    assert {:ok, _} = Carts.add_item(cart.id, product_a)
    assert %{id: id, quantity: 4} = find_item(cart.id, product_a)
    assert id == item_a.id
    assert Carts.list_saved(cart.id) == []
  end

  defp find_item(cart_id, product),
    do: cart_id |> Carts.list_items() |> Enum.find(&(&1.product.id == product.id))

  test "complete/1 marks a cart as completed" do
    {:ok, cart} = Carts.create()
    assert {:ok, %Cart{status: :completed}} = Carts.complete(cart)
  end
end

defmodule GoodDeal.Foundation.OrdersTest do
  use GoodDeal.DataCase

  alias GoodDeal.Foundation.{Orders, Carts}
  alias GoodDeal.Foundation.Schemas.{CartItem, Order}

  import GoodDeal.StoreFixtures

  test "create/1 marks cart as completed and creates order" do
    {cart, _products} = cart_with_items_fixture()
    assert {:ok, %Order{cart_id: cart_id}} = Orders.create(cart.id)
    assert cart_id == cart.id
    assert Carts.get(cart.id).status == :completed
  end

  test "create/1 makes the cart's held removals final" do
    {cart, [product_a, _]} = cart_with_items_fixture()
    item_a = cart.id |> Carts.list_items() |> Enum.find(&(&1.product.id == product_a.id))
    Carts.apply_change({:held, cart.id, item_a.id})

    {:ok, _} = Orders.create(cart.id)
    refute Repo.get(CartItem, item_a.id)
  end
end
