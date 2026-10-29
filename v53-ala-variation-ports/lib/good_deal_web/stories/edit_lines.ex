defmodule GoodDealWeb.Stories.EditLines do
  @moduledoc """
  The lines of a cart or an order are edited: quantities by a step or outright, removal, gift wrap,
  setting aside, a line for the wishlist, lines arriving from elsewhere, and stock that changes
  while they look. One story for the shopper's cart and the buyer's order (Spray §2.2: a feature
  with ports, wired by two applications). Its part is the lines; what a line looks like on the page
  is the page's (the `row` component it hands in), and what the lines cost is another story's
  (`contents` goes out). Out: `:contents`, `:removed`, `:saved`, `:line`, `:checkout_requested`.
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [stream: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts, only: [none: 1]

  alias GoodDeal.Domain.AddLine
  alias GoodDeal.State.CartLines
  alias GoodDeal.Foundation.{Carts, Products}
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{lines: CartLines}

  def events,
    do:
      ~w(update_quantity set_line_quantity remove_item save_for_later toggle_gift_wrap toggle_wishlist)

  def ports,
    do: %{
      in: [
        request_checkout: :event,
        receive: :item,
        add_product: :product,
        add: :product_quantity,
        confirm_removal: :item_id,
        stock: :stock_change
      ],
      out: [
        contents: :contents,
        removed: :item,
        saved: :item,
        line: :line,
        checkout_requested: :checkout_request
      ]
    }

  @doc """
  Config: `cart_id`, `stock_status` (a configured `StockStatus`), `stream`, the page's name for its
  rows, and `hold_ms`, how long a removed line stays undoable.
  """
  def mount(s, opts, out) do
    cart_id = opts[:cart_id]
    Carts.finalize_holds(cart_id, opts[:hold_ms])

    s
    |> assign(
      lines: CartLines.new(cart_id: cart_id, stock_status: opts[:stock_status]),
      lines_stream: opts[:stream],
      add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id}
    )
    |> stream(opts[:stream], [])
    |> feed(&CartLines.load/2, &Carts.list_items/1, cart_id, out)
  end

  def handle_event("update_quantity", %{"item-id" => id, "delta" => d}, s, out),
    do: run(s, &CartLines.update_quantity(&1, %{item_id: int(id), delta: int(d)}), out)

  def handle_event("set_line_quantity", %{"item-id" => id, "quantity" => q}, s, out),
    do: run(s, &CartLines.update_quantity(&1, %{item_id: int(id), quantity: int(q)}), out)

  def handle_event("remove_item", %{"item-id" => id}, s, out),
    do: run(s, &CartLines.remove(&1, %{item_id: int(id)}), out)

  def handle_event("save_for_later", %{"item-id" => id}, s, out),
    do: run(s, &CartLines.save_for_later(&1, %{item_id: int(id)}), out)

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, s, out),
    do: run(s, &CartLines.toggle_gift_wrap(&1, %{item_id: int(id)}), out)

  def handle_event("toggle_wishlist", %{"item-id" => id}, s, out),
    do: run(s, &CartLines.line(&1, %{item_id: int(id)}), out)

  def input(s, :request_checkout, _, out), do: run(s, &CartLines.request_checkout(&1, nil), out)
  def input(s, :receive, item, out), do: run(s, &CartLines.receive(&1, item), out)

  def input(s, :add_product, product, out),
    do: feed(s, &CartLines.receive/2, &AddLine.run(s.assigns.add_line, &1), product, out)

  def input(s, :add, request, out),
    do: feed(s, &CartLines.receive/2, &AddLine.run(s.assigns.add_line, &1), request, out)

  def input(s, :confirm_removal, item_id, out),
    do: run(s, &CartLines.confirm_removal(&1, item_id), out)

  def input(s, :stock, change, out), do: run(s, &CartLines.set_stock(&1, change), out)

  defp run(s, step, out), do: Steps.run(s, :lines, step, &wire(&1, &2, &3, out))
  defp int(s), do: String.to_integer(s)

  defp feed(s, input, source, payload, out),
    do: Steps.feed(s, :lines, input, source, payload, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :lines, {:rows, change}, _out),
    do: Steps.stream_change(s, s.assigns.lines_stream, change)

  defp wire(s, :lines, {:changed, change}, _out) do
    Carts.apply_change(change)
    s
  end

  defp wire(s, :lines, {:contents, contents}, out), do: out.(s, {:contents, contents})
  defp wire(s, :lines, {:removed, item}, out), do: out.(s, {:removed, item})
  defp wire(s, :lines, {:saved, item}, out), do: out.(s, {:saved, item})
  defp wire(s, :lines, {:line, line}, out), do: out.(s, {:line, line})

  defp wire(s, :lines, {:checkout_requested, request}, out),
    do: out.(s, {:checkout_requested, request})

  attr :streams, :any, required: true
  attr :stream, :atom, required: true, doc: "the page's name for its rows, as given to mount"
  attr :row, :any, required: true, doc: "the page's row component: a function of assigns"

  attr :row_attrs, :map,
    default: %{},
    doc: "what the page's row needs beyond the row and the events"

  attr :count, :integer, required: true
  attr :empty, :string, required: true

  # the story owns the events its rows fire; the page owns what a row looks like
  def rows(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id={Atom.to_string(@stream)} stream={@streams[@stream]}>
      <.line_row
        component={@row}
        id={dom_id}
        row={row}
        on_quantity="update_quantity"
        on_set_quantity="set_line_quantity"
        on_remove="remove_item"
        on_gift_wrap="toggle_gift_wrap"
        on_save="save_for_later"
        on_wishlist="toggle_wishlist"
        {@row_attrs}
      />
    </.stream_list>
    <.none count={@count} text={@empty} />
    """
  end

  defp line_row(assigns) do
    {component, assigns} = Map.pop(assigns, :component)
    component.(assigns)
  end
end
