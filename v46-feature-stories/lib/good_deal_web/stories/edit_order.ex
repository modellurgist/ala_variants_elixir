defmodule GoodDealWeb.Stories.EditOrder do
  @moduledoc """
  A business buyer edits a bulk order's lines: quantities, removal, stock that changes, and lines the
  catalog adds. Its part is the order's lines; its view is the lines, the summary and the button to
  review. Ports: `mounted` with the draft's id, `add` a stored line, `receive` a restored one,
  `confirm_removal`, `stock`; out, the `summary`, a `removed` line, and the summary to `review`.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts, only: [none: 1, primary_button: 1]
  import GoodDeal.Components.Rows, only: [order_line_row: 1, order_summary: 1]

  alias GoodDeal.Foundation.Carts
  alias GoodDeal.State.OrderLines
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  def parts, do: %{order: OrderLines}
  def streams, do: [:order_lines]
  def events, do: ~w(set_line_quantity remove_line go_review)

  def ports,
    do: %{
      in: [
        mounted: :cart_id,
        add: :item_quantity,
        receive: :item,
        confirm_removal: :item_id,
        stock: :stock_change
      ],
      out: [summary: :summary, removed: :item, review: :summary]
    }

  @doc "Config: `cart_id` and `pricing` (the order's configured rules)."
  def new(opts), do: Story.new(__MODULE__, %{order: OrderLines.new(opts)}, view: [summary: nil])

  def input(s, me, :mounted, cart_id),
    do: Story.feed(s, me, :order, &OrderLines.load/2, &Carts.list_items/1, cart_id)

  def input(s, me, :add, line), do: Story.run(s, me, :order, &OrderLines.add(&1, line))
  def input(s, me, :receive, item), do: Story.run(s, me, :order, &OrderLines.receive(&1, item))

  def input(s, me, :confirm_removal, item_id),
    do: Story.run(s, me, :order, &OrderLines.confirm_removal(&1, item_id))

  def input(s, me, :stock, change),
    do: Story.run(s, me, :order, &OrderLines.set_stock(&1, change))

  def event(s, me, "set_line_quantity", %{"item-id" => id, "quantity" => q}),
    do:
      Story.run(
        s,
        me,
        :order,
        &OrderLines.set_quantity(&1, %{item_id: int(id), quantity: int(q)})
      )

  def event(s, me, "remove_line", %{"item-id" => id}),
    do: Story.run(s, me, :order, &OrderLines.remove(&1, %{item_id: int(id)}))

  def event(s, me, "go_review", _),
    do: Story.run(s, me, :order, &OrderLines.request_review(&1, nil))

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, _me, :order, {:rows, change}), do: Sinks.stream_change(s, :order_lines, change)

  def wire(s, me, :order, {:summary, summary}),
    do: s |> Story.show(me, :summary, summary) |> Story.send_out(me, :summary, summary)

  def wire(s, me, :order, {:changed, change}),
    do: Story.call(s, me, &Carts.apply_change/1, change)

  def wire(s, me, :order, {:removed, item}), do: Story.send_out(s, me, :removed, item)
  def wire(s, me, :order, {:review, summary}), do: Story.send_out(s, me, :review, summary)

  defp int(s) when is_binary(s), do: String.to_integer(s)
  defp int(n) when is_integer(n), do: n

  attr :story, :map, required: true
  attr :streams, :map, required: true
  attr :t, :map, required: true, doc: "the order's texts, from the page"

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
    <.none count={@story.view.summary.item_count} text={@t.empty} />
    """
  end

  attr :story, :map, required: true
  attr :t, :map, required: true, doc: "the order's texts, from the page"

  def totals(assigns) do
    ~H"""
    <.order_summary summary={@story.view.summary} t={@t.summary} />
    <.primary_button event="go_review" disabled={@story.view.summary.empty?} class="mt-6 w-full">
      {@t.review} · {@story.view.summary.total}
    </.primary_button>
    """
  end
end
