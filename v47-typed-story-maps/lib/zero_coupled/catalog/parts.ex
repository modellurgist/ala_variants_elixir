defmodule ZeroCoupled.Catalog.Parts do
  @moduledoc """
  Generic page parts over the summary shapes the features project: the cart's price summary, a
  shipping choice, a promo form, a notice with one action, an empty note, a primary button and
  a card to hold any of them.
  They take their words from the page and the events they fire as attributes, so a page's markup
  only places them.
  """
  use Phoenix.Component

  attr :title, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section class={["rounded-2xl border border-stone-200 bg-white p-6 shadow-sm", @class]}>
      <h2 :if={@title} class="pb-2 text-base font-semibold text-stone-900">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :summary, :map, required: true
  attr :t, :map, required: true, doc: "the texts this part shows, from the page"

  def cart_summary(assigns) do
    ~H"""
    <dl class="space-y-2 text-sm">
      <div class="flex justify-between text-stone-600">
        <dt>{@t.items}</dt>
        <dd>{@summary.item_count}</dd>
      </div>
      <div class="flex justify-between text-stone-600">
        <dt>{@t.subtotal}</dt>
        <dd>{@summary.subtotal}</dd>
      </div>
      <div :if={@summary.promo_code} class="flex justify-between text-brand-700">
        <dt>{@t.discount} ({@summary.promo_code})</dt>
        <dd>-{@summary.discount}</dd>
      </div>
      <div :if={Money.positive?(@summary.gift_wrap_total)} class="flex justify-between text-stone-600">
        <dt>{@t.gift_wrap}</dt>
        <dd>{@summary.gift_wrap_total}</dd>
      </div>
      <div class="flex justify-between text-stone-600">
        <dt>{@t.shipping} ({@summary.shipping_label})</dt>
        <dd>{if Money.zero?(@summary.shipping_cost), do: @t.free, else: @summary.shipping_cost}</dd>
      </div>
      <div class="flex items-center justify-between border-t border-stone-200 pt-3 text-lg font-semibold text-stone-900">
        <dt>{@t.total}</dt>
        <dd>{@summary.total}</dd>
      </div>
    </dl>
    """
  end

  attr :summary, :map, required: true
  attr :heading, :string, required: true
  attr :free_over, :string, required: true
  attr :event, :string, required: true
  attr :target, :any, default: nil

  def shipping_selector(assigns) do
    ~H"""
    <fieldset class="mt-6">
      <legend class="pb-2 text-sm font-semibold text-stone-900">{@heading}</legend>
      <div class="space-y-2">
        <label
          :for={opt <- @summary.shipping_options}
          class={[
            "flex cursor-pointer items-center gap-3 rounded-xl border px-3 py-2.5 text-sm",
            (@summary.shipping_method == opt.method && "border-brand-600 bg-brand-50") ||
              "border-stone-200 hover:border-stone-300"
          ]}
        >
          <input
            type="radio"
            name="shipping_method"
            value={opt.method}
            checked={@summary.shipping_method == opt.method}
            phx-click={@event}
            phx-value-method={opt.method}
            phx-target={@target}
            class="text-brand-700 focus:ring-brand-600"
          />
          <span class="flex-1 text-stone-800">{opt.label}</span>
          <span class="text-right text-stone-500">
            {opt.cost}<span :if={opt.free_above} class="block text-xs">{@free_over} {opt.free_above}</span>
          </span>
        </label>
      </div>
    </fieldset>
    """
  end

  attr :code, :string, default: nil
  attr :error, :string, default: nil
  attr :event, :string, required: true
  attr :target, :any, default: nil
  attr :t, :map, required: true, doc: "`promo_placeholder` and `apply`"

  def promo_form(assigns) do
    ~H"""
    <form phx-submit={@event} phx-target={@target} class="pt-6">
      <div class="flex gap-2">
        <input
          type="text"
          name="code"
          placeholder={@t.promo_placeholder}
          value={@code || ""}
          class="min-w-0 flex-1 rounded-lg border-stone-300 px-3 py-2 text-sm focus:border-brand-600 focus:ring-2 focus:ring-brand-100"
        />
        <button
          type="submit"
          class="rounded-lg border border-stone-300 bg-white px-4 py-2 text-sm font-medium text-stone-700 hover:bg-stone-50"
        >
          {@t.apply}
        </button>
      </div>
      <p :if={@error} class="pt-2 text-sm text-red-600">{@error}</p>
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
      class="mb-6 flex items-center justify-between rounded-xl border border-amber-200 bg-amber-50 px-4 py-3"
    >
      <span class="text-sm text-amber-900">{@text}</span>
      <button
        phx-click={@event}
        class="rounded-lg bg-amber-100 px-3 py-1 text-sm font-semibold text-amber-900 hover:bg-amber-200"
      >
        {@action}
      </button>
    </div>
    """
  end

  attr :count, :integer, required: true, doc: "shown only when this is zero"
  attr :text, :string, required: true

  def none(assigns) do
    ~H"""
    <div :if={@count == 0} class="py-14 text-center text-sm text-stone-400">{@text}</div>
    """
  end

  attr :disabled, :boolean, default: false
  attr :event, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def primary_button(assigns) do
    ~H"""
    <button
      phx-click={@event}
      disabled={@disabled}
      class={[
        "rounded-xl bg-brand-700 px-5 py-3 text-sm font-semibold text-white shadow-sm hover:bg-brand-800",
        "disabled:cursor-not-allowed disabled:bg-stone-300 disabled:shadow-none",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
