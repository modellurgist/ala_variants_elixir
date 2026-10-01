defmodule GoodDealWeb.Parts do
  @moduledoc """
  Generic page parts over the shapes the features project: tabs and panes, a cart line, a stock
  badge, the cart's summary, a shipping choice, a toggle, a promo form, buttons and
  notes. Each takes its words from the page and the events it fires as attributes, so a page's
  markup only places them.
  """
  use Phoenix.Component

  attr :current, :any, required: true
  attr :event, :string, required: true

  slot :tab, required: true do
    attr :name, :atom, required: true
    attr :label, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <nav class="flex gap-2 border-b mb-6 pb-2">
      <button
        :for={tab <- @tab}
        phx-click={@event}
        phx-value-tab={tab.name}
        class={[
          "px-4 py-2 text-sm font-medium rounded-t",
          (@current == tab.name && "bg-zinc-900 text-white") || "text-zinc-500 hover:text-zinc-700"
        ]}
      >
        {tab.label}
      </button>
    </nav>
    """
  end

  attr :current, :any, required: true
  attr :name, :any, required: true
  slot :inner_block, required: true

  @doc "Keeps its content mounted and hides it unless current (a stream's container must stay)."
  def pane(assigns) do
    ~H"""
    <div class={@current != @name && "hidden"}>{render_slot(@inner_block)}</div>
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

  attr :count, :integer, required: true, doc: "shown only when this is zero"
  slot :inner_block, required: true

  def none(assigns) do
    ~H"""
    <div :if={@count == 0} class="py-12 text-center text-zinc-400">{render_slot(@inner_block)}</div>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :on_quantity, :string, required: true
  attr :on_remove, :string, required: true
  attr :t, :map, required: true, doc: "`each`, `remove`, and `stock` (labels by status)"

  def line_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto_auto] items-center gap-4 border-b py-4">
      <img class="w-16 h-16 object-contain" src={@row.product.thumbnail} alt={@row.product.name} />
      <div>
        <div class="font-medium">{@row.product.name}</div>
        <div class="text-sm text-zinc-500">{@row.product.amount}{@t.each}</div>
        <.stock_badge status={@row.stock_status} labels={@t.stock} />
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click={@on_quantity}
          phx-value-item-id={@row.id}
          phx-value-delta="-1"
          disabled={@row.at_minimum}
          class="w-8 h-8 rounded border text-lg font-bold disabled:opacity-30 hover:bg-zinc-100"
        >
          -
        </button>
        <span class="w-8 text-center font-mono">{@row.quantity}</span>
        <button
          phx-click={@on_quantity}
          phx-value-item-id={@row.id}
          phx-value-delta="1"
          class="w-8 h-8 rounded border text-lg font-bold hover:bg-zinc-100"
        >
          +
        </button>
      </div>
      <div class="text-right w-24">
        <div class="font-semibold">{@row.line_total}</div>
        <button
          phx-click={@on_remove}
          phx-value-item-id={@row.id}
          class="text-xs text-red-500 hover:text-red-700"
        >
          {@t.remove}
        </button>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :labels, :map, required: true

  def stock_badge(assigns) do
    ~H"""
    <span
      :if={@status != :in_stock}
      class={[
        "text-xs font-medium px-1.5 py-0.5 rounded",
        @status == :low_stock && "bg-amber-100 text-amber-700",
        @status == :out_of_stock && "bg-red-100 text-red-700"
      ]}
    >
      {@labels[@status]}
    </span>
    """
  end

  attr :summary, :map, required: true
  attr :t, :map, required: true

  def cart_summary(assigns) do
    ~H"""
    <div class="space-y-3 py-6">
      <div class="flex justify-between text-zinc-600">
        <span>{@t.items}</span><span>{@summary.item_count}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>{@t.subtotal}</span><span>{@summary.subtotal}</span>
      </div>
      <div :if={@summary.promo_code} class="flex justify-between text-green-600">
        <span>{@t.discount} ({@summary.promo_code})</span><span>-{@summary.discount}</span>
      </div>
      <div :if={@summary.shipping_method} class="flex justify-between text-zinc-600">
        <span>{@t.shipping}</span><span>{@summary.shipping}</span>
      </div>
      <div :if={@summary.gift_wrap?} class="flex justify-between text-zinc-600">
        <span>{@t.gift_wrap}</span><span>{@summary.gift_wrap}</span>
      </div>
      <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
        <span>{@t.total}</span><span>{@summary.total}</span>
      </div>
    </div>
    """
  end

  attr :options, :list, required: true
  attr :selected, :atom, default: nil
  attr :event, :string, required: true
  attr :t, :map, required: true, doc: "`heading` and `free_over`"

  def shipping_selector(assigns) do
    ~H"""
    <fieldset class="py-4 border-t">
      <legend class="text-sm font-medium text-zinc-700 pb-2">{@t.heading}</legend>
      <label :for={opt <- @options} class="flex items-center gap-2 py-1 text-sm">
        <input
          type="radio"
          name="shipping_method"
          value={opt.method}
          checked={@selected == opt.method}
          phx-click={@event}
          phx-value-method={opt.method}
        />
        <span>{opt.label}</span>
        <span class="text-zinc-500">
          {opt.cost}<span :if={opt.free_above}> ({@t.free_over} {opt.free_above})</span>
        </span>
      </label>
    </fieldset>
    """
  end

  attr :on, :boolean, required: true
  attr :event, :string, required: true
  attr :label, :string, required: true

  def toggle(assigns) do
    ~H"""
    <label class="flex items-center gap-2 py-3 border-t text-sm">
      <input type="checkbox" checked={@on} phx-click={@event} />
      <span>{@label}</span>
    </label>
    """
  end

  attr :code, :string, default: nil
  attr :error, :string, default: nil
  attr :event, :string, required: true
  attr :t, :map, required: true, doc: "`placeholder` and `apply`"

  def promo_form(assigns) do
    ~H"""
    <form phx-submit={@event} class="flex gap-2 py-4">
      <input
        type="text"
        name="code"
        placeholder={@t.placeholder}
        value={@code || ""}
        class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
      />
      <button
        type="submit"
        class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium hover:bg-zinc-300"
      >
        {@t.apply}
      </button>
      <span :if={@error} class="text-red-500 text-sm self-center">{@error}</span>
    </form>
    """
  end

  attr :disabled, :boolean, default: false
  attr :event, :string, required: true
  slot :inner_block, required: true

  def primary_button(assigns) do
    ~H"""
    <button
      phx-click={@event}
      disabled={@disabled}
      class={[
        "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white",
        @disabled && "opacity-50 cursor-not-allowed"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :text, :string, required: true

  def working(assigns) do
    ~H"""
    <div class="flex items-center gap-3 text-zinc-500 py-2">
      <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
      {@text}
    </div>
    """
  end
end
