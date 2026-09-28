defprotocol ZeroCoupled.Ports.Step do
  @moduledoc """
  The dataflow port every part of a circuit speaks: push `{input, payload}` in; get
  `{:emit, [{port, payload}], step}` or `{:quiet, step}` back. Sinks emit their effect on port
  `:ui`; features emit on the ports their docs name.
  """
  def push(step, data)
end
