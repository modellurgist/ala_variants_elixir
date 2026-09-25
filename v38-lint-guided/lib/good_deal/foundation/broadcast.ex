defmodule GoodDeal.Foundation.Broadcast do
  @moduledoc """
  Foundation-layer PubSub wrapper for application events.
  """

  @product_topic "products"

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(GoodDeal.PubSub, @product_topic)
  end

  @spec notify(atom(), term()) :: :ok | {:error, term()}
  def notify(event, payload) do
    Phoenix.PubSub.broadcast(GoodDeal.PubSub, @product_topic, {event, payload})
  end
end
