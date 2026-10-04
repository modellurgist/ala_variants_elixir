defmodule GoodDealWeb.Stories.KeepWishlist do
  @moduledoc """
  The shopper marks products to buy later, and takes one into the cart from the list. Its view is the
  wishlisted products. Out: `:ids` (to mark the cart's rows), `:count`, `:taken` (a product to add
  to the cart).
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3, stream: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts, only: [none: 1]
  import GoodDeal.Components.Rows, only: [wishlist_row: 1]

  alias GoodDeal.State.Wishlist
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{wishlist: Wishlist}
  def events, do: ~w(remove_wishlist add_wishlisted_to_cart)
  def ports, do: %{in: [toggle: :line], out: [ids: :ids, count: :count, taken: :product]}

  def mount(s, _opts, _out),
    do: s |> assign(:wishlist, Wishlist.new([])) |> stream(:wishlist_products, [])

  def input(s, :toggle, line, out), do: run(s, &Wishlist.toggle(&1, line), out)

  def handle_event("remove_wishlist", %{"product-id" => id}, s, out),
    do: run(s, &Wishlist.remove(&1, %{product_id: String.to_integer(id)}), out)

  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, s, out),
    do: run(s, &Wishlist.take(&1, %{product_id: String.to_integer(id)}), out)

  defp run(s, step, out), do: Steps.run(s, :wishlist, step, &wire(&1, &2, &3, out))

  defp wire(s, :wishlist, {:rows, change}, _out),
    do: Steps.stream_change(s, :wishlist_products, change)

  defp wire(s, :wishlist, {:added, _product}, _out), do: put_flash(s, :info, "Added to wishlist")

  defp wire(s, :wishlist, {:dropped, _product}, _out),
    do: put_flash(s, :info, "Removed from wishlist")

  defp wire(s, :wishlist, {:ids, ids}, out), do: out.(s, {:ids, ids})
  defp wire(s, :wishlist, {:count, count}, out), do: out.(s, {:count, count})
  defp wire(s, :wishlist, {:taken, product}, out), do: out.(s, {:taken, product})

  attr :streams, :any, required: true
  attr :count, :integer, required: true
  attr :t, :map, required: true

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
    <.none count={@count} text={@t.empty} />
    """
  end
end
