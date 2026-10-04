defmodule GoodDealWeb.Stories.EditCart do
  @moduledoc """
  The shopper edits their cart: quantities, removal, gift wrap, shipping, a promo code, and stock that
  changes while they look. Its parts are the cart's lines, the promo code and the totals, wired to
  each other here; its view is the rows and the totals. What it can't finish itself leaves on its
  ports: the summary, a promo error to show, a removed or saved line, a line for the wishlist, and
  checkout starting or asking to pay.
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3, stream: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts
  import GoodDeal.Components.Rows, only: [cart_item_row: 1]

  alias GoodDeal.Domain.AddLine
  alias GoodDeal.State.{CartLines, CartTotals, Promo}
  alias GoodDeal.Foundation.{Carts, Products}
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{lines: CartLines, promo: Promo, totals: CartTotals}

  def events,
    do:
      ~w(update_quantity remove_item save_for_later toggle_gift_wrap toggle_wishlist select_shipping apply_promo start_checkout)

  def ports,
    do: %{
      in: [
        request_checkout: :event,
        receive: :item,
        add_product: :product,
        confirm_removal: :item_id,
        stock: :stock_change
      ],
      out: [
        summary: :summary,
        promo_error: :message,
        removed: :item,
        saved: :item,
        line: :line,
        checkout_started: :summary,
        checkout_requested: :checkout_request
      ]
    }

  @doc "Config: `cart_id`, and `pricing` (`shipping`, `stock_status`, `promo`, `gift_wrap`)."
  def mount(s, opts, out) do
    cart_id = opts[:cart_id]
    pricing = opts[:pricing]

    s
    |> assign(
      lines: CartLines.new(cart_id: cart_id, stock_status: pricing.stock_status),
      promo: Promo.new(codes: pricing[:promo]),
      totals: CartTotals.new(pricing: pricing),
      add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id}
    )
    |> stream(:cart_items, [])
    |> feed(:lines, &CartLines.load/2, &Carts.list_items/1, cart_id, out)
  end

  def handle_event("update_quantity", %{"item-id" => id, "delta" => d}, s, out),
    do: run(s, :lines, &CartLines.update_quantity(&1, %{item_id: int(id), delta: int(d)}), out)

  def handle_event("remove_item", %{"item-id" => id}, s, out),
    do: run(s, :lines, &CartLines.remove(&1, %{item_id: int(id)}), out)

  def handle_event("save_for_later", %{"item-id" => id}, s, out),
    do: run(s, :lines, &CartLines.save_for_later(&1, %{item_id: int(id)}), out)

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, s, out),
    do: run(s, :lines, &CartLines.toggle_gift_wrap(&1, %{item_id: int(id)}), out)

  def handle_event("toggle_wishlist", %{"item-id" => id}, s, out),
    do: run(s, :lines, &CartLines.line(&1, %{item_id: int(id)}), out)

  def handle_event("select_shipping", %{"method" => m}, s, out),
    do:
      run(s, :totals, &CartTotals.select_shipping(&1, %{method: String.to_existing_atom(m)}), out)

  def handle_event("apply_promo", %{"code" => code}, s, out),
    do: run(s, :promo, &Promo.enter(&1, %{code: code}), out)

  def handle_event("start_checkout", _params, s, out),
    do: run(s, :totals, &CartTotals.start_checkout(&1, nil), out)

  def input(s, :request_checkout, _, out),
    do: run(s, :lines, &CartLines.request_checkout(&1, nil), out)

  def input(s, :receive, item, out), do: run(s, :lines, &CartLines.receive(&1, item), out)

  def input(s, :add_product, product, out),
    do: feed(s, :lines, &CartLines.receive/2, &AddLine.run(s.assigns.add_line, &1), product, out)

  def input(s, :confirm_removal, item_id, out),
    do: run(s, :lines, &CartLines.confirm_removal(&1, item_id), out)

  def input(s, :stock, change, out), do: run(s, :lines, &CartLines.set_stock(&1, change), out)

  defp run(s, part, step, out), do: Steps.run(s, part, step, &wire(&1, &2, &3, out))
  defp int(s), do: String.to_integer(s)

  defp feed(s, part, input, source, payload, out),
    do: Steps.feed(s, part, input, source, payload, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :lines, {:rows, change}, _out), do: Steps.stream_change(s, :cart_items, change)

  defp wire(s, :lines, {:contents, contents}, out),
    do: run(s, :totals, &CartTotals.contents(&1, contents), out)

  defp wire(s, :lines, {:changed, change}, _out) do
    Carts.apply_change(change)
    s
  end

  defp wire(s, :lines, {:removed, item}, out), do: out.(s, {:removed, item})
  defp wire(s, :lines, {:saved, item}, out), do: out.(s, {:saved, item})
  defp wire(s, :lines, {:line, line}, out), do: out.(s, {:line, line})

  defp wire(s, :lines, {:checkout_requested, request}, out),
    do: out.(s, {:checkout_requested, request})

  defp wire(s, :promo, {:discount, discount}, out),
    do: run(s, :totals, &CartTotals.discount(&1, discount), out)

  defp wire(s, :promo, {:applied, _code}, out),
    do: s |> out.({:promo_error, nil}) |> put_flash(:info, "Promo applied!")

  defp wire(s, :promo, {:rejected, _code}, out),
    do:
      s
      |> out.({:promo_error, "Invalid promo code"})
      |> put_flash(:error, "Invalid promo code")

  defp wire(s, :totals, {:summary, summary}, out), do: out.(s, {:summary, summary})

  defp wire(s, :totals, {:checkout_started, summary}, out),
    do: out.(s, {:checkout_started, summary})

  attr :streams, :any, required: true
  attr :summary, :map, required: true
  attr :wishlist_ids, :list, required: true
  attr :t, :map, required: true

  def rows(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="cart_items" stream={@streams.cart_items}>
      <.cart_item_row
        id={dom_id}
        row={row}
        wishlist_ids={@wishlist_ids}
        gift_wrap_label={@t.gift_wrap_label}
        t={@t.row}
        on_quantity="update_quantity"
        on_remove="remove_item"
        on_gift_wrap="toggle_gift_wrap"
        on_save="save_for_later"
        on_wishlist="toggle_wishlist"
      />
    </.stream_list>
    <.none count={@summary.item_count} text={@t.empty} />
    """
  end

  attr :summary, :map, required: true
  attr :promo_error, :string, default: nil
  attr :t, :map, required: true

  def totals(assigns) do
    ~H"""
    <.cart_summary summary={@summary} t={@t} />
    <.shipping_selector
      summary={@summary}
      heading={@t.shipping}
      free_over={@t.free_over}
      event="select_shipping"
    />
    <.promo_form code={@summary.promo_code} error={@promo_error} event="apply_promo" t={@t} />
    <.primary_button event="start_checkout" disabled={@summary.empty?} class="mt-6 w-full">
      {@t.checkout} · {@summary.total}
    </.primary_button>
    """
  end
end
