defmodule GoodDealWeb.Stories.SaveForLater do
  @moduledoc """
  The shopper sets a line aside and later moves it back to the cart. Its view is the saved lines.
  Out: `:moved` (the line, back to the cart), `:count`.
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [stream: 3]
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts, only: [none: 1]
  import GoodDeal.Components.Rows, only: [saved_row: 1]

  alias GoodDeal.State.SavedItems
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{saved: SavedItems}
  def events, do: ~w(move_to_cart)
  def ports, do: %{in: [stash: :item], out: [moved: :item, count: :count]}

  def mount(s, _opts, _out),
    do: s |> assign(:saved, SavedItems.new([])) |> stream(:saved_items, [])

  def input(s, :stash, item, out), do: run(s, &SavedItems.stash(&1, item), out)

  def handle_event("move_to_cart", %{"item-id" => id}, s, out),
    do: run(s, &SavedItems.move_to_cart(&1, %{item_id: String.to_integer(id)}), out)

  defp run(s, step, out), do: Steps.run(s, :saved, step, &wire(&1, &2, &3, out))

  defp wire(s, :saved, {:rows, change}, _out), do: Steps.stream_change(s, :saved_items, change)
  defp wire(s, :saved, {:count, count}, out), do: out.(s, {:count, count})
  defp wire(s, :saved, {:moved, item}, out), do: out.(s, {:moved, item})

  attr :streams, :any, required: true
  attr :count, :integer, required: true
  attr :t, :map, required: true

  def view(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="saved_items" stream={@streams.saved_items}>
      <.saved_row id={dom_id} row={row} t={@t.row} on_move="move_to_cart" />
    </.stream_list>
    <.none count={@count} text={@t.empty} />
    """
  end
end
