defmodule GoodDeal.ShoppingCartTest do
  use GoodDeal.DataCase, async: true

  import GoodDeal.CatalogFixtures
  import GoodDeal.ShoppingCartFixtures

  alias GoodDeal.ShoppingCart
  alias GoodDeal.ShoppingCart.Cart
  alias GoodDealWeb.Calibration

  @postal Calibration.postal_code_length()

  describe "carts" do
    test "a new cart is open" do
      assert {:ok, %Cart{status: :open, shipping_method: "standard"}} =
               ShoppingCart.create_cart(Calibration.new_cart())
    end

    test "status is one of open, completed, abandoned" do
      cart = cart_fixture()

      for status <- [:completed, :abandoned, :open] do
        assert {:ok, %Cart{status: ^status}} = ShoppingCart.update_cart(cart, %{status: status})
      end

      assert {:error, changeset} = ShoppingCart.update_cart(cart, %{status: :lost})
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "get_or_create_open_cart/2 reuses an open cart" do
      cart = cart_fixture()
      assert ShoppingCart.get_or_create_open_cart(cart.id, Calibration.new_cart()).id == cart.id
    end

    test "get_or_create_open_cart/2 creates a new cart when none, unknown or not open" do
      completed = cart_fixture(%{status: :completed})

      for id <- [nil, completed.id, -1] do
        cart = ShoppingCart.get_or_create_open_cart(id, Calibration.new_cart())
        assert cart.status == :open
        refute cart.id == completed.id
      end
    end

    test "apply_promo_code/3 stores a valid code, normalised" do
      cart = cart_fixture()

      assert {:ok, %Cart{promo_code: "SAVE10"}} =
               ShoppingCart.apply_promo_code(cart, " save10 ", Calibration.promo_codes())
    end

    test "apply_promo_code/3 rejects an unknown code and leaves the cart unchanged" do
      cart = cart_fixture()

      assert {:error, :invalid_promo_code} =
               ShoppingCart.apply_promo_code(cart, "BOGUS", Calibration.promo_codes())

      assert ShoppingCart.get_cart!(cart.id).promo_code == nil
    end

    test "select_shipping_method/3 accepts only known methods" do
      cart = cart_fixture()

      assert {:ok, %Cart{shipping_method: "express"}} =
               ShoppingCart.select_shipping_method(
                 cart,
                 "express",
                 Calibration.shipping_methods()
               )

      assert {:error, :invalid_shipping_method} =
               ShoppingCart.select_shipping_method(
                 cart,
                 "teleport",
                 Calibration.shipping_methods()
               )
    end

    test "save_address/3 validates and stores the address" do
      cart = cart_fixture()

      assert {:error, changeset} =
               ShoppingCart.save_address(cart, %{name: "", postal_code: "x"}, @postal)

      assert %{name: ["can't be blank"], line1: _, city: _, postal_code: [_]} =
               errors_on(changeset)

      assert {:ok, cart} = ShoppingCart.save_address(cart, address_attrs(), @postal)
      assert ShoppingCart.get_cart!(cart.id).address.city == "London"
      assert ShoppingCart.change_address(cart, %{}, @postal).data.city == "London"

      assert {:ok, cart} =
               ShoppingCart.save_address(cart, %{address_attrs() | city: "Paris"}, @postal)

      assert ShoppingCart.get_cart!(cart.id).address.city == "Paris"
    end
  end

  describe "cart items" do
    setup do
      %{cart: cart_fixture()}
    end

    test "add_item/3 adds a line; adding again increments the same line", %{cart: cart} do
      product = product_fixture()
      {:ok, item} = ShoppingCart.add_item(cart.id, product.id)
      assert item.quantity == 1
      assert item.product.id == product.id

      {:ok, again} = ShoppingCart.add_item(cart.id, product.id, 3)
      assert again.id == item.id
      assert again.quantity == 4
      assert [%{quantity: 4}] = ShoppingCart.list_cart_items(cart.id)
    end

    test "add_item/3 rejects a quantity below 1", %{cart: cart} do
      product = product_fixture()
      assert {:error, changeset} = ShoppingCart.add_item(cart.id, product.id, 0)
      assert %{quantity: [_]} = errors_on(changeset)
    end

    test "items persist with their cart", %{cart: cart} do
      item = cart_item_fixture(cart, quantity: 2)
      other_cart = cart_fixture()

      assert [%{id: id, quantity: 2}] = ShoppingCart.list_cart_items(cart.id)
      assert id == item.id
      assert ShoppingCart.list_cart_items(other_cart.id) == []
      assert_raise Ecto.NoResultsError, fn -> ShoppingCart.get_cart_item!(other_cart.id, id) end
    end

    test "change_quantity/2 never goes below 1", %{cart: cart} do
      item = cart_item_fixture(cart)
      assert {:ok, %{quantity: 2} = item} = ShoppingCart.change_quantity(item, 1)
      assert {:ok, %{quantity: 1} = item} = ShoppingCart.change_quantity(item, -1)
      assert {:ok, %{quantity: 1}} = ShoppingCart.change_quantity(item, -1)
    end

    test "toggle_gift_wrap/1 flips the flag; restore_item/1 clears it", %{cart: cart} do
      item = cart_item_fixture(cart)
      assert {:ok, %{gift_wrap: true} = item} = ShoppingCart.toggle_gift_wrap(item)
      assert {:ok, %{gift_wrap: false}} = ShoppingCart.restore_item(item)
    end

    test "save_for_later/1 and move_to_cart/1 move a line between lists", %{cart: cart} do
      item = cart_item_fixture(cart)
      {:ok, item} = ShoppingCart.save_for_later(item)
      {:ok, item} = ShoppingCart.save_for_later(item)

      assert ShoppingCart.list_cart_items(cart.id) == []
      assert [%{id: id}] = ShoppingCart.list_saved_items(cart.id)
      assert id == item.id

      {:ok, _} = ShoppingCart.move_to_cart(item)
      assert [_] = ShoppingCart.list_cart_items(cart.id)
      assert ShoppingCart.list_saved_items(cart.id) == []
    end

    test "adding a saved product moves it back to the cart", %{cart: cart} do
      item = cart_item_fixture(cart)
      {:ok, _} = ShoppingCart.save_for_later(item)
      {:ok, item} = ShoppingCart.add_item(cart.id, item.product_id)
      assert %{quantity: 2, saved_for_later: false} = item
    end

    test "delete_item/1 deletes the line, even if it is already gone", %{cart: cart} do
      item = cart_item_fixture(cart)
      assert :ok = ShoppingCart.delete_item(item)
      assert :ok = ShoppingCart.delete_item(item)
      assert ShoppingCart.list_cart_items(cart.id) == []
    end

    test "get_cart_item_for_product/2 finds the line for a product", %{cart: cart} do
      item = cart_item_fixture(cart)
      assert ShoppingCart.get_cart_item_for_product(cart.id, item.product_id).id == item.id
      assert ShoppingCart.get_cart_item_for_product(cart.id, -1) == nil
    end

    test "check_stock/1 reports an empty cart, short stock, or the items", %{cart: cart} do
      assert ShoppingCart.check_stock(cart.id) == {:error, :empty}

      item = cart_item_fixture(cart, quantity: 3, stock: 3)
      assert {:ok, [%{id: id}]} = ShoppingCart.check_stock(cart.id)
      assert id == item.id

      {:ok, _} = ShoppingCart.change_quantity(item, 1)
      assert ShoppingCart.check_stock(cart.id) == {:error, :out_of_stock}
    end
  end

  describe "wishlist" do
    setup do
      %{cart: cart_fixture(), product: product_fixture()}
    end

    test "toggle_wishlist/2 adds then removes", %{cart: cart, product: product} do
      assert ShoppingCart.toggle_wishlist(cart.id, product.id) == :added
      assert ShoppingCart.in_wishlist?(cart.id, product.id)
      assert [%{id: id}] = ShoppingCart.list_wishlist(cart.id)
      assert id == product.id

      assert ShoppingCart.toggle_wishlist(cart.id, product.id) == :removed
      assert ShoppingCart.list_wishlist(cart.id) == []
    end

    test "remove_from_wishlist/2", %{cart: cart, product: product} do
      :added = ShoppingCart.toggle_wishlist(cart.id, product.id)
      assert :ok = ShoppingCart.remove_from_wishlist(cart.id, product.id)
      refute ShoppingCart.in_wishlist?(cart.id, product.id)
    end

    test "move_wishlist_item_to_cart/2 adds a cart line and drops the wish",
         %{cart: cart, product: product} do
      :added = ShoppingCart.toggle_wishlist(cart.id, product.id)
      assert {:ok, item} = ShoppingCart.move_wishlist_item_to_cart(cart.id, product.id)
      assert item.product_id == product.id
      assert [_] = ShoppingCart.list_cart_items(cart.id)
      assert ShoppingCart.list_wishlist(cart.id) == []
    end
  end
end
