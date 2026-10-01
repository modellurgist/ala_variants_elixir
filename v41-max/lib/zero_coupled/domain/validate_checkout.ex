defmodule ZeroCoupled.Domain.ValidateCheckout do
  @moduledoc "Single-function domain abstraction: validate cart is non-empty for checkout."

  @spec call([term()]) :: {:ok, [term()]} | {:error, :empty_cart}
  def call([]), do: {:error, :empty_cart}
  def call(items) when is_list(items), do: {:ok, items}
end
