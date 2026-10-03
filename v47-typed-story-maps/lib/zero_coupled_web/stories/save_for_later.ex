defmodule ZeroCoupledWeb.Stories.SaveForLater do
  @moduledoc """
  A line saved for later waits in its own list and can move back to the cart. Its part is the saved
  list; its view is that list.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.Panes, only: [stream_list: 1]
  import ZeroCoupled.Catalog.Parts, only: [none: 1]
  import ZeroCoupled.Catalog.Rows, only: [saved_row: 1]

  alias ZeroCoupled.State.SavedItems
  alias ZeroCoupledWeb.Paradigms.Binder

  def parts, do: %{saved: SavedItems}
  def streams, do: [:saved_items]
  def events, do: ["move_to_cart"]
  def ports, do: %{in: [stash: :item], out: [moved: :item, count: :count]}

  def new(_opts \\ []),
    do: Binder.story(__MODULE__, %{saved: SavedItems.new([])}, bindings(), count: 0)

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings do
    %{
      {:in, :stash} => [{:input, :saved, &SavedItems.stash/2}],
      {:saved, :rows} => [{:stream, :saved_items}],
      {:saved, :count} => [{:show, :count}, {:out, :count}],
      {:saved, :moved} => [{:out, :moved}]
    }
  end

  def event(s, me, "move_to_cart", %{"item-id" => id}),
    do: Binder.run(s, me, :saved, &SavedItems.move_to_cart(&1, %{item_id: String.to_integer(id)}))

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
