defmodule ZeroCoupled.Domain.ApplyDiscount do
  @moduledoc "Single-function domain abstraction: apply percentage discount."

  @spec call(integer(), non_neg_integer() | nil) :: {integer(), integer()}
  def call(subtotal_cents, nil), do: {subtotal_cents, 0}
  def call(subtotal_cents, 0), do: {subtotal_cents, 0}

  def call(subtotal_cents, percentage)
      when is_integer(subtotal_cents) and is_integer(percentage) do
    discount = div(subtotal_cents * percentage, 100)
    {max(0, subtotal_cents - discount), discount}
  end
end
