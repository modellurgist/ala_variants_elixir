defmodule ZeroCoupled.Domain.StockStatus do
  @moduledoc "Classifies a stock level as in stock, low, or out, against a low-stock threshold the composition configures once."
  defstruct low_at: 0

  def new(opts), do: %__MODULE__{low_at: Keyword.fetch!(opts, :low_at)}

  @spec call(%__MODULE__{}, integer()) :: :in_stock | :low_stock | :out_of_stock
  def call(%__MODULE__{}, stock) when stock <= 0, do: :out_of_stock
  def call(%__MODULE__{low_at: low_at}, stock) when stock <= low_at, do: :low_stock
  def call(%__MODULE__{}, _stock), do: :in_stock
end
