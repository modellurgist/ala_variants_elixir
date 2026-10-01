defmodule GoodDeal.Domain.Shipping do
  @moduledoc """
  Shipping cost over a rate table the store configures once (`new/1`), so nothing here is specific
  to one store's prices. Each tier is `%{method, label, cost, free_above}`; `free_above: nil` means
  never free.
  """
  defstruct methods: []

  def new(methods), do: %__MODULE__{methods: methods}

  @doc "Cost of a tier over a subtotal, free once `free_above` is met; nothing chosen costs nothing."
  @spec cost(%__MODULE__{}, atom() | nil, integer()) :: integer()
  def cost(%__MODULE__{} = sh, method, subtotal_cents) do
    case Enum.find(sh.methods, &(&1.method == method)) do
      nil -> 0
      _ when subtotal_cents <= 0 -> 0
      %{free_above: free} when is_integer(free) and subtotal_cents >= free -> 0
      %{cost: cost} -> cost
    end
  end

  @doc "The tiers as a shopper chooses among them, amounts as money."
  def options(%__MODULE__{methods: methods}) do
    for m <- methods do
      %{
        method: m.method,
        label: m.label,
        cost: Money.new(m.cost),
        free_above: m.free_above && Money.new(m.free_above)
      }
    end
  end
end
