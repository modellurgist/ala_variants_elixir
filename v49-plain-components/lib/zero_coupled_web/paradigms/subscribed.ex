defmodule ZeroCoupledWeb.Paradigms.Subscribed do
  @moduledoc "An on_mount hook: calls the configured `{module, function}` once the page has a live connection, so a page subscribes without branching."
  import Phoenix.LiveView, only: [connected?: 1]

  def on_mount({module, function}, _params, _session, socket) do
    if connected?(socket), do: apply(module, function, [])
    {:cont, socket}
  end
end
