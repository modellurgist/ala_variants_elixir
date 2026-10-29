defmodule GoodDeal.OrdersTest do
  use GoodDeal.DataCase, async: true

  import GoodDeal.ShoppingCartFixtures

  alias GoodDeal.{Catalog, Orders, ProductEvents, ShoppingCart}
  alias GoodDeal.Domain.Pricing
  alias GoodDealWeb.Calibration

  defp summary(cart, items, channel \\ :storefront),
    do: Pricing.summary(Calibration.pricing(Calibration.channel(channel), cart), items)

  defp portal(cart), do: shop(cart.id, :portal)

  describe "complete_checkout/2" do
    test "creates the order with line items, completes the cart and decrements stock" do
      cart = cart_fixture(%{promo_code: "SAVE10"})
      a = cart_item_fixture(cart, quantity: 2, amount: 1000, stock: 5)
      b = cart_item_fixture(cart, quantity: 1, amount: 500, stock: 1)
      {:ok, _} = ShoppingCart.toggle_gift_wrap(b)

      {:ok, cart} = ShoppingCart.save_address(shop(cart.id), address_attrs())

      ProductEvents.subscribe()
      items = ShoppingCart.list_cart_items(shop(cart.id))

      assert {:ok, order} = Orders.complete_checkout(shop(cart.id), summary(cart, items))

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
      {:ok, cart} = ShoppingCart.save_address(shop(cart.id), address_attrs())
      items = ShoppingCart.list_cart_items(shop(cart.id))
      {:ok, _} = Catalog.update_product(item.product, %{stock: 1})

      assert {:error, :out_of_stock} =
               Orders.complete_checkout(shop(cart.id), summary(cart, items))

      assert ShoppingCart.get_cart!(cart.id).status == :open
      assert Catalog.get_product!(item.product_id).stock == 1
    end

    test "refuses a cart with no address, an empty summary, or another cart's items" do
      cart = cart_fixture()
      item = cart_item_fixture(cart, stock: 5)
      items = ShoppingCart.list_cart_items(shop(cart.id))

      assert {:error, changeset} = Orders.complete_checkout(shop(cart.id), summary(cart, items))
      assert %{address: ["can't be blank"]} = errors_on(changeset)

      {:ok, cart} = ShoppingCart.save_address(shop(cart.id), address_attrs())

      assert {:error, changeset} = Orders.complete_checkout(shop(cart.id), summary(cart, []))
      assert %{line_items: ["can't be blank"]} = errors_on(changeset)

      other = cart_fixture()
      {:ok, other} = ShoppingCart.save_address(shop(other.id), address_attrs())

      assert {:error, :not_in_cart} =
               Orders.complete_checkout(shop(other.id), summary(other, items))

      assert ShoppingCart.get_cart!(cart.id).status == :open
      assert ShoppingCart.get_cart!(other.id).status == :open
      assert Catalog.get_product!(item.product_id).stock == 5
    end
  end

  describe "submit_portal_order/3" do
    test "requires a PO number like PO-1234" do
      for bad <- [nil, "", "PO-123", "po-1234", "PO-12a4"] do
        cart = cart_fixture()

        assert {:error, changeset} =
                 Orders.submit_portal_order(
                   portal(cart),
                   summary(cart, [], :portal),
                   %{"number" => bad}
                 )

        assert errors_on(changeset).number != []
      end

      shop = portal(cart_fixture())
      assert %Ecto.Changeset{valid?: false} = Orders.change_purchase_order(shop)

      assert %{number: ["must look like PO-1234"]} =
               errors_on(Orders.change_purchase_order(shop, %{"number" => "PO-1"}))
    end

    test "creates the order with volume pricing and completes the draft, leaving stock" do
      cart = cart_fixture()
      item = cart_item_fixture(cart, quantity: 6, amount: 10_000, stock: 50)
      items = ShoppingCart.list_cart_items(portal(cart))

      assert {:ok, order} =
               Orders.submit_portal_order(
                 portal(cart),
                 summary(cart, items, :portal),
                 %{"number" => "PO-2026"}
               )

      assert order.source == :portal
      assert order.po_number == "PO-2026"
      assert order.subtotal == 60_000
      assert order.discount == 3_000
      assert order.total == 57_000
      assert GoodDealWeb.ShopComponents.order_reference(order) =~ ~r/^GD-\d{6}$/

      assert ShoppingCart.get_cart!(cart.id).status == :completed
      assert Catalog.get_product!(item.product_id).stock == 50
    end

    test "an order needs line items" do
      cart = cart_fixture()

      assert {:error, changeset} =
               Orders.submit_portal_order(
                 portal(cart),
                 summary(cart, [], :portal),
                 %{"number" => "PO-2026"}
               )

      assert %{line_items: ["can't be blank"]} = errors_on(changeset)
    end

    test "refuses another cart's items" do
      cart = cart_fixture()
      cart_item_fixture(cart)
      items = ShoppingCart.list_cart_items(portal(cart))
      other = cart_fixture()

      assert {:error, :not_in_cart} =
               Orders.submit_portal_order(
                 portal(other),
                 summary(other, items, :portal),
                 %{"number" => "PO-2026"}
               )

      assert ShoppingCart.get_cart!(other.id).status == :open
    end
  end
end
