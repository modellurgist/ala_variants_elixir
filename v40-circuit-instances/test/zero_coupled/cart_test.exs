defmodule ZeroCoupled.CartTest do
  use ExUnit.Case, async: true

  import ZeroCoupled.CartFixtures
  alias ZeroCoupled.Cart

  # V34: the aggregate holds no baked rates/codes, so a test — playing the
  # composition role — supplies the pricing config the manifest would.
  @config [
    shipping: %{
      standard: %{label: "Standard", cost: 599, free_above: 5000},
      express: %{label: "Express", cost: 1299, free_above: nil}
    },
    promo: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50},
    gift_wrap_unit: 299
  ]

  defp cart(items), do: Cart.new(cart_id: 1, items: items, config: @config)

  describe "derived pricing (recalc)" do
    test "subtotal, item_count and total for a fresh cart" do
      c = cart([line_item(1, amount: 1000, quantity: 2), line_item(2, amount: 500, quantity: 1)])

      assert c.subtotal == Money.new(2500)
      assert c.item_count == 3
      assert c.total == Money.new(2500 + shipping_for(2500))
    end

    test "empty cart has zero everything and free shipping" do
      c = cart([])
      assert c.subtotal == Money.new(0)
      assert c.total == Money.new(0)
      assert c.shipping_cost == Money.new(0)
      assert Cart.empty?(c)
    end
  end

  describe "update_quantity/3" do
    test "increments and returns the updated item; recomputes totals" do
      c = cart([line_item(1, amount: 1000, quantity: 1)])
      assert {:ok, c, item} = Cart.update_quantity(c, 1, 1)
      assert item.quantity == 2
      assert c.subtotal == Money.new(2000)
    end

    test "never drops below 1" do
      c = cart([line_item(1, quantity: 1)])
      assert {:ok, _c, item} = Cart.update_quantity(c, 1, -5)
      assert item.quantity == 1
    end

    test "returns :error for an unknown item" do
      assert :error = Cart.update_quantity(cart([line_item(1)]), 999, 1)
    end
  end

  describe "remove_item/2 and add_item/2" do
    test "remove returns the removed item and drops its gift-wrap flag" do
      c = cart([line_item(1), line_item(2)])
      {:ok, c, _, _} = Cart.toggle_gift_wrap(c, 1)
      assert Cart.gift_wrapped?(c, 1)

      assert {:ok, c, removed} = Cart.remove_item(c, 1)
      assert removed.id == 1
      refute Cart.gift_wrapped?(c, 1)
      assert length(c.items) == 1
    end

    test "add_item is idempotent by id" do
      item = line_item(1)
      c = cart([])
      {:ok, c, _} = Cart.add_item(c, item)
      {:ok, c, _} = Cart.add_item(c, item)
      assert length(c.items) == 1
    end

    test "remove of unknown item is an error" do
      assert :error = Cart.remove_item(cart([]), 1)
    end
  end

  describe "gift wrap" do
    test "toggling adds cost per wrapped item" do
      c = cart([line_item(1, amount: 1000), line_item(2, amount: 1000)])
      {:ok, c, _item, wrapped?} = Cart.toggle_gift_wrap(c, 1)
      assert wrapped?
      assert c.gift_wrap_total == Money.new(299)

      {:ok, c, _item, wrapped?} = Cart.toggle_gift_wrap(c, 2)
      refute wrapped? == false
      assert c.gift_wrap_total == Money.new(598)
    end

    test "toggling twice removes it" do
      c = cart([line_item(1)])
      {:ok, c, _, true} = Cart.toggle_gift_wrap(c, 1)
      {:ok, c, _, false} = Cart.toggle_gift_wrap(c, 1)
      assert c.gift_wrap_total == Money.new(0)
    end
  end

  describe "promo codes" do
    test "valid code applies a percentage discount" do
      c = cart([line_item(1, amount: 1000, quantity: 1)])
      assert {:ok, c} = Cart.apply_promo(c, "save10")
      assert c.promo_code == "SAVE10"
      assert c.discount == Money.new(100)
    end

    test "invalid code is rejected and leaves the cart unchanged" do
      c = cart([line_item(1, amount: 1000)])
      assert {:error, :invalid_code} = Cart.apply_promo(c, "NOPE")
      assert c.discount == Money.new(0)
    end
  end

  describe "shipping" do
    test "selecting a method recomputes shipping cost" do
      c = cart([line_item(1, amount: 1000)])
      c = Cart.select_shipping(c, :express)
      assert c.shipping_method == :express
      assert c.shipping_cost == Money.new(1299)
    end
  end

  describe "set_stock/3" do
    test "updates the stock of a product in the cart" do
      c = cart([line_item(1, product_id: 7, stock: 10)])
      assert {:ok, c, item} = Cart.set_stock(c, 7, 2)
      assert item.product.stock == 2
      assert hd(c.items).product.stock == 2
    end

    test "is :none when the product is not in the cart" do
      assert :none = Cart.set_stock(cart([line_item(1, product_id: 7)]), 99, 0)
    end
  end

  describe "check_ready/2 and line_items/1" do
    test "ok when non-empty and in stock" do
      c = cart([line_item(1, product_id: 7, quantity: 2)])
      assert :ok = Cart.check_ready(c, %{7 => 5})
    end

    test "error when empty" do
      assert {:error, :empty_cart} = Cart.check_ready(cart([]), %{})
    end

    test "error when out of stock" do
      c = cart([line_item(1, product_id: 7, quantity: 5)])
      assert {:error, :out_of_stock} = Cart.check_ready(c, %{7 => 1})
    end

    test "line_items builds a payment payload" do
      c = cart([line_item(1, amount: 1000, quantity: 2)])
      assert [%{unit_amount: 1000, quantity: 2, currency: "usd"}] = Cart.line_items(c)
    end
  end

  # standard shipping is free above $50, else 599
  defp shipping_for(subtotal) when subtotal >= 5000, do: 0
  defp shipping_for(_), do: 599
end
