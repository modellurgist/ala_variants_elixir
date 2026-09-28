defmodule ZeroCoupled.Features.PortalCatalog do
  @moduledoc """
  The products a buyer can order from, with live stock. Ports out: `:rows` (a change to the
  displayed products) and `:requested` (`{product, quantity}`: the buyer wants this many).
  """
  alias ZeroCoupled.Domain.StockStatus
  defstruct products: []

  def new(opts), do: %__MODULE__{products: opts[:products] || []}

  def request(%__MODULE__{} = catalog, %{product_id: product_id, quantity: quantity}) do
    case Enum.find(catalog.products, &(&1.id == product_id)) do
      nil -> {catalog, []}
      product -> {catalog, [requested: {product, max(quantity, 1)}]}
    end
  end

  def set_stock(%__MODULE__{} = catalog, %{product_id: product_id, stock: stock}) do
    case Enum.find(catalog.products, &(&1.id == product_id)) do
      nil ->
        {catalog, []}

      product ->
        product = %{product | stock: stock}
        products = Enum.map(catalog.products, &if(&1.id == product_id, do: product, else: &1))
        {%{catalog | products: products}, [rows: {:changed, row(product)}]}
    end
  end

  def row(product) do
    %{
      id: product.id,
      product: %{thumbnail: product.thumbnail, name: product.name, amount: product.amount},
      stock_status: StockStatus.call(product.stock)
    }
  end

  def rows(%__MODULE__{products: products}), do: Enum.map(products, &row/1)
end
