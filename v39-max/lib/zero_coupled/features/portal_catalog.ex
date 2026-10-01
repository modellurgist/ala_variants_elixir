defmodule ZeroCoupled.Features.PortalCatalog do
  @moduledoc """
  The products a buyer can order from, with live stock. Ports out: `:rows` (a change to the
  displayed products) and `:requested` (`{product, quantity}`: the buyer wants this many).
  """
  alias ZeroCoupled.Domain.StockStatus
  defstruct products: [], stock_status: nil

  def ports,
    do: %{
      in: [load: :products, request: :event, set_stock: :stock_change],
      out: [rows: :row_change, requested: :product_quantity]
    }

  @doc "Config: `stock_status` (a `StockStatus`)."
  def new(opts),
    do: %__MODULE__{
      products: opts[:products] || [],
      stock_status: Keyword.fetch!(opts, :stock_status)
    }

  def load(%__MODULE__{} = catalog, products) do
    catalog = %{catalog | products: products}
    {catalog, [rows: {:reset, rows(catalog)}]}
  end

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
        {%{catalog | products: products}, [rows: {:changed, row(catalog, product)}]}
    end
  end

  def row(%__MODULE__{} = catalog, product) do
    %{
      id: product.id,
      product: %{thumbnail: product.thumbnail, name: product.name, amount: product.amount},
      stock_status: StockStatus.call(catalog.stock_status, product.stock)
    }
  end

  def rows(%__MODULE__{products: products} = catalog), do: Enum.map(products, &row(catalog, &1))
end
