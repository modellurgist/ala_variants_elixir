defmodule ZeroCoupled.Catalog.RecordForm do
  @moduledoc """
  A form for one record, as a UI widget whose own state is the form being typed. It takes the record,
  the changeset function that validates it, the fields and the words as attributes, validates as the
  user types, and sends `{name, :submitted, {action, record, params}}` to the page that placed it. It
  never saves: the page wires that, and sends back `invalid: changeset` if the save fails. Nothing in
  it knows a page or a product, so it replaces the page-specific `FormComponent` that `phx.gen.live`
  generates.
  """
  use Phoenix.LiveComponent
  import ZeroCoupledWeb.CoreComponents, only: [header: 1, simple_form: 1, input: 1, button: 1]
  alias ZeroCoupledWeb.Paradigms.Instance

  @doc "What it sends the page that placed it, as `{name, port, payload}`; its input is `invalid: changeset`."
  def sent_port_outputs, do: [:submitted]

  @impl true
  def update(%{invalid: changeset}, socket), do: {:ok, assign(socket, :form, to_form(changeset))}

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, assign(socket, :form, to_form(assigns.changeset.(assigns.record, %{})))}
  end

  @impl true
  def handle_event("validate", params, socket) do
    changeset = socket.assigns.changeset.(socket.assigns.record, params[socket.assigns.form.name])
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("submit", params, socket) do
    request = {socket.assigns.action, socket.assigns.record, params[socket.assigns.form.name]}
    {:noreply, Instance.send_port_output(socket, socket.assigns.name, {:submitted, request})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header class="mb-6">
        {@title}
        <:subtitle :if={@subtitle}>{@subtitle}</:subtitle>
      </.header>
      <.simple_form
        for={@form}
        id={@id}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="submit"
      >
        <.input :for={{field, type, label} <- @fields} field={@form[field]} type={type} label={label} />
        <:actions>
          <.button phx-disable-with={@saving}>{@submit}</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
