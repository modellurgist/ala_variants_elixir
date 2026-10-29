defmodule GoodDealWeb.CheckoutLiveTest do
  use GoodDealWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Mox
  import Phoenix.LiveViewTest
  import GoodDeal.ShoppingCartFixtures

  alias GoodDeal.{Catalog, ShoppingCart}
  alias GoodDeal.Orders.Order
  alias GoodDeal.Payments.{InProcessProvider, MockProvider}

  setup :verify_on_exit!

  setup %{conn: conn} do
    cart = cart_fixture()
    a = cart_item_fixture(cart, name: "Alpha Mug", amount: 1000, stock: 10, quantity: 2)
    b = cart_item_fixture(cart, name: "Beta Press", amount: 2500, stock: 3)
    %{conn: init_test_session(conn, %{"cart_id" => cart.id}), cart: cart, a: a, b: b}
  end

  defp to_payment(conn) do
    {:ok, lv, _html} = live(conn, ~p"/cart/checkout")
    lv |> form("#address-form", address: address_attrs()) |> render_submit()
    assert_patch(lv, ~p"/cart/checkout/payment")
    lv
  end

  defp success_url, do: GoodDealWeb.Endpoint.url() <> "/cart/success"

  describe "address step" do
    test "shows the milestones with Address current", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/cart/checkout")
      assert lv |> element(~s(#checkout-steps [aria-current="step"])) |> render() =~ "Address"
      assert has_element?(lv, "#address-form")
    end

    test "validates required fields live and on submit", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/cart/checkout")

      assert lv |> form("#address-form", address: %{name: ""}) |> render_change() =~
               "can&#39;t be blank"

      html =
        lv
        |> form("#address-form", address: %{name: "Ada", line1: "", city: "", postal_code: "x"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert has_element?(lv, "#address-form")
    end

    test "a valid address advances to payment", %{conn: conn, cart: cart} do
      lv = to_payment(conn)
      assert lv |> element(~s(#checkout-steps [aria-current="step"])) |> render() =~ "Payment"
      assert ShoppingCart.get_cart!(cart.id).address.name == "Ada Lovelace"
    end
  end

  describe "payment step" do
    test "shows the address summary, the total, Edit address and Pay", %{conn: conn} do
      lv = to_payment(conn)
      html = lv |> element("#payment-step") |> render()

      assert html =~ "Ada Lovelace"
      assert html =~ "1 Analytical Way"
      assert html =~ "Total: $50.99"
      assert has_element?(lv, "button", "Edit address")
      assert has_element?(lv, "button", "Pay")
    end

    test "Edit address goes back to the address step, prefilled", %{conn: conn} do
      lv = to_payment(conn)
      lv |> element("button", "Edit address") |> render_click()
      assert_patch(lv, ~p"/cart/checkout")
      assert lv |> element("#address-form") |> render() =~ "Ada Lovelace"
    end
  end

  describe "step URLs" do
    test "back is honoured and a forward jump is ignored", %{conn: conn} do
      lv = to_payment(conn)

      assert render_patch(lv, ~p"/cart/checkout") =~ "Continue to payment"

      render_patch(lv, ~p"/cart/checkout/payment")
      assert_patch(lv, ~p"/cart/checkout")
      assert has_element?(lv, "#address-form")
      refute has_element?(lv, "#payment-step")
    end

    test "loading the payment URL without an address lands on the address step", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/cart/checkout"}}} =
               live(conn, ~p"/cart/checkout/payment")
    end

    test "reloading the payment URL lands on payment", %{conn: conn, cart: cart} do
      {:ok, _} =
        ShoppingCart.save_address(
          cart,
          address_attrs(),
          GoodDealWeb.Calibration.postal_code_length()
        )

      {:ok, lv, _html} = live(conn, ~p"/cart/checkout/payment")
      assert has_element?(lv, "#payment-step")
    end
  end

  describe "pay" do
    test "checks for an empty cart", %{conn: conn, cart: cart} do
      lv = to_payment(conn)
      for item <- ShoppingCart.list_cart_items(cart.id), do: ShoppingCart.delete_item(item)

      assert lv |> element("button", "Pay") |> render_click() =~ "Your cart is empty"
    end

    test "checks stock for every item", %{conn: conn, b: b} do
      lv = to_payment(conn)
      {:ok, _} = Catalog.update_product(b.product, %{stock: 0})

      assert lv |> element("button", "Pay") |> render_click() =~ "Some items are out of stock"
    end

    test "processes asynchronously, creates the order, completes the cart, decrements and broadcasts stock",
         %{conn: conn, cart: cart, a: a, b: b} do
      test_pid = self()

      expect(MockProvider, :create_checkout_session, fn line_items, opts ->
        assert length(line_items) == 2
        send(test_pid, {:paying, self()})
        assert_receive :settle
        {:ok, opts[:success_url]}
      end)

      {:ok, products_lv, _} = live(conn, ~p"/products")
      lv = to_payment(conn)

      html = lv |> element("button", "Pay") |> render_click()
      assert html =~ "Processing payment…"
      assert has_element?(lv, "button[disabled]", "Pay")
      assert has_element?(lv, "button[disabled]", "Edit address")

      assert_receive {:paying, payment_pid}
      send(payment_pid, :settle)

      assert_redirect(lv, success_url())

      assert ShoppingCart.get_cart!(cart.id).status == :completed
      assert [%Order{subtotal: 4500, total: 5099}] = GoodDeal.Repo.all(Order)
      assert Catalog.get_product!(a.product_id).stock == 8
      assert Catalog.get_product!(b.product_id).stock == 2
      assert products_lv |> element("#products-#{b.product_id}") |> render() =~ "Low stock"
    end

    test "the default provider settles in-process and returns the shop's success URL",
         %{conn: conn, cart: cart} do
      stub_with(MockProvider, InProcessProvider)
      lv = to_payment(conn)

      lv |> element("button", "Pay") |> render_click()
      assert_redirect(lv, success_url())
      assert ShoppingCart.get_cart!(cart.id).status == :completed
    end

    test "a failed payment shows Payment failed. and a retry that pays again",
         %{conn: conn, cart: cart} do
      MockProvider
      |> expect(:create_checkout_session, fn _, _ -> {:error, :declined} end)
      |> expect(:create_checkout_session, fn _, opts -> {:ok, opts[:success_url]} end)

      lv = to_payment(conn)
      lv |> element("button", "Pay") |> render_click()

      assert render_async(lv) =~ "Payment failed."
      assert ShoppingCart.get_cart!(cart.id).status == :open

      lv |> element("button", "Try again") |> render_click()
      assert_redirect(lv, success_url())
    end

    test "a crashing provider counts as a failed payment", %{conn: conn} do
      expect(MockProvider, :create_checkout_session, fn _, _ -> raise "provider down" end)
      lv = to_payment(conn)

      capture_log(fn ->
        lv |> element("button", "Pay") |> render_click()
        assert render_async(lv) =~ "Payment failed."
      end)
    end

    test "stock that runs out during payment stops the order", %{conn: conn, cart: cart, b: b} do
      expect(MockProvider, :create_checkout_session, fn _, opts ->
        {:ok, _} = Catalog.update_product(b.product, %{stock: 0})
        {:ok, opts[:success_url]}
      end)

      lv = to_payment(conn)
      lv |> element("button", "Pay") |> render_click()

      assert render_async(lv) =~ "Some items are out of stock"
      assert ShoppingCart.get_cart!(cart.id).status == :open
      refute has_element?(lv, "#processing")
    end
  end

  test "the success page thanks the shopper", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/cart/success")
    assert html =~ "Thank you for your order!"
  end
end
