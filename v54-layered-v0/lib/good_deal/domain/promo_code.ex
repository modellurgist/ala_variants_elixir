defmodule GoodDeal.Domain.PromoCode do
  @moduledoc """
  Promo codes as a map from code to percent off. Codes are matched after trimming and upcasing.
  """

  def normalize(code), do: code |> to_string() |> String.trim() |> String.upcase()

  def valid?(codes, code), do: Map.has_key?(codes, code)

  def discount(codes, code) do
    case codes[code] do
      nil -> {0, nil}
      percent -> {percent, code}
    end
  end
end
