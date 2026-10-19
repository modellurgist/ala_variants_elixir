defmodule GoodDealWeb.ProductLive.Index do
  use GoodDealWeb, :live_view

  alias GoodDeal.{Catalog, ShoppingCart}
  alias GoodDeal.Catalog.Product

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Catalog.subscribe()

    {:ok, stream(socket, :products, Catalog.list_products())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, Catalog.get_product!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, %Product{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Products")
    |> assign(:product, nil)
  end

  @impl true
  def handle_info({GoodDealWeb.ProductLive.FormComponent, {:saved, product}}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  def handle_info({event, product}, socket) when event in [:product_created, :product_updated] do
    {:noreply, stream_insert(socket, :products, product)}
  end

  def handle_info({:product_deleted, product}, socket) do
    {:noreply, stream_delete(socket, :products, product)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Catalog.get_product!(id)
    {:ok, _} = Catalog.delete_product(product)

    {:noreply, stream_delete(socket, :products, product)}
  end

  def handle_event("add_to_cart", %{"id" => id}, socket) do
    product = Catalog.get_product!(id)
    {:ok, _item} = ShoppingCart.add_item(socket.assigns.cart_id, product.id)
    {:noreply, put_flash(socket, :info, "Added to cart")}
  end
end
