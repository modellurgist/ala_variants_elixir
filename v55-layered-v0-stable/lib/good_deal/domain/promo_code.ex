defmodule GoodDeal.Domain.PromoCode do
  @moduledoc """
  Promo codes are the channel's map from code to percent off. Codes are matched after
  trimming and upcasing.
  """

  alias GoodDeal.Channel

  def normalize(code), do: code |> to_string() |> String.trim() |> String.upcase()

  def valid?(%Channel{promo_codes: codes}, code), do: Map.has_key?(codes, code)

  def discount(%Channel{promo_codes: codes}, code) do
    case codes[code] do
      nil -> {0, nil}
      percent -> {percent, code}
    end
  end
end
