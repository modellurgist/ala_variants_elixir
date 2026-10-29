defmodule GoodDeal.Domain.VolumeTier do
  @moduledoc """
  Picks the discount of the highest tier a subtotal reaches. The channel's tiers are
  `{min_subtotal, percent, label}`, highest first.
  """

  alias GoodDeal.Channel

  def discount(%Channel{volume_tiers: tiers}, subtotal) do
    Enum.find_value(tiers, {0, nil}, fn {min, percent, label} ->
      if subtotal >= min, do: {percent, label}
    end)
  end
end
