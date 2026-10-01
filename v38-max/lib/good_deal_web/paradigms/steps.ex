defmodule GoodDealWeb.Paradigms.Steps do
  @moduledoc """
  Runs one step of a feature held in the socket's assigns under `key`, stores its new value, and
  lands each port output through the page's own function: `land.(socket, key, {port, payload})`.
  The page's `land/3` clauses are then its wiring, one clause per port. `feed/6` runs an input on
  what a source answers for a payload (a store read, a configured instance's I/O; a source
  of no arguments is a plain read), so a clause
  never nests one call's result inside another. Also a stream change and a named timer. Knows
  LiveView; never a page or a feature.
  """
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3, stream_delete: 3, push_patch: 2]
  import Phoenix.Component, only: [assign: 3]

  def run(socket, key, step, land) do
    {state, outputs} = step.(socket.assigns[key])
    Enum.reduce(outputs, assign(socket, key, state), &land.(&2, key, &1))
  end

  def feed(socket, key, input, source, payload, land),
    do: run(socket, key, &input.(&1, ask(source, payload)), land)

  defp ask(source, payload) when is_function(source, 1), do: source.(payload)
  defp ask(source, _payload) when is_function(source, 0), do: source.()

  def stream_change(socket, name, {:reset, rows}), do: stream(socket, name, rows, reset: true)
  def stream_change(socket, name, {:removed, row}), do: stream_delete(socket, name, row)
  def stream_change(socket, name, {_added_or_changed, row}), do: stream_insert(socket, name, row)

  @doc "Patch to the URL `paths` gives the step, when the step has one."
  def patch(socket, paths, step) do
    case Map.fetch(paths, step) do
      {:ok, path} -> push_patch(socket, to: path)
      :error -> socket
    end
  end

  @doc "Send `{:timer, name, payload}` to this page after `ms`, replacing a running timer of that name."
  def start_timer(socket, name, payload, ms) do
    socket = stop_timer(socket, name)
    ref = Process.send_after(self(), {:timer, name, payload}, ms)
    assign(socket, :timers, Map.put(timers(socket), name, ref))
  end

  def stop_timer(socket, name) do
    case Map.pop(timers(socket), name) do
      {nil, _} ->
        socket

      {ref, rest} ->
        Process.cancel_timer(ref)
        assign(socket, :timers, rest)
    end
  end

  defp timers(socket), do: socket.assigns[:timers] || %{}
end
