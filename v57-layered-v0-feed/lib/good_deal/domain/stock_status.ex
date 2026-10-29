defmodule GoodDeal.Domain.StockStatus do
  @moduledoc """
  Returns `:in_stock`, `:low_stock` (at or below the channel's threshold) or `:out_of_stock`.
  """

  alias GoodDeal.Channel

  def of(%Channel{}, stock) when stock <= 0, do: :out_of_stock
  def of(%Channel{low_stock_threshold: low}, stock) when stock <= low, do: :low_stock
  def of(%Channel{}, _stock), do: :in_stock
end
