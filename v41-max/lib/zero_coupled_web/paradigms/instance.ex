defmodule ZeroCoupledWeb.Paradigms.Instance do
  @moduledoc """
  What a feature's UI instance (a LiveComponent) needs beyond LiveView: run one step of the
  feature it holds in `:state` and hand each output to the instance's own `wire/2`; send
  an output it doesn't show to whoever mounted it, as `{name, port, payload}`; and route those
  port outputs by a page's table.

  A route target is one of `pass: {component, id, input}` (send the payload to an instance's
  input), `assign: name`, `flash: {level, text}`, `flash_by: {level, texts}` (the text keyed by
  the payload), `patch: paths` (push the path for the payload, when it has one), `redirect: true`
  (to the payload's URL), and three that wire a data source or sink at the page: `call: fun` or
  `call: {name, fun}` (for its effect), `feed: {name, fun, {component, id, input}}` (pass what
  `fun.(instance, payload)` answers to an instance's input), and `async: {task, name, fun}` (run
  `fun.(instance, payload)` in a `start_async` task on the page). `name` is a configured instance
  the page keeps under `@instances`.
  """
  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [send_update: 2, put_flash: 3, push_patch: 2, redirect: 2, start_async: 3]

  def step(socket, fun, show) do
    {state, outputs} = fun.(socket.assigns.state)
    Enum.reduce(outputs, assign(socket, :state, state), &show.(&2, &1))
  end

  def send_port_output(socket, name, {port, payload}) do
    send(self(), {name, port, payload})
    socket
  end

  def route(socket, routes, {name, port, payload}),
    do: routes |> Map.fetch!({name, port}) |> Enum.reduce(socket, &deliver(&2, &1, payload))

  defp deliver(socket, {:pass, {component, id, input}}, payload) do
    send_update(component, [{:id, id}, {input, payload}])
    socket
  end

  defp deliver(socket, {:assign, name}, payload), do: assign(socket, name, payload)
  defp deliver(socket, {:redirect, true}, url), do: redirect(socket, external: url)

  defp deliver(socket, {:call, fun}, payload) when is_function(fun, 1) do
    fun.(payload)
    socket
  end

  defp deliver(socket, {:call, {name, fun}}, payload) do
    fun.(instance!(socket, name), payload)
    socket
  end

  defp deliver(socket, {:feed, {name, fun, target}}, payload),
    do: deliver(socket, {:pass, target}, fun.(instance!(socket, name), payload))

  defp deliver(socket, {:async, {task, name, fun}}, payload) do
    instance = instance!(socket, name)
    start_async(socket, task, fn -> fun.(instance, payload) end)
  end

  defp deliver(socket, {:flash, {level, text}}, _payload), do: put_flash(socket, level, text)

  defp deliver(socket, {:flash_by, {level, texts}}, payload),
    do: put_flash(socket, level, Map.fetch!(texts, payload))

  defp deliver(socket, {:patch, paths}, payload) do
    case Map.fetch(paths, payload) do
      {:ok, path} -> push_patch(socket, to: path)
      :error -> socket
    end
  end

  defp instance!(socket, name) do
    case socket.assigns[:instances] do
      %{^name => instance} -> instance
      _ -> raise ArgumentError, "no configured instance #{inspect(name)} in @instances"
    end
  end
end
