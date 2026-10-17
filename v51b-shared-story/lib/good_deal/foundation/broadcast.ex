defmodule GoodDeal.Foundation.Broadcast do
  @moduledoc """
  Foundation-layer PubSub wrapper for application events.
  """

  @product_topic "catalog_events"

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(GoodDeal.PubSub, @product_topic)
  end

  @spec stock_changed(integer(), integer()) :: :ok | {:error, term()}
  def stock_changed(product_id, stock), do: notify(:stock_changed, {product_id, stock})

  @spec notify(atom(), term()) :: :ok | {:error, term()}
  def notify(event, payload) do
    Phoenix.PubSub.broadcast(GoodDeal.PubSub, @product_topic, {event, payload})
  end
end
