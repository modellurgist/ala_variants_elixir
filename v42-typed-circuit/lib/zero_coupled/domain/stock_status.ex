defmodule ZeroCoupled.Domain.StockStatus do
  @moduledoc "Single-function domain abstraction: stock level classification."

  @low_stock_threshold 5

  @spec call(integer()) :: :in_stock | :low_stock | :out_of_stock
  def call(stock) when stock <= 0, do: :out_of_stock
  def call(stock) when stock <= @low_stock_threshold, do: :low_stock
  def call(_stock), do: :in_stock
end
