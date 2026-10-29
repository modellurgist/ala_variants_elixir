defmodule GoodDeal.ProductEvents do
  @moduledoc """
  The product change feed: `{:product_created | :product_updated | :product_deleted, product}`.
  Catalog edits and checkout's stock decrements both publish here.
  """

  @topic "product_events"

  def subscribe, do: Phoenix.PubSub.subscribe(GoodDeal.PubSub, @topic)

  def broadcast({:ok, product}, event) do
    broadcast(product, event)
    {:ok, product}
  end

  def broadcast({:error, _} = error, _event), do: error

  def broadcast(%GoodDeal.Catalog.Product{} = product, event) do
    Phoenix.PubSub.broadcast(GoodDeal.PubSub, @topic, {event, product})
  end
end
