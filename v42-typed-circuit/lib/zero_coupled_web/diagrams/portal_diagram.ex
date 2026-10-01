defmodule ZeroCoupledWeb.PortalDiagram do
  @moduledoc """
  The bulk-order portal's diagram: a second circuit over the same aggregate, domain rules, undo
  feature and paradigms, with its own instances, pricing, flow and literals. The page passes the
  draft's cart id.
  """
  alias ZeroCoupled.Domain.{AddLine, CalculateShipping, PlaceOrder, VolumeTier}
  alias ZeroCoupled.Features.{OrderLines, PortalCatalog, PortalSubmit, Undo}
  alias ZeroCoupled.Foundation.{Carts, Orders, Products}

  alias ZeroCoupled.Paradigms.{
    Adapter,
    Circuit,
    FromStore,
    ToAssign,
    ToComponent,
    ToFlash,
    ToForm,
    ToPatch,
    ToStore,
    ToTimer
  }

  alias ZeroCoupledWeb.PortalLive.{CatalogPanel, OrderPanel}

  @rates %{
    standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
    express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
    overnight: %{label: "Overnight", cost: 2499, free_above: nil}
  }
  @volume_tiers [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]
  @undo_window_ms 5_000
  @flow [
    {:lines, :go_review, :review},
    {:review, :edit_lines, :lines},
    {:review, :submit_order, :submitted}
  ]
  @url_edges [{:review, :lines}]
  @step_paths %{lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"}

  def circuit(%{cart_id: cart_id}) do
    Circuit.new(
      lines: %FromStore{read: &Carts.list_items/1, type: :items},
      products: %FromStore{read: &Products.list/0, type: :products},
      order:
        Adapter.new(
          OrderLines,
          OrderLines.new(
            cart_id: cart_id,
            pricing: %{
              shipping: CalculateShipping.new(@rates),
              volume: VolumeTier.new(@volume_tiers)
            }
          )
        ),
      catalog: Adapter.new(PortalCatalog, PortalCatalog.new([])),
      undo: Adapter.new(Undo, Undo.new([])),
      flow:
        Adapter.new(
          PortalSubmit,
          PortalSubmit.new(flow: @flow, start: :lines, url_edges: @url_edges)
        ),
      add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
      place_order: %PlaceOrder{orders: Orders, cart_id: cart_id},
      order_rows: %ToComponent{module: OrderPanel, id: "order"},
      catalog_rows: %ToComponent{module: CatalogPanel, id: "catalog"},
      summary: %ToAssign{name: :summary},
      persist: %ToStore{write: &Carts.apply_change/1},
      undo_armed: %ToAssign{name: :undo_pending, value: true},
      undo_cleared: %ToAssign{name: :undo_pending, value: false},
      undo_clock: %ToTimer{name: :undo, ms: @undo_window_ms, into: {:undo, :expire}},
      step: %ToAssign{name: :step},
      url: %ToPatch{paths: @step_paths},
      po_form: %ToForm{name: :po_form},
      po: %ToAssign{name: :po},
      order_id: %ToAssign{name: :order_id},
      added_notice: %ToFlash{text: "Added to order"},
      submitted_notice: %ToFlash{text: "Order submitted"},
      blocked_notice: %ToFlash{level: :error, texts: %{empty: "Your order is empty"}}
    )
    |> Circuit.wire({:lines, :loaded}, {:order, :load})
    |> Circuit.wire({:products, :loaded}, {:catalog, :load})
    |> Circuit.wire({:order, :rows}, {:order_rows, :change})
    |> Circuit.wire({:order, :summary}, {:summary, :value})
    |> Circuit.wire({:order, :persist}, {:persist, :value})
    |> Circuit.wire({:order, :removed}, {:undo, :capture})
    |> Circuit.wire({:undo, :captured}, {:undo_armed, :value})
    |> Circuit.wire({:undo, :timer}, {:undo_clock, :value})
    |> Circuit.wire({:undo, :restored}, {:order, :receive})
    |> Circuit.wire({:undo, :restored}, {:undo_cleared, :value})
    |> Circuit.wire({:undo, :expired}, {:order, :confirm_removal})
    |> Circuit.wire({:undo, :expired}, {:undo_cleared, :value})
    |> Circuit.wire({:catalog, :rows}, {:catalog_rows, :change})
    |> Circuit.wire({:catalog, :requested}, {:add_line, :add_with_quantity})
    |> Circuit.wire({:add_line, :line_with_quantity}, {:order, :add})
    |> Circuit.wire({:add_line, :line_with_quantity}, {:added_notice, :show})
    |> Circuit.wire({:flow, :step}, {:step, :value})
    |> Circuit.wire({:flow, :step}, {:url, :value})
    |> Circuit.wire({:flow, :form}, {:po_form, :value})
    |> Circuit.wire({:flow, :blocked}, {:blocked_notice, :show})
    |> Circuit.wire({:flow, :approved}, {:po, :value})
    |> Circuit.wire({:flow, :approved}, {:place_order, :place})
    |> Circuit.wire({:place_order, :placed}, {:flow, :complete})
    |> Circuit.wire({:flow, :reference}, {:order_id, :value})
    |> Circuit.wire({:flow, :reference}, {:submitted_notice, :show})
    |> Circuit.ground({:add_line, :line})
  end
end
