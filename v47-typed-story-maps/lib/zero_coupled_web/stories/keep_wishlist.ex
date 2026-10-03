defmodule ZeroCoupledWeb.Stories.KeepWishlist do
  @moduledoc """
  The shopper keeps a wishlist: marks lines from the cart, removes products, or adds one to the cart.
  Its part is the wishlist; its configured `AddLine` stores a product in the cart.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.Panes, only: [stream_list: 1]
  import ZeroCoupled.Catalog.Parts, only: [none: 1]
  import ZeroCoupled.Catalog.Rows, only: [wishlist_row: 1]

  alias ZeroCoupled.State.Wishlist
  alias ZeroCoupledWeb.Paradigms.Binder

  def parts, do: %{wishlist: Wishlist}
  def streams, do: [:wishlist_products]
  def events, do: ["remove_wishlist", "add_wishlisted_to_cart"]
  def ports, do: %{in: [toggle: :line], out: [ids: :ids, count: :count, added_to_cart: :item]}

  @doc "Config: `add_line`, the configured instance that adds a product to the stored cart."
  def new(opts),
    do:
      Binder.story(
        __MODULE__,
        %{wishlist: Wishlist.new([])},
        bindings(Keyword.fetch!(opts, :add_line)),
        count: 0
      )

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings(add_line) do
    %{
      {:in, :toggle} => [{:input, :wishlist, &Wishlist.toggle/2}],
      {:wishlist, :rows} => [{:stream, :wishlist_products}],
      {:wishlist, :count} => [{:show, :count}, {:out, :count}],
      {:wishlist, :ids} => [{:out, :ids}],
      {:wishlist, :added} => [{:flash, :info, "Added to wishlist"}],
      {:wishlist, :dropped} => [{:flash, :info, "Removed from wishlist"}],
      {:wishlist, :taken} => [
        {:via, add_line, [{:out, :added_to_cart}, {:flash, :info, "Added to cart"}]}
      ]
    }
  end

  def event(s, me, "remove_wishlist", %{"product-id" => id}),
    do: Binder.run(s, me, :wishlist, &Wishlist.remove(&1, %{product_id: String.to_integer(id)}))

  def event(s, me, "add_wishlisted_to_cart", %{"product-id" => id}),
    do: Binder.run(s, me, :wishlist, &Wishlist.take(&1, %{product_id: String.to_integer(id)}))

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
