defmodule GoodDeal.Domain.CalculateShipping do
  @moduledoc """
  Shipping by method, against a rate table the composition configures once:
  `%{method => %{label:, cost:, free_above:}}`. Cost for a subtotal, and the
  methods and labels to offer. Nothing here changes if the product changes.
  """
  defstruct rates: %{}

  @type t :: %__MODULE__{
          rates: %{atom() => %{label: String.t(), cost: integer(), free_above: integer() | nil}}
        }

  def new(rates), do: %__MODULE__{rates: rates}

  @spec call(t(), atom(), integer()) :: integer()
  def call(%__MODULE__{}, _method, 0), do: 0

  def call(%__MODULE__{rates: rates}, method, subtotal_cents) when subtotal_cents > 0 do
    case Map.fetch(rates, method) do
      :error -> 0
      {:ok, %{free_above: over}} when is_integer(over) and subtotal_cents >= over -> 0
      {:ok, info} -> info.cost
    end
  end

  @doc "The methods on offer, each with its label, cost and free threshold."
  def options(%__MODULE__{rates: rates}),
    do: for({method, rate} <- rates, do: Map.put(rate, :method, method))

  def label(%__MODULE__{rates: rates}, method), do: (rates[method] || %{})[:label]
end
