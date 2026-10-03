defmodule GoodDealWeb.Stories.SaveForLater do
  @moduledoc """
  A line saved for later waits in its own list and can move back to the cart. Its part is the saved
  list; its view is that list. Ports: `stash` a line; out, the line `moved` back and the `count`.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import GoodDeal.Components.Panes, only: [stream_list: 1]
  import GoodDeal.Components.Parts, only: [none: 1]
  import GoodDeal.Components.Rows, only: [saved_row: 1]

  alias GoodDeal.State.SavedItems
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  def parts, do: %{saved: SavedItems}
  def streams, do: [:saved_items]
  def events, do: ["move_to_cart"]
  def ports, do: %{in: [stash: :item], out: [moved: :item, count: :count]}

  def new(_opts \\ []), do: Story.new(__MODULE__, %{saved: SavedItems.new([])}, view: [count: 0])

  def input(s, me, :stash, item), do: Story.run(s, me, :saved, &SavedItems.stash(&1, item))

  def event(s, me, "move_to_cart", %{"item-id" => id}),
    do: Story.run(s, me, :saved, &SavedItems.move_to_cart(&1, %{item_id: String.to_integer(id)}))

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, _me, :saved, {:rows, change}), do: Sinks.stream_change(s, :saved_items, change)

  def wire(s, me, :saved, {:count, count}),
    do: s |> Story.show(me, :count, count) |> Story.send_out(me, :count, count)

  def wire(s, me, :saved, {:moved, item}), do: Story.send_out(s, me, :moved, item)

  attr :story, :map, required: true
  attr :streams, :map, required: true
  attr :t, :map, required: true, doc: "`empty` and the row's texts, from the page"

  def view(assigns) do
    ~H"""
    <.stream_list :let={{dom_id, row}} id="saved_items" stream={@streams.saved_items}>
      <.saved_row id={dom_id} row={row} t={@t.row} on_move="move_to_cart" />
    </.stream_list>
    <.none count={@story.view.count} text={@t.empty} />
    """
  end
end
