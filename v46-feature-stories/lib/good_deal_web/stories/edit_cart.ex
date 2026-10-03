defmodule GoodDealWeb.Stories.EditCart do
  @moduledoc """
  The shopper edits their cart: quantities, removal, gift wrap, shipping, a promo code, and stock that
  changes while they look. Its part is the cart; its view is the cart's rows and its totals. What it
  can't finish itself leaves on its ports: a removed line, a line saved for later or marked for the
  wishlist, the summary, and the cart when checkout starts or asks to pay.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import Phoenix.LiveView, only: [put_flash: 3]
  import GoodDeal.Components.{Panes, Parts, Rows}

  alias GoodDeal.State.Cart
  alias GoodDeal.Foundation.Carts
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  def parts, do: %{cart: Cart}
  def streams, do: [:cart_items]

  def events,
    do:
      ~w(update_quantity remove_item save_for_later toggle_gift_wrap toggle_wishlist select_shipping apply_promo start_checkout)

  def ports,
    do: %{
      in: [
        mounted: :cart_id,
        receive: :item,
        confirm_removal: :item_id,
        wishlist_ids: :ids,
        stock: :stock_change,
        request_checkout: :event
      ],
      out: [
        summary: :summary,
        removed: :item,
        saved: :item,
        line: :line,
        checkout_started: :summary,
        checkout_requested: :checkout_request
      ]
    }

  @doc "Config: `cart_id` and `pricing` (the cart's configured rules)."
  def new(opts),
    do:
      Story.new(__MODULE__, %{cart: GoodDeal.Cart.new(opts)},
        view: [summary: nil, promo_error: nil, wishlist_ids: []]
      )

  def input(s, me, :mounted, cart_id),
    do: Story.feed(s, me, :cart, &Cart.load/2, &Carts.list_items/1, cart_id)

  def input(s, me, :receive, item), do: Story.run(s, me, :cart, &Cart.receive(&1, item))

  def input(s, me, :confirm_removal, item_id),
    do: Story.run(s, me, :cart, &Cart.confirm_removal(&1, item_id))

  def input(s, me, :wishlist_ids, ids), do: Story.show(s, me, :wishlist_ids, ids)
  def input(s, me, :stock, change), do: Story.run(s, me, :cart, &Cart.set_stock(&1, change))

  def input(s, me, :request_checkout, _),
    do: Story.run(s, me, :cart, &Cart.request_checkout(&1, nil))

  def event(s, me, "update_quantity", %{"item-id" => id, "delta" => d}),
    do: Story.run(s, me, :cart, &Cart.update_quantity(&1, %{item_id: int(id), delta: int(d)}))

  def event(s, me, "remove_item", %{"item-id" => id}),
    do: Story.run(s, me, :cart, &Cart.remove(&1, %{item_id: int(id)}))

  def event(s, me, "save_for_later", %{"item-id" => id}),
    do: Story.run(s, me, :cart, &Cart.save_for_later(&1, %{item_id: int(id)}))

  def event(s, me, "toggle_gift_wrap", %{"item-id" => id}),
    do: Story.run(s, me, :cart, &Cart.toggle_gift_wrap(&1, %{item_id: int(id)}))

  def event(s, me, "toggle_wishlist", %{"item-id" => id}),
    do: Story.run(s, me, :cart, &Cart.line(&1, %{item_id: int(id)}))

  def event(s, me, "select_shipping", %{"method" => m}),
    do: Story.run(s, me, :cart, &Cart.select_shipping(&1, %{method: String.to_existing_atom(m)}))

  def event(s, me, "apply_promo", %{"code" => code}),
    do: Story.run(s, me, :cart, &Cart.apply_promo(&1, %{code: code}))

  def event(s, me, "start_checkout", _),
    do: Story.run(s, me, :cart, &Cart.start_checkout(&1, nil))

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, _me, :cart, {:rows, change}), do: Sinks.stream_change(s, :cart_items, change)

  def wire(s, me, :cart, {:summary, summary}),
    do: s |> Story.show(me, :summary, summary) |> Story.send_out(me, :summary, summary)

  def wire(s, me, :cart, {:changed, change}), do: Story.call(s, me, &Carts.apply_change/1, change)

  def wire(s, me, :cart, {:promo_applied, _code}),
    do: s |> Story.show(me, :promo_error, nil) |> put_flash(:info, "Promo applied!")

  def wire(s, me, :cart, {:promo_rejected, _code}),
    do:
      s
      |> Story.show(me, :promo_error, "Invalid promo code")
      |> put_flash(:error, "Invalid promo code")

  def wire(s, me, :cart, {:removed, item}), do: Story.send_out(s, me, :removed, item)
  def wire(s, me, :cart, {:saved, item}), do: Story.send_out(s, me, :saved, item)
  def wire(s, me, :cart, {:line, line}), do: Story.send_out(s, me, :line, line)

  def wire(s, me, :cart, {:checkout_started, summary}),
    do: Story.send_out(s, me, :checkout_started, summary)

  def wire(s, me, :cart, {:checkout_requested, cart}),
    do: Story.send_out(s, me, :checkout_requested, cart)

  defp int(s), do: String.to_integer(s)

  attr :story, :map, required: true
  attr :streams, :map, required: true
  attr :t, :map, required: true, doc: "the cart's texts, from the page"

  def rows(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="cart_items" stream={@streams.cart_items}>
      <.cart_item_row
        id={dom_id}
        row={row}
        wishlist_ids={@story.view.wishlist_ids}
        gift_wrap_label={@t.gift_wrap_label}
        t={@t.row}
        on_quantity="update_quantity"
        on_remove="remove_item"
        on_gift_wrap="toggle_gift_wrap"
        on_save="save_for_later"
        on_wishlist="toggle_wishlist"
      />
    </.stream_list>
    <.none count={@story.view.summary.item_count} text={@t.empty} />
    """
  end

  attr :story, :map, required: true
  attr :t, :map, required: true, doc: "the cart's texts, from the page"

  def totals(assigns) do
    ~H"""
    <.cart_summary summary={@story.view.summary} t={@t} />
    <.shipping_selector
      summary={@story.view.summary}
      heading={@t.shipping}
      free_over={@t.free_over}
      event="select_shipping"
    />
    <.promo_form
      code={@story.view.summary.promo_code}
      error={@story.view.promo_error}
      event="apply_promo"
      t={@t}
    />
    <.primary_button
      event="start_checkout"
      disabled={@story.view.summary.empty?}
      class="mt-6 w-full"
    >
      {@t.checkout} · {@story.view.summary.total}
    </.primary_button>
    """
  end
end
