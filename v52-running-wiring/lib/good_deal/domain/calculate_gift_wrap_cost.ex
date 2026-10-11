defmodule GoodDeal.Domain.CalculateGiftWrapCost do
  @moduledoc "Gift-wrap cost for a number of wrapped items, at a unit cost the composition configures once."
  defstruct unit: 0

  def new(unit), do: %__MODULE__{unit: unit}

  @spec call(%__MODULE__{}, non_neg_integer()) :: integer()
  def call(%__MODULE__{unit: unit}, count) when is_integer(count) and count >= 0, do: count * unit
end
