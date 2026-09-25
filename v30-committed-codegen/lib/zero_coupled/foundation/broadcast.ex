defmodule ZeroCoupled.Foundation.Broadcast do
  @moduledoc """
  Foundation-layer PubSub transport.

  Emitters broadcast a **fact** (something that happened) as a typed
  message. Consumers subscribe and interpret it — the consumer's shell
  turns the fact into a `Session` intent. There is no interpreted
  routing table (v27's `Wiring.pubsub_routes`); the "wiring" of a
  cross-process fact is just the `handle_info` clause that receives it,
  which is explicit and greppable like everything else in v28.
  """

  @topic "storefront"

  @type message ::
          {:stock_changed, product_id :: integer(), stock :: integer()}
          | {:product_saved, product :: struct()}

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(ZeroCoupled.PubSub, @topic)

  @spec stock_changed(integer(), integer()) :: :ok | {:error, term()}
  def stock_changed(product_id, stock), do: broadcast({:stock_changed, product_id, stock})

  @spec product_saved(struct()) :: :ok | {:error, term()}
  def product_saved(product), do: broadcast({:product_saved, product})

  defp broadcast(message), do: Phoenix.PubSub.broadcast(ZeroCoupled.PubSub, @topic, message)
end
