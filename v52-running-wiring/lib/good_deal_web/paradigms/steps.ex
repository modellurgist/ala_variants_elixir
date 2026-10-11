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

  alias GoodDealWeb.Paradigms.Trace

  @doc """
  Send a story's input from a page: `parts[key].input(...)`, recording the hop from whatever output
  is being routed (or the browser) when the trace is on. Which output that is rides in the socket's
  private map for the length of one clause, so nested routing restores it on the way out.
  """
  def to(socket, page, parts, key, port, payload, out) do
    Trace.hop(page, hop(socket) || :outside, {key, port})
    parts[key].input(mark(socket, routed: true), port, payload, out)
  end

  @doc """
  Route one of a story's outputs through the page's `wire/3`, recording the output as the hop being
  routed and, when the clause sends it to no story, that it landed on the page.
  """
  def out(socket, page, key, {port, _} = output, wire) do
    previous = Map.take(socket.private, [:ala_hop, :ala_routed])
    socket = wire.(mark(socket, hop: {key, port}, routed: false), key, output)
    unless socket.private[:ala_routed], do: Trace.hop(page, {key, port}, :page)

    %{
      socket
      | private: socket.private |> Map.drop([:ala_hop, :ala_routed]) |> Map.merge(previous)
    }
  end

  defp hop(socket), do: socket.private[:ala_hop]

  defp mark(socket, marks) do
    private = Enum.reduce(marks, socket.private, fn {k, v}, p -> Map.put(p, :"ala_#{k}", v) end)
    %{socket | private: private}
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
