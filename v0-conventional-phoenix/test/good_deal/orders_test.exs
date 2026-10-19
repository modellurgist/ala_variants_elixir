defmodule GoodDeal.OrdersTest do
  use GoodDeal.DataCase, async: true

  import GoodDeal.ShoppingCartFixtures

  alias GoodDeal.{Catalog, Orders, ShoppingCart}

  describe "complete_checkout/2" do
    test "creates the order with line items, completes the cart and decrements stock" do
      cart = cart_fixture(%{promo_code: "SAVE10"})
      a = cart_item_fixture(cart, quantity: 2, amount: 1000, stock: 5)
      b = cart_item_fixture(cart, quantity: 1, amount: 500, stock: 1)
      {:ok, _} = ShoppingCart.toggle_gift_wrap(b)
      {:ok, cart} = ShoppingCart.save_address(cart, address_attrs())
      Catalog.subscribe()

      assert {:ok, order} = Orders.complete_checkout(cart, ShoppingCart.list_cart_items(cart.id))

      order = Orders.get_order!(order.id)
      assert order.source == :storefront
      assert order.subtotal == 2500
      assert order.discount == 250
      assert order.gift_wrap == 299
      assert order.shipping == 599
      assert order.total == 2500 - 250 + 299 + 599
      assert order.address["city"] == "London"
      assert Enum.map(order.line_items, &{&1.name, &1.quantity}) |> length() == 2

      assert ShoppingCart.get_cart!(cart.id).status == :completed
      assert Catalog.get_product!(a.product_id).stock == 3
      assert Catalog.get_product!(b.product_id).stock == 0

      a_id = a.product_id
      assert_receive {:product_updated, %{id: ^a_id, stock: 3}}
    end

    test "rolls back when stock ran out meanwhile" do
      cart = cart_fixture()
      item = cart_item_fixture(cart, quantity: 2, stock: 2)
      items = ShoppingCart.list_cart_items(cart.id)
      {:ok, _} = Catalog.update_product(item.product, %{stock: 1})

      assert {:error, :out_of_stock} = Orders.complete_checkout(cart, items)
      assert ShoppingCart.get_cart!(cart.id).status == :open
      assert Catalog.get_product!(item.product_id).stock == 1
    end
  end

  describe "submit_portal_order/3" do
    test "requires a PO number like PO-1234" do
      for bad <- [nil, "", "PO-123", "po-1234", "PO-12a4"] do
        assert {:error, changeset} =
                 Orders.submit_portal_order(cart_fixture(), [], %{"number" => bad})

        assert errors_on(changeset).number != []
      end

      assert %Ecto.Changeset{valid?: false} = Orders.change_purchase_order()

      assert %{number: ["must look like PO-1234"]} =
               errors_on(Orders.change_purchase_order(%{"number" => "PO-1"}))
    end

    test "creates the order with volume pricing and completes the draft, leaving stock" do
      cart = cart_fixture()
      item = cart_item_fixture(cart, quantity: 6, amount: 10_000, stock: 50)
      items = ShoppingCart.list_cart_items(cart.id)

      assert {:ok, order} = Orders.submit_portal_order(cart, items, %{"number" => "PO-2026"})
      assert order.source == :portal
      assert order.po_number == "PO-2026"
      assert order.subtotal == 60_000
      assert order.discount == 3_000
      assert order.total == 57_000
      assert Orders.reference(order) =~ ~r/^GD-\d{6}$/

      assert ShoppingCart.get_cart!(cart.id).status == :completed
      assert Catalog.get_product!(item.product_id).stock == 50
    end

    test "an order needs line items" do
      assert {:error, changeset} =
               Orders.submit_portal_order(cart_fixture(), [], %{"number" => "PO-2026"})

      assert %{line_items: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
