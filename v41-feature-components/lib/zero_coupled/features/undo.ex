defmodule ZeroCoupled.Features.Undo do
  @moduledoc """
  Holds the last removed line for a while so it can come back. Ports out:

    * `:captured`  the line now held (something may want to say so, and start a clock)
    * `:timer`     `{:start, item_id}` when a line is held, `:cancel` when it comes back
    * `:restored`  the line coming back
    * `:expired`   the id of a line whose removal is now final

  The window's length is not this feature's business: whoever binds `:timer` chooses it.
  """
  defstruct pending: nil

  def new(_opts), do: %__MODULE__{}
  def pending?(%__MODULE__{pending: p}), do: p != nil

  def capture(%__MODULE__{} = undo, item),
    do: {%{undo | pending: item}, [captured: item, timer: {:start, item.id}]}

  def restore(%__MODULE__{pending: nil} = undo, _), do: {undo, []}

  def restore(%__MODULE__{pending: item} = undo, _),
    do: {%{undo | pending: nil}, [restored: item, timer: :cancel]}

  def expire(%__MODULE__{pending: %{id: id}} = undo, id),
    do: {%{undo | pending: nil}, [expired: id]}

  def expire(%__MODULE__{} = undo, _id), do: {undo, []}
end
