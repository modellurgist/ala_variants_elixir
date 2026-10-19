defmodule GoodDeal.Catalog do
  @moduledoc """
  The Catalog context.
  """

  import Ecto.Query, warn: false
  alias GoodDeal.Repo

  alias GoodDeal.Catalog.Product

  @topic "products"
  @low_stock_threshold 5

  @doc """
  Subscribes the caller to product changes: `{:product_created | :product_updated | :product_deleted, product}`.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(GoodDeal.PubSub, @topic)
  end

  def broadcast({:ok, product}, event) do
    broadcast(product, event)
    {:ok, product}
  end

  def broadcast({:error, _} = error, _event), do: error

  def broadcast(%Product{} = product, event) do
    Phoenix.PubSub.broadcast(GoodDeal.PubSub, @topic, {event, product})
  end

  @doc """
  Returns `:in_stock`, `:low_stock` or `:out_of_stock`.
  """
  def stock_status(%Product{stock: stock}) when stock <= 0, do: :out_of_stock
  def stock_status(%Product{stock: stock}) when stock <= @low_stock_threshold, do: :low_stock
  def stock_status(%Product{}), do: :in_stock

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

  @doc """
  Creates a product.

  ## Examples

      iex> create_product(%{field: value})
      {:ok, %Product{}}

      iex> create_product(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:product_created)
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
    product
    |> Product.changeset(attrs)
    |> Repo.update()
    |> broadcast(:product_updated)
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
    product
    |> Repo.delete()
    |> broadcast(:product_deleted)
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
