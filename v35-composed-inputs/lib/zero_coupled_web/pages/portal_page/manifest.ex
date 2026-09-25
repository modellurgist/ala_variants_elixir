defmodule ZeroCoupledWeb.PortalPage.Manifest do
  @moduledoc """
  The B2B bulk-order portal's **diagram** (D6: the second consumer of the
  storefront's domain catalog). Same machinery as the cart page —
  manifest → `mix zc.gen` → committed glue — over the same aggregate,
  domain abstractions, undo feature, contracts, and flow tables.

  **Change this file first**, then run `mix zc.gen`.
  """

  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupled.Features.OrderLines.Facts, as: OrderFacts
  alias ZeroCoupled.Features.Undo.Facts, as: UndoFacts
  alias ZeroCoupled.Foundation.Broadcast.Facts, as: BroadcastFacts
  alias ZeroCoupledWeb.PortalLive.PortalView

  # ── Calibration on the diagram (V34) ──────────────────────────────────
  # What makes this the *B2B portal* rather than the retail cart: the volume
  # discount tiers, plus its shipping rates. The same generic `Cart` +
  # `VolumeTier` + `CalculateShipping` abstractions the storefront uses,
  # configured here for this consumer. Reading this block is reading the
  # portal's pricing policy.
  @portal_pricing [
    shipping: %{
      standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
      overnight: %{label: "Overnight", cost: 2499, free_above: nil}
    },
    volume_tiers: [
      {200_000, 10, "10% volume discount"},
      {50_000, 5, "5% volume discount"}
    ]
  ]

  @doc "Slot → feature. `render:`/`config:` as in the cart page's manifest (V34)."
  def features do
    [
      order: {OrderLines, render: :render_data, config: [pricing: @portal_pricing]},
      catalog: PortalCatalog,
      undo: {Undo, render: :render_data, config: [window_ms: 5_000]},
      flow: {PortalSubmit, render: :render_data}
    ]
  end

  @doc """
  Typed fact → slot-scoped reaction. The undo feature is wired **reused
  unchanged** from the cart page — only the transform differs, translating
  this page's `LineRemoved{line, line_id}` vocabulary into undo's
  `%{item, item_id}` port. `StockChanged` fans out to both stock-aware
  slots from one wire.
  """
  def reactions do
    [
      {OrderFacts.LineRemoved,
       to: {:undo, Undo.Intents, :capture_removed, transform: &%{item: &1.line, item_id: &1.line_id}}},
      {UndoFacts.ItemRestored, to: {:order, OrderLines.Intents, :receive_line}},
      {UndoFacts.RemovalFinal, to: {:order, OrderLines.Intents, :confirm_removal}},
      {BroadcastFacts.StockChanged,
       to: [
         {:order, OrderLines.Intents, :set_stock},
         {:catalog, PortalCatalog.Intents, :set_stock}
       ]}
    ]
  end

  @doc "One live_action; the view branches on the flow slot's step."
  def action_views, do: [index: PortalView]

  @doc "The bulk-order wizard skeleton (V33 flows channel). All steps are URL-bound."
  def flows do
    [
      bulk_order: [
        initial: :lines,
        milestones: [lines: "Order", review: "Review", submitted: "Done"],
        transitions: [
          {:lines, :go_review, :review},
          {:review, :edit_lines, :lines},
          {:review, :submit_order, :submitted}
        ],
        paths: [lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"]
      ]
    ]
  end
end
