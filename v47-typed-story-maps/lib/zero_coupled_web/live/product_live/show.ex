defmodule ZeroCoupledWeb.ProductLive.Show do
  use ZeroCoupledWeb, :live_view

  import ZeroCoupled.Catalog.Panes, only: [only_on: 1]
  import ZeroCoupled.Catalog.RecordForm
  alias ZeroCoupled.Actions.SaveProduct
  alias ZeroCoupled.Foundation.Products
  alias ZeroCoupled.State.RecordEdit
  alias ZeroCoupledWeb.StoreConfig
  alias ZeroCoupledWeb.Paradigms.Binder

  def parts, do: %{form: RecordEdit}
  def ports, do: %{in: [], out: [edit: :product_id]}
  def grounded, do: [{:form, :row}]

  # {source, port} → where it goes on this page, for the product it shows
  def bindings(id) do
    %{
      {:page, :edit} => [
        {:via, &Products.get!/1, :record, [{:input, :form, &RecordEdit.edit/2}]}
      ],
      {:form, :form} => [{:form, :form}],
      {:form, :submit} => [
        {:via, &SaveProduct.save/1, :save_result, [{:input, :form, &RecordEdit.saved/2}]}
      ],
      {:form, :saved} => [{:show, :product}],
      {:form, :closed} => [
        {:flash, :info, "Product updated successfully"},
        {:patch, %{edit: ~p"/products/#{id}"}}
      ]
    }
  end

  @doc "The page (the root story) with its record form, for one product."
  def composition(id),
    do:
      {Binder.story(
         __MODULE__,
         %{form: RecordEdit.new(changeset: &Products.changeset/2)},
         bindings(id)
       ), %{}}

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, form_text: StoreConfig.product_form(), form: nil)}

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:product, Products.get!(id))
     |> Binder.mount(composition(id))
     |> Binder.send_out(:page, :edit, id)}
  end

  @impl true
  def handle_event("validate_product", %{"product" => params}, socket),
    do: {:noreply, Binder.run(socket, :page, :form, &RecordEdit.validate(&1, params))}

  def handle_event("save_product", %{"product" => params}, socket),
    do: {:noreply, Binder.run(socket, :page, :form, &RecordEdit.submit(&1, params))}

  defp page_title(:show), do: "Show Product"
  defp page_title(:edit), do: "Edit Product"
end
