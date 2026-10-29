defmodule GoodDeal.Domain.StockStatus do
  @moduledoc """
  Returns `:in_stock`, `:low_stock` (at or below the threshold) or `:out_of_stock`.
  """

  def of(stock, _low_threshold) when stock <= 0, do: :out_of_stock
  def of(stock, low_threshold) when stock <= low_threshold, do: :low_stock
  def of(_stock, _low_threshold), do: :in_stock
end
