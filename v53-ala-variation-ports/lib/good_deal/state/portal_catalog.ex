defmodule GoodDeal.State.PortalCatalog do
  @moduledoc "The products a buyer can order from, with live stock, and the rows that show them."
  alias GoodDeal.Domain.StockStatus
  defstruct products: [], stock_status: nil

  @doc "Config: `stock_status` (a `StockStatus`) and `products`."
  def new(opts),
    do: %__MODULE__{
      products: opts[:products] || [],
      stock_status: Keyword.fetch!(opts, :stock_status)
    }

  @doc "The buyer wants this many of a product: `{product, quantity}`, or nil for one not listed."
  def request(%__MODULE__{} = catalog, %{product_id: product_id, quantity: quantity}) do
    case Enum.find(catalog.products, &(&1.id == product_id)) do
      nil -> nil
      product -> {product, max(quantity, 1)}
    end
  end

  @doc "A product's new stock: `{catalog, row}` to show, or `{catalog, nil}` for one not listed."
  def set_stock(%__MODULE__{} = catalog, %{product_id: product_id, stock: stock}) do
    case Enum.find(catalog.products, &(&1.id == product_id)) do
      nil ->
        {catalog, nil}

      product ->
        product = %{product | stock: stock}
        products = Enum.map(catalog.products, &if(&1.id == product_id, do: product, else: &1))
        {%{catalog | products: products}, row(catalog, product)}
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
