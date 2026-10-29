defmodule GoodDeal.ChangeFeed do
  @moduledoc """
  Live updates as a paradigm. A writer publishes a fact once its change has committed: a kind,
  the identity it is about and the values that changed. A LiveView subscribes once, mapping each
  kind it listens to onto a `(fact, socket) -> socket` function. Each kind is its own topic, so a
  page receives only the kinds it declared.
  """
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  @enforce_keys [:kind, :id, :values]
  defstruct [:kind, :id, :values]

  def publish(kind, id, values) when is_atom(kind) and is_map(values) do
    Phoenix.PubSub.broadcast(GoodDeal.PubSub, topic(kind), %__MODULE__{
      kind: kind,
      id: id,
      values: values
    })
  end

  def subscribe(socket, handlers) when is_map(handlers) do
    if connected?(socket) do
      listen(Map.keys(handlers))
      attach_hook(socket, __MODULE__, :handle_info, &dispatch(handlers, &1, &2))
    else
      socket
    end
  end

  def listen(kinds), do: Enum.each(kinds, &Phoenix.PubSub.subscribe(GoodDeal.PubSub, topic(&1)))

  def dispatch(handlers, %__MODULE__{kind: kind} = fact, socket)
      when is_map_key(handlers, kind),
      do: {:halt, Map.fetch!(handlers, kind).(fact, socket)}

  def dispatch(_handlers, _message, socket), do: {:cont, socket}

  defp topic(kind), do: "change_feed:#{kind}"
end
