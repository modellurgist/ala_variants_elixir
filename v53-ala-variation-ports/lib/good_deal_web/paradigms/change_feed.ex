defmodule GoodDealWeb.Paradigms.ChangeFeed do
  @moduledoc """
  Outside change, as a part. A page mounts a feed, `mount(socket, [topic:, facts:], out)`, and wires
  its outputs like a story's: `wire(s, :feed, {:stock, change})`. A composition that changes a
  product hands it to `publish/2`, configured the same way. Facts are keyed by product id and this
  module alone builds them, so a publisher and a subscriber share only the topic and the id.
  """
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  @pubsub GoodDeal.PubSub

  def ports, do: %{in: [], out: [product: :product, stock: :stock_change]}

  @doc "Config: `topic`, and `facts`, the kinds this page is sent; each arrives as `out.(socket, {kind, fact})`."
  def mount(socket, opts, out) do
    topic = Keyword.fetch!(opts, :topic)
    facts = Keyword.fetch!(opts, :facts)
    if connected?(socket), do: Phoenix.PubSub.subscribe(@pubsub, topic)

    attach_hook(socket, {__MODULE__, topic}, :handle_info, fn
      {__MODULE__, ^topic, kind, fact}, s ->
        {:halt, if(kind in facts, do: out.(s, {kind, fact}), else: s)}

      _message, s ->
        {:cont, s}
    end)
  end

  @doc "Send each of `facts` about a changed product on `topic`. Config as `mount/3`'s."
  def publish(opts, product) do
    topic = Keyword.fetch!(opts, :topic)
    kinds = Keyword.fetch!(opts, :facts)

    for {kind, fact} <- facts(product),
        kind in kinds,
        do: Phoenix.PubSub.broadcast(@pubsub, topic, {__MODULE__, topic, kind, fact})

    product
  end

  @doc "Every fact about a product, by kind: the record itself, and its stock by id."
  def facts(%{id: id, stock: stock} = product),
    do: [product: product, stock: %{product_id: id, stock: stock}]
end
