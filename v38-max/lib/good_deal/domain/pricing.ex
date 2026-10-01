defmodule GoodDeal.Domain.Pricing do
  @moduledoc """
  Price arithmetic over cart lines: line totals, subtotals, counts, a percentage discount.
  Pure functions on data, with no store's configuration in them.
  """

  @spec line_total(integer(), integer()) :: integer()
  def line_total(unit_amount, quantity) when is_integer(unit_amount) and is_integer(quantity) do
    unit_amount * quantity
  end

  @spec cart_total([%{product: %{amount: integer()}, quantity: integer()}]) :: Money.t()
  def cart_total(items) do
    subtotal_cents(items) |> Money.new()
  end

  @spec subtotal_cents([%{product: %{amount: integer()}, quantity: integer()}]) :: integer()
  def subtotal_cents(items) do
    items
    |> Enum.map(fn item -> line_total(item.product.amount, item.quantity) end)
    |> Enum.sum()
  end

  @spec item_count([%{quantity: integer()}]) :: non_neg_integer()
  def item_count(items), do: items |> Enum.map(& &1.quantity) |> Enum.sum()

  @spec apply_discount(integer(), non_neg_integer()) :: {integer(), integer()}
  def apply_discount(subtotal, percentage) when is_integer(subtotal) and is_integer(percentage) do
    discount = div(subtotal * percentage, 100)
    {max(0, subtotal - discount), discount}
  end

  @spec discounted_total(
          [%{product: %{amount: integer()}, quantity: integer()}],
          non_neg_integer() | nil
        ) ::
          {Money.t(), Money.t()}
  def discounted_total(items, nil), do: {cart_total(items), Money.new(0)}

  def discounted_total(items, percentage) do
    sub = subtotal_cents(items)
    {final, disc} = apply_discount(sub, percentage)
    {Money.new(final), Money.new(disc)}
  end
end
