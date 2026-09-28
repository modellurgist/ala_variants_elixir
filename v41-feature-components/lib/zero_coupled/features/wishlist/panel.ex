defmodule ZeroCoupled.Features.Wishlist.Panel do
  @moduledoc "The wishlist tab as a UI instance. Config: `empty_text`. Input: `toggle: line_or_nil`. Announces `{:wishlist, port, _}` for `:added`, `:dropped`, `:taken`, `:ids`, `:count`."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.Features.Wishlist
  alias ZeroCoupledWeb.Paradigms.Instance

  def mount(socket),
    do:
      {:ok, socket |> stream(:wishlist_products, []) |> assign(state: Wishlist.new([]), count: 0)}

  def update(%{toggle: line}, s), do: {:ok, step(s, &Wishlist.toggle(&1, line))}
  def update(assigns, s), do: {:ok, assign(s, assigns)}

  def handle_event("remove_wishlist", %{"product-id" => id}, s),
    do: {:noreply, step(s, &Wishlist.remove(&1, %{product_id: String.to_integer(id)}))}

  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, s),
    do: {:noreply, step(s, &Wishlist.take(&1, %{product_id: String.to_integer(id)}))}

  defp step(s, fun), do: Instance.step(s, fun, &land/2)
  defp land(s, {:rows, {:removed, row}}), do: stream_delete(s, :wishlist_products, row)
  defp land(s, {:rows, {_, row}}), do: stream_insert(s, :wishlist_products, row)
  defp land(s, {:count, n} = out), do: s |> assign(count: n) |> Instance.announce(:wishlist, out)
  defp land(s, out), do: Instance.announce(s, :wishlist, out)

  def render(assigns) do
    ~H"""
    <div>
      <div id="wishlist_products" phx-update="stream">
        <.wishlist_row
          :for={{dom_id, row} <- @streams.wishlist_products}
          id={dom_id}
          row={row}
          target={@myself}
          on_add="add_wishlisted_to_cart"
          on_remove="remove_wishlist"
        />
      </div>
      <div :if={@count == 0} class="py-12 text-center text-zinc-400">{@empty_text}</div>
    </div>
    """
  end
end
