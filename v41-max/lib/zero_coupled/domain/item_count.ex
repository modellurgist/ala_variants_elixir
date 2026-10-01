defmodule ZeroCoupled.Domain.ItemCount do
  @moduledoc "Single-function domain abstraction: total quantity across items."

  @spec call([%{quantity: integer()}]) :: non_neg_integer()
  def call(items) do
    items |> Enum.map(& &1.quantity) |> Enum.sum()
  end
end
