defmodule GoodDeal.Domain.Shipping do
  @moduledoc """
  Domain abstraction for shipping cost. Pure functions over data — and generic:
  the rate table is supplied by the caller (the composition owns calibration),
  so nothing here is specific to any one store's prices.
  """

  @type method_info :: %{:cost => integer(), optional(atom()) => any()}

  @doc "Cost for a chosen tier over a subtotal. Free once `free_above` is met."
  @spec cost(method_info() | nil, integer()) :: integer()
  def cost(nil, _subtotal_cents), do: 0
  def cost(_info, subtotal_cents) when subtotal_cents <= 0, do: 0

  def cost(%{cost: base} = info, subtotal_cents) do
    case Map.get(info, :free_above) do
      threshold when is_integer(threshold) and subtotal_cents >= threshold -> 0
      _ -> base
    end
  end

  @doc "Find a tier by name in a supplied methods list; nil if absent."
  @spec find([map()], atom()) :: method_info() | nil
  def find(methods, method) when is_list(methods) do
    Enum.find(methods, &(&1.method == method))
  end
end
