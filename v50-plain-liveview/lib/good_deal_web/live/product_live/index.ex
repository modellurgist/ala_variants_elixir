defmodule GoodDealWeb.ProductLive.Index do
  use GoodDealWeb, :live_view
  import GoodDeal.Components.Panes, only: [only_on: 1, stream_list: 1]
  import GoodDeal.Domain.StockIndicator

  import GoodDeal.Components.RecordForm

  alias GoodDeal.Actions.SaveProduct
  alias GoodDeal.Domain.{AddLine, StockStatus}
  alias GoodDeal.Foundation.{Products, Carts}
  alias GoodDeal.Foundation.Schemas.Product
  alias GoodDeal.State.RecordEdit
  alias GoodDealWeb.CartSession
  alias GoodDealWeb.Paradigms.{ChangeFeed, Steps}

  @flash_ms 2500
  @changes ChangeFeed.new(GoodDeal.Catalog.changes_topic())
  @saved %{new: "Product created successfully", edit: "Product updated successfully"}

  @doc "Which state each `wire/3` key names, so a test can check every declared port has a clause."
  @features %{
    product_form: RecordEdit,
    feed: ChangeFeed.new(GoodDeal.Catalog.changes_topic(), [:product, :stock])
  }
  def features, do: @features

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
        stock_rule: StockStatus.new(low_at: GoodDeal.Catalog.low_stock_threshold()),
        stock_labels: @stock_labels,
        add_line: %AddLine{carts: Carts, products: Products, cart_id: CartSession.fetch(session)},
        product_form: RecordEdit.new(changeset: &Products.changeset/2),
        form_text: GoodDeal.Catalog.product_form(),
        form: nil
      )
      |> stream(:products, Products.list())
      |> ChangeFeed.attach(:feed, @features.feed, &run/3)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Product")
    |> Steps.feed(:product_form, &RecordEdit.edit/2, &Products.get!/1, id, &wire/3)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> run(:product_form, &RecordEdit.create(&1, %Product{}))
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "All Products")
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, product} = Products.delete_by_id(id)
    {:noreply, stream_delete(socket, :products, product)}
  end

  def handle_event("validate_product", %{"product" => params}, socket),
    do: {:noreply, run(socket, :product_form, &RecordEdit.validate(&1, params))}

  def handle_event("save_product", %{"product" => params}, socket),
    do: {:noreply, run(socket, :product_form, &RecordEdit.submit(&1, params))}

  @impl true
  def handle_event("add_to_cart", %{"id" => id}, socket) do
    AddLine.run(socket.assigns.add_line, %{id: String.to_integer(id)})
    Process.send_after(self(), :clear_flash, @flash_ms)
    {:noreply, put_flash(socket, :info, "Added to cart")}
  end

  defp run(socket, key, step), do: Steps.run(socket, key, step, &wire/3)

  # {state, port} → where it wires on this page
  defp wire(s, :product_form, {:form, changeset}), do: assign(s, :form, to_form(changeset))

  defp wire(s, :product_form, {:submit, request}),
    do: Steps.feed(s, :product_form, &RecordEdit.saved/2, &SaveProduct.save/1, request, &wire/3)

  defp wire(s, :product_form, {:saved, {action, product}}) do
    ChangeFeed.publish(@changes, :product, product.id)
    ChangeFeed.publish(@changes, :stock, product.id, product.stock)

    s
    |> stream_insert(:products, product)
    |> put_flash(:info, @saved[action])
    |> push_patch(to: ~p"/products")
  end

  defp wire(s, :feed, {:product, id}), do: stream_insert(s, :products, Products.get!(id))
  defp wire(s, :feed, {:stock, {id, _stock}}), do: stream_insert(s, :products, Products.get!(id))
end
