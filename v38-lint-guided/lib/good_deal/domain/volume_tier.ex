defmodule GoodDeal.Domain.VolumeTier do
  @moduledoc """
  Volume pricing: the percentage discount for a subtotal, from tiers the caller
  supplies as `{minimum_subtotal_cents, percent, label}` in descending order.
  """

  @spec discount([{integer(), non_neg_integer(), String.t()}], integer()) ::
          {non_neg_integer(), String.t() | nil}
  def discount(tiers, subtotal_cents) do
    case Enum.find(tiers, fn {min, _pct, _label} -> subtotal_cents >= min end) do
      {_min, pct, label} -> {pct, label}
      nil -> {0, nil}
    end
  end
end
