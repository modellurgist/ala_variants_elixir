defmodule ZeroCoupledWeb.Rows do
  @moduledoc """
  Row markup for the stream rows the pages show. Each row takes the event names it fires as
  attributes, so a page can bind the same row to its own handlers; the rows know the row shapes
  the features project and the catalog components, nothing about any page.
  """
  use Phoenix.Component
  import ZeroCoupled.Catalog.{ActionButton, ProductLineRow, StockBadge}

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :wishlisted, :boolean, required: true
  attr :gift_wrap_label, :string, required: true
  attr :on_quantity, :string, required: true
  attr :on_remove, :string, required: true
  attr :on_gift_wrap, :string, required: true
  attr :on_save, :string, required: true
  attr :on_wishlist, :string, required: true

  def cart_item_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto" price_suffix=" each">
      <:detail>
        <.stock_badge status={@row.stock_status} />
        <div class="flex items-center gap-3 mt-1">
          <label class="flex items-center gap-1.5 text-xs text-zinc-500 cursor-pointer">
            <input
              type="checkbox"
              checked={@row.gift_wrapped}
              phx-click={@on_gift_wrap}
              phx-value-item-id={@row.id}
            />
            {@gift_wrap_label}
          </label>
          <.action_button
            on={@on_save}
            phx-value-item-id={@row.id}
            label="Save for later"
            class="text-xs text-blue-500"
          />
          <button phx-click={@on_wishlist} phx-value-item-id={@row.id} class="text-xs">
            <span class={(@wishlisted && "text-red-500") || "text-zinc-400"}>
              {if @wishlisted, do: "♥ Wishlisted", else: "♡ Wishlist"}
            </span>
          </button>
        </div>
      </:detail>
      <:actions>
        <div class="flex items-center gap-2">
          <button
            phx-click={@on_quantity}
            phx-value-item-id={@row.id}
            phx-value-delta="-1"
            disabled={@row.quantity <= 1}
            class="w-8 h-8 rounded border text-lg font-bold disabled:opacity-30"
          >
            -
          </button>
          <span class="w-8 text-center font-mono">{@row.quantity}</span>
          <button
            phx-click={@on_quantity}
            phx-value-item-id={@row.id}
            phx-value-delta="1"
            class="w-8 h-8 rounded border text-lg font-bold"
          >
            +
          </button>
        </div>
        <div class="text-right w-24">
          <div class="font-semibold">{@row.line_total}</div>
          <.action_button
            on={@on_remove}
            phx-value-item-id={@row.id}
            label="Remove"
            class="text-xs text-red-500"
          />
        </div>
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :on_move, :string, required: true

  def saved_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto">
      <:actions>
        <.action_button on={@on_move} phx-value-item-id={@row.id} label="Move to cart" />
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :on_add, :string, required: true
  attr :on_remove, :string, required: true

  def wishlist_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto">
      <:actions>
        <.action_button on={@on_add} phx-value-product-id={@row.id} label="Add to cart" />
        <.action_button
          on={@on_remove}
          phx-value-product-id={@row.id}
          label="Remove"
          class="text-sm font-medium text-red-500"
        />
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :on_quantity, :string, required: true
  attr :on_remove, :string, required: true

  def order_line_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto" price_suffix=" each">
      <:detail>
        <.stock_badge status={@row.stock_status} />
      </:detail>
      <:actions>
        <form phx-change={@on_quantity} class="flex items-center gap-2">
          <input type="hidden" name="item-id" value={@row.id} />
          <input
            type="number"
            name="quantity"
            value={@row.quantity}
            min="1"
            class="w-20 rounded border border-zinc-300 px-2 py-1 text-sm text-right"
          />
        </form>
        <div class="text-right w-24">
          <div class="font-semibold">{@row.line_total}</div>
          <.action_button
            on={@on_remove}
            phx-value-item-id={@row.id}
            label="Remove"
            class="text-xs text-red-500"
          />
        </div>
      </:actions>
    </.product_line>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :on_add, :string, required: true

  def catalog_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto">
      <:detail>
        <.stock_badge status={@row.stock_status} />
      </:detail>
      <:actions>
        <form phx-submit={@on_add} class="flex items-center gap-2">
          <input type="hidden" name="product-id" value={@row.id} />
          <input
            type="number"
            name="quantity"
            value="10"
            min="1"
            class="w-20 rounded border border-zinc-300 px-2 py-1 text-sm text-right"
          />
          <button
            type="submit"
            disabled={@row.stock_status == :out_of_stock}
            class="rounded bg-zinc-900 text-white px-3 py-1.5 text-sm font-medium disabled:opacity-40"
          >
            Add
          </button>
        </form>
      </:actions>
    </.product_line>
    """
  end

  attr :on_undo, :string, required: true

  def undo_banner(assigns) do
    ~H"""
    <div class="flex items-center justify-between bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 mb-4">
      <span class="text-sm text-amber-800">Item removed.</span>
      <button phx-click={@on_undo} class="text-sm font-semibold text-amber-700 underline">
        Undo
      </button>
    </div>
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
    <ol class="flex gap-4 text-sm mb-6">
      <li
        :for={{s, label} <- @milestones}
        class={["font-medium", (s in @reached && "text-zinc-900") || "text-zinc-400"]}
      >
        {label}
      </li>
    </ol>
    """
  end
end
