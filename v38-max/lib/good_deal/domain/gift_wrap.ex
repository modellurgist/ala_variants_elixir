defmodule GoodDeal.Domain.GiftWrap do
  @moduledoc "Gift wrapping charged per item, at a fee the store configures once, in cents."
  defstruct cents_per_item: 0

  def new(cents_per_item), do: %__MODULE__{cents_per_item: cents_per_item}

  @spec total(%__MODULE__{}, non_neg_integer()) :: integer()
  def total(%__MODULE__{cents_per_item: cents}, count) when is_integer(count) and count >= 0,
    do: count * cents
end
