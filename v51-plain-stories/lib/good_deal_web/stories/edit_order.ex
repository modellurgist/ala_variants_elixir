defmodule GoodDealWeb.Stories.EditOrder do
  @moduledoc """
  The buyer builds a bulk order: lines added from the catalogue at a quantity, absolute quantities,
  removal, and stock that changes while they look. Its part is the order's lines, priced by volume
  tier; its view is the rows and the totals. Out: `:summary`, `:removed` (a line that left),
  `:review` (the summary, when the buyer wants to review).
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [stream: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts, only: [none: 1, primary_button: 1]
  import GoodDeal.Components.Rows, only: [order_line_row: 1, order_summary: 1]

  alias GoodDeal.Domain.AddLine
  alias GoodDeal.State.OrderLines
  alias GoodDeal.Foundation.{Carts, Products}
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{order: OrderLines}
  def events, do: ~w(set_line_quantity remove_line go_review)

  def ports,
    do: %{
      in: [
        add: :product_quantity,
        receive: :item,
        confirm_removal: :item_id,
        stock: :stock_change
      ],
      out: [summary: :summary, removed: :item, review: :summary]
    }

  @doc "Config: `cart_id`, and `pricing` (`shipping`, `volume`, `stock_status`)."
  def mount(s, opts, out) do
    cart_id = opts[:cart_id]

    s
    |> assign(
      order: OrderLines.new(cart_id: cart_id, pricing: opts[:pricing]),
      add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id}
    )
    |> stream(:order_lines, [])
    |> feed(&OrderLines.load/2, &Carts.list_items/1, cart_id, out)
  end

  def handle_event("set_line_quantity", %{"item-id" => id, "quantity" => q}, s, out),
    do: run(s, &OrderLines.set_quantity(&1, %{item_id: int(id), quantity: int(q)}), out)

  def handle_event("remove_line", %{"item-id" => id}, s, out),
    do: run(s, &OrderLines.remove(&1, %{item_id: int(id)}), out)

  def handle_event("go_review", _params, s, out),
    do: run(s, &OrderLines.request_review(&1, nil), out)

  def input(s, :add, request, out),
    do: feed(s, &OrderLines.add/2, &AddLine.run(s.assigns.add_line, &1), request, out)

  def input(s, :receive, item, out), do: run(s, &OrderLines.receive(&1, item), out)

  def input(s, :confirm_removal, item_id, out),
    do: run(s, &OrderLines.confirm_removal(&1, item_id), out)

  def input(s, :stock, change, out), do: run(s, &OrderLines.set_stock(&1, change), out)

  defp run(s, step, out), do: Steps.run(s, :order, step, &wire(&1, &2, &3, out))
  defp int(s) when is_binary(s), do: String.to_integer(s)
  defp int(n) when is_integer(n), do: n

  defp feed(s, input, source, payload, out),
    do: Steps.feed(s, :order, input, source, payload, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :order, {:rows, change}, _out), do: Steps.stream_change(s, :order_lines, change)

  defp wire(s, :order, {:changed, change}, _out) do
    Carts.apply_change(change)
    s
  end

  defp wire(s, :order, {:summary, summary}, out), do: out.(s, {:summary, summary})
  defp wire(s, :order, {:removed, item}, out), do: out.(s, {:removed, item})
  defp wire(s, :order, {:review, summary}, out), do: out.(s, {:review, summary})

  attr :streams, :any, required: true
  attr :summary, :map, required: true
  attr :t, :map, required: true

  def rows(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="order_lines" stream={@streams.order_lines}>
      <.order_line_row
        id={dom_id}
        row={row}
        on_quantity="set_line_quantity"
        on_remove="remove_line"
        t={@t.row}
      />
    </.stream_list>
    <.none count={@summary.item_count} text={@t.empty} />
    """
  end

  attr :summary, :map, required: true
  attr :t, :map, required: true

  def totals(assigns) do
    ~H"""
    <.order_summary summary={@summary} t={@t.summary} />
    <.primary_button event="go_review" disabled={@summary.empty?} class="mt-6 w-full">
      {@t.review} · {@summary.total}
    </.primary_button>
    """
  end
end
