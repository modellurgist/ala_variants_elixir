defprotocol ZeroCoupled.Ports.Call do
  @moduledoc """
  The request/response port: a configured instance answers one payload. Domain abstractions that do
  their own I/O (placing an order, adding a line, starting a payment) implement it, so a page's
  wiring can name the instance instead of wrapping it in a function.
  """
  def call(instance, payload)
end
