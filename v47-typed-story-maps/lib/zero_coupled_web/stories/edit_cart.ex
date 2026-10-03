defmodule ZeroCoupledWeb.Stories.EditCart do
  @moduledoc """
  The shopper edits their cart: quantities, removal, gift wrap, shipping, a promo code, and stock that
  changes while they look. Its part is the cart; `bindings/0` is its diagram; its view is the cart's
  rows and its totals.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.{Panes, Parts, Rows}

  alias ZeroCoupled.Foundation.Carts
  alias ZeroCoupled.State.Cart
  alias ZeroCoupledWeb.Paradigms.Binder

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
      Binder.story(__MODULE__, %{cart: ZeroCoupled.Cart.new(opts)}, bindings(),
        summary: nil,
        promo_error: nil,
        wishlist_ids: []
      )

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings do
    %{
      {:in, :mounted} => [{:via, &Carts.list_items/1, :items, [{:input, :cart, &Cart.load/2}]}],
      {:in, :receive} => [{:input, :cart, &Cart.receive/2}],
      {:in, :confirm_removal} => [{:input, :cart, &Cart.confirm_removal/2}],
      {:in, :wishlist_ids} => [{:show, :wishlist_ids}],
      {:in, :stock} => [{:input, :cart, &Cart.set_stock/2}],
      {:in, :request_checkout} => [{:input, :cart, &Cart.request_checkout/2}],
      {:cart, :rows} => [{:stream, :cart_items}],
      {:cart, :summary} => [{:show, :summary}, {:out, :summary}],
      {:cart, :changed} => [{:call, &Carts.apply_change/1}],
      {:cart, :removed} => [{:out, :removed}],
      {:cart, :saved} => [{:out, :saved}],
      {:cart, :line} => [{:out, :line}],
      {:cart, :promo_applied} => [{:set, :promo_error, nil}, {:flash, :info, "Promo applied!"}],
      {:cart, :promo_rejected} => [
        {:set, :promo_error, "Invalid promo code"},
        {:flash, :error, "Invalid promo code"}
      ],
      {:cart, :checkout_started} => [{:out, :checkout_started}],
      {:cart, :checkout_requested} => [{:out, :checkout_requested}]
    }
  end

  def event(s, me, "update_quantity", %{"item-id" => id, "delta" => d}),
    do: Binder.run(s, me, :cart, &Cart.update_quantity(&1, %{item_id: int(id), delta: int(d)}))

  def event(s, me, "remove_item", %{"item-id" => id}),
    do: Binder.run(s, me, :cart, &Cart.remove(&1, %{item_id: int(id)}))

  def event(s, me, "save_for_later", %{"item-id" => id}),
    do: Binder.run(s, me, :cart, &Cart.save_for_later(&1, %{item_id: int(id)}))

  def event(s, me, "toggle_gift_wrap", %{"item-id" => id}),
    do: Binder.run(s, me, :cart, &Cart.toggle_gift_wrap(&1, %{item_id: int(id)}))

  def event(s, me, "toggle_wishlist", %{"item-id" => id}),
    do: Binder.run(s, me, :cart, &Cart.line(&1, %{item_id: int(id)}))

  def event(s, me, "select_shipping", %{"method" => m}),
    do: Binder.run(s, me, :cart, &Cart.select_shipping(&1, %{method: String.to_existing_atom(m)}))

  def event(s, me, "apply_promo", %{"code" => code}),
    do: Binder.run(s, me, :cart, &Cart.apply_promo(&1, %{code: code}))

  def event(s, me, "start_checkout", _),
    do: Binder.run(s, me, :cart, &Cart.start_checkout(&1, nil))

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
    <div class="py-4">
      <.primary_button event="start_checkout" disabled={@story.view.summary.empty?}>
        {@t.checkout} · {@story.view.summary.total}
      </.primary_button>
    </div>
    """
  end
end
