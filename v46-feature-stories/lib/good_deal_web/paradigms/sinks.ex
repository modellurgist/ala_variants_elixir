defmodule GoodDealWeb.Paradigms.Sinks do
  @moduledoc """
  Where a port output lands in LiveView: a stream change, a patch to a step's URL, a named timer.
  The runners (`Steps` for a page's own values, `Story` for features) and the wiring both use these.
  Knows LiveView; never a page, a story or a domain abstraction.
  """
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3, stream_delete: 3, push_patch: 2]
  import Phoenix.Component, only: [assign: 3]

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

  @doc "Send `message` to this page after `ms`, replacing a running timer of that name."
  def send_after(socket, name, message, ms) do
    socket = stop_timer(socket, name)
    ref = Process.send_after(self(), message, ms)
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
