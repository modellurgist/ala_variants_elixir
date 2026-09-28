defmodule ZeroCoupled.Domain.CheckStock do
  @moduledoc "Single-function domain abstraction: check item availability against stock levels."

  @spec call([%{product: %{id: term()}, quantity: integer()}], %{term() => integer()}) ::
          :ok | {:error, :out_of_stock}
  def call(items, stock_levels) do
    all_ok =
      Enum.all?(items, fn item ->
        Map.get(stock_levels, item.product.id, 0) >= item.quantity
      end)

    if all_ok, do: :ok, else: {:error, :out_of_stock}
  end
end
