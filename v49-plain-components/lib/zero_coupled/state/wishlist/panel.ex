defmodule ZeroCoupled.State.Wishlist.Panel do
  @moduledoc "The wishlist tab as a UI instance. Config: `empty_text`. Input: `toggle: line_or_nil`. Sends the page, under the `name` it's given, `{name, port, _}` for `:added`, `:dropped`, `:taken`, `:ids`, `:count`."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.State.Wishlist
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is sent
  @wired_here [:rows]

  @doc "The ports this instance sends the page, as `{name, port, payload}`."
  def sent_port_outputs, do: Keyword.keys(Wishlist.ports().out) -- @wired_here

  def mount(socket),
    do:
      {:ok, socket |> stream(:wishlist_products, []) |> assign(state: Wishlist.new([]), count: 0)}

  def update(%{toggle: line}, s), do: {:ok, step(s, &Wishlist.toggle(&1, line))}
  def update(assigns, s), do: {:ok, assign(s, assigns)}

  def handle_event("remove_wishlist", %{"product-id" => id}, s),
    do: {:noreply, step(s, &Wishlist.remove(&1, %{product_id: String.to_integer(id)}))}

  def handle_event("add_wishlisted_to_cart", %{"product-id" => id}, s),
    do: {:noreply, step(s, &Wishlist.take(&1, %{product_id: String.to_integer(id)}))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)
  defp wire(s, {:rows, {:removed, row}}), do: stream_delete(s, :wishlist_products, row)
  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :wishlist_products, row)

  defp wire(s, {:count, n} = out),
    do: s |> assign(count: n) |> Instance.send_port_output(s.assigns.name, out)

  defp wire(s, out), do: Instance.send_port_output(s, s.assigns.name, out)

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
          t={@t.row}
        />
      </div>
      <div :if={@count == 0} class="py-12 text-center text-zinc-400">{@empty_text}</div>
    </div>
    """
  end
end
