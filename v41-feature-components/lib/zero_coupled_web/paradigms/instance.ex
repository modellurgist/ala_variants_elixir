defmodule ZeroCoupledWeb.Paradigms.Instance do
  @moduledoc """
  What a feature's UI instance (a LiveComponent) needs beyond LiveView: run one step of the
  feature it holds in `:state` and hand each output to the instance's own `wire/2`; send
  an output it doesn't show to whoever mounted it, as `{name, port, payload}`.
  """
  import Phoenix.Component, only: [assign: 3]

  def step(socket, fun, show) do
    {state, outputs} = fun.(socket.assigns.state)
    Enum.reduce(outputs, assign(socket, :state, state), &show.(&2, &1))
  end

  def send_port_output(socket, name, {port, payload}) do
    send(self(), {name, port, payload})
    socket
  end
end
