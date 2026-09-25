defmodule ZeroCoupled.Domain.VolumeTier do
  @moduledoc """
  Single-function domain abstraction: the volume-pricing tier for a
  subtotal, against a **passed-in tier table** (V34: the thresholds and
  percentages are application config on the diagram, not baked). Now
  genuinely `[]` — nothing here is portal- or product-specific.
  """

  @type tiers :: [{integer(), non_neg_integer(), String.t()}]

  @spec call(integer(), tiers()) :: {non_neg_integer(), String.t() | nil}
  def call(subtotal_cents, tiers) when is_integer(subtotal_cents) do
    Enum.find_value(tiers, {0, nil}, fn {min, pct, label} ->
      if subtotal_cents >= min, do: {pct, label}
    end)
  end
end
