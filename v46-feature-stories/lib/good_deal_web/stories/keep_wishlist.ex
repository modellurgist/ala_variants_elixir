defmodule GoodDealWeb.Stories.KeepWishlist do
  @moduledoc """
  The shopper keeps a wishlist: marks lines from the cart, removes products, or adds one to the cart.
  Its part is the wishlist, and its instance adds a product to the stored cart. Ports: `toggle` a
  cart line; out, the wishlisted `ids`, the `count`, and the line `added_to_cart`.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import Phoenix.LiveView, only: [put_flash: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts, only: [none: 1]
  import GoodDeal.Components.Rows, only: [wishlist_row: 1]

  alias GoodDeal.Domain.AddLine
  alias GoodDeal.State.Wishlist
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  def parts, do: %{wishlist: Wishlist}
  def streams, do: [:wishlist_products]
  def events, do: ["remove_wishlist", "add_wishlisted_to_cart"]
  def ports, do: %{in: [toggle: :line], out: [ids: :ids, count: :count, added_to_cart: :item]}

  @doc "Config: `add_line`, the configured instance that adds a product to the stored cart."
  def new(opts),
    do:
      Story.new(__MODULE__, %{wishlist: Wishlist.new([])},
        instances: %{add_line: Keyword.fetch!(opts, :add_line)},
        view: [count: 0]
      )

  def input(s, me, :toggle, line), do: Story.run(s, me, :wishlist, &Wishlist.toggle(&1, line))

  def event(s, me, "remove_wishlist", %{"product-id" => id}),
    do: Story.run(s, me, :wishlist, &Wishlist.remove(&1, %{product_id: String.to_integer(id)}))

  def event(s, me, "add_wishlisted_to_cart", %{"product-id" => id}),
    do: Story.run(s, me, :wishlist, &Wishlist.take(&1, %{product_id: String.to_integer(id)}))

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, _me, :wishlist, {:rows, change}),
    do: Sinks.stream_change(s, :wishlist_products, change)

  def wire(s, me, :wishlist, {:count, count}),
    do: s |> Story.show(me, :count, count) |> Story.send_out(me, :count, count)

  def wire(s, me, :wishlist, {:ids, ids}), do: Story.send_out(s, me, :ids, ids)
  def wire(s, _me, :wishlist, {:added, _product}), do: put_flash(s, :info, "Added to wishlist")

  def wire(s, _me, :wishlist, {:dropped, _product}),
    do: put_flash(s, :info, "Removed from wishlist")

  def wire(s, me, :wishlist, {:taken, product}),
    do:
      s
      |> Story.send_out_answer(me, :added_to_cart, {:add_line, &AddLine.run/2}, product)
      |> put_flash(:info, "Added to cart")

  attr :story, :map, required: true
  attr :streams, :map, required: true
  attr :t, :map, required: true, doc: "`empty` and the row's texts, from the page"

  def view(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="wishlist_products" stream={@streams.wishlist_products}>
      <.wishlist_row
        id={dom_id}
        row={row}
        t={@t.row}
        on_add="add_wishlisted_to_cart"
        on_remove="remove_wishlist"
      />
    </.stream_list>
    <.none count={@story.view.count} text={@t.empty} />
    """
  end
end
