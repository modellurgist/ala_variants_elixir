defmodule GoodDeal.Components.RecordForm do
  @moduledoc """
  A form for one record: a heading, an input per configured field, and a submit button. It takes the
  form, the fields, the words and the event names as attributes, and keeps no state of its own, so
  any page can place it over any record a store validates (Spray's UI abstraction: data in,
  events out, §3.5.1). It replaces the page-specific `FormComponent` that `phx.gen.live` generates.
  """
  use Phoenix.Component
  import GoodDealWeb.CoreComponents, only: [header: 1, simple_form: 1, input: 1, button: 1]

  attr :id, :string, required: true
  attr :form, :any, required: true
  attr :fields, :list, required: true, doc: "`{field, type, label}` for each input, in order"
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :submit, :string, required: true
  attr :saving, :string, required: true
  attr :on_validate, :string, required: true
  attr :on_submit, :string, required: true

  def record_form(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle :if={@subtitle}>{@subtitle}</:subtitle>
      </.header>
      <.simple_form for={@form} id={@id} phx-change={@on_validate} phx-submit={@on_submit}>
        <.input :for={{field, type, label} <- @fields} field={@form[field]} type={type} label={label} />
        <:actions>
          <.button phx-disable-with={@saving}>{@submit}</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
