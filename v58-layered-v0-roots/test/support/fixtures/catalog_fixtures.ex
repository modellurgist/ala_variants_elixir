defmodule GoodDeal.CatalogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `GoodDeal.Catalog` context.
  """

  @doc """
  Generate a product.
  """
  def product_fixture(attrs \\ %{}) do
    {:ok, product} =
      attrs
      |> Enum.into(%{
        amount: 42,
        description: "some description",
        name: "some name",
        stock: 42,
        thumbnail: "some thumbnail"
      })
      |> GoodDeal.Catalog.create_product()

    product
  end
end
