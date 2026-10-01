defmodule GoodDeal.Domain.Promo do
  @moduledoc "Promo codes a store honours, configured once as code to percent off; codes match trimmed and in any case."
  defstruct codes: %{}

  def new(codes), do: %__MODULE__{codes: codes}

  @spec call(%__MODULE__{}, term()) :: {:ok, non_neg_integer()} | {:error, :invalid_code}
  def call(%__MODULE__{codes: codes}, code) when is_binary(code) do
    case Map.fetch(codes, code |> String.trim() |> String.upcase()) do
      {:ok, pct} -> {:ok, pct}
      :error -> {:error, :invalid_code}
    end
  end

  def call(%__MODULE__{}, _code), do: {:error, :invalid_code}
end
