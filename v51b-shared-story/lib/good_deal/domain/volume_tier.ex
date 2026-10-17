defmodule GoodDeal.Domain.VolumeTier do
  @moduledoc """
  The volume-pricing tier for a subtotal, against a tier table the composition
  configures once: `[{min_cents, percent, label}]`, highest first.
  """
  defstruct tiers: []

  def new(tiers), do: %__MODULE__{tiers: tiers}

  @spec call(%__MODULE__{}, integer()) :: {non_neg_integer(), String.t() | nil}
  def call(%__MODULE__{tiers: tiers}, subtotal_cents) when is_integer(subtotal_cents) do
    Enum.find_value(tiers, {0, nil}, fn {min, pct, label} ->
      if subtotal_cents >= min, do: {pct, label}
    end)
  end
end
