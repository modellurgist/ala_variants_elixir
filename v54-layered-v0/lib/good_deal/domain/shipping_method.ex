defmodule GoodDeal.Domain.ShippingMethod do
  @moduledoc """
  A shipping method: a flat cost, waived above `free_above` when it is set. An empty cart ships free.
  """

  @enforce_keys [:id, :label, :cost]
  defstruct [:id, :label, :cost, free_above: nil]

  def find(methods, id), do: Enum.find(methods, &(&1.id == id))

  def cost(%__MODULE__{}, 0), do: 0

  def cost(%__MODULE__{free_above: min}, subtotal) when is_integer(min) and subtotal >= min,
    do: 0

  def cost(%__MODULE__{cost: cost}, _subtotal), do: cost
end
