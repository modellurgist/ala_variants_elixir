defmodule ZeroCoupled.Domain.CalculateGiftWrapCost do
  @moduledoc "Single-function domain abstraction: gift wrap cost by item count."

  @cost_per_item 299

  @spec call(non_neg_integer()) :: integer()
  def call(count) when is_integer(count) and count >= 0 do
    count * @cost_per_item
  end
end
