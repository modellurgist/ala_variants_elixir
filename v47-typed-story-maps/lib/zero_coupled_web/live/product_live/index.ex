defmodule ZeroCoupledWeb.ProductLive.Index do
  use ZeroCoupledWeb, :live_view

  on_mount {ZeroCoupledWeb.Paradigms.Subscribed, {ZeroCoupled.Foundation.Broadcast, :subscribe}}
  import ZeroCoupled.Catalog.Panes
  import ZeroCoupled.Domain.StockIndicator
  import ZeroCoupled.Catalog.RecordForm
  alias ZeroCoupled.Actions.SaveProduct
  alias ZeroCoupled.Domain.{AddLine, StockStatus}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Products, Schemas.Product}
  alias ZeroCoupled.State.RecordEdit
  alias ZeroCoupledWeb.{CartSession, StoreConfig}
  alias ZeroCoupledWeb.Paradigms.Binder

  @flash_ms 2500
  @stock_labels %{
    in_stock: "%{n} in stock",
    low_stock: "Only %{n} left!",
    out_of_stock: "Out of stock"
  }

  @saved %{new: "Product created successfully", edit: "Product updated successfully"}

  def parts, do: %{form: RecordEdit}
  def ports, do: %{in: [], out: [edit: :product_id]}
  def grounded, do: [{:form, :saved}]

  # {source, port} → where it goes on this page
  def bindings do
    %{
      {:page, :edit} => [
        {:via, &Products.get!/1, :record, [{:input, :form, &RecordEdit.edit/2}]}
      ],
      {:form, :form} => [{:form, :form}],
      {:form, :submit} => [
        {:via, &SaveProduct.save/1, :save_result, [{:input, :form, &RecordEdit.saved/2}]}
      ],
      {:form, :row} => [{:stream, :products}],
      {:form, :closed} => [
        {:flash_for, :info, @saved},
        {:patch, %{new: ~p"/products", edit: ~p"/products"}}
      ]
    }
  end

  @doc "The page (the root story) with its record form, and no stories."
  def composition,
    do:
      {Binder.story(
         __MODULE__,
         %{form: RecordEdit.new(changeset: &Products.changeset/2)},
         bindings()
       ), %{}}

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
        },
        form_text: StoreConfig.product_form(),
        form: nil
      )
      |> stream(:products, Products.list())
      |> Binder.mount(composition())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Product")
    |> Binder.send_out(:page, :edit, id)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> Binder.run(:page, :form, &RecordEdit.create(&1, %Product{}))
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "All Products")
  end

  @impl true
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
  def handle_event("validate_product", %{"product" => params}, socket),
    do: {:noreply, Binder.run(socket, :page, :form, &RecordEdit.validate(&1, params))}

  def handle_event("save_product", %{"product" => params}, socket),
    do: {:noreply, Binder.run(socket, :page, :form, &RecordEdit.submit(&1, params))}

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
