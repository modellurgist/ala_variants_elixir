defmodule ZeroCoupledWeb.PortalLive.PortalView do
  @moduledoc "The portal's screens: lines and catalog, then the PO review, then the confirmation."
  use ZeroCoupledWeb, :html
  import ZeroCoupledWeb.Rows

  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <.step_body
        step={@step}
        summary={@summary}
        undo_pending={@undo_pending}
        po_form={@po_form}
        po={@po}
        order_id={@order_id}
        streams={@streams}
      />
    </div>
    """
  end

  defp step_body(%{step: :lines} = assigns) do
    ~H"""
    <div class="space-y-8">
      <.undo_banner :if={@undo_pending} on_undo="undo_remove" />

      <section>
        <h2 class="text-lg font-semibold pb-2">Your order</h2>
        <div id="order_lines" phx-update="stream">
          <.order_line_row
            :for={{dom_id, row} <- @streams.order_lines}
            id={dom_id}
            row={row}
            on_quantity="set_line_quantity"
            on_remove="remove_line"
          />
        </div>
        <div :if={@summary.empty?} class="py-8 text-center text-zinc-400">
          No lines yet. Add products below.
        </div>
        <.summary summary={@summary} />
        <button
          phx-click="go_review"
          disabled={@summary.empty?}
          class={[
            "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
            @summary.empty? && "opacity-50 cursor-not-allowed"
          ]}
        >
          Review order · {@summary.total}
        </button>
      </section>

      <section>
        <h2 class="text-lg font-semibold pb-2">Products</h2>
        <div id="portal_products" phx-update="stream">
          <.catalog_row
            :for={{dom_id, row} <- @streams.portal_products}
            id={dom_id}
            row={row}
            on_add="add_to_order"
          />
        </div>
      </section>
    </div>
    """
  end

  defp step_body(%{step: :review} = assigns) do
    ~H"""
    <div class="space-y-4 max-w-lg">
      <.summary summary={@summary} />
      <.simple_form for={@po_form} phx-change="validate_po" phx-submit="submit_order">
        <.input field={@po_form[:number]} label="Purchase order number" placeholder="PO-1234" />
        <.input field={@po_form[:notes]} label="Notes (optional)" />
        <:actions>
          <button type="button" phx-click="edit_lines" class="text-sm text-zinc-500 underline">
            Back to lines
          </button>
          <.button phx-disable-with="Submitting…">Submit order · {@summary.total}</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  defp step_body(%{step: :submitted} = assigns) do
    ~H"""
    <div class="py-10 space-y-2">
      <h2 class="text-2xl font-semibold">Order submitted</h2>
      <p class="text-zinc-600">
        Reference <span class="font-mono">#{@order_id}</span> · {@po.number}
      </p>
      <p class="text-zinc-500 text-sm">Total {@summary.total} ({@summary.item_count} items)</p>
    </div>
    """
  end

  defp summary(assigns) do
    ~H"""
    <div class="space-y-1 py-4 border-t mt-4 text-sm">
      <div class="flex justify-between text-zinc-600">
        <span>Items</span><span>{@summary.item_count}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Subtotal</span><span>{@summary.subtotal}</span>
      </div>
      <div :if={@summary.tier_label} class="flex justify-between text-green-700">
        <span>{@summary.tier_label}</span><span>-{@summary.discount}</span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Shipping ({@summary.shipping_label})</span>
        <span>
          {if Money.zero?(@summary.shipping_cost), do: "Free", else: @summary.shipping_cost}
        </span>
      </div>
      <div class="flex justify-between items-center py-2 border-t font-bold text-lg">
        <span>Total</span><span>{@summary.total}</span>
      </div>
    </div>
    """
  end
end
