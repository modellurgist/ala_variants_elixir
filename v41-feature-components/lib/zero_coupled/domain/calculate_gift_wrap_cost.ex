defmodule ZeroCoupled.Domain.CalculateGiftWrapCost do
  @moduledoc """
  Single-function domain abstraction: gift-wrap cost by item count, at a
  **passed-in unit cost** (V34: the price is application config, not baked).
  """

  @spec call(non_neg_integer(), non_neg_integer()) :: integer()
  def call(count, unit_cost) when is_integer(count) and count >= 0, do: count * unit_cost
end
