defmodule GoodDeal.State.Promo do
  @moduledoc """
  A promo code the shopper enters: checked by the store's `codes` function, kept in its normal
  form once it's valid. Ports out: `:discount` (the code and its
  percentage), `:applied` and `:rejected` (the code, after an attempt).
  """
  defstruct codes: nil, code: nil

  def ports,
    do: %{in: [enter: :code], out: [discount: :discount, applied: :code, rejected: :code]}

  @doc "Config: `codes`, a function of a code returning `{:ok, percent}` or `{:error, :invalid_code}`, or nil for a store with none."
  def new(opts), do: %__MODULE__{codes: opts[:codes]}

  def enter(%__MODULE__{} = promo, %{code: code}) do
    case check(promo.codes, code) do
      {:ok, percentage} ->
        code = code |> String.trim() |> String.upcase()
        {%{promo | code: code}, [discount: %{code: code, percentage: percentage}, applied: code]}

      {:error, :invalid_code} ->
        {promo, [rejected: code]}
    end
  end

  defp check(nil, _code), do: {:error, :invalid_code}
  defp check(codes, code), do: codes.(code)
end
