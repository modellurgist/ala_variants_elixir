defmodule GoodDealWeb.Paradigms.ChangeFeed do
  @moduledoc """
  Change feed: change made elsewhere, as a part a page wires. One instance,
  `%ChangeFeed{topic, format, facts}`, serves either end. `mount/3` subscribes a page (once
  connected) and delivers each fact of a kind in `facts` as the output `{kind, fact}` through the `out` the
  page gives it, so the page wires `feed.stock` like any story output and writes no `handle_info`
  for it; the page's key for it names `format`, which declares the ports. `publish/2` sends a
  changed record as the facts `format` builds from it, those of a kind in `facts`. The subscription
  ends with the page's process.
  """
  import Phoenix.LiveView, only: [connected?: 1, attach_hook: 4]

  defstruct topic: nil, format: nil, facts: []

  def mount(socket, %__MODULE__{} = feed, out) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(GoodDeal.PubSub, feed.topic)
    attach_hook(socket, __MODULE__, :handle_info, &deliver(&1, feed, &2, out))
  end

  def publish(%__MODULE__{} = feed, record) do
    for {kind, fact} <- Keyword.take(feed.format.facts(record), feed.facts),
        do:
          Phoenix.PubSub.broadcast(
            GoodDeal.PubSub,
            feed.topic,
            {__MODULE__, feed.topic, kind, fact}
          )

    :ok
  end

  @doc "The page's `handle_info` hook: a fact on this topic goes out if the page listens to its kind; other messages pass on."
  def deliver({__MODULE__, topic, kind, fact}, %__MODULE__{topic: topic} = feed, socket, out),
    do: {:halt, if(kind in feed.facts, do: out.(socket, {kind, fact}), else: socket)}

  def deliver(_message, _live, socket, _out), do: {:cont, socket}
end
