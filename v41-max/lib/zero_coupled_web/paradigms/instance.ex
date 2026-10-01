defmodule ZeroCoupledWeb.Paradigms.Instance do
  @moduledoc """
  What a feature's UI instance (a LiveComponent) needs beyond LiveView: run one step of the
  feature it holds in `:state` and hand each output to the instance's own `land/2`; announce
  an output it doesn't show to whoever mounted it, as `{name, port, payload}`; and route those
  announcements by a page's table.

  A route target is one of `pass: {component, id, input}` (send the payload to an instance's
  input), `assign: name`, `flash: {level, text}`, `flash_by: {level, texts}` (the text keyed by
  the payload), or `patch: paths` (push the path for the payload, when it has one).
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2, put_flash: 3, push_patch: 2]

  def step(socket, fun, show) do
    {state, outputs} = fun.(socket.assigns.state)
    Enum.reduce(outputs, assign(socket, :state, state), &show.(&2, &1))
  end

  def announce(socket, name, {port, payload}) do
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
  defp deliver(socket, {:flash, {level, text}}, _payload), do: put_flash(socket, level, text)

  defp deliver(socket, {:flash_by, {level, texts}}, payload),
    do: put_flash(socket, level, Map.fetch!(texts, payload))

  defp deliver(socket, {:patch, paths}, payload) do
    case Map.fetch(paths, payload) do
      {:ok, path} -> push_patch(socket, to: path)
      :error -> socket
    end
  end
end
