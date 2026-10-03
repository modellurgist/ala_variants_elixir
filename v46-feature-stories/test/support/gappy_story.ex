defmodule GoodDealWeb.GappyStory do
  @moduledoc false
  alias GoodDeal.State.Undo

  def parts, do: %{undo: Undo}
  def events, do: ["undo_remove", "never_handled"]
  def ports, do: %{in: [capture: :item, expire: :item_id], out: []}

  def input(s, _me, :capture, _item), do: s
  def input(s, _me, :surprise, _item), do: s
  def event(s, _me, "undo_remove", _), do: s
  def wire(s, _me, :undo, {:captured, _}), do: s
end
