defmodule GoodDeal.Domain.Pricing do
  @moduledoc """
  Domain abstraction for price calculations.
  Pure functions on data — no Ecto, no persistence, no framework dependencies.
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

  @spec validate_promo(String.t(), %{String.t() => non_neg_integer()}) ::
          {:ok, non_neg_integer()} | {:error, :invalid_code}
  def validate_promo(code, codes) when is_binary(code) and is_map(codes) do
    case Map.get(codes, String.upcase(String.trim(code))) do
      nil -> {:error, :invalid_code}
      pct -> {:ok, pct}
    end
  end
  def validate_promo(_, _), do: {:error, :invalid_code}

  @spec apply_discount(integer(), non_neg_integer()) :: {integer(), integer()}
  def apply_discount(subtotal, percentage) when is_integer(subtotal) and is_integer(percentage) do
    discount = div(subtotal * percentage, 100)
    {max(0, subtotal - discount), discount}
  end

  @spec discounted_total([%{product: %{amount: integer()}, quantity: integer()}], non_neg_integer() | nil) ::
          {Money.t(), Money.t()}
  def discounted_total(items, nil), do: {cart_total(items), Money.new(0)}
  def discounted_total(items, percentage) do
    sub = subtotal_cents(items)
    {final, disc} = apply_discount(sub, percentage)
    {Money.new(final), Money.new(disc)}
  end

  @spec gift_wrap_total(non_neg_integer(), non_neg_integer()) :: integer()
  def gift_wrap_total(count, cents_per_item)
      when is_integer(count) and count >= 0 and is_integer(cents_per_item) do
    count * cents_per_item
  end
end
