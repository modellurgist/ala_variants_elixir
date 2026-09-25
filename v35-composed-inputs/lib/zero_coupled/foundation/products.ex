defmodule ZeroCoupled.Foundation.Products do
  @moduledoc """
  Foundation-layer persistence for products.
  Pure database operations — no broadcasting, no domain logic.
  """

  import Ecto.Query, warn: false
  alias ZeroCoupled.Repo
  alias ZeroCoupled.Foundation.Schemas.Product

  @spec list() :: [Product.t()]
  def list do
    Repo.all(Product)
  end

  @spec get!(integer()) :: Product.t()
  def get!(id), do: Repo.get!(Product, id)

  @spec insert(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @spec update(Product.t(), map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def update(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @spec delete(Product.t()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Product{} = product) do
    Repo.delete(product)
  end

  @spec decrement_stock(integer(), integer()) :: {:ok, Product.t()} | {:error, term()}
  def decrement_stock(product_id, amount \\ 1) do
    {count, _} =
      Product
      |> where([p], p.id == ^product_id and p.stock >= ^amount)
      |> Repo.update_all(inc: [stock: -amount])

    if count > 0, do: {:ok, get!(product_id)}, else: {:error, :insufficient_stock}
  end

  @spec stock_levels([integer()]) :: %{integer() => integer()}
  def stock_levels(product_ids) when is_list(product_ids) do
    Product
    |> where([p], p.id in ^product_ids)
    |> select([p], {p.id, p.stock})
    |> Repo.all()
    |> Map.new()
  end

  @spec changeset(Product.t(), map()) :: Ecto.Changeset.t()
  def changeset(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end
end
