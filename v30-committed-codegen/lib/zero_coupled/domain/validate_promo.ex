defmodule ZeroCoupled.Domain.ValidatePromo do
  @moduledoc "Single-function domain abstraction: validate promo codes."

  @promo_codes %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}

  @spec call(String.t()) :: {:ok, non_neg_integer()} | {:error, :invalid_code}
  def call(code) when is_binary(code) do
    case Map.get(@promo_codes, String.upcase(String.trim(code))) do
      nil -> {:error, :invalid_code}
      pct -> {:ok, pct}
    end
  end

  def call(_), do: {:error, :invalid_code}
end
