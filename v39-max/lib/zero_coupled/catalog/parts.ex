defmodule ZeroCoupled.Catalog.Parts do
  @moduledoc """
  Generic page parts over the summary shapes the features project: the cart's price summary, a
  shipping choice, a promo form, a notice with one action, an empty note, and a primary button.
  They take their words from the page and the events they fire as attributes, so a page's markup
  only places them.
  """
  use Phoenix.Component

  attr :summary, :map, required: true
  attr :t, :map, required: true, doc: "the texts this part shows, from the page"

  def cart_summary(assigns) do
    ~H"""
    <div class="space-y-2 py-6 border-t mt-6">
      <div class="flex justify-between text-zinc-600">
        <span>{@t.items}</span><span>{@summary.item_count}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>{@t.subtotal}</span><span>{@summary.subtotal}</span>
      </div>
      <div :if={@summary.promo_code} class="flex justify-between text-green-600">
        <span>{@t.discount} ({@summary.promo_code})</span><span>-{@summary.discount}</span>
      </div>
      <div :if={Money.positive?(@summary.gift_wrap_total)} class="flex justify-between text-zinc-600">
        <span>{@t.gift_wrap}</span><span>{@summary.gift_wrap_total}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>{@t.shipping} ({@summary.shipping_label})</span>
        <span>
          {if Money.zero?(@summary.shipping_cost), do: @t.free, else: @summary.shipping_cost}
        </span>
      </div>
      <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
        <span>{@t.total}</span><span>{@summary.total}</span>
      </div>
    </div>
    """
  end

  attr :summary, :map, required: true
  attr :heading, :string, required: true
  attr :free_over, :string, required: true
  attr :event, :string, required: true
  attr :target, :any, default: nil

  def shipping_selector(assigns) do
    ~H"""
    <div class="py-2">
      <h3 class="text-sm font-semibold text-zinc-700 mb-2">{@heading}</h3>
      <div class="flex gap-2">
        <label
          :for={opt <- @summary.shipping_options}
          class="flex items-center gap-2 p-2 border rounded cursor-pointer text-sm"
        >
          <input
            type="radio"
            name="shipping_method"
            value={opt.method}
            checked={@summary.shipping_method == opt.method}
            phx-click={@event}
            phx-value-method={opt.method}
            phx-target={@target}
          />
          {opt.label}
          <span class="text-zinc-400">
            {opt.cost}<span :if={opt.free_above}> ({@free_over} {opt.free_above})</span>
          </span>
        </label>
      </div>
    </div>
    """
  end

  attr :code, :string, default: nil
  attr :error, :string, default: nil
  attr :event, :string, required: true
  attr :target, :any, default: nil
  attr :t, :map, required: true, doc: "`promo_placeholder` and `apply`"

  def promo_form(assigns) do
    ~H"""
    <form phx-submit={@event} phx-target={@target} class="flex gap-2 py-4">
      <input
        type="text"
        name="code"
        placeholder={@t.promo_placeholder}
        value={@code || ""}
        class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
      />
      <button type="submit" class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium">
        {@t.apply}
      </button>
      <span :if={@error} class="text-red-500 text-sm self-center">{@error}</span>
    </form>
    """
  end

  attr :shown, :boolean, required: true
  attr :text, :string, required: true
  attr :action, :string, required: true
  attr :event, :string, required: true

  def notice(assigns) do
    ~H"""
    <div
      :if={@shown}
      class="flex items-center justify-between bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 mb-4"
    >
      <span class="text-sm text-amber-800">{@text}</span>
      <button phx-click={@event} class="text-sm font-semibold text-amber-700 underline">
        {@action}
      </button>
    </div>
    """
  end

  attr :count, :integer, required: true, doc: "shown only when this is zero"
  attr :text, :string, required: true

  def none(assigns) do
    ~H"""
    <div :if={@count == 0} class="py-12 text-center text-zinc-400">{@text}</div>
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
        "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
        @disabled && "opacity-50 cursor-not-allowed"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
