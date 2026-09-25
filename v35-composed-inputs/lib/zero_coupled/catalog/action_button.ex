defmodule ZeroCoupled.Catalog.ActionButton do
  @moduledoc """
  Zero-coupled **event port** as a component. The event to fire is passed in as
  data (`on`, sourced from `ZeroCoupled.Web.Contracts.event/1`), not baked in as
  a literal `phx-click="…"`. The button therefore knows no intent names — the
  composition site wires which intent this button triggers, exactly like a
  manifest wire, but for a UI action.

  Event payloads ride the `:rest` global (`phx-value-item-id={…}` etc.), so the
  wire's param names — part of the intent's declared contract — are chosen by
  the composition site, not this component.
  """
  use Phoenix.Component

  attr :on, :string, required: true, doc: "event name from Web.Contracts.event/1"
  attr :label, :string, required: true
  attr :class, :string, default: "text-sm font-medium text-blue-600"
  attr :rest, :global, doc: "phx-value-* payload attributes"

  def action_button(assigns) do
    ~H"""
    <button phx-click={@on} class={@class} {@rest}>
      <%= @label %>
    </button>
    """
  end
end
