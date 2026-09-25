defmodule GoodDealWeb.ProductLive.Index do
  use GoodDealWeb, :live_view

  alias GoodDeal.Foundation.{Products, Carts, Broadcast}
  alias GoodDeal.Foundation.Schemas.Product
  alias GoodDealWeb.CartSession

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Broadcast.subscribe()

    socket =
      socket
      |> assign(:cart_id, CartSession.fetch(session))
      |> assign(:low_stock, GoodDeal.Catalog.low_stock_threshold())
      |> stream(:products, Products.list())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, Products.get!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, %Product{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "All Products")
    |> assign(:product, nil)
  end

  @impl true
  def handle_info({GoodDealWeb.ProductLive.FormComponent, {:saved, product}}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  @impl true
  def handle_info({:product_updated, updated_product}, socket) do
    {:noreply, stream_insert(socket, :products, updated_product)}
  end

  @impl true
  def handle_info({:product_created, created_product}, socket) do
    {:noreply, stream_insert(socket, :products, created_product)}
  end

  @impl true
  def handle_info({:stock_changed, {product_id, new_stock}}, socket) do
    product = Products.get!(product_id)
    {:noreply, stream_insert(socket, :products, %{product | stock: new_stock})}
  end

  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Products.get!(id)
    {:ok, _} = Products.delete(product)
    {:noreply, stream_delete(socket, :products, product)}
  end

  @impl true
  def handle_event("add_to_cart", %{"id" => id}, socket) do
    product = Products.get!(id)
    Carts.add_item(socket.assigns.cart_id, product)
    Process.send_after(self(), :clear_flash, 2500)
    {:noreply, socket |> put_flash(:info, "Added to cart")}
  end
end
