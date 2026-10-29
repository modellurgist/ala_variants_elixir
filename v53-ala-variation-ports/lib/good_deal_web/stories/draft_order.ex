defmodule GoodDealWeb.Stories.DraftOrder do
  @moduledoc """
  An order is drafted: its lines edited, a removed line held while it can be taken back, and stock
  kept current as the catalogue changes. Placed by the shopper's cart and the buyer's portal, each
  with its own cart, rows and window. It holds what both pages used to wire the same way (a removal
  goes to undo, an undo or expiry comes back to the lines, a stock change reaches the lines) and runs
  it through `Steps` under its own name, so the trace checks the inside as it checks a page.
  Out: `:contents`, `:saved`, `:line`, `:checkout_requested` (the lines'), `:restored`, `:pending`
  (the undo's), `:stock` (each change, after the lines have it).
  """
  alias GoodDealWeb.Paradigms.{ChangeFeed, Steps}
  alias GoodDealWeb.Stories.{EditLines, UndoRemoval}

  @parts %{edit_lines: EditLines, undo: UndoRemoval, feed: ChangeFeed}
  def parts, do: @parts

  @doc "A saved product's other fields: no line shows them."
  def grounded, do: [feed: :product]

  @edit_lines_events EditLines.events()
  @undo_events UndoRemoval.events()
  def events, do: @edit_lines_events ++ @undo_events

  def ports,
    do: %{
      in: [
        request_checkout: :event,
        receive: :item,
        add_product: :product,
        add: :product_quantity,
        expire: :item
      ],
      out: [
        contents: :contents,
        saved: :item,
        line: :line,
        checkout_requested: :checkout_request,
        restored: :item,
        pending: :flag,
        stock: :stock_change
      ]
    }

  @doc """
  Config: `cart_id`, `stock_status`, `stream` (the page's name for its rows), `timer` (the name the
  page gives the undo timer, whose message it sends to `expire`), `window_ms`, and `changes`, the
  topic stock changes arrive on. A removed line is held in the store exactly as long as it can be
  undone, so one window sets both.
  """
  def mount(s, opts, out) do
    s
    |> UndoRemoval.mount([timer: opts[:timer], window_ms: opts[:window_ms]], inner(:undo, out))
    |> EditLines.mount(
      [
        cart_id: opts[:cart_id],
        stock_status: opts[:stock_status],
        stream: opts[:stream],
        hold_ms: opts[:window_ms]
      ],
      inner(:edit_lines, out)
    )
    |> ChangeFeed.mount([topic: opts[:changes], facts: [:stock]], inner(:feed, out))
  end

  def handle_event(event, params, s, out) when event in @edit_lines_events,
    do: EditLines.handle_event(event, params, s, inner(:edit_lines, out))

  def handle_event(event, params, s, out) when event in @undo_events,
    do: UndoRemoval.handle_event(event, params, s, inner(:undo, out))

  def input(s, :request_checkout, request, out),
    do: to(s, :edit_lines, :request_checkout, request, out)

  def input(s, :receive, item, out), do: to(s, :edit_lines, :receive, item, out)
  def input(s, :add_product, product, out), do: to(s, :edit_lines, :add_product, product, out)
  def input(s, :add, request, out), do: to(s, :edit_lines, :add, request, out)
  def input(s, :expire, item, out), do: to(s, :undo, :expire, item, out)

  defp to(s, key, port, payload, out),
    do: Steps.to(s, __MODULE__, @parts, key, port, payload, inner(key, out))

  defp inner(key, out),
    do: fn s, output -> Steps.out(s, __MODULE__, key, output, &wire(&1, &2, &3, out)) end

  # {story, port} → where it wires inside this story, or out of it
  defp wire(s, :edit_lines, {:removed, item}, out), do: to(s, :undo, :capture, item, out)
  defp wire(s, :edit_lines, {:contents, contents}, out), do: out.(s, {:contents, contents})
  defp wire(s, :edit_lines, {:saved, item}, out), do: out.(s, {:saved, item})
  defp wire(s, :edit_lines, {:line, line}, out), do: out.(s, {:line, line})

  defp wire(s, :edit_lines, {:checkout_requested, request}, out),
    do: out.(s, {:checkout_requested, request})

  defp wire(s, :undo, {:restored, item}, out),
    do: s |> to(:edit_lines, :receive, item, out) |> out.({:restored, item})

  defp wire(s, :undo, {:expired, item_id}, out),
    do: to(s, :edit_lines, :confirm_removal, item_id, out)

  defp wire(s, :undo, {:pending, pending}, out), do: out.(s, {:pending, pending})

  defp wire(s, :feed, {:stock, change}, out),
    do: s |> to(:edit_lines, :stock, change, out) |> out.({:stock, change})
end
