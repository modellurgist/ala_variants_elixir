defmodule GoodDeal.Domain.ValidatePromo do
  @moduledoc """
  Validates a promo code against a code table the composition configures once
  (`%{"CODE" => percent}`); codes are normalised before lookup.
  """
  defstruct codes: %{}

  def new(codes), do: %__MODULE__{codes: codes}

  @spec call(%__MODULE__{}, term()) :: {:ok, non_neg_integer()} | {:error, :invalid_code}
  def call(%__MODULE__{codes: codes}, code) when is_binary(code) do
    case Map.get(codes, String.upcase(String.trim(code))) do
      nil -> {:error, :invalid_code}
      pct -> {:ok, pct}
    end
  end

  def call(%__MODULE__{}, _code), do: {:error, :invalid_code}
end
