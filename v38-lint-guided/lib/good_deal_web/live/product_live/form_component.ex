defmodule GoodDealWeb.ProductLive.FormComponent do
  use GoodDealWeb, :live_component

  alias GoodDeal.Foundation.Products
  alias GoodDeal.Actions.SaveProduct

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage product records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="product-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:amount]} type="number" label="Amount" />
        <.input field={@form[:description]} type="text" label="Description" />
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:stock]} type="number" label="Stock" />
        <.input field={@form[:thumbnail]} type="text" label="Thumbnail" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Product</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{product: product} = assigns, socket) do
    changeset = Products.changeset(product)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset =
      socket.assigns.product
      |> Products.changeset(product_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"product" => product_params}, socket) do
    action = socket.assigns.action
    result = save_product(action, socket.assigns.product, product_params)
    {:noreply, apply_save(socket, action, result)}
  end

  defp save_product(:new, _product, params), do: SaveProduct.run(:new, params)
  defp save_product(:edit, product, params), do: SaveProduct.run(:edit, product, params)

  defp apply_save(socket, action, {:ok, product}) do
    notify_parent({:saved, product})
    verb = if action == :new, do: "created", else: "updated"

    socket
    |> put_flash(:info, "Product #{verb} successfully")
    |> push_patch(to: socket.assigns.patch)
  end

  defp apply_save(socket, _action, {:error, %Ecto.Changeset{} = changeset}) do
    assign_form(socket, changeset)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
