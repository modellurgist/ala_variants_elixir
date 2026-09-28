defmodule ZeroCoupled.Domain.CalculateShipping do
  @moduledoc """
  Single-function domain abstraction: shipping cost by method and subtotal,
  against a **passed-in rate table** (V34: no baked rates — the calibration
  lives on the diagram, the manifest `config:` channel). Genuinely `[]`:
  nothing here changes if the product changes.
  """

  @type rates :: %{atom() => %{cost: integer(), free_above: integer() | nil}}

  @spec call(atom(), integer(), rates()) :: integer()
  def call(_method, 0, _rates), do: 0

  def call(method, subtotal_cents, rates) when subtotal_cents > 0 do
    case Map.fetch(rates, method) do
      :error ->
        0

      {:ok, info} ->
        case info[:free_above] do
          nil -> info.cost
          threshold when subtotal_cents >= threshold -> 0
          _ -> info.cost
        end
    end
  end
end
