defmodule GoodDealWeb.Paradigms.Steps do
  @moduledoc """
  Runs one step of a feature held in the socket's assigns under `key`, stores its new value, and
  wires each port output through the page's own function: `wire.(socket, key, {port, payload})`.
  The page's `wire/3` clauses are then its wiring, one clause per port. `feed/6` does the same with
  an input that takes what a function answers (a store read, a configured instance's call), so a
  clause never holds one abstraction's answer to hand to another.   Knows LiveView; never a page or a feature.
  """
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3, stream_delete: 3, push_patch: 2]
  import Phoenix.Component, only: [assign: 3]

  def run(socket, key, step, wire) do
    {state, outputs} = step.(socket.assigns[key])
    Enum.reduce(outputs, assign(socket, key, state), &wire.(&2, key, &1))
  end

  @doc "Run feature `key`'s `input` on what `source` answers for `payload` (or answers, for a read of nothing)."
  def feed(socket, key, input, source, payload, wire),
    do: run(socket, key, &input.(&1, ask(source, payload)), wire)

  def stream_change(socket, stream_name, {:reset, rows}),
    do: stream(socket, stream_name, rows, reset: true)

  def stream_change(socket, stream_name, {:removed, row}),
    do: stream_delete(socket, stream_name, row)

  def stream_change(socket, stream_name, {_added_or_changed, row}),
    do: stream_insert(socket, stream_name, row)

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

  defp ask(source, payload) when is_function(source, 1), do: source.(payload)
  defp ask(source, _payload) when is_function(source, 0), do: source.()

  defp timers(socket), do: socket.assigns[:timers] || %{}
end
