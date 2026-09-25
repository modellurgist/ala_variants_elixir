defmodule ZeroCoupledWeb.ProductLive.Index do
  use ZeroCoupledWeb, :live_view

  alias ZeroCoupled.Foundation.{Products, Carts, Broadcast, Schemas.Product}

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Broadcast.subscribe()

    socket =
      socket
      |> assign(:cart_id, session["cart_id"])
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

  # Product form component saved a product in this process.
  @impl true
  def handle_info({ZeroCoupledWeb.ProductLive.FormComponent, {:saved, product}}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  # A product was saved anywhere (PubSub fact).
  def handle_info({:product_saved, product}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  # Stock changed (e.g. via a completed checkout in another session).
  def handle_info({:stock_changed, product_id, new_stock}, socket) do
    product = %{Products.get!(product_id) | stock: new_stock}
    {:noreply, stream_insert(socket, :products, product)}
  end

  def handle_info(:clear_flash, socket), do: {:noreply, clear_flash(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Products.get!(id)
    {:ok, _} = Products.delete(product)
    {:noreply, stream_delete(socket, :products, product)}
  end

  def handle_event("add_to_cart", %{"id" => id}, socket) do
    product = Products.get!(id)
    Carts.add_item(socket.assigns.cart_id, product)
    Process.send_after(self(), :clear_flash, 2500)
    {:noreply, put_flash(socket, :info, "Added to cart")}
  end
end
