defmodule ZeroCoupled.Catalog.StockBadge do
  @moduledoc """
  Generic stock-status badge. Promoted from `CartItems.Components` to the
  catalog when the portal became its second consumer (the reuse-count
  discipline: an abstraction earns a catalog place at use two). Takes the
  already-computed status — a projected port value, never a stock number
  to interpret, so it stays domain-free.
  """
  use Phoenix.Component

  attr :status, :atom, required: true

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
      <%= if @status == :low_stock, do: "Low stock", else: "Out of stock" %>
    </span>
    """
  end
end
