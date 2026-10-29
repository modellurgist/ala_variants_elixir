defmodule GoodDeal.State.Promo do
  @moduledoc """
  A promo code the shopper enters, checked by the store's `codes` function and answered in its
  normal form with its percentage.
  """
  defstruct codes: nil

  @doc "Config: `codes`, a function of a code returning `{:ok, percent}` or `{:error, :invalid_code}`, or nil for a store with none."
  def new(opts), do: %__MODULE__{codes: opts[:codes]}

  @doc "`{:ok, %{code, percentage}}` for a valid code, or `:error`."
  def enter(%__MODULE__{} = promo, code) do
    case check(promo.codes, code) do
      {:ok, percentage} ->
        {:ok, %{code: code |> String.trim() |> String.upcase(), percentage: percentage}}

      {:error, :invalid_code} ->
        :error
    end
  end

  defp check(nil, _code), do: {:error, :invalid_code}
  defp check(codes, code), do: codes.(code)
end
