defmodule GoodDeal.Components.Panes do
  @moduledoc """
  Generic "show this part when" components, so a page's markup places parts without comparing
  values itself. `pane/1` keeps its content mounted and hides it; `only_on/1` renders its content
  only when current; `tabs/1` renders a tab bar whose buttons fire a configured event.
  """
  use Phoenix.Component

  attr :current, :any, required: true
  attr :name, :any, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def pane(assigns) do
    ~H"""
    <div class={[@class, @current != @name && "hidden"]}>{render_slot(@inner_block)}</div>
    """
  end

  attr :current, :any, required: true
  attr :name, :any, required: true
  slot :inner_block, required: true

  def only_on(assigns) do
    ~H"""
    <%= if @current == @name do %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end

  attr :current, :any, required: true
  attr :event, :string, required: true

  slot :tab, required: true do
    attr :name, :atom, required: true
    attr :label, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <nav class="mb-2 flex gap-6 border-b border-stone-200">
      <button
        :for={tab <- @tab}
        phx-click={@event}
        phx-value-tab={tab.name}
        class={[
          "-mb-px border-b-2 pb-3 text-sm font-medium",
          (@current == tab.name && "border-brand-700 text-stone-900") ||
            "border-transparent text-stone-500 hover:text-stone-800"
        ]}
      >
        {tab.label}
      </button>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :stream, :any, required: true, doc: "a LiveView stream (`@streams.name`)"
  attr :class, :any, default: nil

  slot :inner_block,
    required: true,
    doc: "one entry, given `{dom_id, item}`; its root element takes `id={dom_id}`"

  @doc "A stream's container, rendering each entry through the slot, so a page iterates nothing itself."
  def stream_list(assigns) do
    ~H"""
    <div id={@id} phx-update="stream" class={@class}>
      <%= for entry <- @stream do %>
        {render_slot(@inner_block, entry)}
      <% end %>
    </div>
    """
  end
end
