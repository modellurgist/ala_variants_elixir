defmodule ZeroCoupledWeb.Stories.EditOrder do
  @moduledoc """
  A business buyer edits a bulk order's lines: quantities, removal, stock that changes, and lines the
  catalog adds. Its part is the order's lines; its view is the lines, the summary and the button to
  review.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.Panes, only: [stream_list: 1]
  import ZeroCoupled.Catalog.Parts, only: [none: 1, primary_button: 1]
  import ZeroCoupled.Catalog.Rows, only: [order_line_row: 1, order_summary: 1]

  alias ZeroCoupled.Foundation.Carts
  alias ZeroCoupled.State.OrderLines
  alias ZeroCoupledWeb.Paradigms.Binder

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
  def new(opts),
    do: Binder.story(__MODULE__, %{order: OrderLines.new(opts)}, bindings(), summary: nil)

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings do
    %{
      {:in, :mounted} => [
        {:via, &Carts.list_items/1, :items, [{:input, :order, &OrderLines.load/2}]}
      ],
      {:in, :add} => [{:input, :order, &OrderLines.add/2}],
      {:in, :receive} => [{:input, :order, &OrderLines.receive/2}],
      {:in, :confirm_removal} => [{:input, :order, &OrderLines.confirm_removal/2}],
      {:in, :stock} => [{:input, :order, &OrderLines.set_stock/2}],
      {:order, :rows} => [{:stream, :order_lines}],
      {:order, :summary} => [{:show, :summary}, {:out, :summary}],
      {:order, :changed} => [{:call, &Carts.apply_change/1}],
      {:order, :removed} => [{:out, :removed}],
      {:order, :review} => [{:out, :review}]
    }
  end

  def event(s, me, "set_line_quantity", %{"item-id" => id, "quantity" => q}),
    do:
      Binder.run(
        s,
        me,
        :order,
        &OrderLines.set_quantity(&1, %{item_id: int(id), quantity: int(q)})
      )

  def event(s, me, "remove_line", %{"item-id" => id}),
    do: Binder.run(s, me, :order, &OrderLines.remove(&1, %{item_id: int(id)}))

  def event(s, me, "go_review", _),
    do: Binder.run(s, me, :order, &OrderLines.request_review(&1, nil))

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
