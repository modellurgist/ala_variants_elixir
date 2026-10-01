defmodule ZeroCoupledWeb.Paradigms.Runner do
  @moduledoc """
  Feeds the circuit held in the socket's assigns and lands whatever reaches its edge on `:ui`
  ports as LiveView effects. Outputs on any other unwired port are dropped. Timers and async
  jobs come back as `{:feed, instance, data}` messages, which `feed_message/2` returns to the
  circuit, so a page needs no handler of its own for them.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  alias ZeroCoupled.Paradigms.Circuit

  def feed(socket, id, data) do
    {circuit, edge} = Circuit.push(socket.assigns.circuit, id, data)
    Enum.reduce(edge, assign(socket, :circuit, circuit), &land/2)
  end

  def feed_message({:feed, id, data}, socket), do: feed(socket, id, data)

  @doc "The result of an async job the circuit started: back into the circuit, or dropped if the job died."
  def async_result({:ok, {:feed, {id, input}, value}}, socket),
    do: feed(socket, id, {input, value})

  def async_result({:exit, _reason}, socket), do: socket

  defp land({{_, :ui}, {:stream_insert, name, row}}, s), do: stream_insert(s, name, row)
  defp land({{_, :ui}, {:stream_delete, name, row}}, s), do: stream_delete(s, name, row)
  defp land({{_, :ui}, {:stream_reset, name, rows}}, s), do: stream(s, name, rows, reset: true)
  defp land({{_, :ui}, {:assign, name, value}}, s), do: assign(s, name, value)
  defp land({{_, :ui}, {:flash, level, text}}, s), do: put_flash(s, level, text)

  defp land({{_, :ui}, {:component, m, id, change}}, s),
    do:
      (
        send_update(m, id: id, change: change)
        s
      )

  defp land({{_, :ui}, {:patch, path}}, s), do: push_patch(s, to: path)
  defp land({{_, :ui}, {:async, name, job}}, s), do: start_async(s, name, job)
  defp land({{_, :ui}, {:redirect, url}}, s), do: redirect(s, external: url)

  defp land({{_, :ui}, {:timer_start, name, ms, message}}, s) do
    s = cancel_timer(s, name)
    assign(s, :timers, Map.put(timers(s), name, Process.send_after(self(), message, ms)))
  end

  defp land({{_, :ui}, {:timer_cancel, name}}, s), do: cancel_timer(s, name)
  defp land(_other_port, s), do: s

  defp cancel_timer(s, name) do
    case Map.pop(timers(s), name) do
      {nil, _} ->
        s

      {ref, rest} ->
        Process.cancel_timer(ref)
        assign(s, :timers, rest)
    end
  end

  defp timers(s), do: s.assigns[:timers] || %{}
end
