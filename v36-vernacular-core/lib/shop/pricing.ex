defmodule Shop.Pricing do
  @moduledoc """
  Generic pricing calculations — the domain-abstraction layer. Every function
  is pure and takes its calibration as data (rates, promo table, tiers come
  from the composition), so nothing here is product-specific: this module would
  work unchanged in any storefront. (ALA's "domain abstractions know nothing of
  the application.")
  """

  @doc "Subtotal in cents for `[%{unit_amount, quantity}, …]` (a neutral shape the caller projects to)."
  def subtotal(lines), do: Enum.reduce(lines, 0, fn l, acc -> acc + l.unit_amount * l.quantity end)

  @doc "Discounted total and the discount, given a percentage (nil = none)."
  def discount(subtotal, nil), do: {subtotal, 0}
  def discount(subtotal, pct) when is_integer(pct), do: (d = div(subtotal * pct, 100); {subtotal - d, d})

  @doc "Shipping cost for a method against a passed-in rate table."
  def shipping(_method, 0, _rates), do: 0
  def shipping(method, subtotal, rates) do
    case Map.get(rates, method) do
      %{free_above: t} when is_integer(t) and subtotal >= t -> 0
      %{cost: c} -> c
      _ -> 0
    end
  end

  @doc "Gift-wrap cost for a count at a passed-in unit price."
  def gift_wrap(count, unit_cents), do: count * unit_cents

  @doc "Validate a promo code against a passed-in table."
  def promo(code, table) when is_binary(code) do
    case Map.get(table, String.upcase(String.trim(code))) do
      nil -> :error
      pct -> {:ok, pct}
    end
  end
end
