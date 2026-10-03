defmodule GoodDealWeb.Paradigms.Steps do
  @moduledoc """
  Runs one step of a feature held in the socket's assigns under `key`, stores its new value, and
  wires each port output through the page's own function: `wire.(socket, key, {port, payload})`.
  The page's `wire/3` clauses are then its wiring, one clause per port. For a page's own values;
  features (user stories) run through `Story`, and outputs land through `Sinks`.

  A *source* is what a clause asks for a payload's answer: a function of the payload, a function of
  nothing (a plain read), or `{name, fun}`, which calls `fun.(instance, payload)` on the configured
  instance the page keeps under `@instances[name]`. Naming instances keeps clauses from reading
  assigns, and a missing name fails here with a clear message. Knows LiveView; never a page or a
  feature.
  """
  import Phoenix.LiveView, only: [start_async: 3]

  import Phoenix.Component, only: [assign: 3]

  def run(socket, key, step, wire) do
    {state, outputs} = step.(socket.assigns[key])
    Enum.reduce(outputs, assign(socket, key, state), &wire.(&2, key, &1))
  end

  @doc "Run feature `key`'s `input` on what `source` answers for `payload`."
  def feed(socket, key, input, source, payload, wire),
    do: run(socket, key, &input.(&1, ask(socket, source, payload)), wire)

  @doc "Ask `source` for its effect only."
  def call(socket, source, payload) do
    ask(socket, source, payload)
    socket
  end

  @doc "Ask `source` in a `start_async` task named `name`."
  def async(socket, name, {instance_name, fun}, payload) do
    instance = instance!(socket, instance_name)
    start_async(socket, name, fn -> fun.(instance, payload) end)
  end

  defp ask(socket, {name, fun}, payload) when is_atom(name) and is_function(fun, 2),
    do: fun.(instance!(socket, name), payload)

  defp ask(_socket, fun, payload) when is_function(fun, 1), do: fun.(payload)
  defp ask(_socket, fun, _payload) when is_function(fun, 0), do: fun.()

  defp instance!(socket, name) do
    case socket.assigns[:instances] do
      %{^name => instance} -> instance
      _ -> raise ArgumentError, "no configured instance #{inspect(name)} in @instances"
    end
  end
end
