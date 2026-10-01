defmodule GoodDealWeb.ProductLive.Index do
  use GoodDealWeb, :live_view
  on_mount {GoodDealWeb.Paradigms.Subscribed, {GoodDeal.Foundation.Broadcast, :subscribe}}
  import GoodDealWeb.Parts, only: [only_on: 1]
  import GoodDeal.Domain.StockIndicator

  alias GoodDeal.Domain.{AddLine, Inventory}
  alias GoodDeal.Foundation.{Products, Carts}
  alias GoodDeal.Foundation.Schemas.Product
  alias GoodDealWeb.CartSession

  @flash_ms 2500
  @stock_labels %{
    in_stock: "%{n} in stock",
    low_stock: "Only %{n} left!",
    out_of_stock: "Out of stock"
  }

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(
        cart_id: CartSession.fetch(session),
        stock_rule: Inventory.new(low_at: GoodDeal.Catalog.low_stock_threshold()),
        stock_labels: @stock_labels,
        add_line: %AddLine{carts: Carts, products: Products}
      )
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
  def handle_info({:stock_changed, {product_id, _stock}}, socket),
    do: {:noreply, stream_insert(socket, :products, Products.get!(product_id))}

  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, product} = Products.delete_by_id(id)
    {:noreply, stream_delete(socket, :products, product)}
  end

  @impl true
  def handle_event("add_to_cart", %{"id" => id}, socket) do
    AddLine.run(socket.assigns.add_line, socket.assigns.cart_id, String.to_integer(id))
    Process.send_after(self(), :clear_flash, @flash_ms)
    {:noreply, put_flash(socket, :info, "Added to cart")}
  end
end
