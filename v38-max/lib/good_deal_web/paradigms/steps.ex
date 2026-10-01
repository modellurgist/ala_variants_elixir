defmodule GoodDealWeb.Paradigms.Steps do
  @moduledoc """
  Runs one step of a feature held in the socket's assigns under `key`, stores its new value, and
  lands each port output through the page's own function: `land.(socket, key, {port, payload})`.
  The page's `land/3` clauses are then its wiring, one clause per port. Also applies a feature's
  row change to a stream. Knows LiveView; never a page or a feature.
  """
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3, stream_delete: 3]
  import Phoenix.Component, only: [assign: 3]

  def run(socket, key, step, land) do
    {state, outputs} = step.(socket.assigns[key])
    Enum.reduce(outputs, assign(socket, key, state), &land.(&2, key, &1))
  end

  def stream_change(socket, name, {:reset, rows}), do: stream(socket, name, rows, reset: true)
  def stream_change(socket, name, {:removed, row}), do: stream_delete(socket, name, row)
  def stream_change(socket, name, {_added_or_changed, row}), do: stream_insert(socket, name, row)
end
