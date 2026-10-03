defmodule ZeroCoupledWeb.ProductLive.Show do
  use ZeroCoupledWeb, :live_view

  import ZeroCoupled.Catalog.Panes, only: [only_on: 1]
  alias ZeroCoupled.Actions.SaveProduct
  alias ZeroCoupled.Catalog.RecordForm
  alias ZeroCoupled.Foundation.Products
  alias ZeroCoupledWeb.StoreConfig

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, :form_text, StoreConfig.product_form())}

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:product, Products.get!(id))}
  end

  # saving is I/O; LiveView's task carries the outcome back
  @impl true
  def handle_info({:product_form, :submitted, request}, socket),
    do: {:noreply, start_async(socket, :save_product, fn -> SaveProduct.save(request) end)}

  @impl true
  def handle_async(:save_product, {:ok, {:ok, product}}, socket),
    do:
      {:noreply,
       socket
       |> assign(:product, product)
       |> put_flash(:info, "Product updated successfully")
       |> push_patch(to: ~p"/products/#{product}")}

  def handle_async(:save_product, {:ok, {:error, changeset}}, socket) do
    send_update(RecordForm, id: socket.assigns.form_text.id, invalid: changeset)
    {:noreply, socket}
  end

  defp page_title(:show), do: "Show Product"
  defp page_title(:edit), do: "Edit Product"
end
