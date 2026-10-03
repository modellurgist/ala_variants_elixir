defmodule GoodDeal.Lines do
  @moduledoc """
  A list of order lines: the stored records (`id`, `quantity`, `product`) a cart or a bulk order holds.
  Find a line, add one, change a quantity, remove one, and set a product's new stock level. It holds no
  prices, codes or flags of any use case, so the storefront's cart and the portal's order each build
  their own data on it instead of sharing one struct (Spray §6.17.2).
  """

  def find(lines, id), do: Enum.find(lines, &(&1.id == id))
  def find_by_product(lines, product_id), do: Enum.find(lines, &(&1.product.id == product_id))

  @doc "Add a line; one already there by id is kept as it is."
  def add(lines, line), do: if(find(lines, line.id), do: lines, else: lines ++ [line])

  @doc "Change a line's quantity by `delta`, never below 1: `{:ok, lines, line}`, or `:error` if absent."
  def bump(lines, id, delta) do
    case find(lines, id) do
      nil ->
        :error

      _line ->
        lines =
          Enum.map(lines, fn
            %{id: ^id} = line -> %{line | quantity: max(1, line.quantity + delta)}
            line -> line
          end)

        {:ok, lines, find(lines, id)}
    end
  end

  @doc "Remove a line: `{:ok, remaining, removed}`, or `:error` if absent."
  def remove(lines, id) do
    case Enum.split_with(lines, &(&1.id == id)) do
      {[removed | _], remaining} -> {:ok, remaining, removed}
      {[], _} -> :error
    end
  end

  @doc "A product's new stock level on its line: `{:ok, lines, line}`, or `:none` if no line has it."
  def set_stock(lines, product_id, stock) do
    lines =
      Enum.map(lines, fn line ->
        if line.product.id == product_id,
          do: %{line | product: %{line.product | stock: stock}},
          else: line
      end)

    case find_by_product(lines, product_id) do
      nil -> :none
      line -> {:ok, lines, line}
    end
  end
end
