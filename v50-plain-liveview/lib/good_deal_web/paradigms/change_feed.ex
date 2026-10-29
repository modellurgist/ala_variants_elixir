defmodule GoodDealWeb.Paradigms.ChangeFeed do
  @moduledoc """
  Outside change as a part. A page's feed (`new(topic, facts)`) is one more part in its wiring: it
  leaves each fact it was configured for on the port named for its kind, and the page's `wire/3`
  clauses route it (`feed.stock → cart.set_stock`). A publisher is another instance on the same
  topic, so the two share only the fact format: a kind and an identity, with at most one value,
  never a row or a struct. Knows PubSub and LiveView; never a page or a feature.
  """
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]
  import Phoenix.Component, only: [assign: 3]

  defstruct topic: nil, facts: []

  @pubsub GoodDeal.PubSub

  def new(topic, facts \\ []), do: %__MODULE__{topic: topic, facts: facts}

  def ports(%__MODULE__{facts: facts}),
    do: %{in: [deliver: :fact], out: Enum.map(facts, &{&1, :fact})}

  def deliver(%__MODULE__{} = feed, fact), do: {feed, Keyword.take([fact], feed.facts)}

  def publish(%__MODULE__{topic: topic}, kind, id), do: broadcast(topic, {kind, id})

  def publish(%__MODULE__{topic: topic}, kind, id, value),
    do: broadcast(topic, {kind, {id, value}})

  @doc """
  Put the feed in the page's assigns under `key` and, once connected, subscribe; each fact then runs
  `deliver/2` through the page's own `run(socket, key, step)`, so the page writes no `handle_info`
  for it. The subscription ends with the page's process.
  """
  def attach(socket, key, %__MODULE__{topic: topic} = feed, run) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(@pubsub, topic)

    socket
    |> assign(key, feed)
    |> attach_hook(key, :handle_info, fn
      {__MODULE__, ^topic, fact}, s -> {:halt, run.(s, key, &deliver(&1, fact))}
      _other, s -> {:cont, s}
    end)
  end

  defp broadcast(topic, fact),
    do: Phoenix.PubSub.broadcast(@pubsub, topic, {__MODULE__, topic, fact})
end
