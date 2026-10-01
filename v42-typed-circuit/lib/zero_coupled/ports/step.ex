defprotocol ZeroCoupled.Ports.Step do
  @moduledoc """
  The dataflow port every part of a circuit speaks: push `{input, payload}` in; get
  `{:emit, [{port, payload}], step}` or `{:quiet, step}` back. Sinks emit their effect on port
  `:ui`; features emit on the ports they declare.

  `ports/1` declares the instance's inputs and outputs, each with a paradigm type (`:any` accepts
  every type; `:ui` marks an output the runner lands). `feeds/1` lists the `{instance, input}`
  targets an instance pushes back into later (a timer, an async job), so they can be checked too.
  """
  @fallback_to_any true
  def push(step, data)
  def ports(step)
  def feeds(step)
end

defimpl ZeroCoupled.Ports.Step, for: Any do
  def push(step, _data), do: raise(ArgumentError, "#{inspect(step)} is not a circuit instance")
  def ports(step), do: raise(ArgumentError, "#{inspect(step)} is not a circuit instance")
  def feeds(_step), do: []
end
