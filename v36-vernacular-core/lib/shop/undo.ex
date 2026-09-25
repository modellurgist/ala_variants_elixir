defmodule Shop.Undo do
  @moduledoc "The undo feature — holds the last removed item during a window. No peer knowledge."
  alias Shop.Outcome

  defstruct pending: nil, window_ms: 5_000

  def new(opts \\ []), do: %__MODULE__{window_ms: opts[:window_ms] || 5_000}
  def pending?(%__MODULE__{pending: p}), do: p != nil

  @doc "Capture a removed item and arm the timer (window is config)."
  def capture(%__MODULE__{} = u, item) do
    {%{u | pending: item},
     [Outcome.start_timer(:undo, u.window_ms, {:undo_expired, item.id}),
      Outcome.flash(:info, "Item removed — undo?")]}
  end

  @doc "Take the pending item back (or nil); returns the item for the composition to restore."
  def take(%__MODULE__{pending: nil} = u), do: {u, nil, []}
  def take(%__MODULE__{pending: item} = u),
    do: {%{u | pending: nil}, item, [Outcome.cancel_timer(:undo), Outcome.flash(:info, "Item restored")]}

  def clear(%__MODULE__{} = u), do: {%{u | pending: nil}, []}
end
