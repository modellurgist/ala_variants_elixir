defmodule ZeroCoupled.Catalog.Rows do
  @moduledoc """
  Row markup for the stream rows the pages show. Each row takes the event names it fires as
  attributes, so a page can bind the same row to its own handlers; the rows know the row shapes
  the features project and the catalog components, nothing about any page. `target` is the
  instance the events go to (`@myself` inside a LiveComponent).
  """
  use Phoenix.Component
  import ZeroCoupled.Catalog.{ActionButton, ProductLineRow, StockBadge}

  attr :id, :string, required: true
  attr :target, :any, default: nil
  attr :row, :map, required: true
  attr :wishlist_ids, :list, required: true, doc: "the wishlisted product ids, to mark this row"
  attr :gift_wrap_label, :string, required: true
  attr :on_quantity, :string, required: true
  attr :on_remove, :string, required: true
  attr :on_gift_wrap, :string, required: true
  attr :on_save, :string, required: true
  attr :on_wishlist, :string, required: true

  attr :t, :map, required: true, doc: "the texts this row shows, from the page"

  def cart_item_row(assigns) do
    assigns = assign(assigns, :wishlisted, assigns.row.product_id in assigns.wishlist_ids)

    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto" price_suffix={@t.each}>
      <:detail>
        <.stock_badge status={@row.stock_status} labels={@t.stock} />
        <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1">
          <label class="flex cursor-pointer items-center gap-1.5 text-xs text-stone-500">
            <input
              type="checkbox"
              checked={@row.gift_wrapped}
              phx-click={@on_gift_wrap}
              phx-target={@target}
              phx-value-item-id={@row.id}
              class="rounded border-stone-300 text-brand-700 focus:ring-brand-600"
            />
            {@gift_wrap_label}
          </label>
          <.action_button
            on={@on_save}
            phx-target={@target}
            phx-value-item-id={@row.id}
            label={@t.save}
            class="text-xs font-medium text-stone-500 hover:text-stone-800"
          />
          <button
            phx-click={@on_wishlist}
            phx-target={@target}
            phx-value-item-id={@row.id}
            class="text-xs font-medium"
          >
            <span class={(@wishlisted && "text-rose-600") || "text-stone-500 hover:text-stone-800"}>
              {if @wishlisted, do: @t.wishlisted, else: @t.wishlist}
            </span>
          </button>
        </div>
      </:detail>
      <:actions>
        <div class="flex items-center rounded-lg border border-stone-300">
          <button
            phx-click={@on_quantity}
            phx-target={@target}
            phx-value-item-id={@row.id}
            phx-value-delta="-1"
            disabled={@row.quantity <= 1}
            class="h-8 w-8 text-stone-600 hover:bg-stone-100 disabled:opacity-30"
          >
            -
          </button>
          <span class="w-8 text-center text-sm tabular-nums">{@row.quantity}</span>
          <button
            phx-click={@on_quantity}
            phx-target={@target}
            phx-value-item-id={@row.id}
            phx-value-delta="1"
            class="h-8 w-8 text-stone-600 hover:bg-stone-100"
          >
            +
          </button>
        </div>
        <div class="w-24 text-right">
          <div class="font-semibold tabular-nums">{@row.line_total}</div>
          <.action_button
            on={@on_remove}
            phx-target={@target}
            phx-value-item-id={@row.id}
            label={@t.remove}
            class="text-xs font-medium text-stone-400 hover:text-red-600"
          />
        </div>
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, default: nil
  attr :row, :map, required: true
  attr :on_move, :string, required: true

  attr :t, :map, required: true, doc: "the texts this row shows, from the page"

  def saved_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto">
      <:actions>
        <.action_button
          on={@on_move}
          phx-target={@target}
          phx-value-item-id={@row.id}
          label={@t.move}
        />
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, default: nil
  attr :row, :map, required: true
  attr :on_add, :string, required: true
  attr :on_remove, :string, required: true

  attr :t, :map, required: true, doc: "the texts this row shows, from the page"

  def wishlist_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto">
      <:actions>
        <.action_button
          on={@on_add}
          phx-target={@target}
          phx-value-product-id={@row.id}
          label={@t.add}
        />
        <.action_button
          on={@on_remove}
          phx-target={@target}
          phx-value-product-id={@row.id}
          label={@t.remove}
          class="text-sm font-medium text-stone-400 hover:text-red-600"
        />
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, default: nil
  attr :row, :map, required: true
  attr :on_quantity, :string, required: true
  attr :on_remove, :string, required: true

  attr :t, :map, required: true, doc: "the texts this row shows, from the page"

  def order_line_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto" price_suffix={@t.each}>
      <:detail>
        <.stock_badge status={@row.stock_status} labels={@t.stock} />
      </:detail>
      <:actions>
        <form phx-change={@on_quantity} phx-target={@target} class="flex items-center gap-2">
          <input type="hidden" name="item-id" value={@row.id} />
          <input
            type="number"
            name="quantity"
            value={@row.quantity}
            min="1"
            class="w-20 rounded-lg border-stone-300 px-2 py-1.5 text-right text-sm focus:border-brand-600 focus:ring-2 focus:ring-brand-100"
          />
        </form>
        <div class="w-24 text-right">
          <div class="font-semibold tabular-nums">{@row.line_total}</div>
          <.action_button
            on={@on_remove}
            phx-target={@target}
            phx-value-item-id={@row.id}
            label={@t.remove}
            class="text-xs font-medium text-stone-400 hover:text-red-600"
          />
        </div>
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, default: nil
  attr :row, :map, required: true
  attr :on_add, :string, required: true

  attr :t, :map, required: true, doc: "the texts this row shows, from the page"

  def catalog_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto">
      <:detail>
        <.stock_badge status={@row.stock_status} labels={@t.stock} />
      </:detail>
      <:actions>
        <form phx-submit={@on_add} phx-target={@target} class="flex items-center gap-2">
          <input type="hidden" name="product-id" value={@row.id} />
          <input
            type="number"
            name="quantity"
            value={@t.default_quantity}
            min="1"
            class="w-20 rounded-lg border-stone-300 px-2 py-1.5 text-right text-sm focus:border-brand-600 focus:ring-2 focus:ring-brand-100"
          />
          <button
            type="submit"
            disabled={@row.stock_status == :out_of_stock}
            class="rounded-lg bg-brand-700 px-3 py-1.5 text-sm font-semibold text-white hover:bg-brand-800 disabled:bg-stone-300"
          >
            {@t.add}
          </button>
        </form>
      </:actions>
    </.product_line>
    """
  end

  attr :step, :atom, required: true

  attr :milestones, :list,
    required: true,
    doc: "[{step, label}]; a step is active when it or any later one is current"

  attr :order, :list,
    default: nil,
    doc: "all steps in order, when the flow has steps between milestones"

  def milestones(assigns) do
    order = assigns.order || Enum.map(assigns.milestones, &elem(&1, 0))

    assigns =
      assign(assigns, :reached, Enum.take_while(order, &(&1 != assigns.step)) ++ [assigns.step])

    ~H"""
    <ol class="mb-8 flex items-center gap-3 text-sm">
      <li :for={{{s, label}, i} <- Enum.with_index(@milestones, 1)} class="flex items-center gap-3">
        <span :if={i > 1} class={["h-px w-8", (s in @reached && "bg-brand-600") || "bg-stone-300"]} />
        <span class={[
          "flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold",
          (s in @reached && "bg-brand-700 text-white") || "bg-stone-200 text-stone-500"
        ]}>
          {i}
        </span>
        <span class={["font-medium", (s in @reached && "text-stone-900") || "text-stone-400"]}>
          {label}
        </span>
      </li>
    </ol>
    """
  end

  attr :summary, :map, required: true

  attr :t, :map, required: true, doc: "the texts this row shows, from the page"

  def order_summary(assigns) do
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
      <div :if={@summary.tier_label} class="flex justify-between text-brand-700">
        <dt>{@summary.tier_label}</dt>
        <dd>-{@summary.discount}</dd>
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
end
