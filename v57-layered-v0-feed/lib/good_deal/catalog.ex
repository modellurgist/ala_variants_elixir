defmodule GoodDeal.Catalog do
  @moduledoc """
  The Catalog context.
  """

  import Ecto.Query, warn: false
  alias GoodDeal.Repo

  alias GoodDeal.Catalog.Product
  alias GoodDeal.ChangeFeed

  # Which feed fact an edited field is published under.
  @fact_fields [details: [:name, :description, :thumbnail], price: [:amount], stock: [:stock]]

  @doc """
  Returns the list of products.

  ## Examples

      iex> list_products()
      [%Product{}, ...]

  """
  def list_products do
    Repo.all(from p in Product, order_by: p.id)
  end

  @doc """
  Gets a single product.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %Product{}

      iex> get_product!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product!(id), do: Repo.get!(Product, id)

  def get_product(id), do: Repo.get(Product, id)

  @doc """
  Creates a product.

  ## Examples

      iex> create_product(%{field: value})
      {:ok, %Product{}}

      iex> create_product(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(attrs \\ %{}) do
    with {:ok, product} <- %Product{} |> Product.changeset(attrs) |> Repo.insert() do
      values = Map.take(product, [:name, :description, :amount, :stock, :thumbnail])
      ChangeFeed.publish(:product_added, product.id, values)
      {:ok, product}
    end
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{field: new_value})
      {:ok, %Product{}}

      iex> update_product(product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product(%Product{} = product, attrs) do
    changeset = Product.changeset(product, attrs)

    with {:ok, product} <- Repo.update(changeset) do
      for {kind, fields} <- @fact_fields,
          values = Map.take(changeset.changes, fields),
          values != %{},
          do: ChangeFeed.publish(kind, product.id, values)

      {:ok, product}
    end
  end

  @doc """
  Deletes a product.

  ## Examples

      iex> delete_product(product)
      {:ok, %Product{}}

      iex> delete_product(product)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product(%Product{} = product) do
    with {:ok, product} <- Repo.delete(product) do
      ChangeFeed.publish(:product_removed, product.id, %{})
      {:ok, product}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{data: %Product{}}

  """
  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end
end
