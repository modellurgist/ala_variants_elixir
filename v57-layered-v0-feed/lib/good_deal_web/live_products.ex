defmodule GoodDealWeb.LiveProducts do
  @moduledoc """
  Keeps a page's stream of products current from `GoodDeal.ChangeFeed` facts, for the pages that
  list the catalog. A page maps the product kinds onto these, naming its stream.
  """
  import Phoenix.LiveView, only: [stream_delete: 3, stream_insert: 3]

  alias GoodDeal.Catalog
  alias GoodDeal.Catalog.Product

  # An added product's fact carries all its fields, so the row needs no read.
  def add(%{id: id, values: values}, socket, stream),
    do: stream_insert(socket, stream, struct(Product, Map.put(values, :id, id)))

  def refresh(%{id: id}, socket, stream) do
    case Catalog.get_product(id) do
      nil -> socket
      product -> stream_insert(socket, stream, product)
    end
  end

  def drop(%{id: id}, socket, stream), do: stream_delete(socket, stream, %Product{id: id})
end
