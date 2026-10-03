defmodule ZeroCoupled.State.Undo do
  @moduledoc """
  Holds the last removed line for a while so it can come back. Ports out:

    * `:captured`  the line now held (something may want to say so, and start a clock)
    * `:restored`  the line coming back
    * `:expired`   the id of a line whose removal is now final

  The window's length is not this feature's business: whoever shows the offer runs the clock.
  """
  defstruct pending: nil

  def ports,
    do: %{
      in: [capture: :item, restore: :event, expire: :item],
      out: [captured: :item, restored: :item, expired: :item_id]
    }

  def new(_opts), do: %__MODULE__{}
  def pending?(%__MODULE__{pending: p}), do: p != nil

  @doc "Hold a removed line. A line already held has its removal made final: only the latest is undoable."
  def capture(%__MODULE__{pending: %{id: held}} = undo, item),
    do: {%{undo | pending: item}, [expired: held, captured: item]}

  def capture(%__MODULE__{} = undo, item),
    do: {%{undo | pending: item}, [captured: item]}

  def restore(%__MODULE__{pending: nil} = undo, _), do: {undo, []}

  def restore(%__MODULE__{pending: item} = undo, _),
    do: {%{undo | pending: nil}, [restored: item]}

  def expire(%__MODULE__{} = undo, %{id: id}), do: expire(undo, id)

  def expire(%__MODULE__{pending: %{id: id}} = undo, id),
    do: {%{undo | pending: nil}, [expired: id]}

  def expire(%__MODULE__{} = undo, _id), do: {undo, []}
end
