defmodule GoodDealWeb.ProductLive.Show do
  use GoodDealWeb, :live_view
  import GoodDeal.Components.RecordForm

  alias GoodDeal.Actions.SaveProduct
  alias GoodDeal.Foundation.Products
  alias GoodDeal.State.RecordEdit
  alias GoodDealWeb.Paradigms.Steps

  @doc "Which state each `wire/3` key names, so a test can check every declared port has a clause."
  @parts %{product_form: RecordEdit}
  def parts, do: @parts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       product_form: RecordEdit.new(changeset: &Products.changeset/2),
       form_text: GoodDeal.Catalog.product_form(),
       form: nil
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:product, Products.get!(id))
     |> Steps.feed(:product_form, &RecordEdit.edit/2, &Products.get!/1, id, &wire/3)}
  end

  @impl true
  def handle_event("validate_product", %{"product" => params}, socket),
    do: {:noreply, Steps.run(socket, :product_form, &RecordEdit.validate(&1, params), &wire/3)}

  def handle_event("save_product", %{"product" => params}, socket),
    do: {:noreply, Steps.run(socket, :product_form, &RecordEdit.submit(&1, params), &wire/3)}

  defp page_title(:show), do: "Show Product"
  defp page_title(:edit), do: "Edit Product"

  # {state, port} → where it wires on this page
  defp wire(s, :product_form, {:form, changeset}), do: assign(s, :form, to_form(changeset))

  defp wire(s, :product_form, {:submit, request}),
    do: Steps.feed(s, :product_form, &RecordEdit.saved/2, &SaveProduct.save/1, request, &wire/3)

  defp wire(s, :product_form, {:saved, {_action, product}}),
    do:
      s
      |> assign(:product, product)
      |> put_flash(:info, "Product updated successfully")
      |> push_patch(to: ~p"/products/#{product}")
end
