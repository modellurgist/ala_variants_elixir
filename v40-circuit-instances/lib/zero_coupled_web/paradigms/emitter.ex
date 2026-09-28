defmodule ZeroCoupledWeb.Paradigms.Emitter do
  @moduledoc """
  For a UI instance (a LiveComponent): turn a browser event into a push on a circuit input,
  delivered to the page process that holds the circuit. The instance names the input it feeds;
  the page's circuit decides where that leads.
  """
  def feed(socket, instance, data) do
    send(self(), {:feed, instance, data})
    socket
  end
end
