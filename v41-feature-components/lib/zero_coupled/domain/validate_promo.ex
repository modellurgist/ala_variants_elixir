defmodule ZeroCoupled.Domain.ValidatePromo do
  @moduledoc """
  Single-function domain abstraction: validate a promo code against a
  **passed-in table** (V34: codes are data, not baked — realistic too,
  since a real app's codes come from a store, and ALA-honest, since the
  table is application config on the diagram).
  """

  @type table :: %{String.t() => non_neg_integer()}

  @spec call(String.t(), table()) :: {:ok, non_neg_integer()} | {:error, :invalid_code}
  def call(code, table) when is_binary(code) do
    case Map.get(table, String.upcase(String.trim(code))) do
      nil -> {:error, :invalid_code}
      pct -> {:ok, pct}
    end
  end

  def call(_, _table), do: {:error, :invalid_code}
end
