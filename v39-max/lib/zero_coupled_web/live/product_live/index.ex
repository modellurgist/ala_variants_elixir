defmodule ZeroCoupledWeb.ProductLive.Index do
  use ZeroCoupledWeb, :live_view

  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  import ZeroCoupled.Catalog.Panes
  import ZeroCoupled.Domain.StockIndicator
  alias ZeroCoupled.Domain.{AddLine, StockStatus}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Products, Schemas.Product}
  alias ZeroCoupledWeb.{CartSession, StoreConfig}

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
        cart_id: session[CartSession.cart_key()],
        stock_status: StockStatus.new(low_at: StoreConfig.low_stock_at()),
        stock_labels: @stock_labels,
        add_line: %AddLine{
          carts: Carts,
          products: Products,
          cart_id: session[CartSession.cart_key()]
        }
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

  # Product form component saved a product in this process.
  @impl true
  def handle_info({ZeroCoupledWeb.ProductLive.FormComponent, {:saved, product}}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  # A product was saved anywhere (typed PubSub fact — V32 Enhancement B:
  # a shape change here is a compile error at the emit site, not a
  # silently-unmatched tuple).
  def handle_info(%Broadcast.Facts.ProductSaved{product: product}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  # Stock changed (e.g. via a completed checkout in another session).
  def handle_info(%Broadcast.Facts.StockChanged{product_id: product_id}, socket),
    do: {:noreply, stream_insert(socket, :products, Products.get!(product_id))}

  def handle_info(:clear_flash, socket), do: {:noreply, clear_flash(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, product} = Products.delete_by_id(id)
    {:noreply, stream_delete(socket, :products, product)}
  end

  def handle_event("add_to_cart", %{"id" => id}, socket) do
    AddLine.run(socket.assigns.add_line, %{id: String.to_integer(id)})
    Process.send_after(self(), :clear_flash, @flash_ms)
    {:noreply, put_flash(socket, :info, "Added to cart")}
  end
end
