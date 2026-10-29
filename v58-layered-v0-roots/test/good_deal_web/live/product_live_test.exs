defmodule GoodDealWeb.ProductLiveTest do
  use GoodDealWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GoodDeal.CatalogFixtures
  import GoodDeal.ShoppingCartFixtures, only: [shop: 1]

  @create_attrs %{
    name: "some name",
    description: "some description",
    amount: 42,
    stock: 42,
    thumbnail: "some thumbnail"
  }
  @update_attrs %{
    name: "some updated name",
    description: "some updated description",
    amount: 43,
    stock: 43,
    thumbnail: "some updated thumbnail"
  }
  @invalid_attrs %{name: nil, description: nil, amount: nil, stock: nil, thumbnail: nil}

  defp create_product(_) do
    product = product_fixture()
    %{product: product}
  end

  describe "Index" do
    setup [:create_product]

    test "lists all products", %{conn: conn, product: product} do
      {:ok, _index_live, html} = live(conn, ~p"/products")

      assert html =~ "Listing Products"
      assert html =~ product.name
    end

    test "stock shows as low at 5 and in stock at 6", %{conn: conn} do
      five = product_fixture(%{stock: 5})
      six = product_fixture(%{stock: 6})
      {:ok, index_live, _html} = live(conn, ~p"/products")

      assert index_live |> element("#products-#{five.id}") |> render() =~ "Low stock"
      assert index_live |> element("#products-#{six.id}") |> render() =~ "In stock"
    end

    test "saves new product", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/products")

      assert index_live |> element("a", "New Product") |> render_click() =~
               "New Product"

      assert_patch(index_live, ~p"/products/new")

      assert index_live
             |> form("#product-form", product: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#product-form", product: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/products")

      html = render(index_live)
      assert html =~ "Product created successfully"
      assert html =~ "some name"
    end

    test "updates product in listing", %{conn: conn, product: product} do
      {:ok, index_live, _html} = live(conn, ~p"/products")

      assert index_live |> element("#products-#{product.id} a", "Edit") |> render_click() =~
               "Edit Product"

      assert_patch(index_live, ~p"/products/#{product}/edit")

      assert index_live
             |> form("#product-form", product: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#product-form", product: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/products")

      html = render(index_live)
      assert html =~ "Product updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes product in listing", %{conn: conn, product: product} do
      {:ok, index_live, _html} = live(conn, ~p"/products")

      assert index_live |> element("#products-#{product.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#products-#{product.id}")
    end
  end

  describe "Show" do
    setup [:create_product]

    test "displays product", %{conn: conn, product: product} do
      {:ok, _show_live, html} = live(conn, ~p"/products/#{product}")

      assert html =~ "Show Product"
      assert html =~ product.name
    end

    test "updates product within modal", %{conn: conn, product: product} do
      {:ok, show_live, _html} = live(conn, ~p"/products/#{product}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Product"

      assert_patch(show_live, ~p"/products/#{product}/show/edit")

      assert show_live
             |> form("#product-form", product: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#product-form", product: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/products/#{product}")

      html = render(show_live)
      assert html =~ "Product updated successfully"
      assert html =~ "some updated name"
    end
  end

  describe "Index extras" do
    setup [:create_product]

    test "lists name, description, price, thumbnail and stock", %{conn: conn} do
      product = product_fixture(%{name: "Mug", amount: 1299, stock: 3, thumbnail: "/mug.png"})
      {:ok, index_live, _html} = live(conn, ~p"/products")

      row = index_live |> element("#products-#{product.id}") |> render()
      assert row =~ "Mug"
      assert row =~ "some description"
      assert row =~ "$12.99"
      assert row =~ ~s(src="/mug.png")
      assert row =~ "Low stock"
      assert has_element?(index_live, ~s(#products[phx-update="stream"]))
    end

    test "submitting an invalid form keeps the modal open with errors", %{
      conn: conn,
      product: product
    } do
      {:ok, index_live, _html} = live(conn, ~p"/products/new")

      assert index_live |> form("#product-form", product: @invalid_attrs) |> render_submit() =~
               "can&#39;t be blank"

      {:ok, show_live, _html} = live(conn, ~p"/products/#{product}/show/edit")

      assert show_live |> form("#product-form", product: @invalid_attrs) |> render_submit() =~
               "can&#39;t be blank"
    end

    test "add to cart persists a line in the session cart", %{conn: conn, product: product} do
      conn = get(conn, ~p"/products")
      cart_id = get_session(conn, "cart_id")
      {:ok, index_live, _html} = live(conn, ~p"/products")

      html =
        index_live |> element("#products-#{product.id} a", "Add to cart") |> render_click()

      assert html =~ "Added to cart"
      assert [%{quantity: 1}] = GoodDeal.ShoppingCart.list_cart_items(shop(cart_id))

      index_live |> element("#products-#{product.id} a", "Add to cart") |> render_click()
      assert [%{quantity: 2}] = GoodDeal.ShoppingCart.list_cart_items(shop(cart_id))
    end

    test "products saved elsewhere appear and update in every open list", %{conn: conn} do
      {:ok, editor, _html} = live(conn, ~p"/products/new")
      {:ok, viewer, _html} = live(conn, ~p"/products")

      editor
      |> form("#product-form", product: %{name: "Fresh Kettle", amount: 100})
      |> render_submit()

      assert render(viewer) =~ "Fresh Kettle"

      product = product_fixture(%{name: "Context Product"})
      assert render(viewer) =~ "Context Product"

      {:ok, _} = GoodDeal.Catalog.update_product(product, %{name: "Renamed Product"})
      assert render(viewer) =~ "Renamed Product"

      {:ok, _} = GoodDeal.Catalog.delete_product(product)
      refute has_element?(viewer, "#products-#{product.id}")
    end

    test "a stock change shows in every open list", %{conn: conn, product: product} do
      {:ok, viewer, _html} = live(conn, ~p"/products")

      {:ok, _} = GoodDeal.Catalog.update_product(product, %{stock: 0})
      assert viewer |> element("#products-#{product.id}") |> render() =~ "Out of stock"
    end
  end
end
