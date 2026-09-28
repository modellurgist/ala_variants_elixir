defmodule ZeroCoupledWeb.Paradigms.Binder do
  @moduledoc """
  Runs one feature step held in the socket's assigns and delivers each of its port outputs
  along the page's bindings. A binding says where a `{feature, port}` goes: a stream, an assign,
  a flash, a form, a timer, a URL patch, an async job, a redirect, another feature's input, or a
  function of the page's own (persistence, a payment). Knows LiveView and the binding kinds;
  never a page, a feature, or a product.

  Binding kinds:

      {:stream, name}            rows: {:added | :changed, row} inserts, {:removed, row} deletes, {:reset, rows}
      {:assign, name}            the payload becomes the assign
      {:set, name, value}        a fixed value becomes the assign (the payload is ignored)
      {:form, name}              the payload is a changeset; it becomes a form assign
      {:flash, level, text}      a fixed message
      {:flash_for, level, texts} the message under the payload's key, if any
      {:input, key, fun}         run `fun.(state, payload)` on feature `key`, then deliver its outputs
      {:via, fun, targets}       deliver `fun.(payload)` to `targets` (a page function, often I/O)
      {:call, fun}               `fun.(payload)` for its effect only
      {:timer, name, ms}         {:start, payload} schedules {:timer, name, payload} to self after ms; :cancel cancels
      {:patch, paths}            push_patch to `paths[payload]`, when the step has a URL
      {:async, name, fun}        start_async(name, fn -> fun.(payload) end)
      :redirect                  redirect(external: payload)
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3, to_form: 2]

  def run(socket, bindings, key, step) do
    {state, outputs} = step.(socket.assigns[key])
    deliver(assign(socket, key, state), bindings, key, outputs)
  end

  @doc "Deliver outputs that arrived from elsewhere (a timer, an async result) as if feature `key` emitted them."
  def deliver(socket, bindings, key, outputs) do
    Enum.reduce(outputs, socket, fn {port, payload}, socket ->
      bindings
      |> Map.get({key, port}, [])
      |> Enum.reduce(socket, &apply_binding(&1, payload, bindings, &2))
    end)
  end

  defp apply_binding({:stream, name}, {:added, row}, _b, s), do: stream_insert(s, name, row)
  defp apply_binding({:stream, name}, {:changed, row}, _b, s), do: stream_insert(s, name, row)
  defp apply_binding({:stream, name}, {:removed, row}, _b, s), do: stream_delete(s, name, row)

  defp apply_binding({:stream, name}, {:reset, rows}, _b, s),
    do: stream(s, name, rows, reset: true)

  defp apply_binding({:assign, name}, payload, _b, s), do: assign(s, name, payload)
  defp apply_binding({:set, name, value}, _payload, _b, s), do: assign(s, name, value)

  defp apply_binding({:form, name}, changeset, _b, s),
    do: assign(s, name, to_form(changeset, action: :validate))

  defp apply_binding({:flash, level, text}, _payload, _b, s), do: put_flash(s, level, text)

  defp apply_binding({:flash_for, level, texts}, payload, _b, s) do
    case Map.fetch(texts, payload) do
      {:ok, text} -> put_flash(s, level, text)
      :error -> s
    end
  end

  defp apply_binding({:input, key, fun}, payload, bindings, s),
    do: run(s, bindings, key, &fun.(&1, payload))

  defp apply_binding({:via, fun, targets}, payload, bindings, s) do
    result = fun.(payload)
    Enum.reduce(targets, s, &apply_binding(&1, result, bindings, &2))
  end

  defp apply_binding({:call, fun}, payload, _b, s),
    do:
      (
        fun.(payload)
        s
      )

  defp apply_binding({:timer, name, ms}, {:start, payload}, _b, s) do
    s = cancel_timer(s, name)
    ref = Process.send_after(self(), {:timer, name, payload}, ms)
    assign(s, :timers, Map.put(timers(s), name, ref))
  end

  defp apply_binding({:timer, name, _ms}, :cancel, _b, s), do: cancel_timer(s, name)

  defp apply_binding({:patch, paths}, step, _b, s) do
    case Map.fetch(paths, step) do
      {:ok, path} -> push_patch(s, to: path)
      :error -> s
    end
  end

  defp apply_binding({:async, name, fun}, payload, _b, s),
    do: start_async(s, name, fn -> fun.(payload) end)

  defp apply_binding(:redirect, url, _b, s), do: redirect(s, external: url)

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
