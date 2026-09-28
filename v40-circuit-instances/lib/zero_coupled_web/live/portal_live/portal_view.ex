defmodule ZeroCoupledWeb.PortalLive.PortalView do
  @moduledoc "The portal's screens: which instances show at each step, and the totals block they share."
  use ZeroCoupledWeb, :html
  import ZeroCoupledWeb.Rows, only: [milestones: 1]
  alias ZeroCoupledWeb.PortalLive.{CatalogPanel, OrderPanel, PoForm}

  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <div :if={@step == :lines} class="space-y-8">
        <.live_component
          module={OrderPanel}
          id="order"
          summary={@summary}
          undo_pending={@undo_pending}
        />
        <.live_component module={CatalogPanel} id="catalog" />
      </div>
      <.live_component
        :if={@step == :review}
        module={PoForm}
        id="po"
        summary={@summary}
        po_form={@po_form}
      />
      <div :if={@step == :submitted} class="py-10 space-y-2">
        <h2 class="text-2xl font-semibold">Order submitted</h2>
        <p class="text-zinc-600">
          Reference <span class="font-mono">#{@order_id}</span> · {@po.number}
        </p>
        <p class="text-zinc-500 text-sm">Total {@summary.total} ({@summary.item_count} items)</p>
      </div>
    </div>
    """
  end

  attr :summary, :map, required: true

  def summary(assigns) do
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
