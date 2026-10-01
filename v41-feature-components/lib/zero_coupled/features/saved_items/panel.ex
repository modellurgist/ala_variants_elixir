defmodule ZeroCoupled.Features.SavedItems.Panel do
  @moduledoc "The saved-for-later tab as a UI instance. Config: `empty_text`. Input: `stash: item`. Announces `{:saved, :moved, item}` and `{:saved, :count, n}`."
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.Features.SavedItems
  alias ZeroCoupledWeb.Paradigms.Instance

  @doc "The ports this instance announces, as `{:saved, port, payload}`."
  def announces, do: [:count, :moved]

  def mount(socket),
    do: {:ok, socket |> stream(:saved_items, []) |> assign(state: SavedItems.new([]), count: 0)}

  def update(%{stash: item}, s), do: {:ok, step(s, &SavedItems.stash(&1, item))}
  def update(assigns, s), do: {:ok, assign(s, assigns)}

  def handle_event("move_to_cart", %{"item-id" => id}, s),
    do: {:noreply, step(s, &SavedItems.move_to_cart(&1, %{item_id: String.to_integer(id)}))}

  defp step(s, fun), do: Instance.step(s, fun, &land/2)
  defp land(s, {:rows, {:removed, row}}), do: stream_delete(s, :saved_items, row)
  defp land(s, {:rows, {_, row}}), do: stream_insert(s, :saved_items, row)
  defp land(s, {:count, n} = out), do: s |> assign(count: n) |> Instance.announce(:saved, out)
  defp land(s, out), do: Instance.announce(s, :saved, out)

  def render(assigns) do
    ~H"""
    <div>
      <div id="saved_items" phx-update="stream">
        <.saved_row
          :for={{dom_id, row} <- @streams.saved_items}
          id={dom_id}
          row={row}
          target={@myself}
          on_move="move_to_cart"
        />
      </div>
      <div :if={@count == 0} class="py-12 text-center text-zinc-400">{@empty_text}</div>
    </div>
    """
  end
end
