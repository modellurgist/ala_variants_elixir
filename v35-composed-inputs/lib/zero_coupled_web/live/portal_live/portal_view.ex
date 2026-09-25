defmodule ZeroCoupledWeb.PortalLive.PortalView do
  @moduledoc """
  ActionView for the portal's single `:index` action — the bulk-order
  wizard, branching on the flow slot's step (the URL tracks the step via
  the flows channel). Ports only: `@order`/`@undo` render ports, the
  `@flow_slot` struct, projected stream rows, and `Web.Contracts` events.
  """
  use ZeroCoupledWeb, :html

  alias ZeroCoupled.Features.OrderLines.Components, as: OrderRows
  alias ZeroCoupled.Features.PortalCatalog.Components, as: CatalogRows
  alias ZeroCoupled.Features.Undo.Components, as: UndoUI
  alias ZeroCoupled.Web.Contracts
  alias ZeroCoupledWeb.PortalPage.Generated

  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@flow.step} />
      <.step_body
        step={@flow.step}
        order={@order}
        undo={@undo}
        flow={@flow}
        po_form={@po_form}
        streams={@streams}
      />
    </div>
    """
  end

  defp milestones(assigns) do
    ~H"""
    <ol class="flex gap-4 text-sm mb-6">
      <li :for={{s, label} <- Generated.flow_milestones(:bulk_order)} class={[
        "font-medium",
        @step == s && "text-zinc-900",
        @step != s && "text-zinc-400"
      ]}>
        <%= label %>
      </li>
    </ol>
    """
  end

  # ── Step: lines (browse + order draft) ──────────────────────────────

  defp step_body(%{step: :lines} = assigns) do
    ~H"""
    <div class="space-y-8">
      <UndoUI.undo_banner :if={@undo.pending?} />

      <section>
        <h2 class="text-lg font-semibold pb-2">Your order</h2>
        <div id={Contracts.stream_dom_id(:order)} phx-update="stream">
          <OrderRows.order_line_row :for={{dom_id, row} <- @streams.order_lines} id={dom_id} row={row} />
        </div>
        <div :if={@order.empty?} class="py-8 text-center text-zinc-400">No lines yet — add products below.</div>
        <.summary order={@order} />
        <button
          phx-click={Contracts.event(:go_review)}
          disabled={@order.empty?}
          class={[
            "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
            @order.empty? && "opacity-50 cursor-not-allowed"
          ]}
        >
          Review order · <%= @order.total %>
        </button>
      </section>

      <section>
        <h2 class="text-lg font-semibold pb-2">Products</h2>
        <div id={Contracts.stream_dom_id(:catalog)} phx-update="stream">
          <CatalogRows.catalog_row :for={{dom_id, row} <- @streams.portal_products} id={dom_id} row={row} />
        </div>
      </section>
    </div>
    """
  end

  # ── Step: review (PO + totals) ──────────────────────────────────────

  defp step_body(%{step: :review} = assigns) do
    ~H"""
    <div class="space-y-4 max-w-lg">
      <.summary order={@order} />
      <.simple_form for={@po_form} phx-change={Contracts.event(:validate_po)} phx-submit={Contracts.event(:submit_order)}>
        <.input field={@po_form[:number]} label="Purchase order number" placeholder="PO-1234" />
        <.input field={@po_form[:notes]} label="Notes (optional)" />
        <:actions>
          <button
            type="button"
            phx-click={Contracts.event(:edit_lines)}
            class="text-sm text-zinc-500 underline"
          >
            Back to lines
          </button>
          <.button phx-disable-with="Submitting…">Submit order · <%= @order.total %></.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  # ── Step: submitted ─────────────────────────────────────────────────

  defp step_body(%{step: :submitted} = assigns) do
    ~H"""
    <div class="py-10 space-y-2">
      <h2 class="text-2xl font-semibold">Order submitted</h2>
      <p class="text-zinc-600">
        Reference <span class="font-mono">#<%= @flow.order_id %></span>
        · <%= @flow.po_number %>
      </p>
      <p class="text-zinc-500 text-sm">Total <%= @order.total %> (<%= @order.item_count %> items)</p>
    </div>
    """
  end

  # ── Cross-feature composite ─────────────────────────────────────────

  defp summary(assigns) do
    ~H"""
    <div class="space-y-1 py-4 border-t mt-4 text-sm">
      <div class="flex justify-between text-zinc-600"><span>Items</span><span><%= @order.item_count %></span></div>
      <div class="flex justify-between text-zinc-600"><span>Subtotal</span><span><%= @order.subtotal %></span></div>
      <div :if={@order.tier_label} class="flex justify-between text-green-700">
        <span><%= @order.tier_label %></span><span>-<%= @order.discount %></span>
      </div>
      <div class="flex justify-between text-zinc-600">
        <span>Shipping (<%= @order.shipping_label %>)</span>
        <span><%= if Money.zero?(@order.shipping_cost), do: "Free", else: @order.shipping_cost %></span>
      </div>
      <div class="flex justify-between items-center py-2 border-t font-bold text-lg">
        <span>Total</span><span><%= @order.total %></span>
      </div>
    </div>
    """
  end
end
